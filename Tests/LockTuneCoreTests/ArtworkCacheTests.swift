import Foundation
import Testing
import LockTuneDomain
import LockTuneInfrastructure

@Test("Artwork cache stores bytes separately and returns a persistent key")
func persistsArtworkSeparately() async throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let artwork = Data([1, 2, 3, 4])
    let track = Track(
        contentFingerprint: "abc123",
        metadata: TrackMetadata(artworkData: artwork, status: .partial)
    )
    let cache = ArtworkCache(rootURL: root)

    let updated = try await cache.persistArtwork(in: track)

    let key = try #require(updated.metadata.artworkCacheKey)
    #expect(try await cache.data(for: key) == artwork)
}
