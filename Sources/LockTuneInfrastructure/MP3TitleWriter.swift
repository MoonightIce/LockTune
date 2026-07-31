import Foundation

public enum MP3TitleWriterError: Error, Equatable {
    case unsupportedID3Version
    case invalidID3Tag
    case emptyTitle
    case replacementFailed
}

/// Rewrites the ID3 tag while preserving the MP3 payload and unrelated frames.
public struct MP3TitleWriter: Sendable {
    public init() {}

    public func writeTitle(_ title: String, to url: URL) throws {
        try writeMetadata(title: title, to: url)
    }

    public func writeMetadata(
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        to url: URL
    ) throws {
        let fields = [("TIT2", title), ("TPE1", artist), ("TALB", album)].compactMap { id, value -> (String, String)? in
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            return (id, value)
        }
        guard !fields.isEmpty else { throw MP3TitleWriterError.emptyTitle }

        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        let header = try input.read(upToCount: 10) ?? Data()
        let existing: ExistingTag?
        if header.count >= 10, String(data: header.prefix(3), encoding: .ascii) == "ID3" {
            existing = try readExistingTag(from: input, header: header)
        } else {
            existing = nil
        }

        let tagVersion = existing?.version ?? 4
        let tag = makeTag(fields: fields, existingBody: existing?.body, version: tagVersion)
        let temporaryURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).locktune-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        guard FileManager.default.createFile(atPath: temporaryURL.path, contents: nil) else {
            throw MP3TitleWriterError.replacementFailed
        }
        let output = try FileHandle(forWritingTo: temporaryURL)
        try output.write(contentsOf: tag)
        try input.seek(toOffset: existing?.endOffset ?? 0)
        while true {
            let chunk = try input.read(upToCount: 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            try output.write(contentsOf: chunk)
        }
        try output.close()
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) {
            try? FileManager.default.setAttributes(attributes, ofItemAtPath: temporaryURL.path)
        }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporaryURL)
    }

    private func readExistingTag(from handle: FileHandle, header: Data) throws -> ExistingTag {
        let version = header[3]
        guard version == 3 || version == 4 else { throw MP3TitleWriterError.unsupportedID3Version }
        guard let size = decodeSynchsafe(header[6..<10]) else { throw MP3TitleWriterError.invalidID3Tag }
        let body = try handle.read(upToCount: size) ?? Data()
        guard body.count == size else { throw MP3TitleWriterError.invalidID3Tag }
        return ExistingTag(version: version, body: body, endOffset: UInt64(10 + size))
    }

    private func makeTag(fields: [(String, String)], existingBody: Data?, version: UInt8) -> Data {
        let ids = Set(fields.map(\.0))
        var body = existingBody.map { removeFrames(from: $0, identifiers: ids, version: version) } ?? Data()
        for (id, value) in fields {
            let text = Data([3]) + Data(value.utf8)
            var frame = Data(id.utf8)
            frame.append(contentsOf: encodeFrameSize(text.count, version: version))
            frame.append(contentsOf: [0, 0])
            frame.append(text)
            body.append(frame)
        }
        var result = Data("ID3".utf8)
        result.append(version)
        result.append(contentsOf: [0, 0])
        result.append(contentsOf: encodeSynchsafe(body.count))
        result.append(body)
        return result
    }

    private func removeFrames(from body: Data, identifiers: Set<String>, version: UInt8) -> Data {
        var result = Data()
        var offset = 0
        while offset + 10 <= body.count {
            let id = String(data: body[offset..<(offset + 4)], encoding: .ascii) ?? ""
            if id.allSatisfy({ $0 == "\0" }) { break }
            let sizeBytes = body[(offset + 4)..<(offset + 8)]
            let size = version == 4
                ? decodeSynchsafe(sizeBytes) ?? -1
                : sizeBytes.reduce(0) { ($0 << 8) | Int($1) }
            guard size >= 0, offset + 10 + size <= body.count else { return body }
            if !identifiers.contains(id) { result.append(body[offset..<(offset + 10 + size)]) }
            offset += 10 + size
        }
        if offset < body.count { result.append(body[offset..<body.count]) }
        return result
    }

    private func encodeFrameSize(_ size: Int, version: UInt8) -> [UInt8] {
        version == 4 ? encodeSynchsafe(size) : [UInt8((size >> 24) & 255), UInt8((size >> 16) & 255), UInt8((size >> 8) & 255), UInt8(size & 255)]
    }

    private func encodeSynchsafe(_ value: Int) -> [UInt8] {
        [UInt8((value >> 21) & 127), UInt8((value >> 14) & 127), UInt8((value >> 7) & 127), UInt8(value & 127)]
    }

    private func decodeSynchsafe(_ bytes: Data.SubSequence) -> Int? {
        guard bytes.count == 4, bytes.allSatisfy({ $0 & 128 == 0 }) else { return nil }
        return bytes.reduce(0) { ($0 << 7) | Int($1) }
    }
}

public enum FilenameTitleParser {
    public static func title(for url: URL, artist: String?) -> String? {
        guard let artist = artist?.trimmingCharacters(in: .whitespacesAndNewlines), !artist.isEmpty else { return nil }
        let stem = url.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = stem.lastIndex(where: { $0 == "-" || $0 == "–" || $0 == "—" }) else { return nil }
        let title = stem[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = stem[stem.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, suffix == artist || suffix.hasPrefix(artist + "_") || suffix.hasPrefix(artist + " ") || suffix.hasPrefix(artist + "-") else { return nil }
        return String(title)
    }
}

private struct ExistingTag {
    let version: UInt8
    let body: Data
    let endOffset: UInt64
}
