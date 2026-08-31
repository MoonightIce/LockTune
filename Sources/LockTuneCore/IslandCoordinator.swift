import LockTuneDomain

public struct IslandCoordinator: Sendable {
    /// Horizontal shoulder inset for an expanded notch-attached surface,
    /// measured off Droppy 14.2.0.
    public static let expandedShoulderInset = 20.0

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
        expansionState: IslandExpansionState,
        collapsedReferenceHeight: Double = 32
    ) -> IslandSurfaceGeometry {
        let isNotched = attachment == .notchAttached
        switch expansionState {
        case .collapsed:
            return IslandSurfaceGeometry(
                width: isNotched ? 0 : 196,
                height: max(1, collapsedReferenceHeight),
                cornerRadius: isNotched ? min(10, max(1, collapsedReferenceHeight) / 2) : max(1, collapsedReferenceHeight) / 2,
                topCornerRadius: isNotched ? 10 : max(1, collapsedReferenceHeight) / 2,
                notchSideInset: isNotched ? 80 : 0
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
                notchSideInset: isNotched ? 24 : 0,
                // 20pt matches the horizontal inset measured off Droppy 14.2.0.
                // Only the expanded surface carries a shoulder; the shorter
                // states interpolate up to it from zero.
                shoulderInset: isNotched ? Self.expandedShoulderInset : 0
            )
        }
    }

    /// Fraction of the surface held at full opacity before the ramp starts.
    /// Measured from Droppy 14.2.0, whose shade stays pure black through the
    /// top 60% of its 208pt panel. A surface shorter than the status bar's
    /// share of it overrides this upward.
    static let shadeSolidFraction = 0.60
    /// Where the linear ramp reaches its floor. Past this the shade is flat.
    static let shadeFloorStart = 0.92
    /// The shade never reaches zero. This residual black is what gives the
    /// bottom edge its weight; ramping to fully clear reads as washed out.
    static let shadeFloorOpacity = 0.27

    /// Vertical shade for a hovered or expanded surface, profiled off Droppy
    /// 14.2.0: pure black through the top 60%, a linear fall to 0.27 by 92%,
    /// then that floor held to the bottom edge. Glass refraction still shows
    /// through the floor, so the bottom stays a lens rather than a painted
    /// panel. The status-bar band stays opaque even when it reaches past 60%,
    /// which is what keeps a short hovered surface seamless with the hardware
    /// notch. Reduce Transparency keeps the shade opaque, as its backing is too.
    public func surfaceShade(
        statusBarHeight: Double,
        surfaceHeight: Double,
        reduceTransparency: Bool = false
    ) -> IslandSurfaceShade {
        let opaque = IslandSurfaceShade(stops: [
            IslandSurfaceShade.Stop(location: 0, opacity: 1),
            IslandSurfaceShade.Stop(location: 1, opacity: 1),
        ])
        guard !reduceTransparency, surfaceHeight > 0 else { return opaque }

        let statusBarFraction = min(max(statusBarHeight, 0), surfaceHeight) / surfaceHeight
        let solidEnd = min(max(Self.shadeSolidFraction, statusBarFraction), 1)
        guard solidEnd < Self.shadeFloorStart else { return opaque }

        return IslandSurfaceShade(stops: [
            IslandSurfaceShade.Stop(location: 0, opacity: 1),
            IslandSurfaceShade.Stop(location: solidEnd, opacity: 1),
            IslandSurfaceShade.Stop(location: Self.shadeFloorStart, opacity: Self.shadeFloorOpacity),
            IslandSurfaceShade.Stop(location: 1, opacity: Self.shadeFloorOpacity),
        ])
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

    /// Compact content remains present for notched displays. The view chooses
    /// the wing-only icon layout for collapsed/hovered states so the physical
    /// notch is never covered by text while the two wings remain interactive.
    public func showsCompactContent(
        attachment: IslandAttachment,
        expansionState _: IslandExpansionState
    ) -> Bool {
        true
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
