import Foundation
import LockTuneAPEBridge

public enum APEAudioDecoderError: Error, Equatable, Sendable {
    case cannotOpen(code: Int32)
    case readFailed(code: Int32)
    case seekFailed(code: Int32)
}

public final class APEAudioDecoder: @unchecked Sendable {
    public let sampleRate: Double
    public let channelCount: Int
    public let totalFrames: Int64

    private let handle: OpaquePointer

    public init(url: URL) throws {
        var format = LTAPEAudioFormat()
        var errorCode: Int32 = 0
        let opened = url.path.withCString {
            lt_ape_decoder_open($0, &format, &errorCode)
        }
        guard let opened else { throw APEAudioDecoderError.cannotOpen(code: errorCode) }
        handle = opened
        sampleRate = format.sample_rate
        channelCount = Int(format.channel_count)
        totalFrames = format.total_frames
    }

    deinit {
        lt_ape_decoder_close(handle)
    }

    public func read(
        into interleavedSamples: UnsafeMutablePointer<Float>,
        maximumFrames: Int
    ) throws -> Int {
        var errorCode: Int32 = 0
        let frameCount = lt_ape_decoder_read_float(
            handle,
            interleavedSamples,
            Int64(maximumFrames),
            &errorCode
        )
        guard errorCode == 0 else { throw APEAudioDecoderError.readFailed(code: errorCode) }
        return Int(frameCount)
    }

    public func seek(toFrame frame: Int64) throws {
        let errorCode = lt_ape_decoder_seek(handle, frame)
        guard errorCode == 0 else { throw APEAudioDecoderError.seekFailed(code: errorCode) }
    }
}
