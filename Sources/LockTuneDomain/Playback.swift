import Foundation

public struct PlaybackItem: Identifiable, Equatable, Codable, Sendable {
    public let trackID: UUID
    public let locationID: String
    public let url: URL
    public let title: String
    public let artist: String?
    public let duration: TimeInterval?

    public var id: String { locationID }

    public init(
        trackID: UUID,
        locationID: String,
        url: URL,
        title: String,
        artist: String? = nil,
        duration: TimeInterval? = nil
    ) {
        self.trackID = trackID
        self.locationID = locationID
        self.url = url
        self.title = title
        self.artist = artist
        self.duration = duration
    }
}

public enum PlaybackPhase: String, Equatable, Codable, Sendable {
    case idle
    case loading
    case playing
    case paused
    case failed
}

public enum PlaybackFailureReason: String, Equatable, Codable, Sendable {
    case cannotOpen
    case decodingFailed
    case audioOutputUnavailable
}

public struct PlaybackSnapshot: Equatable, Codable, Sendable {
    public var queue: [PlaybackItem]
    public var currentIndex: Int?
    public var phase: PlaybackPhase
    public var elapsed: TimeInterval
    public var duration: TimeInterval?
    public var volume: Float
    public var failureReason: PlaybackFailureReason?

    public var currentItem: PlaybackItem? {
        guard let currentIndex, queue.indices.contains(currentIndex) else { return nil }
        return queue[currentIndex]
    }

    public init(
        queue: [PlaybackItem] = [],
        currentIndex: Int? = nil,
        phase: PlaybackPhase = .idle,
        elapsed: TimeInterval = 0,
        duration: TimeInterval? = nil,
        volume: Float = 1,
        failureReason: PlaybackFailureReason? = nil
    ) {
        self.queue = queue
        self.currentIndex = currentIndex
        self.phase = phase
        self.elapsed = elapsed
        self.duration = duration
        self.volume = volume
        self.failureReason = failureReason
    }
}
