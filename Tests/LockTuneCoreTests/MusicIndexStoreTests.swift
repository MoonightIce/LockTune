import Foundation
import Testing
import LockTuneDomain
import LockTuneInfrastructure

@Test("SwiftData music index round-trips tracks and locations")
func roundTripsMusicIndex() async throws {
    let track = IndexedTrack(
        id: UUID(),
        contentFingerprint: "fingerprint",
        metadata: TrackMetadata(
            title: "Title",
            artist: "Artist",
            album: "Album",
            trackNumber: 3,
            duration: 42,
            artworkCacheKey: "artwork-key",
            status: .complete
        )
    )
    let location = TrackLocation(
        trackID: track.id,
        url: URL(fileURLWithPath: "/Music/Title.flac"),
        format: .flac,
        fileSize: 1_024,
        contentModificationDate: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let expected = MusicLibrarySnapshot(tracks: [track], locations: [location])
    let store = try MusicIndexStore(inMemory: true)

    try await store.save(expected)
    let loaded = try await store.load()

    #expect(loaded == expected)
}
