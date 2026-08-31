import AppKit
import Observation
import LockTuneCore
import LockTuneDomain
import LockTuneInfrastructure

enum CalendarConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case syncing
}

@MainActor
@Observable
final class AppSession {
    let islandCoordinator = IslandCoordinator()
    var musicLibrary = MusicLibrarySnapshot()
    var musicFolders: [URL] = []
    var playback = PlaybackSnapshot()
    var favoriteTrackIDs: Set<UUID> = []
    var calendarSnapshot = CalendarSnapshot()
    var selectedCalendarIDs: Set<String> = []
    var calendarConnectionState: CalendarConnectionState = .disconnected
    var calendarError: String?
    var isScanningMusic = false
    var musicScanProgress: MusicScanProgress?
    var currentArtworkData: Data?
    var isIslandEnabled: Bool
    var glassTint: Double
    var glassBackingLevel: GlassBackingLevel
    var glassRefraction: Double
    var glassMotionEnabled: Bool
    var privateRefractionEnabled: Bool
    var liquidGlassRuntimeMode: LiquidGlassRuntimeMode = .notEvaluated
    var preferredIslandDisplayID: String?
    var availableIslandDisplays: [IslandDisplay] = []
    var islandDisplayGeometry: IslandDisplayGeometry?
    /// The reference height is session-scoped so a floating display keeps the
    /// same collapsed rhythm as the last real hardware-notch geometry.
    var islandCollapsedReferenceHeight: Double = 32
    var islandAttachment: IslandAttachment {
        islandDisplayGeometry?.attachment ?? .floatingCapsule
    }
    var islandHardwareNotchWidth: Double {
        islandDisplayGeometry?.hardwareNotchWidth ?? 0
    }
    /// Transient capability reported after the Island panel installs its
    /// five active-appearance overrides; this is never persisted.
    var islandActiveAppearanceOverrideAvailable = false
    var lastMusicScan: Date? { musicLibrary.scanState.lastCompletedAt }
    var musicLibraryError: String?
    var musicLibraryNotice: String?
    var currentTrackTitle: String {
        playback.currentItem?.title ?? String(localized: "player.nothingPlaying")
    }
    var isGoogleCalendarConfigured: Bool { googleOAuthConfiguration.isConfigured }

    private let folderStore = SecurityScopedFolderStore()
    private let artworkCache = ArtworkCache()
    private let playbackController = PlaybackController(engine: SystemAudioEngine())
    private let playbackStateStore = PlaybackStateStore()
    private let favoritesStore = FavoritesStore()
    private let nowPlayingCenter = SystemNowPlayingCenter()
    private let googleOAuthConfiguration: GoogleOAuthConfiguration
    private let googleOAuthClient: GoogleOAuthClient
    private let calendarSyncService: GoogleCalendarSyncService
    private let indexStore: MusicIndexStore?
    private var activeMusicFolders: [URL] = []
    private var playbackObservationTask: Task<Void, Never>?
    private var systemCommandTask: Task<Void, Never>?
    private var calendarRefreshTask: Task<Void, Never>?
    private var activeOAuthServer: LoopbackOAuthServer?
    private var lastPersistedPlaybackState: PersistedPlaybackState?
    private var musicScanTask: Task<Void, Never>?
    private var currentArtworkTrackID: UUID?

    init() {
        let islandPreference = UserDefaults.standard.object(forKey: "island.enabled") as? Bool
        isIslandEnabled = islandPreference ?? true
        glassTint = UserDefaults.standard.object(forKey: "glass.tint") as? Double ?? 0
        if let savedBackingLevel = UserDefaults.standard.object(forKey: "glass.backingLevel") as? Int {
            glassBackingLevel = GlassBackingLevel(rawValue: savedBackingLevel) ?? .light
        } else if let legacyBlur = UserDefaults.standard.object(forKey: "glass.blur") as? Double {
            glassBackingLevel = GlassBackingLevel(migratingLegacyBlur: legacyBlur)
        } else {
            glassBackingLevel = .clear
        }
        let persistedRefraction = UserDefaults.standard.object(forKey: "glass.refraction") as? Double
        let migratedRefraction: Double
        if let persistedRefraction {
            migratedRefraction = min(max(
                persistedRefraction > 6
                    ? (persistedRefraction / 160 * 6).rounded()
                    : persistedRefraction,
                0
            ), 6)
            if persistedRefraction > 6 {
                UserDefaults.standard.set(migratedRefraction, forKey: "glass.refraction")
            }
        } else {
            migratedRefraction = 6
        }
        glassRefraction = migratedRefraction
        glassMotionEnabled = UserDefaults.standard.object(forKey: "glass.motion") as? Bool ?? true
        privateRefractionEnabled = UserDefaults.standard.object(forKey: "glass.privateRefractionEnabled") as? Bool ?? true
        preferredIslandDisplayID = UserDefaults.standard.string(forKey: "island.preferredDisplayID")
        let clientID = Bundle.main.object(forInfoDictionaryKey: "LockTuneGoogleClientID") as? String ?? ""
        let clientSecret = Bundle.main.object(forInfoDictionaryKey: "LockTuneGoogleClientSecret") as? String ?? ""
        let oauthConfiguration = GoogleOAuthConfiguration(clientID: clientID, clientSecret: clientSecret)
        googleOAuthConfiguration = oauthConfiguration
        googleOAuthClient = GoogleOAuthClient(configuration: oauthConfiguration)
        calendarSyncService = GoogleCalendarSyncService(oauthConfiguration: oauthConfiguration)
        do {
            indexStore = try MusicIndexStore()
        } catch {
            indexStore = nil
            musicLibraryError = String(localized: "library.error.indexUnavailable")
        }
    }

    func restoreCalendar() async {
        do {
            let localState = try await calendarSyncService.loadLocalState()
            calendarSnapshot = localState.snapshot
            selectedCalendarIDs = localState.selectedCalendarIDs
            guard try await calendarSyncService.hasStoredAuthorization() else {
                calendarConnectionState = .disconnected
                return
            }
            calendarConnectionState = .connected
            await syncCalendar(forceFull: true)
            startCalendarRefreshLoopIfNeeded()
        } catch {
            calendarConnectionState = .disconnected
            calendarError = String(localized: "calendar.error.restore")
        }
    }

    func connectGoogleCalendar() async {
        guard googleOAuthConfiguration.isConfigured else {
            calendarError = String(localized: "calendar.error.notConfigured")
            return
        }
        guard calendarConnectionState != .connecting else { return }
        calendarConnectionState = .connecting
        calendarError = nil
        let server = LoopbackOAuthServer()
        activeOAuthServer = server
        defer { activeOAuthServer = nil }
        do {
            let redirectURL = try await server.start()
            let verifier = GoogleOAuthPKCE.makeVerifier()
            let state = GoogleOAuthPKCE.makeState()
            guard let authorizationURL = googleOAuthConfiguration.authorizationURL(
                redirectURI: redirectURL.absoluteString,
                state: state,
                codeChallenge: GoogleOAuthPKCE.codeChallenge(for: verifier)
            ) else { throw GoogleOAuthError.missingConfiguration }
            guard NSWorkspace.shared.open(authorizationURL) else {
                throw GoogleOAuthError.authorizationDenied
            }
            let callbackURL = try await server.waitForCallback()
            let code = try GoogleOAuthCallback.authorizationCode(from: callbackURL, expectedState: state)
            let token = try await googleOAuthClient.exchangeCode(
                code,
                verifier: verifier,
                redirectURI: redirectURL.absoluteString
            )
            try await calendarSyncService.storeAuthorization(token)
            calendarConnectionState = .connected
            await syncCalendar(forceFull: true)
            startCalendarRefreshLoopIfNeeded()
        } catch is CancellationError {
            calendarConnectionState = .disconnected
            calendarError = nil
        } catch {
            await server.stop()
            calendarConnectionState = .disconnected
            calendarError = String(localized: "calendar.error.authorization")
        }
    }

    func cancelGoogleConnection() async {
        guard calendarConnectionState == .connecting else { return }
        await activeOAuthServer?.cancel()
    }

    func disconnectGoogleCalendar() async {
        do {
            try await calendarSyncService.disconnect()
            calendarConnectionState = .disconnected
            calendarSnapshot = CalendarSnapshot()
            selectedCalendarIDs = []
            calendarError = nil
            calendarRefreshTask?.cancel()
            calendarRefreshTask = nil
        } catch {
            if calendarConnectionState != .disconnected {
                calendarConnectionState = .connected
            }
            calendarError = String(localized: "calendar.error.disconnect")
        }
    }

    func syncCalendar(forceFull: Bool = false) async {
        guard calendarConnectionState != .disconnected,
              calendarConnectionState != .connecting,
              calendarConnectionState != .syncing
        else { return }
        calendarConnectionState = .syncing
        calendarError = nil
        do {
            let result = try await calendarSyncService.sync(
                from: calendarSnapshot,
                selectedCalendarIDs: selectedCalendarIDs,
                forceFull: forceFull
            )
            calendarSnapshot = result.snapshot
            selectedCalendarIDs = result.selectedCalendarIDs
            calendarConnectionState = .connected
        } catch {
            await handleCalendarSyncFailure(error)
        }
    }

    var upcomingTimedEvents: [CalendarEvent] {
        let now = Date()
        return calendarSnapshot.events
            .filter { !$0.isAllDay && $0.end > now }
            .sorted { $0.start < $1.start }
    }

    var nextMeeting: CalendarEvent? { upcomingTimedEvents.first }

    var islandPresentation: IslandPresentation {
        islandCoordinator.presentation(for: IslandContext(
            hasCurrentTrack: playback.currentItem != nil,
            minutesUntilMeeting: nextMeeting.map {
                max(0, Int(ceil($0.start.timeIntervalSinceNow / 60)))
            }
        ))
    }

    func toggleCalendarSelection(_ calendarID: String) async {
        guard calendarSnapshot.calendars.contains(where: { $0.id == calendarID }) else { return }
        if selectedCalendarIDs.contains(calendarID) {
            guard selectedCalendarIDs.count > 1 else { return }
            selectedCalendarIDs.remove(calendarID)
        } else {
            selectedCalendarIDs.insert(calendarID)
        }
        await calendarSyncService.saveSelection(selectedCalendarIDs)
        await syncCalendar(forceFull: true)
    }

    func restoreMusicLibrary() async {
        let persistedPlayback = try? await playbackStateStore.load()
        favoriteTrackIDs = await favoritesStore.load()
        defer { observePlaybackIfNeeded() }
        do {
            let resolution = folderStore.resolveAll()
            musicFolders = resolution.urls
            refreshMusicFolderAccess(resolution.urls)
            guard let indexStore else {
                musicLibraryError = String(localized: "library.error.indexUnavailable")
                return
            }
            musicLibrary = try await indexStore.load()
            if resolution.urls.isEmpty, resolution.failedBookmarkCount == 0 {
                musicLibrary = MusicLibrarySnapshot()
                try await indexStore.save(musicLibrary)
            }
            if resolution.failedBookmarkCount > 0 {
                musicLibraryError = String(localized: "library.error.someFoldersUnavailable")
            }
            if let persistedPlayback {
                let availableLocations = Set(musicLibrary.locations.map(\.id))
                let currentLocationID = persistedPlayback.currentIndex.flatMap {
                    persistedPlayback.queue.indices.contains($0) ? persistedPlayback.queue[$0].locationID : nil
                }
                let queue = persistedPlayback.queue.filter { availableLocations.contains($0.locationID) }
                let restored = PersistedPlaybackState(
                    queue: queue,
                    currentIndex: currentLocationID.flatMap { id in queue.firstIndex(where: { $0.locationID == id }) },
                    volume: persistedPlayback.volume,
                    order: persistedPlayback.order,
                    repeatMode: persistedPlayback.repeatMode
                )
                await playbackController.restore(restored)
            }
        } catch {
            musicLibraryError = String(localized: "library.error.restore")
        }
    }

    func chooseMusicFolder() async {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "library.addFolder")
        guard panel.runModal() == .OK else { return }
        do {
            let selectedFolders = panel.urls.map(\.standardizedFileURL)
            let existingFolders = Set(folderStore.resolveAll().urls.map(\.standardizedFileURL))
            let newlyAuthorizedFolders = selectedFolders.filter {
                !existingFolders.contains($0.standardizedFileURL)
            }
            for url in selectedFolders { try folderStore.add(url) }
            let resolution = folderStore.resolveAll()
            musicFolders = resolution.urls
            refreshMusicFolderAccess(resolution.urls)
            guard !newlyAuthorizedFolders.isEmpty else { return }
            await scanMusicFolders(folderURLs: newlyAuthorizedFolders)
        } catch {
            musicLibraryError = String(localized: "library.error.authorization")
        }
    }

    func scanMusicFolders() async {
        await scanMusicFolders(folderURLs: nil)
    }

    func cancelMusicScan() {
        musicScanTask?.cancel()
    }

    func removeMusicFolder(_ folder: URL) async {
        cancelMusicScan()
        await musicScanTask?.value
        folderStore.remove(folder)
        await applyFolderRemoval()
    }

    func clearMusicFolders() async {
        cancelMusicScan()
        await musicScanTask?.value
        folderStore.removeAll()
        await applyFolderRemoval()
    }

    func loadArtworkData(for trackID: UUID?) async -> Data? {
        guard let trackID,
              let track = musicLibrary.tracks.first(where: { $0.id == trackID })
        else { return nil }
        if let data = track.metadata.artworkData, !data.isEmpty {
            return data
        }
        guard let key = track.metadata.artworkCacheKey else { return nil }
        return try? await artworkCache.data(for: key)
    }

    private func scanMusicFolders(folderURLs: [URL]?) async {
        guard !isScanningMusic else { return }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await performMusicScan(folderURLs: folderURLs)
        }
        musicScanTask = task
        await task.value
        musicScanTask = nil
    }

    private func performMusicScan(folderURLs requestedFolders: [URL]?) async {
        guard let indexStore else {
            musicLibraryError = String(localized: "library.error.indexUnavailable")
            return
        }
        isScanningMusic = true
        musicScanProgress = MusicScanProgress(phase: .discovering, completed: 0, total: 0)
        musicLibraryError = nil
        musicLibraryNotice = nil
        defer {
            isScanningMusic = false
            musicScanProgress = nil
        }
        do {
            let resolution = folderStore.resolveAll()
            let folders = resolution.urls
            musicFolders = folders
            if Set(folders.map(\.standardizedFileURL)) != Set(musicFoldersWithActiveAccess.map(\.standardizedFileURL)) {
                refreshMusicFolderAccess(folders)
            }
            let accessibleFolders = musicFoldersWithActiveAccess
            let scanFolders: [URL]
            if let requestedFolders {
                let requested = Set(requestedFolders.map(\.standardizedFileURL))
                scanFolders = accessibleFolders.filter { requested.contains($0.standardizedFileURL) }
            } else {
                scanFolders = accessibleFolders
            }
            guard !folders.isEmpty, !scanFolders.isEmpty else {
                musicLibraryError = String(localized: "library.error.authorization")
                return
            }
            var snapshot = await MusicLibraryScanner(metadataReader: SystemAudioMetadataReader())
                .scan(folderURLs: scanFolders, previous: musicLibrary) { [weak self] progress in
                    await MainActor.run {
                        self?.musicScanProgress = progress
                    }
                }
            guard !Task.isCancelled else { return }
            musicScanProgress = MusicScanProgress(
                phase: .artwork,
                completed: 0,
                total: snapshot.tracks.count
            )
            var lastArtworkProgress = ContinuousClock.now
            for index in snapshot.tracks.indices {
                guard !Task.isCancelled else { return }
                snapshot.tracks[index] = try await artworkCache.persistArtwork(in: snapshot.tracks[index])
                let now = ContinuousClock.now
                if index + 1 == snapshot.tracks.count
                    || lastArtworkProgress.duration(to: now) >= .milliseconds(120) {
                    musicScanProgress = MusicScanProgress(
                        phase: .artwork,
                        completed: index + 1,
                        total: snapshot.tracks.count
                    )
                    lastArtworkProgress = now
                }
            }
            guard !Task.isCancelled else { return }
            snapshot.scanState.lastCompletedAt = Date()
            musicScanProgress = MusicScanProgress(phase: .saving, completed: 0, total: 1)
            try await indexStore.save(snapshot)
            musicScanProgress = MusicScanProgress(phase: .saving, completed: 1, total: 1)
            musicLibrary = snapshot
            await refreshCurrentArtwork()
            if resolution.failedBookmarkCount > 0 || accessibleFolders.count != folders.count {
                musicLibraryError = String(localized: "library.error.someFoldersUnavailable")
            }
        } catch {
            musicLibraryError = String(localized: "library.error.scan")
        }
    }

    private func applyFolderRemoval() async {
        let resolution = folderStore.resolveAll()
        musicFolders = resolution.urls
        refreshMusicFolderAccess(resolution.urls)
        let snapshot = musicLibrary.retainingAuthorizedRoots(resolution.urls)
        do {
            try await indexStore?.save(snapshot)
            musicLibrary = snapshot
            await prunePlaybackForAvailableLocations()
            await refreshCurrentArtwork()
            musicLibraryError = resolution.failedBookmarkCount > 0
                ? String(localized: "library.error.someFoldersUnavailable")
                : nil
        } catch {
            musicLibraryError = String(localized: "library.error.scan")
        }
    }

    private func prunePlaybackForAvailableLocations() async {
        let availableLocations = Set(musicLibrary.locations.map(\.id))
        let currentLocationID = playback.currentItem?.locationID
        let queue = playback.queue.filter { availableLocations.contains($0.locationID) }
        let currentIndex = currentLocationID.flatMap { id in
            queue.firstIndex(where: { $0.locationID == id })
        }
        await playbackController.restore(PersistedPlaybackState(
            queue: queue,
            currentIndex: currentIndex,
            volume: playback.volume,
            order: playback.order,
            repeatMode: playback.repeatMode
        ))
    }

    private func refreshCurrentArtwork() async {
        currentArtworkTrackID = playback.currentItem?.trackID
        currentArtworkData = await loadArtworkData(for: currentArtworkTrackID)
        nowPlayingCenter.update(playback, artworkData: currentArtworkData)
    }

    func play(trackID: UUID) async {
        let items = playbackItems
        guard let index = items.firstIndex(where: { $0.trackID == trackID }) else { return }
        await playbackController.replaceQueue(items, startingAt: index)
    }

    func playQueueItem(at index: Int) async {
        guard playback.queue.indices.contains(index) else { return }
        await playbackController.replaceQueue(playback.queue, startingAt: index)
    }

    func togglePlayPause() async { await playbackController.togglePlayPause() }
    func playNext() async { await playbackController.next() }
    func playPrevious() async { await playbackController.previous() }
    func seek(to seconds: TimeInterval) async { await playbackController.seek(to: seconds) }
    func setVolume(_ volume: Float) async { await playbackController.setVolume(volume) }
    func setPlaybackOrder(_ order: PlaybackOrder) async { await playbackController.setOrder(order) }
    func setRepeatMode(_ mode: PlaybackRepeatMode) async { await playbackController.setRepeatMode(mode) }
    func retryPlayback() async { await playbackController.retry() }

    func canRepairMusicMetadata() -> Bool {
        musicLibrary.tracks.contains { FilenameMetadataRepair.needsRepair($0.metadata) }
    }

    func repairMusicMetadata() async {
        guard !isScanningMusic else { return }
        musicLibraryError = nil
        musicLibraryNotice = nil
        let writer = MP3TitleWriter()
        var suspectTracks = 0
        var repairedTracks = 0
        var repairedFields = 0
        var writtenFiles = 0
        var pendingNonMP3Files = 0
        var failedFiles = 0
        var unresolvedTracks = 0

        for index in musicLibrary.tracks.indices {
            let original = musicLibrary.tracks[index]
            guard FilenameMetadataRepair.needsRepair(original.metadata) else { continue }
            suspectTracks += 1
            let locations = musicLibrary.locations.filter { $0.trackID == original.id }
            let mp3Locations = locations.filter { $0.format == .mp3 }
            guard !mp3Locations.isEmpty else {
                pendingNonMP3Files += max(locations.count, 1)
                continue
            }
            let suggestion = FilenameMetadataRepair.suggestion(for: mp3Locations[0].url, metadata: original.metadata)
            let title = FilenameMetadataRepair.isUnknownOrGarbled(original.metadata.title) ? suggestion.title : nil
            let artist = FilenameMetadataRepair.isUnknownOrGarbled(original.metadata.artist) ? suggestion.artist : nil
            let album = FilenameMetadataRepair.isUnknownOrGarbled(original.metadata.album) ? suggestion.album : nil
            guard title != nil || artist != nil || album != nil else {
                unresolvedTracks += 1
                continue
            }
            var writtenForTrack = 0
            for location in mp3Locations {
                do {
                    try writer.writeMetadata(title: title, artist: artist, album: album, to: location.url)
                    writtenFiles += 1
                    writtenForTrack += 1
                } catch {
                    failedFiles += 1
                }
            }
            guard writtenForTrack > 0 else {
                unresolvedTracks += 1
                continue
            }
            var track = original
            if let title { track.metadata.title = title; repairedFields += 1 }
            if let artist { track.metadata.artist = artist; repairedFields += 1 }
            if let album { track.metadata.album = album; repairedFields += 1 }
            if track.metadata.status == .unavailable { track.metadata.status = .partial }
            musicLibrary.tracks[index] = track
            repairedTracks += 1
        }

        do {
            if repairedTracks > 0, let indexStore { try await indexStore.save(musicLibrary) }
            var message = "已检查 \(suspectTracks) 个异常文件；MP3 修复 \(repairedTracks) 个，写回 \(writtenFiles) 个文件，更新 \(repairedFields) 项信息。"
            if pendingNonMP3Files > 0 { message += " \(pendingNonMP3Files) 个非 MP3 文件待确认修复方案。" }
            if failedFiles > 0 { message += " \(failedFiles) 个文件写回失败。" }
            if unresolvedTracks > 0 { message += " \(unresolvedTracks) 个文件无法从文件名或目录安全推断。" }
            musicLibraryNotice = message
        } catch {
            musicLibraryError = "保存修复结果失败：\(error.localizedDescription)"
        }
    }

    func toggleFavorite(trackID: UUID) async {
        if favoriteTrackIDs.contains(trackID) {
            favoriteTrackIDs.remove(trackID)
        } else {
            favoriteTrackIDs.insert(trackID)
        }
        await favoritesStore.save(favoriteTrackIDs)
    }

    func setIslandEnabled(_ enabled: Bool) {
        isIslandEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "island.enabled")
    }

    func setPreferredIslandDisplayID(_ displayID: String?) {
        preferredIslandDisplayID = displayID
        if let displayID {
            UserDefaults.standard.set(displayID, forKey: "island.preferredDisplayID")
        } else {
            UserDefaults.standard.removeObject(forKey: "island.preferredDisplayID")
        }
    }

    func updateIslandDisplayEnvironment(
        displays: [IslandDisplay],
        geometry: IslandDisplayGeometry
    ) {
        availableIslandDisplays = displays
        islandDisplayGeometry = geometry
        if geometry.hardwareNotchHeight > 0 {
            islandCollapsedReferenceHeight = geometry.hardwareNotchHeight
        }
    }

    func setIslandActiveAppearanceOverrideAvailable(_ available: Bool) {
        islandActiveAppearanceOverrideAvailable = available
    }

    func setGlassTint(_ value: Double) {
        glassTint = value
        UserDefaults.standard.set(value, forKey: "glass.tint")
    }

    func setGlassBackingLevel(_ level: GlassBackingLevel) {
        glassBackingLevel = level
        UserDefaults.standard.set(level.rawValue, forKey: "glass.backingLevel")
    }

    func setGlassRefraction(_ value: Double) {
        glassRefraction = min(max(value.rounded(), 0), 6)
        UserDefaults.standard.set(glassRefraction, forKey: "glass.refraction")
    }

    func setGlassMotionEnabled(_ enabled: Bool) {
        glassMotionEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "glass.motion")
    }

    func setPrivateRefractionEnabled(_ enabled: Bool) {
        privateRefractionEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "glass.privateRefractionEnabled")
    }

    func setLiquidGlassRuntimeMode(_ mode: LiquidGlassRuntimeMode) {
        guard liquidGlassRuntimeMode != mode else { return }
        liquidGlassRuntimeMode = mode
    }

    func resumeAfterWake() async {
        await playbackController.resumeAfterWake()
        if calendarConnectionState != .disconnected { await syncCalendar(forceFull: true) }
    }

    func artworkData(for trackID: UUID?) -> Data? {
        guard let trackID, currentArtworkTrackID == trackID else { return nil }
        return currentArtworkData
    }

    private var playbackItems: [PlaybackItem] {
        let locationsByTrack = Dictionary(grouping: musicLibrary.locations, by: \.trackID)
        return musicLibrary.tracks
            .sorted {
                ($0.metadata.title ?? "").localizedStandardCompare($1.metadata.title ?? "") == .orderedAscending
            }
            .compactMap { track in
                guard let location = locationsByTrack[track.id]?.first else { return nil }
                return PlaybackItem(
                    trackID: track.id,
                    locationID: location.id,
                    url: location.url,
                    title: track.metadata.title ?? String(localized: "library.unknownTitle"),
                    artist: track.metadata.artist,
                    album: track.metadata.album,
                    duration: track.metadata.duration
                )
            }
    }

    private var musicFoldersWithActiveAccess: [URL] { activeMusicFolders }

    private func refreshMusicFolderAccess(_ folders: [URL]) {
        for url in activeMusicFolders { url.stopAccessingSecurityScopedResource() }
        activeMusicFolders = folders.filter { $0.startAccessingSecurityScopedResource() }
    }

    private func observePlaybackIfNeeded() {
        guard playbackObservationTask == nil else { return }
        observeSystemCommandsIfNeeded()
        let controller = playbackController
        playbackObservationTask = Task { @MainActor [weak self] in
            let updates = await controller.updates()
            for await snapshot in updates {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                playback = snapshot
                if currentArtworkTrackID != snapshot.currentItem?.trackID {
                    currentArtworkTrackID = snapshot.currentItem?.trackID
                    currentArtworkData = await loadArtworkData(for: currentArtworkTrackID)
                }
                nowPlayingCenter.update(snapshot, artworkData: currentArtworkData)
                let persisted = PersistedPlaybackState(snapshot: snapshot)
                if persisted != lastPersistedPlaybackState {
                    try? await playbackStateStore.save(persisted)
                    lastPersistedPlaybackState = persisted
                }
            }
        }
    }

    private func observeSystemCommandsIfNeeded() {
        guard systemCommandTask == nil else { return }
        let commands = nowPlayingCenter.commands()
        systemCommandTask = Task { @MainActor [weak self] in
            for await command in commands {
                guard let self, !Task.isCancelled else { return }
                switch command {
                case .play:
                    if playback.phase == .paused || playback.phase == .idle { await togglePlayPause() }
                case .pause:
                    if playback.phase == .playing { await togglePlayPause() }
                case .next: await playNext()
                case .previous: await playPrevious()
                case let .seek(position): await seek(to: position)
                }
            }
        }
    }

    private func startCalendarRefreshLoopIfNeeded() {
        guard calendarRefreshTask == nil, calendarConnectionState == .connected else { return }
        calendarRefreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                guard let self, !Task.isCancelled else { return }
                await syncCalendar()
            }
        }
    }

    private func handleCalendarSyncFailure(_ error: Error) async {
        if requiresCalendarReconnect(error) {
            try? await calendarSyncService.deleteAuthorization()
            calendarConnectionState = .disconnected
            calendarError = String(localized: "calendar.error.authorizationExpired")
            calendarRefreshTask?.cancel()
            calendarRefreshTask = nil
        } else {
            calendarConnectionState = .connected
            calendarError = calendarSyncErrorMessage(for: error)
        }
    }

    private func requiresCalendarReconnect(_ error: Error) -> Bool {
        if GoogleAuthorizationFailure.requiresReconnect(error) { return true }
        guard let syncError = error as? GoogleCalendarSyncServiceError else { return false }
        if case .missingAuthorization = syncError { return true }
        return false
    }

    private func calendarSyncErrorMessage(for error: Error) -> String {
        if error is URLError {
            return String(localized: "calendar.error.network")
        }
        if let calendarError = error as? GoogleCalendarClientError {
            switch calendarError {
            case let .server(statusCode) where statusCode == 403:
                return String(localized: "calendar.error.permission")
            case let .server(statusCode) where statusCode == 429:
                return String(localized: "calendar.error.rateLimited")
            case let .server(statusCode) where statusCode >= 500:
                return String(localized: "calendar.error.service")
            case .invalidResponse:
                return String(localized: "calendar.error.invalidResponse")
            case .invalidRequest, .unauthorized, .server:
                break
            }
        }
        if let oauthError = error as? GoogleOAuthError,
           case let .tokenRequestFailed(statusCode) = oauthError,
           statusCode >= 500 {
            return String(localized: "calendar.error.service")
        }
        return String(localized: "calendar.error.sync")
    }
}
