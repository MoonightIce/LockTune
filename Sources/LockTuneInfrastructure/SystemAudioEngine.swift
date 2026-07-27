import AVFAudio
import Foundation
import LockTuneCore

public enum SystemAudioEngineError: Error, Sendable {
    case cannotOpen
    case cannotDecode
    case outputUnavailable
}

public actor SystemAudioEngine: AudioEngine {
    private var graph: AudioGraph?
    private var graphPrepared = false
    private let eventStream: AsyncStream<AudioEngineEvent>
    private let eventContinuation: AsyncStream<AudioEngineEvent>.Continuation
    private var source: (any PCMSource)?
    private var generation = UUID()
    private var scheduledBufferCount = 0
    private var sourceExhausted = false
    private var baseFrame: Int64 = 0
    private var duration: TimeInterval?
    private var shouldBePlaying = false
    private var progressTask: Task<Void, Never>?
    private var volume: Float = 1

    public init() {
        let pair = AsyncStream.makeStream(of: AudioEngineEvent.self)
        eventStream = pair.stream
        eventContinuation = pair.continuation
    }

    public func events() -> AsyncStream<AudioEngineEvent> {
        eventStream
    }

    public func load(_ url: URL) async throws -> AudioEngineSource {
        stopPlayback(clearSource: true)
        let newSource: any PCMSource
        do {
            if url.pathExtension.lowercased() == "ape" {
                newSource = try APEPCMSource(url: url)
            } else {
                newSource = try AVAudioFilePCMSource(url: url)
            }
        } catch {
            throw SystemAudioEngineError.cannotOpen
        }

        source = newSource
        generation = UUID()
        baseFrame = 0
        duration = Double(newSource.totalFrames) / newSource.format.sampleRate
        graphPrepared = false
        return AudioEngineSource(duration: duration)
    }

    public func play() async throws {
        guard source != nil else { throw SystemAudioEngineError.cannotOpen }
        do {
            let graph = try prepareGraphIfNeeded()
            if !graph.engine.isRunning { try graph.engine.start() }
            graph.player.play()
            shouldBePlaying = true
            startProgressUpdates()
        } catch {
            throw SystemAudioEngineError.outputUnavailable
        }
    }

    public func pause() async {
        graph?.player.pause()
        shouldBePlaying = false
        publishProgress()
    }

    public func stop() async {
        stopPlayback(clearSource: true)
    }

    public func seek(to seconds: TimeInterval) async throws {
        guard let source else { throw SystemAudioEngineError.cannotOpen }
        let target = Int64(max(0, min(seconds * source.format.sampleRate, Double(source.totalFrames))))
        let wasPlaying = shouldBePlaying
        graph?.player.stop()
        generation = UUID()
        scheduledBufferCount = 0
        sourceExhausted = false
        do {
            try source.seek(toFrame: target)
            baseFrame = target
            if graphPrepared {
                try scheduleMore(for: generation)
                if wasPlaying, let graph {
                    if !graph.engine.isRunning { try graph.engine.start() }
                    graph.player.play()
                }
            }
            publishProgress()
        } catch {
            eventContinuation.yield(.failed(.decodingFailed))
            throw SystemAudioEngineError.cannotDecode
        }
    }

    public func setVolume(_ volume: Float) async {
        self.volume = min(max(volume, 0), 1)
        graph?.player.volume = self.volume
    }

    public func resumeAfterWake() async throws {
        guard source != nil else { return }
        do {
            guard shouldBePlaying else { return }
            let graph = try prepareGraphIfNeeded()
            if !graph.engine.isRunning { try graph.engine.start() }
            if !graph.player.isPlaying { graph.player.play() }
        } catch {
            eventContinuation.yield(.failed(.audioOutputUnavailable))
            throw SystemAudioEngineError.outputUnavailable
        }
    }

    private func scheduleMore(for expectedGeneration: UUID) throws {
        guard let source, let graph, expectedGeneration == generation else { return }
        while scheduledBufferCount < 3, !sourceExhausted {
            guard let buffer = try source.read(maximumFrames: 8_192) else {
                sourceExhausted = true
                break
            }
            scheduledBufferCount += 1
            let engine = self
            graph.player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
                Task { await engine.bufferPlayed(generation: expectedGeneration) }
            }
        }
    }

    private func bufferPlayed(generation expectedGeneration: UUID) {
        guard expectedGeneration == generation else { return }
        scheduledBufferCount = max(0, scheduledBufferCount - 1)
        do {
            try scheduleMore(for: expectedGeneration)
            if sourceExhausted, scheduledBufferCount == 0 {
                shouldBePlaying = false
                publishProgress()
                eventContinuation.yield(.ended)
            }
        } catch {
            shouldBePlaying = false
            eventContinuation.yield(.failed(.decodingFailed))
        }
    }

    private func currentFrame() -> Int64 {
        guard let player = graph?.player,
              let renderTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: renderTime)
        else { return baseFrame }
        return baseFrame + max(0, playerTime.sampleTime)
    }

    private func publishProgress() {
        guard let source else { return }
        let elapsed = Double(min(currentFrame(), source.totalFrames)) / source.format.sampleRate
        eventContinuation.yield(.progress(elapsed: elapsed, duration: duration))
    }

    private func startProgressUpdates() {
        guard progressTask == nil else { return }
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self else { return }
                await self.publishProgress()
            }
        }
    }

    private func stopPlayback(clearSource: Bool) {
        progressTask?.cancel()
        progressTask = nil
        graph?.player.stop()
        graphPrepared = false
        shouldBePlaying = false
        generation = UUID()
        scheduledBufferCount = 0
        sourceExhausted = false
        baseFrame = 0
        duration = nil
        if clearSource { source = nil }
    }

    private func prepareGraphIfNeeded() throws -> AudioGraph {
        guard let source else { throw SystemAudioEngineError.cannotOpen }
        let graph = ensureGraph()
        if !graphPrepared {
            graph.engine.disconnectNodeOutput(graph.player)
            graph.engine.connect(graph.player, to: graph.engine.mainMixerNode, format: source.format)
            graph.player.volume = volume
            graphPrepared = true
        }
        if scheduledBufferCount == 0, !sourceExhausted {
            do {
                try scheduleMore(for: generation)
            } catch {
                graphPrepared = false
                throw SystemAudioEngineError.cannotDecode
            }
        }
        return graph
    }

    private func ensureGraph() -> AudioGraph {
        if let graph { return graph }
        let graph = AudioGraph()
        self.graph = graph
        return graph
    }
}

private final class AudioGraph {
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()

    init() {
        engine.attach(player)
    }
}

private protocol PCMSource: AnyObject {
    var format: AVAudioFormat { get }
    var totalFrames: Int64 { get }
    func read(maximumFrames: AVAudioFrameCount) throws -> AVAudioPCMBuffer?
    func seek(toFrame frame: Int64) throws
}

private final class AVAudioFilePCMSource: PCMSource {
    let file: AVAudioFile
    let format: AVAudioFormat
    let totalFrames: Int64

    init(url: URL) throws {
        file = try AVAudioFile(forReading: url)
        format = file.processingFormat
        totalFrames = file.length
    }

    func read(maximumFrames: AVAudioFrameCount) throws -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: maximumFrames) else {
            throw SystemAudioEngineError.cannotDecode
        }
        try file.read(into: buffer, frameCount: maximumFrames)
        return buffer.frameLength > 0 ? buffer : nil
    }

    func seek(toFrame frame: Int64) throws {
        file.framePosition = min(max(0, frame), totalFrames)
    }
}

private final class APEPCMSource: PCMSource {
    let decoder: APEAudioDecoder
    let format: AVAudioFormat
    let totalFrames: Int64

    init(url: URL) throws {
        decoder = try APEAudioDecoder(url: url)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: decoder.sampleRate,
            channels: AVAudioChannelCount(decoder.channelCount),
            interleaved: true
        ) else { throw SystemAudioEngineError.cannotDecode }
        self.format = format
        totalFrames = decoder.totalFrames
    }

    func read(maximumFrames: AVAudioFrameCount) throws -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: maximumFrames) else {
            throw SystemAudioEngineError.cannotDecode
        }
        let buffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        guard let data = buffers.first?.mData else { throw SystemAudioEngineError.cannotDecode }
        let frames = try decoder.read(
            into: data.assumingMemoryBound(to: Float.self),
            maximumFrames: Int(maximumFrames)
        )
        guard frames > 0 else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)
        return buffer
    }

    func seek(toFrame frame: Int64) throws {
        try decoder.seek(toFrame: min(max(0, frame), totalFrames))
    }
}
