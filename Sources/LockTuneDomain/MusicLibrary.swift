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
    public var artworkCacheKey: String?
    public var status: MetadataStatus

    public init(
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        trackNumber: Int? = nil,
        duration: TimeInterval? = nil,
        artworkData: Data? = nil,
        artworkCacheKey: String? = nil,
        status: MetadataStatus
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.trackNumber = trackNumber
        self.duration = duration
        self.artworkData = artworkData
        self.artworkCacheKey = artworkCacheKey
        self.status = status
    }
}

public struct Track: Identifiable, Equatable, Codable, Sendable {
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
    public let fileSize: Int64?
    public let contentModificationDate: Date?

    public init(
        trackID: UUID,
        url: URL,
        format: AudioFileFormat,
        fileSize: Int64? = nil,
        contentModificationDate: Date? = nil
    ) {
        self.id = url.standardizedFileURL.path
        self.trackID = trackID
        self.url = url
        self.format = format
        self.fileSize = fileSize
        self.contentModificationDate = contentModificationDate
    }
}

public enum MusicScanIssueReason: String, Equatable, Codable, Sendable {
    case unreadable
    case metadataUnavailable
    case unsupportedFormat
}

public struct MusicScanIssue: Equatable, Codable, Sendable {
    public let url: URL
    public let reason: MusicScanIssueReason

    public init(url: URL, reason: MusicScanIssueReason) {
        self.url = url
        self.reason = reason
    }
}

public struct MusicScanState: Equatable, Codable, Sendable {
    public var lastCompletedAt: Date?

    public init(lastCompletedAt: Date? = nil) {
        self.lastCompletedAt = lastCompletedAt
    }
}

public struct MusicLibrarySnapshot: Equatable, Codable, Sendable {
    public var tracks: [Track]
    public var locations: [TrackLocation]
    public var issues: [MusicScanIssue]
    public var scanState: MusicScanState

    public init(
        tracks: [Track] = [],
        locations: [TrackLocation] = [],
        issues: [MusicScanIssue] = [],
        scanState: MusicScanState = MusicScanState()
    ) {
        self.tracks = tracks
        self.locations = locations
        self.issues = issues
        self.scanState = scanState
    }
}
