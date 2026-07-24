import Foundation

public enum IslandPresentation: Equatable, Sendable {
    case idle
    case music
    case meeting
}

public struct IslandContext: Equatable, Sendable {
    public var isMusicPlaying: Bool
    public var minutesUntilMeeting: Int?

    public init(
        isMusicPlaying: Bool,
        minutesUntilMeeting: Int?
    ) {
        self.isMusicPlaying = isMusicPlaying
        self.minutesUntilMeeting = minutesUntilMeeting
    }
}
