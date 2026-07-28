import Foundation
import LockTuneDomain

protocol APEByteReading: AnyObject {
    var size: Int { get }
    func read(offset: Int, count: Int) throws -> Data
}

enum APEMetadataParser {
    static func parse(url: URL) -> TrackMetadata {
        guard let reader = try? APEFileReader(url: url) else {
            return TrackMetadata(status: .unavailable)
        }
        return parse(reader: reader)
    }

    static func parse(reader: any APEByteReading) -> TrackMetadata {
        let headerCount = min(reader.size, 512)
        guard let header = try? reader.read(offset: 0, count: headerCount),
              header.count >= 76,
              header.prefix(4) == Data("MAC ".utf8)
        else { return TrackMetadata(status: .unavailable) }

        let duration = durationSeconds(data: header)
        let tags = readTags(from: reader)
        let title = tags["title"].flatMap(text)
        let artist = tags["artist"].flatMap(text)
        let album = tags["album"].flatMap(text)
        let trackNumber = tags["track"].flatMap(text).flatMap {
            Int($0.split(separator: "/").first ?? "")
        }
        let artwork = tags["cover art (front)"].flatMap { value -> Data? in
            guard let separator = value.firstIndex(of: 0) else { return nil }
            return Data(value[value.index(after: separator)...])
        }

        return TrackMetadata(
            title: title,
            artist: artist,
            album: album,
            trackNumber: trackNumber,
            duration: duration,
            artworkData: artwork,
            status: metadataStatus(
                title: title,
                artist: artist,
                album: album,
                trackNumber: trackNumber,
                duration: duration,
                artwork: artwork
            )
        )
    }

    private static func readTags(from reader: any APEByteReading) -> [String: Data] {
        let probeCount = min(reader.size, 512)
        let probeOffset = reader.size - probeCount
        guard let footerProbe = try? reader.read(offset: probeOffset, count: probeCount),
              let markerRange = footerProbe.range(of: Data("APETAGEX".utf8), options: .backwards),
              let tagSize = footerProbe.u32(at: markerRange.lowerBound + 12)
        else { return [:] }
        let markerOffset = probeOffset + markerRange.lowerBound
        let tagStart = markerOffset + 32 - Int(tagSize)
        guard tagStart >= 0,
              Int(tagSize) <= reader.size - tagStart,
              let tagData = try? reader.read(offset: tagStart, count: Int(tagSize))
        else { return [:] }
        return tags(data: tagData)
    }

    private static func durationSeconds(data: Data) -> TimeInterval? {
        guard let version = data.u16(at: 4) else { return nil }
        let blocksPerFrame: UInt32
        let finalFrameBlocks: UInt32?
        let totalFrames: UInt32?
        let sampleRate: UInt32?

        if version >= 3980 {
            guard let descriptorBytes = data.u16(at: 6),
                  let headerBytes = data.u32(at: 8), headerBytes >= 24
            else { return nil }
            let offset = Int(descriptorBytes)
            blocksPerFrame = data.u32(at: offset + 4) ?? 0
            finalFrameBlocks = data.u32(at: offset + 8)
            totalFrames = data.u32(at: offset + 12)
            sampleRate = data.u32(at: offset + 20)
        } else {
            guard version >= 3800, let compressionLevel = data.u16(at: 6) else { return nil }
            if version >= 3950 {
                blocksPerFrame = 73_728 * 4
            } else if version >= 3900 || compressionLevel == 4_000 {
                blocksPerFrame = 73_728
            } else {
                blocksPerFrame = 9_216
            }
            sampleRate = data.u32(at: 12)
            totalFrames = data.u32(at: 24)
            finalFrameBlocks = data.u32(at: 28)
        }

        guard let finalFrameBlocks, let totalFrames, let sampleRate,
              blocksPerFrame > 0, totalFrames > 0, sampleRate > 0
        else { return nil }
        let totalBlocks = UInt64(totalFrames - 1) * UInt64(blocksPerFrame) + UInt64(finalFrameBlocks)
        return Double(totalBlocks) / Double(sampleRate)
    }

    private static func tags(data: Data) -> [String: Data] {
        let marker = Data("APETAGEX".utf8)
        guard let markerRange = data.range(of: marker, options: .backwards),
              let tagSize = data.u32(at: markerRange.lowerBound + 12),
              let itemCount = data.u32(at: markerRange.lowerBound + 16)
        else { return [:] }
        let start = markerRange.lowerBound + 32 - Int(tagSize)
        guard start >= 0 else { return [:] }
        var cursor = start
        var result: [String: Data] = [:]
        for _ in 0..<itemCount {
            guard let valueSize = data.u32(at: cursor),
                  let flags = data.u32(at: cursor + 4),
                  ((flags >> 1) & 0b11) != 2
            else { break }
            cursor += 8
            guard let zero = data[cursor..<markerRange.lowerBound].firstIndex(of: 0) else { break }
            let key = String(decoding: data[cursor..<zero], as: UTF8.self).lowercased()
            cursor = zero + 1
            let end = cursor + Int(valueSize)
            guard end <= markerRange.lowerBound else { break }
            result[key] = Data(data[cursor..<end])
            cursor = end
        }
        return result
    }

    private static func text(_ data: Data) -> String? {
        String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private final class APEFileReader: APEByteReading {
    let size: Int
    private let handle: FileHandle

    init(url: URL) throws {
        handle = try FileHandle(forReadingFrom: url)
        size = Int(try handle.seekToEnd())
    }

    deinit {
        try? handle.close()
    }

    func read(offset: Int, count: Int) throws -> Data {
        guard offset >= 0, count >= 0, offset <= size else { return Data() }
        try handle.seek(toOffset: UInt64(offset))
        return try handle.read(upToCount: min(count, size - offset)) ?? Data()
    }
}

private extension Data {
    func u16(at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= count else { return nil }
        return UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }

    func u32(at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        return UInt32(self[offset])
            | UInt32(self[offset + 1]) << 8
            | UInt32(self[offset + 2]) << 16
            | UInt32(self[offset + 3]) << 24
    }
}
