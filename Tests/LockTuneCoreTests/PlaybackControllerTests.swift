import Foundation
import Testing
import LockTuneCore
import LockTuneDomain

@Test("Selecting a queue item loads it and starts playback")
func startsSelectedQueueItem() async throws {
    let engine = RecordingAudioEngine()
    let first = PlaybackItem(
        trackID: UUID(),
        locationID: "first",
        url: URL(fileURLWithPath: "/Music/First.flac"),
        title: "First",
        artist: "Artist",
        duration: 120
    )
    let second = PlaybackItem(
        trackID: UUID(),
        locationID: "second",
        url: URL(fileURLWithPath: "/Music/Second.ape"),
        title: "Second",
        duration: 90
    )
    let controller = PlaybackController(engine: engine)

    await controller.replaceQueue([first, second], startingAt: 1)

    let snapshot = await controller.snapshot()
    #expect(snapshot.queue == [first, second])
    #expect(snapshot.currentIndex == 1)
    #expect(snapshot.currentItem == second)
    #expect(snapshot.phase == .playing)
    #expect(await engine.loadedURLs == [second.url])
    #expect(await engine.playCount == 1)
}

@Test("Play pause toggles the current queue item")
func togglesPlayPause() async {
    let engine = RecordingAudioEngine()
    let item = makePlaybackItem(id: "only")
    let controller = PlaybackController(engine: engine)
    await controller.replaceQueue([item], startingAt: 0)

    await controller.togglePlayPause()
    #expect(await controller.snapshot().phase == .paused)
    #expect(await engine.pauseCount == 1)

    await controller.togglePlayPause()
    #expect(await controller.snapshot().phase == .playing)
    #expect(await engine.playCount == 2)
}

@Test("Previous and next move through the playback queue")
func movesThroughQueue() async {
    let engine = RecordingAudioEngine()
    let first = makePlaybackItem(id: "first")
    let second = makePlaybackItem(id: "second")
    let controller = PlaybackController(engine: engine)
    await controller.replaceQueue([first, second], startingAt: 0)

    #expect(await controller.snapshot().canAdvance == true)
    await controller.next()
    #expect(await controller.snapshot().currentItem == second)

    await controller.previous()
    #expect(await controller.snapshot().currentItem == first)
    #expect(await engine.loadedURLs == [first.url, second.url, first.url])
    #expect(await engine.playCount == 3)
}

@Test("Seeking and volume changes are clamped and forwarded")
func seeksAndChangesVolume() async {
    let engine = RecordingAudioEngine()
    let controller = PlaybackController(engine: engine)
    await controller.replaceQueue([makePlaybackItem(id: "only")], startingAt: 0)

    await controller.seek(to: 120)
    await controller.setVolume(1.5)

    #expect(await controller.snapshot().elapsed == 90)
    #expect(await controller.snapshot().volume == 1)
    #expect(await engine.seekPositions == [90])
    #expect(await engine.volumes == [1])
}

@Test("Progress updates and end events advance continuous playback")
func advancesAfterEngineEvents() async {
    let engine = RecordingAudioEngine()
    let first = makePlaybackItem(id: "first")
    let second = makePlaybackItem(id: "second")
    let controller = PlaybackController(engine: engine)
    await controller.replaceQueue([first, second], startingAt: 0)

    await engine.emit(.progress(elapsed: 12, duration: 90))
    #expect(await eventually { await controller.snapshot().elapsed == 12 })

    await engine.emit(.ended)
    #expect(await eventually {
        let snapshot = await controller.snapshot()
        return snapshot.currentItem == second && snapshot.phase == .playing
    })
}

@Test("An unplayable item exposes failure and can be retried")
func retriesUnplayableItem() async {
    let engine = RecordingAudioEngine()
    let item = makePlaybackItem(id: "broken")
    await engine.setLoadFailure(for: item.url, enabled: true)
    let controller = PlaybackController(engine: engine)

    await controller.replaceQueue([item], startingAt: 0)
    #expect(await controller.snapshot().phase == .failed)
    #expect(await controller.snapshot().failureReason == .cannotOpen)

    await engine.setLoadFailure(for: item.url, enabled: false)
    await controller.retry()
    #expect(await controller.snapshot().phase == .playing)
    #expect(await engine.loadedURLs == [item.url, item.url])
}

@Test("Wake recovery resumes the audio engine without losing queue state")
func resumesAfterWake() async {
    let engine = RecordingAudioEngine()
    let item = makePlaybackItem(id: "wake")
    let controller = PlaybackController(engine: engine)
    await controller.replaceQueue([item], startingAt: 0)

    await controller.resumeAfterWake()

    #expect(await engine.resumeCount == 1)
    #expect(await controller.snapshot().currentItem == item)
    #expect(await controller.snapshot().phase == .playing)
}

@Test("Playback state updates are published for UI observers")
func publishesPlaybackUpdates() async {
    let engine = RecordingAudioEngine()
    let controller = PlaybackController(engine: engine)
    let updates = await controller.updates()
    var iterator = updates.makeAsyncIterator()

    #expect(await iterator.next()?.phase == .idle)
    await controller.replaceQueue([makePlaybackItem(id: "observable")], startingAt: 0)

    var observedPlaying = false
    for _ in 0..<3 {
        if await iterator.next()?.phase == .playing {
            observedPlaying = true
            break
        }
    }
    #expect(observedPlaying)
}

@Test("Repeat all wraps the end of the queue")
func repeatAllWrapsQueue() async {
    let engine = RecordingAudioEngine()
    let first = makePlaybackItem(id: "first")
    let second = makePlaybackItem(id: "second")
    let controller = PlaybackController(engine: engine)
    await controller.setRepeatMode(.all)
    await controller.replaceQueue([first, second], startingAt: 1)

    #expect(await controller.snapshot().canAdvance == true)
    await controller.next()

    #expect(await controller.snapshot().currentItem == first)
}

@Test("Repeat one reloads the current item after it ends")
func repeatOneReloadsCurrentItem() async {
    let engine = RecordingAudioEngine()
    let item = makePlaybackItem(id: "repeat")
    let controller = PlaybackController(engine: engine)
    await controller.setRepeatMode(.one)
    await controller.replaceQueue([item], startingAt: 0)

    await engine.emit(.ended)

    #expect(await eventually { await engine.playCount == 2 })
    #expect(await controller.snapshot().currentItem == item)
}

@Test("Shuffle advances to a different item")
func shuffleAvoidsCurrentItem() async {
    let engine = RecordingAudioEngine()
    let first = makePlaybackItem(id: "first")
    let second = makePlaybackItem(id: "second")
    let controller = PlaybackController(engine: engine)
    await controller.setOrder(.shuffled)
    await controller.replaceQueue([first, second], startingAt: 0)

    #expect(await controller.snapshot().canAdvance == true)
    await controller.next()

    #expect(await controller.snapshot().currentItem == second)
}

@Test("Shuffle without repeat visits every item once and then stops")
func shuffleStopsAfterOnePass() async {
    let engine = RecordingAudioEngine()
    let items = [
        makePlaybackItem(id: "first"),
        makePlaybackItem(id: "second"),
        makePlaybackItem(id: "third"),
    ]
    let controller = PlaybackController(engine: engine)
    await controller.setOrder(.shuffled)
    await controller.replaceQueue(items, startingAt: 0)

    await controller.next()
    await controller.next()
    await controller.next()

    #expect(Set(await engine.loadedURLs) == Set(items.map(\.url)))
    let snapshot = await controller.snapshot()
    #expect(snapshot.phase == .idle)
    #expect(snapshot.canAdvance == false)
}

@Test("A restored queue stays stopped until the user presses play")
func restoresQueueWithoutAutoplay() async {
    let engine = RecordingAudioEngine()
    let item = makePlaybackItem(id: "restored")
    let controller = PlaybackController(engine: engine)
    await controller.restore(PersistedPlaybackState(
        queue: [item],
        currentIndex: 0,
        volume: 0.4,
        order: .sequential,
        repeatMode: .off
    ))

    #expect(await controller.snapshot().phase == .idle)
    #expect(await engine.playCount == 0)

    await controller.togglePlayPause()
    #expect(await controller.snapshot().phase == .playing)
    #expect(await engine.playCount == 1)
}

private func eventually(_ predicate: @escaping @Sendable () async -> Bool) async -> Bool {
    for _ in 0..<100 {
        if await predicate() { return true }
        await Task.yield()
    }
    return false
}

private func makePlaybackItem(id: String) -> PlaybackItem {
    PlaybackItem(
        trackID: UUID(),
        locationID: id,
        url: URL(fileURLWithPath: "/Music/\(id).flac"),
        title: id.capitalized,
        duration: 60
    )
}

private actor RecordingAudioEngine: AudioEngine {
    private let eventStream: AsyncStream<AudioEngineEvent>
    private let eventContinuation: AsyncStream<AudioEngineEvent>.Continuation
    private(set) var loadedURLs: [URL] = []
    private(set) var playCount = 0
    private(set) var pauseCount = 0
    private(set) var seekPositions: [TimeInterval] = []
    private(set) var volumes: [Float] = []
    private(set) var resumeCount = 0
    private var failingURLs: Set<URL> = []

    init() {
        let pair = AsyncStream.makeStream(of: AudioEngineEvent.self)
        eventStream = pair.stream
        eventContinuation = pair.continuation
    }

    func events() -> AsyncStream<AudioEngineEvent> {
        eventStream
    }

    func emit(_ event: AudioEngineEvent) { eventContinuation.yield(event) }

    func load(_ url: URL) async throws -> AudioEngineSource {
        loadedURLs.append(url)
        if failingURLs.contains(url) { throw TestAudioError.cannotOpen }
        return AudioEngineSource(duration: 90)
    }

    func setLoadFailure(for url: URL, enabled: Bool) {
        if enabled { failingURLs.insert(url) } else { failingURLs.remove(url) }
    }

    func play() async throws {
        playCount += 1
    }

    func pause() async { pauseCount += 1 }
    func stop() async {}
    func seek(to seconds: TimeInterval) async throws { seekPositions.append(seconds) }
    func setVolume(_ volume: Float) async { volumes.append(volume) }
    func resumeAfterWake() async throws { resumeCount += 1 }
}

private enum TestAudioError: Error {
    case cannotOpen
}
