import Foundation

public enum AudioFileFormat: String, CaseIterable, Codable, Sendable {
    case mp3
    case aac
    case m4a
    case flac
    case wav
    case ape

    public init?(url: URL) {
        self.init(rawValue: url.pathExtension.lowercased())
    }
}
