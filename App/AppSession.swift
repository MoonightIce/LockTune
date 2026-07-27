import AppKit
import Observation
import LockTuneCore
import LockTuneDomain
import LockTuneInfrastructure

@MainActor
@Observable
final class AppSession {
    let islandCoordinator = IslandCoordinator()
    var nextMeetingTitle: String?
    var musicLibrary = MusicLibrarySnapshot()
    var musicFolders: [URL] = []
    var playback = PlaybackSnapshot()
    var isScanningMusic = false
    var lastMusicScan: Date? { musicLibrary.scanState.lastCompletedAt }
    var musicLibraryError: String?
    var currentTrackTitle: String {
        playback.currentItem?.title ?? String(localized: "player.nothingPlaying")
    }

    private let folderStore = SecurityScopedFolderStore()
    private let artworkCache = ArtworkCache()
    private let playbackController = PlaybackController(engine: SystemAudioEngine())
    private let nowPlayingCenter = SystemNowPlayingCenter()
    private let indexStore: MusicIndexStore?
    private var activeMusicFolders: [URL] = []
    private var playbackObservationTask: Task<Void, Never>?
    private var systemCommandTask: Task<Void, Never>?

    init() {
        do {
            indexStore = try MusicIndexStore()
        } catch {
            indexStore = nil
            musicLibraryError = String(localized: "library.error.indexUnavailable")
        }
    }

    func restoreMusicLibrary() async {
        observePlaybackIfNeeded()
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
    func retryPlayback() async { await playbackController.retry() }
    func resumePlaybackAfterWake() async { await playbackController.resumeAfterWake() }

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
                    if playback.phase == .paused { await togglePlayPause() }
                case .pause:
                    if playback.phase == .playing { await togglePlayPause() }
                case .next: await playNext()
                case .previous: await playPrevious()
                case let .seek(position): await seek(to: position)
                }
            }
        }
    }
}
