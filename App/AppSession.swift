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
    private let calendarSyncService: GoogleCalendarSyncService
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
