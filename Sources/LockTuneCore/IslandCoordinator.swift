import LockTuneDomain

public struct IslandCoordinator: Sendable {
    public init() {}

    public func presentation(for context: IslandContext) -> IslandPresentation {
        if let minutesUntilMeeting = context.minutesUntilMeeting,
           (0...10).contains(minutesUntilMeeting) {
            return .meeting
        }

        if context.isMusicPlaying {
            return .music
        }

        return .idle
    }
}
