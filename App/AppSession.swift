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
    case failed
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
    var isIslandEnabled: Bool
    var lastMusicScan: Date? { musicLibrary.scanState.lastCompletedAt }
    var musicLibraryError: String?
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
    private let googleTokenStore = GoogleOAuthTokenStore()
    private let googleCalendarClient = GoogleCalendarClient()
    private let calendarCache = CalendarCache()
    private let calendarSelectionStore = CalendarSelectionStore()
    private let indexStore: MusicIndexStore?
    private var activeMusicFolders: [URL] = []
    private var playbackObservationTask: Task<Void, Never>?
    private var systemCommandTask: Task<Void, Never>?
    private var calendarRefreshTask: Task<Void, Never>?
    private var activeOAuthServer: LoopbackOAuthServer?
    private var lastPersistedPlaybackState: PersistedPlaybackState?

    init() {
        let islandPreference = UserDefaults.standard.object(forKey: "island.enabled") as? Bool
        isIslandEnabled = islandPreference ?? true
        let clientID = Bundle.main.object(forInfoDictionaryKey: "LockTuneGoogleClientID") as? String ?? ""
        let oauthConfiguration = GoogleOAuthConfiguration(clientID: clientID)
        googleOAuthConfiguration = oauthConfiguration
        googleOAuthClient = GoogleOAuthClient(configuration: oauthConfiguration)
        do {
            indexStore = try MusicIndexStore()
        } catch {
            indexStore = nil
            musicLibraryError = String(localized: "library.error.indexUnavailable")
        }
    }

    func restoreCalendar() async {
        calendarSnapshot = (try? await calendarCache.load()) ?? CalendarSnapshot()
        selectedCalendarIDs = await calendarSelectionStore.load()
        do {
            guard try await googleTokenStore.load() != nil else {
                calendarConnectionState = .disconnected
                return
            }
            calendarConnectionState = .connected
            await syncCalendar(forceFull: true)
            startCalendarRefreshLoopIfNeeded()
        } catch {
            calendarConnectionState = .failed
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
            try await googleTokenStore.save(token)
            calendarConnectionState = .connected
            await syncCalendar(forceFull: true)
            startCalendarRefreshLoopIfNeeded()
        } catch is CancellationError {
            calendarConnectionState = .disconnected
            calendarError = nil
        } catch {
            await server.stop()
            calendarConnectionState = .failed
            calendarError = String(localized: "calendar.error.authorization")
        }
    }

    func cancelGoogleConnection() async {
        guard calendarConnectionState == .connecting else { return }
        await activeOAuthServer?.cancel()
    }

    func disconnectGoogleCalendar() async {
        do {
            try await googleTokenStore.delete()
            try await calendarCache.clear()
            await calendarSelectionStore.clear()
            calendarSnapshot = CalendarSnapshot()
            selectedCalendarIDs = []
            calendarConnectionState = .disconnected
            calendarError = nil
            calendarRefreshTask?.cancel()
            calendarRefreshTask = nil
        } catch {
            calendarConnectionState = .failed
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
            guard var token = try await googleTokenStore.load() else {
                calendarConnectionState = .disconnected
                return
            }
            if !token.isFresh() {
                token = try await googleOAuthClient.refresh(token)
                try await googleTokenStore.save(token)
            }
            let now = Date()
            let calendars = try await googleCalendarClient.calendars(accessToken: token.accessToken)
            let availableIDs = Set(calendars.map(\.id))
            selectedCalendarIDs.formIntersection(availableIDs)
            if selectedCalendarIDs.isEmpty, let defaultCalendar = calendars.first(where: \.isPrimary) ?? calendars.first {
                selectedCalendarIDs = [defaultCalendar.id]
            }
            await calendarSelectionStore.save(selectedCalendarIDs)

            let start = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
            let end = Calendar.current.date(byAdding: .day, value: 14, to: now) ?? now
            let syncStartedAt = Date()
            var events = calendarSnapshot.events.filter {
                guard let calendarID = $0.calendarID else { return false }
                return selectedCalendarIDs.contains(calendarID) && $0.end > start && $0.start < end
            }
            var cursors = calendarSnapshot.lastSyncByCalendarID.filter {
                selectedCalendarIDs.contains($0.key)
            }
            var fullSyncDates = calendarSnapshot.lastFullSyncByCalendarID.filter {
                selectedCalendarIDs.contains($0.key)
            }
            for calendar in calendars where selectedCalendarIDs.contains(calendar.id) {
                let lastFullSync = fullSyncDates[calendar.id]
                let fullSyncIsRecent = lastFullSync.map {
                    syncStartedAt.timeIntervalSince($0) < 6 * 60 * 60
                } ?? false
                if !forceFull, fullSyncIsRecent, let cursor = cursors[calendar.id] {
                    let changes = try await googleCalendarClient.eventChanges(
                        calendarID: calendar.id,
                        calendarTitle: calendar.title,
                        accessToken: token.accessToken,
                        updatedSince: cursor
                    )
                    for change in changes {
                        switch change {
                        case let .remove(id):
                            events.removeAll { $0.id == id }
                        case let .upsert(event):
                            events.removeAll { $0.id == event.id }
                            if event.end > start && event.start < end { events.append(event) }
                        }
                    }
                } else {
                    events.removeAll { $0.calendarID == calendar.id }
                    events.append(contentsOf: try await googleCalendarClient.events(
                        calendarID: calendar.id,
                        calendarTitle: calendar.title,
                        accessToken: token.accessToken,
                        from: start,
                        to: end
                    ))
                    fullSyncDates[calendar.id] = syncStartedAt
                }
                cursors[calendar.id] = syncStartedAt
            }
            events.sort { $0.start < $1.start }
            let snapshot = CalendarSnapshot(
                events: events,
                calendars: calendars,
                lastSyncByCalendarID: cursors,
                lastFullSyncByCalendarID: fullSyncDates,
                lastSuccessfulSync: Date()
            )
            try await calendarCache.save(snapshot)
            calendarSnapshot = snapshot
            calendarConnectionState = .connected
        } catch {
            calendarConnectionState = .failed
            calendarError = String(localized: "calendar.error.sync")
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
            isMusicPlaying: playback.phase == .playing,
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
        await calendarSelectionStore.save(selectedCalendarIDs)
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
            for index in musicLibrary.tracks.indices {
                guard let key = musicLibrary.tracks[index].metadata.artworkCacheKey else { continue }
                musicLibrary.tracks[index].metadata.artworkData = try? await artworkCache.data(for: key)
                if musicLibrary.tracks[index].metadata.artworkData == nil,
                   musicLibrary.tracks[index].metadata.status == .complete {
                    musicLibrary.tracks[index].metadata.status = .partial
                }
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
            for url in panel.urls { try folderStore.add(url) }
            let resolution = folderStore.resolveAll()
            musicFolders = resolution.urls
            refreshMusicFolderAccess(resolution.urls)
            await scanMusicFolders()
        } catch {
            musicLibraryError = String(localized: "library.error.authorization")
        }
    }

    func scanMusicFolders() async {
        guard !isScanningMusic else { return }
        guard let indexStore else {
            musicLibraryError = String(localized: "library.error.indexUnavailable")
            return
        }
        isScanningMusic = true
        musicLibraryError = nil
        defer { isScanningMusic = false }
        do {
            let resolution = folderStore.resolveAll()
            let folders = resolution.urls
            musicFolders = folders
            if Set(folders.map(\.standardizedFileURL)) != Set(musicFoldersWithActiveAccess.map(\.standardizedFileURL)) {
                refreshMusicFolderAccess(folders)
            }
            let accessibleFolders = musicFoldersWithActiveAccess
            guard !folders.isEmpty, !accessibleFolders.isEmpty else {
                musicLibraryError = String(localized: "library.error.authorization")
                return
            }
            var snapshot = await MusicLibraryScanner(metadataReader: SystemAudioMetadataReader())
                .scan(folderURLs: accessibleFolders, previous: musicLibrary)
            for index in snapshot.tracks.indices {
                snapshot.tracks[index] = try await artworkCache.persistArtwork(in: snapshot.tracks[index])
            }
            snapshot.scanState.lastCompletedAt = Date()
            try await indexStore.save(snapshot)
            musicLibrary = snapshot
            if resolution.failedBookmarkCount > 0 || accessibleFolders.count != folders.count {
                musicLibraryError = String(localized: "library.error.someFoldersUnavailable")
            }
        } catch {
            musicLibraryError = String(localized: "library.error.scan")
        }
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

    func resumeAfterWake() async {
        await playbackController.resumeAfterWake()
        if calendarConnectionState != .disconnected { await syncCalendar(forceFull: true) }
    }

    func artworkData(for trackID: UUID?) -> Data? {
        guard let trackID else { return nil }
        return musicLibrary.tracks.first(where: { $0.id == trackID })?.metadata.artworkData
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
                nowPlayingCenter.update(snapshot, artworkData: artworkData(for: snapshot.currentItem?.trackID))
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
        guard calendarRefreshTask == nil else { return }
        calendarRefreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                guard let self, !Task.isCancelled else { return }
                await syncCalendar()
            }
        }
    }
}
