import LockTuneDomain

public struct IslandCoordinator: Sendable {
    public init() {}

    public func presentation(for context: IslandContext) -> IslandPresentation {
        if let minutesUntilMeeting = context.minutesUntilMeeting,
           (0...10).contains(minutesUntilMeeting) {
            return .meeting
        }

        if context.hasCurrentTrack {
            return .music
        }

        return .idle
    }

    public func isVisible(isEnabled: Bool, isSessionActive: Bool) -> Bool {
        isEnabled && isSessionActive
    }

    public func geometry(
        for presentation: IslandPresentation,
        attachment: IslandAttachment
    ) -> IslandSurfaceGeometry {
        let dimensions: (width: Double, height: Double, radius: Double)
        switch presentation {
        case .idle:
            dimensions = attachment == .notchAttached ? (210, 70, 27) : (210, 54, 27)
        case .music: dimensions = (420, 82, 30)
        case .meeting: dimensions = (440, 76, 30)
        }
        return IslandSurfaceGeometry(
            width: dimensions.width,
            height: dimensions.height,
            cornerRadius: dimensions.radius,
            topCornerRadius: attachment == .notchAttached ? 0 : dimensions.radius
        )
    }

    public func motion(
        reduceMotion: Bool,
        materialMotionEnabled: Bool
    ) -> IslandMotionPolicy {
        IslandMotionPolicy(
            transitionDuration: reduceMotion ? 0 : 0.28,
            animatesOpticalHighlight: !reduceMotion && materialMotionEnabled
        )
    }

    public func resolveDisplay(
        preferredID: String?,
        mainDisplayID: String?,
        displays: [IslandDisplay]
    ) -> IslandDisplay? {
        if let preferredID, let preferred = displays.first(where: { $0.id == preferredID }) {
            return preferred
        }
        if let mainDisplayID, let main = displays.first(where: { $0.id == mainDisplayID }) {
            return main
        }
        return displays.first
    }
}
