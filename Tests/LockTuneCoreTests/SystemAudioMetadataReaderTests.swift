import Foundation
import Testing
import LockTuneDomain
import LockTuneInfrastructure

@Test("APE metadata reader parses APEv2 tags and modern duration")
func readsAPEMetadata() async throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).ape")
    defer { try? FileManager.default.removeItem(at: url) }
    try makeAPEFixture().write(to: url)

    let metadata = await SystemAudioMetadataReader().metadata(for: url, format: .ape)

    #expect(metadata.title == "Fixture Title")
    #expect(metadata.artist == "Fixture Artist")
    #expect(metadata.album == "Fixture Album")
    #expect(metadata.trackNumber == 7)
    #expect(metadata.duration == 10)
    #expect(metadata.artworkData == Data([1, 2, 3, 4]))
    #expect(metadata.status == .complete)
}

@Test(
    "Authorized real music samples expose readable metadata and duration",
    .enabled(if: ProcessInfo.processInfo.environment["LOCKTUNE_REAL_MUSIC_PATH"] != nil)
)
func readsAuthorizedRealMusicSamples() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["LOCKTUNE_REAL_MUSIC_PATH"])
    let samples = findSamples(in: URL(fileURLWithPath: path))
    let reader = SystemAudioMetadataReader()

    for format in [AudioFileFormat.mp3, .m4a, .flac, .ape] {
        let sample = try #require(samples[format])
        let metadata = await reader.metadata(for: sample, format: format)
        #expect(metadata.status != .unavailable, "\(format.rawValue) metadata unavailable")
        #expect((metadata.duration ?? 0) > 0, "\(format.rawValue) duration unavailable")
    }
}

private func findSamples(in folder: URL) -> [AudioFileFormat: URL] {
    guard let enumerator = FileManager.default.enumerator(
        at: folder,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else { return [:] }
    var result: [AudioFileFormat: URL] = [:]
    for case let url as URL in enumerator {
        guard let format = AudioFileFormat(url: url), result[format] == nil else { continue }
        if format == .ape {
            guard let handle = try? FileHandle(forReadingFrom: url),
                  let prefix = try? handle.read(upToCount: 4),
                  prefix == Data("MAC ".utf8)
            else { continue }
        }
        result[format] = url
        if [.mp3, .m4a, .flac, .ape].allSatisfy({ result[$0] != nil }) { break }
    }
    return result
}

private func makeAPEFixture() -> Data {
    var descriptor = Data("MAC ".utf8)
    descriptor.appendLittleEndian(UInt16(3990))
    descriptor.appendLittleEndian(UInt16(52))
    descriptor.appendLittleEndian(UInt32(24))
    descriptor.appendLittleEndian(UInt32(0))
    descriptor.appendLittleEndian(UInt32(0))
    descriptor.appendLittleEndian(UInt32(0))
    descriptor.appendLittleEndian(UInt32(0))
    descriptor.appendLittleEndian(UInt32(0))
    descriptor.append(Data(repeating: 0, count: 16))
    descriptor.append(Data(repeating: 0, count: 4))

    var header = Data()
    header.appendLittleEndian(UInt16(2000))
    header.appendLittleEndian(UInt16(0))
    header.appendLittleEndian(UInt32(73728))
    header.appendLittleEndian(UInt32(441_000))
    header.appendLittleEndian(UInt32(1))
    header.appendLittleEndian(UInt16(16))
    header.appendLittleEndian(UInt16(2))
    header.appendLittleEndian(UInt32(44_100))

    let values = [
        ("Title", "Fixture Title"),
        ("Artist", "Fixture Artist"),
        ("Album", "Fixture Album"),
        ("Track", "7"),
        ("Cover Art (Front)", String(decoding: [102, 114, 111, 110, 116, 46, 106, 112, 103, 0, 1, 2, 3, 4], as: UTF8.self)),
    ]
    var items = Data()
    for (key, value) in values {
        let bytes = Data(value.utf8)
        items.appendLittleEndian(UInt32(bytes.count))
        items.appendLittleEndian(UInt32(0))
        items.append(Data(key.utf8))
        items.append(0)
        items.append(bytes)
    }

    var footer = Data("APETAGEX".utf8)
    footer.appendLittleEndian(UInt32(2000))
    footer.appendLittleEndian(UInt32(items.count + 32))
    footer.appendLittleEndian(UInt32(values.count))
    footer.appendLittleEndian(UInt32(0))
    footer.append(Data(repeating: 0, count: 8))
    return descriptor + header + Data(repeating: 0, count: 16) + items + footer
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
