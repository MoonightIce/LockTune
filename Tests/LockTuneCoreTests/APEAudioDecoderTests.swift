import Foundation
import Testing
import LockTuneInfrastructure

@Test(
    "Authorized real APE decodes finite PCM and seeks",
    .enabled(if: ProcessInfo.processInfo.environment["LOCKTUNE_REAL_MUSIC_PATH"] != nil)
)
func decodesAuthorizedRealAPE() throws {
    let root = URL(fileURLWithPath: try #require(
        ProcessInfo.processInfo.environment["LOCKTUNE_REAL_MUSIC_PATH"]
    ))
    let sample = try #require(firstAPE(in: root))
    let decoder = try APEAudioDecoder(url: sample)
    #expect(decoder.sampleRate > 0)
    #expect(decoder.channelCount > 0)
    #expect(decoder.totalFrames > 0)

    var samples = [Float](repeating: 0, count: 4_096 * decoder.channelCount)
    let firstRead = try samples.withUnsafeMutableBufferPointer {
        try decoder.read(into: $0.baseAddress!, maximumFrames: 4_096)
    }
    #expect(firstRead > 0)
    let decodedSamplesAreFinite = samples
        .prefix(firstRead * decoder.channelCount)
        .reduce(true) { $0 && $1.isFinite }
    #expect(decodedSamplesAreFinite)

    try decoder.seek(toFrame: decoder.totalFrames / 2)
    let secondRead = try samples.withUnsafeMutableBufferPointer {
        try decoder.read(into: $0.baseAddress!, maximumFrames: 4_096)
    }
    #expect(secondRead > 0)
}

private func firstAPE(in root: URL) -> URL? {
    guard let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else { return nil }
    for case let url as URL in enumerator where url.pathExtension.lowercased() == "ape" {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let prefix = try? handle.read(upToCount: 4),
              prefix == Data("MAC ".utf8)
        else { continue }
        return url
    }
    return nil
}
