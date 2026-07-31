import Foundation
import LockTuneDomain

public struct FilenameMetadataSuggestion: Equatable, Sendable {
    public let title: String?
    public let artist: String?
    public let album: String?

    public init(title: String? = nil, artist: String? = nil, album: String? = nil) {
        self.title = title
        self.artist = artist
        self.album = album
    }
}

public enum FilenameMetadataRepair {
    public static func needsRepair(_ metadata: TrackMetadata) -> Bool {
        [metadata.title, metadata.artist, metadata.album].contains(where: isUnknownOrGarbled)
    }

    public static func suggestion(for url: URL, metadata: TrackMetadata) -> FilenameMetadataSuggestion {
        let stem = url.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = url.deletingLastPathComponent().lastPathComponent
        let split = splitFilename(stem)
        let knownArtist = isUnknownOrGarbled(metadata.artist) ? nil : usable(metadata.artist)
        let title = isUnknownOrGarbled(metadata.title) ? split?.title : nil
        let artist = isUnknownOrGarbled(metadata.artist) ? split?.artist : nil
        let album = isUnknownOrGarbled(metadata.album) ? usable(parent) : nil
        if let knownArtist, let split, !split.suffix.hasPrefix(knownArtist) {
            return FilenameMetadataSuggestion(title: nil, artist: artist, album: album)
        }
        return FilenameMetadataSuggestion(title: title, artist: artist, album: album)
    }

    public static func isUnknownOrGarbled(_ value: String?) -> Bool {
        guard let value = usable(value) else { return true }
        let lower = value.lowercased()
        let placeholders = ["unknown", "untitled", "n/a", "null", "未知", "乱码"]
        if placeholders.contains(where: { lower == $0 || lower.contains($0) }) { return true }
        if value.contains(".-[") || value.contains("].专辑") || value.contains("].CD") { return true }
        return ["�", "锟斤拷", "ï¿½", "Ã", "Â", "æ", "ç", "å"].contains(where: value.contains)
    }

    private static func usable(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    private static func splitFilename(_ stem: String) -> (title: String, artist: String, suffix: String)? {
        if stem.contains(".-[") || stem.contains("].专辑") || stem.contains("] .专辑") { return nil }
        guard let separator = stem.lastIndex(where: { $0 == "-" || $0 == "–" || $0 == "—" }) else { return nil }
        let title = stem[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = stem[stem.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !suffix.isEmpty else { return nil }
        let artist = suffix.split(separator: "_", maxSplits: 1).first.map(String.init) ?? suffix
        return (String(title), artist, String(suffix))
    }
}
