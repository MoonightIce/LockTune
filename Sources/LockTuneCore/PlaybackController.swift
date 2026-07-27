import Foundation
import LockTuneDomain

public struct AudioEngineSource: Equatable, Sendable {
    public let duration: TimeInterval?

    public init(duration: TimeInterval?) {
        self.duration = duration
    }
}

public enum AudioEngineEvent: Equatable, Sendable {
    case progress(elapsed: TimeInterval, duration: TimeInterval?)
    case ended
    case failed(PlaybackFailureReason)
}

public protocol AudioEngine: Actor {
    func events() -> AsyncStream<AudioEngineEvent>
    func load(_ url: URL) async throws -> AudioEngineSource
    func play() async throws
    func pause() async
    func stop() async
    func seek(to seconds: TimeInterval) async throws
    func setVolume(_ volume: Float) async
    func resumeAfterWake() async throws
}

public actor PlaybackController {
    private let engine: any AudioEngine
    private var state = PlaybackSnapshot()
    private var eventTask: Task<Void, Never>?
    private var shuffleRemaining: [Int] = []
    private let updateStream: AsyncStream<PlaybackSnapshot>
    private let updateContinuation: AsyncStream<PlaybackSnapshot>.Continuation

    public init(engine: any AudioEngine) {
        self.engine = engine
        let pair = AsyncStream.makeStream(of: PlaybackSnapshot.self, bufferingPolicy: .bufferingNewest(1))
        updateStream = pair.stream
        updateContinuation = pair.continuation
    }

    public func snapshot() -> PlaybackSnapshot {
        state
    }

    public func updates() -> AsyncStream<PlaybackSnapshot> {
        updateContinuation.yield(state)
        return updateStream
    }

    public func replaceQueue(_ items: [PlaybackItem], startingAt index: Int) async {
        observeEngineEventsIfNeeded()
        guard items.indices.contains(index) else {
            await engine.stop()
            state = PlaybackSnapshot(
                queue: items,
                volume: state.volume,
                order: state.order,
                repeatMode: state.repeatMode
            )
            publishState()
            return
        }

        state.queue = items
        state.currentIndex = index
        resetShuffleRemaining(excluding: index)
        state.phase = .loading
        state.elapsed = 0
        state.duration = items[index].duration
        state.failureReason = nil
        publishState()

        do {
            let source = try await engine.load(items[index].url)
            state.duration = source.duration ?? items[index].duration
            try await engine.play()
            state.phase = .playing
        } catch {
            state.phase = .failed
            state.failureReason = .cannotOpen
        }
        publishState()
    }

    public func togglePlayPause() async {
        switch state.phase {
        case .playing:
            await engine.pause()
            state.phase = .paused
        case .paused:
            do {
                try await engine.play()
                state.phase = .playing
                state.failureReason = nil
            } catch {
                state.phase = .failed
                state.failureReason = .audioOutputUnavailable
            }
        case .idle:
            if let currentIndex = state.currentIndex {
                await loadAndPlay(index: currentIndex)
            }
        case .loading, .failed:
            break
        }
        publishState()
    }

    public func next() async {
        guard let currentIndex = state.currentIndex else { return }
        if state.order == .shuffled {
            if shuffleRemaining.isEmpty, state.repeatMode == .all {
                resetShuffleRemaining(excluding: currentIndex)
            }
            guard !shuffleRemaining.isEmpty else {
                await stopAtQueueEnd()
                return
            }
            let position = Int.random(in: shuffleRemaining.indices)
            let nextIndex = shuffleRemaining.remove(at: position)
            await loadAndPlay(index: nextIndex)
            return
        }
        let candidate = currentIndex + 1
        if state.queue.indices.contains(candidate) {
            await loadAndPlay(index: candidate)
        } else if state.repeatMode == .all, !state.queue.isEmpty {
            await loadAndPlay(index: 0)
        } else {
            await stopAtQueueEnd()
        }
    }

    public func previous() async {
        guard let currentIndex = state.currentIndex else { return }
        let previousIndex = currentIndex - 1
        guard state.queue.indices.contains(previousIndex) else {
            try? await engine.seek(to: 0)
            state.elapsed = 0
            publishState()
            return
        }
        await loadAndPlay(index: previousIndex)
    }

    public func seek(to seconds: TimeInterval) async {
        guard state.currentItem != nil, seconds.isFinite else { return }
        let upperBound = state.duration ?? seconds
        let position = max(0, min(seconds, upperBound))
        do {
            try await engine.seek(to: position)
            state.elapsed = position
        } catch {
            state.phase = .failed
            state.failureReason = .decodingFailed
        }
        publishState()
    }

    public func setVolume(_ volume: Float) async {
        guard volume.isFinite else { return }
        let clamped = min(max(volume, 0), 1)
        state.volume = clamped
        await engine.setVolume(clamped)
        publishState()
    }

    public func setOrder(_ order: PlaybackOrder) {
        state.order = order
        resetShuffleRemaining(excluding: state.currentIndex)
        publishState()
    }

    public func setRepeatMode(_ repeatMode: PlaybackRepeatMode) {
        state.repeatMode = repeatMode
        publishState()
    }

    public func restore(_ persisted: PersistedPlaybackState) async {
        await engine.stop()
        let currentIndex = persisted.currentIndex.flatMap { persisted.queue.indices.contains($0) ? $0 : nil }
        state = PlaybackSnapshot(
            queue: persisted.queue,
            currentIndex: currentIndex,
            phase: .idle,
            elapsed: 0,
            duration: currentIndex.map { persisted.queue[$0].duration } ?? nil,
            volume: min(max(persisted.volume, 0), 1),
            order: persisted.order,
            repeatMode: persisted.repeatMode
        )
        await engine.setVolume(state.volume)
        resetShuffleRemaining(excluding: currentIndex)
        publishState()
    }

    public func retry() async {
        guard let currentIndex = state.currentIndex else { return }
        await loadAndPlay(index: currentIndex)
    }

    public func resumeAfterWake() async {
        guard state.phase == .playing || state.phase == .paused else { return }
        do {
            try await engine.resumeAfterWake()
        } catch {
            state.phase = .failed
            state.failureReason = .audioOutputUnavailable
        }
        publishState()
    }

    private func loadAndPlay(index: Int) async {
        state.currentIndex = index
        state.phase = .loading
        state.elapsed = 0
        state.duration = state.queue[index].duration
        state.failureReason = nil
        publishState()
        do {
            let source = try await engine.load(state.queue[index].url)
            state.duration = source.duration ?? state.queue[index].duration
            try await engine.play()
            state.phase = .playing
        } catch {
            state.phase = .failed
            state.failureReason = .cannotOpen
        }
        publishState()
    }

    private func resetShuffleRemaining(excluding currentIndex: Int?) {
        shuffleRemaining = state.queue.indices.filter { $0 != currentIndex }
    }

    private func stopAtQueueEnd() async {
        await engine.stop()
        state.phase = .idle
        state.elapsed = state.duration ?? state.elapsed
        publishState()
    }

    private func observeEngineEventsIfNeeded() {
        guard eventTask == nil else { return }
        let engine = self.engine
        eventTask = Task { [weak self] in
            let events = await engine.events()
            for await event in events {
                guard !Task.isCancelled else { return }
                await self?.handle(event)
            }
        }
    }

    private func handle(_ event: AudioEngineEvent) async {
        switch event {
        case let .progress(elapsed, duration):
            state.elapsed = max(0, elapsed)
            state.duration = duration ?? state.duration
        case .ended:
            if state.repeatMode == .one, let currentIndex = state.currentIndex {
                await loadAndPlay(index: currentIndex)
            } else {
                await next()
            }
        case let .failed(reason):
            state.phase = .failed
            state.failureReason = reason
        }
        publishState()
    }

    private func publishState() {
        updateContinuation.yield(state)
    }
}
