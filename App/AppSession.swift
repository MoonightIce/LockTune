import AppKit
import Observation
import LockTuneCore
import LockTuneDomain
import LockTuneInfrastructure

@MainActor
@Observable
final class AppSession {
    let islandCoordinator = IslandCoordinator()
    var currentTrackTitle = String(localized: "player.nothingPlaying")
    var nextMeetingTitle: String?
    var musicLibrary = MusicLibrarySnapshot()
    var musicFolders: [URL] = []
    var isScanningMusic = false
    var lastMusicScan: Date? { musicLibrary.scanState.lastCompletedAt }
    var musicLibraryError: String?

    private let folderStore = SecurityScopedFolderStore()
    private let artworkCache = ArtworkCache()
    private let indexStore: MusicIndexStore?

    init() {
        do {
            indexStore = try MusicIndexStore()
        } catch {
            indexStore = nil
            musicLibraryError = String(localized: "library.error.indexUnavailable")
        }
    }

    func restoreMusicLibrary() async {
        do {
            let resolution = folderStore.resolveAll()
            musicFolders = resolution.urls
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
            musicFolders = folderStore.resolveAll().urls
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
            let activeAccess = folders.map { ($0, $0.startAccessingSecurityScopedResource()) }
            defer {
                for (url, started) in activeAccess where started {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let accessibleFolders = activeAccess.compactMap { url, started in started ? url : nil }
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
}
