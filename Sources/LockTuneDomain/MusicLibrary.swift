import Foundation

public enum MetadataStatus: String, Codable, Sendable {
    case complete
    case partial
    case unavailable
}

public struct TrackMetadata: Equatable, Codable, Sendable {
    public var title: String?
    public var artist: String?
    public var album: String?
    public var trackNumber: Int?
    public var duration: TimeInterval?
    public var artworkData: Data?
    public var status: MetadataStatus

    public init(
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        trackNumber: Int? = nil,
        duration: TimeInterval? = nil,
        artworkData: Data? = nil,
        status: MetadataStatus
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.trackNumber = trackNumber
        self.duration = duration
        self.artworkData = artworkData
        self.status = status
    }
}

public struct IndexedTrack: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let contentFingerprint: String
    public var metadata: TrackMetadata

    public init(id: UUID = UUID(), contentFingerprint: String, metadata: TrackMetadata) {
        self.id = id
        self.contentFingerprint = contentFingerprint
        self.metadata = metadata
    }
}

public struct TrackLocation: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let trackID: UUID
    public let url: URL
    public let format: AudioFileFormat

    public init(trackID: UUID, url: URL, format: AudioFileFormat) {
        self.id = url.standardizedFileURL.path
        self.trackID = trackID
        self.url = url
        self.format = format
    }
}

public enum MusicScanIssueReason: String, Equatable, Codable, Sendable {
    case unreadable
    case metadataUnavailable
}

public struct MusicScanIssue: Equatable, Codable, Sendable {
    public let url: URL
    public let reason: MusicScanIssueReason

    public init(url: URL, reason: MusicScanIssueReason) {
        self.url = url
        self.reason = reason
    }
}

public struct MusicLibrarySnapshot: Equatable, Codable, Sendable {
    public var tracks: [IndexedTrack]
    public var locations: [TrackLocation]
    public var issues: [MusicScanIssue]

    public init(
        tracks: [IndexedTrack] = [],
        locations: [TrackLocation] = [],
        issues: [MusicScanIssue] = []
    ) {
        self.tracks = tracks
        self.locations = locations
        self.issues = issues
    }
}
