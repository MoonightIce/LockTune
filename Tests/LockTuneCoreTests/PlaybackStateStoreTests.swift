import Foundation
import Testing
import LockTuneDomain
import LockTuneInfrastructure

@Test("Playback queue and modes survive a local state round trip")
func playbackStateRoundTrip() async throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "LockTunePlaybackStateTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PlaybackStateStore(directoryURL: root)
    let item = PlaybackItem(
        trackID: UUID(),
        locationID: "location",
        url: URL(fileURLWithPath: "/Music/Test.flac"),
        title: "Test"
    )
    let snapshot = PlaybackSnapshot(
        queue: [item],
        currentIndex: 0,
        volume: 0.5,
        order: .shuffled,
        repeatMode: .all
    )

    try await store.save(snapshot)
    let restored = try #require(try await store.load())

    #expect(restored.queue == [item])
    #expect(restored.currentIndex == 0)
    #expect(restored.volume == 0.5)
    #expect(restored.order == .shuffled)
    #expect(restored.repeatMode == .all)
}
