import Foundation
import Testing
import LockTuneDomain
import LockTuneInfrastructure

@Test(
    "Authorized real formats load and seek through one audio engine",
    .enabled(if: ProcessInfo.processInfo.environment["LOCKTUNE_REAL_MUSIC_PATH"] != nil)
)
func loadsAndSeeksAuthorizedRealFormats() async throws {
    let root = URL(fileURLWithPath: try #require(
        ProcessInfo.processInfo.environment["LOCKTUNE_REAL_MUSIC_PATH"]
    ))
    let samples = playbackSamples(in: root)
    let engine = SystemAudioEngine()

    for format in [AudioFileFormat.mp3, .m4a, .flac, .ape] {
        let url = try #require(samples[format])
        let source = try await engine.load(url)
        let duration = try #require(source.duration)
        #expect(duration > 0)
        try await engine.seek(to: duration / 2)
        await engine.stop()
    }
}

private func playbackSamples(in root: URL) -> [AudioFileFormat: URL] {
    guard let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else { return [:] }
    var result: [AudioFileFormat: URL] = [:]
    for case let url as URL in enumerator {
        guard let format = AudioFileFormat(url: url),
              [.mp3, .m4a, .flac, .ape].contains(format),
              result[format] == nil
        else { continue }
        if format == .ape {
            guard let handle = try? FileHandle(forReadingFrom: url),
                  let prefix = try? handle.read(upToCount: 4),
                  prefix == Data("MAC ".utf8)
            else { continue }
        }
        result[format] = url
        if result.count == 4 { break }
    }
    return result
}
