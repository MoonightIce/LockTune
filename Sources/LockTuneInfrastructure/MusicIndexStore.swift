import Foundation
import SwiftData
import LockTuneDomain

@Model
private final class StoredTrack {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var contentFingerprint: String
    var title: String?
    var artist: String?
    var album: String?
    var trackNumber: Int?
    var duration: TimeInterval?
    var artworkCacheKey: String?
    var metadataStatus: String

    init(_ track: Track) {
        id = track.id
        contentFingerprint = track.contentFingerprint
        title = track.metadata.title
        artist = track.metadata.artist
        album = track.metadata.album
        trackNumber = track.metadata.trackNumber
        duration = track.metadata.duration
        artworkCacheKey = track.metadata.artworkCacheKey
        metadataStatus = track.metadata.status.rawValue
    }

    var domain: Track {
        Track(
            id: id,
            contentFingerprint: contentFingerprint,
            metadata: TrackMetadata(
                title: title,
                artist: artist,
                album: album,
                trackNumber: trackNumber,
                duration: duration,
                artworkCacheKey: artworkCacheKey,
                status: MetadataStatus(rawValue: metadataStatus) ?? .unavailable
            )
        )
    }
}

@Model
private final class StoredTrackLocation {
    @Attribute(.unique) var id: String
    var trackID: UUID
    var url: URL
    var format: String
    var fileSize: Int64?
    var contentModificationDate: Date?

    init(_ location: TrackLocation) {
        id = location.id
        trackID = location.trackID
        url = location.url
        format = location.format.rawValue
        fileSize = location.fileSize
        contentModificationDate = location.contentModificationDate
    }

    var domain: TrackLocation? {
        guard let format = AudioFileFormat(rawValue: format) else { return nil }
        return TrackLocation(
            trackID: trackID,
            url: url,
            format: format,
            fileSize: fileSize,
            contentModificationDate: contentModificationDate
        )
    }
}

@Model
private final class StoredScanIssue {
    var url: URL
    var reason: String

    init(_ issue: MusicScanIssue) {
        url = issue.url
        reason = issue.reason.rawValue
    }

    var domain: MusicScanIssue? {
        guard let reason = MusicScanIssueReason(rawValue: reason) else { return nil }
        return MusicScanIssue(url: url, reason: reason)
    }
}

@Model
private final class StoredMusicIndexState {
    @Attribute(.unique) var id: String
    var lastCompletedAt: Date?

    init(_ state: MusicScanState) {
        id = "music-index"
        lastCompletedAt = state.lastCompletedAt
    }

    var domain: MusicScanState {
        MusicScanState(lastCompletedAt: lastCompletedAt)
    }
}

public actor MusicIndexStore {
    private let container: ModelContainer

    public init(inMemory: Bool = false) throws {
        let schema = Schema([
            StoredTrack.self,
            StoredTrackLocation.self,
            StoredScanIssue.self,
            StoredMusicIndexState.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        container = try ModelContainer(for: schema, configurations: [configuration])
    }

    public func save(_ snapshot: MusicLibrarySnapshot) throws {
        let context = ModelContext(container)
        try context.fetch(FetchDescriptor<StoredTrack>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<StoredTrackLocation>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<StoredScanIssue>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<StoredMusicIndexState>()).forEach(context.delete)
        snapshot.tracks.map(StoredTrack.init).forEach(context.insert)
        snapshot.locations.map(StoredTrackLocation.init).forEach(context.insert)
        snapshot.issues.map(StoredScanIssue.init).forEach(context.insert)
        context.insert(StoredMusicIndexState(snapshot.scanState))
        try context.save()
    }

    public func load() throws -> MusicLibrarySnapshot {
        let context = ModelContext(container)
        let tracks = try context.fetch(FetchDescriptor<StoredTrack>()).map(\.domain)
        let locations = try context.fetch(FetchDescriptor<StoredTrackLocation>()).compactMap(\.domain)
        let issues = try context.fetch(FetchDescriptor<StoredScanIssue>()).compactMap(\.domain)
        let scanState = try context.fetch(FetchDescriptor<StoredMusicIndexState>()).first?.domain
            ?? MusicScanState()
        return MusicLibrarySnapshot(
            tracks: tracks,
            locations: locations,
            issues: issues,
            scanState: scanState
        )
    }
}
