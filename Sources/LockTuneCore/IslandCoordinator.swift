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
        attachment: IslandAttachment,
        expansionState: IslandExpansionState
    ) -> IslandSurfaceGeometry {
        let isNotched = attachment == .notchAttached
        switch expansionState {
        case .collapsed:
            return IslandSurfaceGeometry(
                width: isNotched ? 0 : 196,
                height: 42,
                cornerRadius: isNotched ? 21 : 21,
                topCornerRadius: isNotched ? 10 : 21,
                notchSideInset: isNotched ? 20 : 0
            )
        case .hovered:
            return IslandSurfaceGeometry(
                width: isNotched ? 0 : 208,
                height: 47,
                cornerRadius: isNotched ? 23 : 23.5,
                topCornerRadius: isNotched ? 11 : 23.5,
                notchSideInset: isNotched ? 32 : 0
            )
        case .expanded:
            let expandedWidth: Double
            switch presentation {
            case .idle, .music: expandedWidth = 420
            case .meeting: expandedWidth = 440
            }
            return IslandSurfaceGeometry(
                width: expandedWidth,
                height: 132,
                cornerRadius: isNotched ? 26 : 32,
                topCornerRadius: isNotched ? 12 : 32,
                notchSideInset: isNotched ? 24 : 0
            )
        }
    }

    public func floatingTopGap(menuBarHeight: Double) -> Double {
        min(max(max(0, menuBarHeight) / 3, 6), 10)
    }

    public func panelPlacement(
        for display: IslandDisplayGeometry,
        panelWidth: Double,
        panelHeight: Double
    ) -> IslandPanelPlacement {
        let menuBarHeight = max(0, display.frame.maxY - display.visibleFrame.maxY)
        let topGap = display.attachment == .notchAttached
            ? 0
            : floatingTopGap(menuBarHeight: menuBarHeight)
        let targetTop = display.attachment == .notchAttached
            ? display.frame.maxY
            : display.visibleFrame.maxY - topGap
        let frame = IslandRect(
            x: display.frame.midX - panelWidth / 2,
            y: targetTop - panelHeight,
            width: panelWidth,
            height: panelHeight
        )
        return IslandPanelPlacement(frame: frame, targetTop: targetTop, topGap: topGap)
    }

    public func resolvedWidth(
        for geometry: IslandSurfaceGeometry,
        attachment: IslandAttachment,
        hardwareNotchWidth: Double,
        availableWidth: Double? = nil
    ) -> Double {
        let minimumNotchWidth = attachment == .notchAttached
            ? max(0, hardwareNotchWidth) + geometry.notchSideInset
            : 0
        let preferredWidth = max(geometry.width, minimumNotchWidth)
        guard let availableWidth else { return preferredWidth }
        return min(preferredWidth, max(minimumNotchWidth, availableWidth))
    }

    public func motion(
        reduceMotion: Bool,
        materialMotionEnabled: Bool
    ) -> IslandMotionPolicy {
        IslandMotionPolicy(
            hoverDuration: reduceMotion ? 0 : 0.22,
            expansionDuration: reduceMotion ? 0 : 0.38,
            collapseDuration: reduceMotion ? 0 : 0.30,
            animatesOpticalHighlight: !reduceMotion && materialMotionEnabled
        )
    }

    /// The hardware notch consumes the top portion of the collapsed and
    /// hovered surface. Text in that narrow remainder is not readable, so
    /// compact copy is reserved for floating capsules and expanded panels.
    public func showsCompactContent(
        attachment: IslandAttachment,
        expansionState: IslandExpansionState
    ) -> Bool {
        attachment != .notchAttached || expansionState == .expanded
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
