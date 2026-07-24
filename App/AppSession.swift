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
    var lastMusicScan: Date?
    var musicLibraryError: String?

    private let folderStore = SecurityScopedFolderStore()
    private let artworkCache = ArtworkCache()
    private let indexStore: MusicIndexStore?

    init() {
        indexStore = try? MusicIndexStore()
    }

    func restoreMusicLibrary() async {
        do {
            musicFolders = try folderStore.resolveAll()
            if let indexStore {
                musicLibrary = try await indexStore.load()
                for index in musicLibrary.tracks.indices {
                    guard let key = musicLibrary.tracks[index].metadata.artworkCacheKey else { continue }
                    musicLibrary.tracks[index].metadata.artworkData = try? await artworkCache.data(for: key)
                }
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
            musicFolders = try folderStore.resolveAll()
            await scanMusicFolders()
        } catch {
            musicLibraryError = String(localized: "library.error.authorization")
        }
    }

    func scanMusicFolders() async {
        guard !isScanningMusic else { return }
        isScanningMusic = true
        musicLibraryError = nil
        defer { isScanningMusic = false }
        do {
            let folders = try folderStore.resolveAll()
            musicFolders = folders
            let activeAccess = folders.map { ($0, $0.startAccessingSecurityScopedResource()) }
            defer {
                for (url, started) in activeAccess where started {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let previous = musicLibrary
            var snapshot = await Task.detached(priority: .userInitiated) {
                await MusicLibraryScanner(metadataReader: SystemAudioMetadataReader())
                    .scan(folderURLs: folders, previous: previous)
            }.value
            for index in snapshot.tracks.indices {
                snapshot.tracks[index] = try await artworkCache.persistArtwork(in: snapshot.tracks[index])
            }
            if let indexStore { try await indexStore.save(snapshot) }
            musicLibrary = snapshot
            lastMusicScan = Date()
        } catch {
            musicLibraryError = String(localized: "library.error.scan")
        }
    }
}
