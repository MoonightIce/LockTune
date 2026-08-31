import LockTuneCore
import LockTuneDomain
import Testing

@Test("An imminent meeting takes the island from normal music playback")
func imminentMeetingTakesPriorityOverNormalMusic() {
    let coordinator = IslandCoordinator()
    let context = IslandContext(
        hasCurrentTrack: true,
        minutesUntilMeeting: 8
    )

    #expect(coordinator.presentation(for: context) == .meeting)
}

@Test("Normal music playback owns the island when no meeting is imminent")
func normalMusicOwnsTheIslandWithoutImminentMeeting() {
    let coordinator = IslandCoordinator()
    let context = IslandContext(
        hasCurrentTrack: true,
        minutesUntilMeeting: 30
    )

    #expect(coordinator.presentation(for: context) == .music)
}

@Test("The island is hidden when disabled or when the macOS session is inactive")
func islandVisibilityHonorsPrivacyAndPreference() {
    let coordinator = IslandCoordinator()

    #expect(coordinator.isVisible(isEnabled: true, isSessionActive: true))
    #expect(!coordinator.isVisible(isEnabled: false, isSessionActive: true))
    #expect(!coordinator.isVisible(isEnabled: true, isSessionActive: false))
    #expect(!coordinator.isVisible(isEnabled: false, isSessionActive: false))
}

@Test("Island geometry separates content from three container expansion states")
func islandGeometryAdaptsToPresentationAndAttachment() {
    let coordinator = IslandCoordinator()

    for attachment in [IslandAttachment.floatingCapsule, .notchAttached] {
        #expect(coordinator.geometry(for: .idle, attachment: attachment, expansionState: .collapsed).height == 32)
        #expect(coordinator.geometry(for: .idle, attachment: attachment, expansionState: .hovered).height == 47)
        #expect(coordinator.geometry(for: .idle, attachment: attachment, expansionState: .expanded).height == 132)
    }

    #expect(coordinator.geometry(for: .idle, attachment: .floatingCapsule, expansionState: .collapsed) == IslandSurfaceGeometry(
        width: 196, height: 32, cornerRadius: 16, topCornerRadius: 16
    ))
    #expect(coordinator.geometry(for: .idle, attachment: .floatingCapsule, expansionState: .hovered) == IslandSurfaceGeometry(
        width: 208, height: 47, cornerRadius: 23.5, topCornerRadius: 23.5
    ))
    #expect(coordinator.geometry(for: .music, attachment: .floatingCapsule, expansionState: .expanded) == IslandSurfaceGeometry(
        width: 420, height: 132, cornerRadius: 32, topCornerRadius: 32
    ))
    #expect(coordinator.geometry(for: .music, attachment: .notchAttached, expansionState: .collapsed) == IslandSurfaceGeometry(
        width: 0, height: 32, cornerRadius: 10, topCornerRadius: 10, notchSideInset: 80
    ))
    #expect(coordinator.geometry(
        for: .music,
        attachment: .notchAttached,
        expansionState: .collapsed,
        collapsedReferenceHeight: 28
    ).height == 28)
    #expect(coordinator.geometry(for: .music, attachment: .notchAttached, expansionState: .hovered) == IslandSurfaceGeometry(
        width: 0, height: 47, cornerRadius: 23, topCornerRadius: 11, notchSideInset: 32
    ))
    #expect(coordinator.geometry(for: .meeting, attachment: .notchAttached, expansionState: .expanded) == IslandSurfaceGeometry(
        width: 440, height: 132, cornerRadius: 26, topCornerRadius: 12, notchSideInset: 24,
        shoulderInset: 20
    ))
}

@Test("Only an expanded notch surface carries a shoulder, so the morph interpolates into it")
func islandShoulderInsetIsExclusiveToExpandedNotchSurfaces() {
    let coordinator = IslandCoordinator()

    // The shoulder grows in from zero rather than the silhouette switching
    // shape, which is what keeps the morph free of a width jump.
    #expect(coordinator.geometry(for: .idle, attachment: .notchAttached, expansionState: .collapsed).shoulderInset == 0)
    #expect(coordinator.geometry(for: .idle, attachment: .notchAttached, expansionState: .hovered).shoulderInset == 0)
    #expect(coordinator.geometry(for: .idle, attachment: .notchAttached, expansionState: .expanded).shoulderInset == 20)

    // A floating capsule has no screen edge to meet, so it never gets one.
    for state in [IslandExpansionState.collapsed, .hovered, .expanded] {
        #expect(coordinator.geometry(for: .idle, attachment: .floatingCapsule, expansionState: state).shoulderInset == 0)
    }
}

@Test("Reduce Motion removes surface and optical animation")
func reduceMotionStopsIslandAnimation() {
    let coordinator = IslandCoordinator()

    #expect(coordinator.motion(reduceMotion: false, materialMotionEnabled: true) == IslandMotionPolicy(
        hoverDuration: 0.22,
        expansionDuration: 0.38,
        collapseDuration: 0.30,
        animatesOpticalHighlight: true
    ))
    #expect(coordinator.motion(reduceMotion: true, materialMotionEnabled: true) == IslandMotionPolicy(
        hoverDuration: 0,
        expansionDuration: 0,
        collapseDuration: 0,
        animatesOpticalHighlight: false
    ))
    #expect(!coordinator.motion(reduceMotion: false, materialMotionEnabled: false).animatesOpticalHighlight)
}

@Test("Notch compact states keep a wing-only content surface available")
func islandCompactContentAvoidsNotchCutout() {
    let coordinator = IslandCoordinator()
    #expect(coordinator.showsCompactContent(attachment: .floatingCapsule, expansionState: .collapsed))
    #expect(coordinator.showsCompactContent(attachment: .floatingCapsule, expansionState: .hovered))
    #expect(coordinator.showsCompactContent(attachment: .notchAttached, expansionState: .collapsed))
    #expect(coordinator.showsCompactContent(attachment: .notchAttached, expansionState: .hovered))
    #expect(coordinator.showsCompactContent(attachment: .notchAttached, expansionState: .expanded))
}

@Test("A hovered surface stays seamless with the notch instead of taking the 60% band")
func islandSurfaceShadeKeepsHoveredSurfaceSeamlessWithNotch() {
    let coordinator = IslandCoordinator()
    // The hovered surface is only 15pt taller than the notch it grows from, so
    // the status bar's 66% share overrides the 60% default and the whole notch
    // band stays pure black.
    let hovered = coordinator.geometry(for: .idle, attachment: .notchAttached, expansionState: .hovered)
    let shade = coordinator.surfaceShade(statusBarHeight: 31, surfaceHeight: hovered.height)

    let solidEnd = shade.stops.filter { $0.opacity == 1 }.map(\.location).max()
    #expect(solidEnd == 31.0 / 47.0)
    #expect(solidEnd! > 0.60)
    // It still lands on the same floor as the expanded surface, so the shade
    // interpolates continuously between the two states.
    #expect(shade.stops.last?.opacity == 0.27)
}

@Test("The surface shade reproduces the measured Droppy profile")
func islandSurfaceShadeMatchesMeasuredProfile() {
    let coordinator = IslandCoordinator()
    let shade = coordinator.surfaceShade(statusBarHeight: 33, surfaceHeight: 132)

    // Pure black through 60%, linear to the 0.27 floor by 92%, floor held to
    // the bottom edge. A 33pt status bar on a 132pt surface is only 25%, so
    // the 60% default governs.
    #expect(shade.stops.map(\.location) == [0, 0.60, 0.92, 1])
    #expect(shade.stops.map(\.opacity) == [1, 1, 0.27, 0.27])

    // Locations stay monotonic and opacity never rises back up.
    #expect(zip(shade.stops, shade.stops.dropFirst()).allSatisfy {
        $0.location <= $1.location && $0.opacity >= $1.opacity
    })
}

@Test("A status bar past 60% of the surface extends the opaque band")
func islandSurfaceShadeExtendsOpaqueBandForTallStatusBar() {
    let coordinator = IslandCoordinator()
    let shade = coordinator.surfaceShade(statusBarHeight: 100, surfaceHeight: 132)

    let solidEnd = shade.stops.filter { $0.opacity == 1 }.map(\.location).max()
    #expect(solidEnd == 100.0 / 132.0)
    #expect(shade.stops.last?.opacity == 0.27)
}

@Test("A floating capsule keeps the same 60% band without a status bar to cover")
func islandSurfaceShadeAppliesDefaultBandToFloatingCapsule() {
    let coordinator = IslandCoordinator()
    let shade = coordinator.surfaceShade(statusBarHeight: 0, surfaceHeight: 132)

    #expect(shade.stops.map(\.location) == [0, 0.60, 0.92, 1])
    #expect(shade.stops.map(\.opacity) == [1, 1, 0.27, 0.27])
}

@Test("Surfaces with no room to ramp, and Reduce Transparency, stay fully opaque")
func islandSurfaceShadeStaysOpaqueWithoutRoomToRamp() {
    let coordinator = IslandCoordinator()
    for shade in [
        // Still measuring at zero height.
        coordinator.surfaceShade(statusBarHeight: 33, surfaceHeight: 0),
        // Status bar taller than the whole surface.
        coordinator.surfaceShade(statusBarHeight: 200, surfaceHeight: 132),
        // Opaque accessibility backing.
        coordinator.surfaceShade(statusBarHeight: 33, surfaceHeight: 132, reduceTransparency: true),
    ] {
        #expect(shade.stops.allSatisfy { $0.opacity == 1 })
    }
}

@Test("Island geometry preserves top gap and notch width invariants")
func islandGeometryPreservesDisplayInvariants() {
    let coordinator = IslandCoordinator()
    #expect(coordinator.floatingTopGap(menuBarHeight: 0) == 6)
    #expect(coordinator.floatingTopGap(menuBarHeight: 24) == 8)
    #expect(coordinator.floatingTopGap(menuBarHeight: 60) == 10)

    let collapsed = coordinator.geometry(for: .idle, attachment: .notchAttached, expansionState: .collapsed)
    #expect(coordinator.resolvedWidth(
        for: collapsed,
        attachment: .notchAttached,
        hardwareNotchWidth: 180
    ) == 260)
    #expect(coordinator.resolvedWidth(
        for: collapsed,
        attachment: .notchAttached,
        hardwareNotchWidth: 260
    ) == 340)
    #expect(coordinator.resolvedWidth(
        for: coordinator.geometry(for: .idle, attachment: .floatingCapsule, expansionState: .expanded),
        attachment: .floatingCapsule,
        hardwareNotchWidth: 0,
        availableWidth: 400
    ) == 400)
}

@Test("Preferred display wins, otherwise the current main display is used")
func islandDisplayResolutionHonorsPreference() {
    let coordinator = IslandCoordinator()
    let displays = [
        IslandDisplay(id: "builtin", name: "Built-in", hasNotch: true),
        IslandDisplay(id: "desk", name: "Desk", hasNotch: false),
    ]

    #expect(coordinator.resolveDisplay(preferredID: "desk", mainDisplayID: "builtin", displays: displays)?.id == "desk")
    #expect(coordinator.resolveDisplay(preferredID: "missing", mainDisplayID: "builtin", displays: displays)?.id == "builtin")
    #expect(coordinator.resolveDisplay(preferredID: nil, mainDisplayID: nil, displays: displays)?.id == "builtin")
}

@Test("Panel placement anchors a notch display to the physical screen top")
func notchPanelPlacementUsesScreenFrameTop() {
    let coordinator = IslandCoordinator()
    let display = IslandDisplayGeometry(
        displayID: 1,
        frame: IslandRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: IslandRect(x: 0, y: 90, width: 1512, height: 859),
        safeAreaInsets: IslandEdgeInsets(top: 32, left: 0, bottom: 0, right: 0),
        auxiliaryTopLeftArea: IslandRect(x: 0, y: 950, width: 665, height: 32),
        auxiliaryTopRightArea: IslandRect(x: 850, y: 950, width: 662, height: 32),
        attachment: .notchAttached
    )

    let placement = coordinator.panelPlacement(for: display, panelWidth: 440, panelHeight: 132)

    #expect(placement.topGap == 0)
    #expect(placement.targetTop == display.frame.maxY)
    #expect(placement.frame.maxY == display.frame.maxY)
    #expect(placement.frame == IslandRect(x: 536, y: 850, width: 440, height: 132))
    #expect(display.hardwareNotchWidth == 185)
    #expect(display.hardwareNotchHeight == 32)
}

@Test("Panel placement preserves the floating gap on negative-coordinate displays")
func floatingPanelPlacementPreservesNegativeDisplayCoordinates() {
    let coordinator = IslandCoordinator()
    let display = IslandDisplayGeometry(
        displayID: 2,
        frame: IslandRect(x: -1920, y: 800, width: 1920, height: 1080),
        visibleFrame: IslandRect(x: -1920, y: 800, width: 1920, height: 990),
        safeAreaInsets: IslandEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
        auxiliaryTopLeftArea: nil,
        auxiliaryTopRightArea: nil,
        attachment: .floatingCapsule
    )

    let placement = coordinator.panelPlacement(for: display, panelWidth: 196, panelHeight: 42)

    #expect(placement.topGap == 10)
    #expect(placement.targetTop == 1780)
    #expect(placement.frame == IslandRect(x: -1058, y: 1738, width: 196, height: 42))
    #expect(placement.frame.maxY == placement.targetTop)
}

@Test("Panel placement handles a vertically stacked display without using the origin")
func panelPlacementHandlesVerticallyStackedDisplay() {
    let coordinator = IslandCoordinator()
    let display = IslandDisplayGeometry(
        displayID: 3,
        frame: IslandRect(x: 0, y: 982, width: 1512, height: 982),
        visibleFrame: IslandRect(x: 0, y: 1072, width: 1512, height: 859),
        safeAreaInsets: IslandEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
        auxiliaryTopLeftArea: nil,
        auxiliaryTopRightArea: nil,
        attachment: .floatingCapsule
    )

    let placement = coordinator.panelPlacement(for: display, panelWidth: 208, panelHeight: 47)

    #expect(placement.topGap == 10)
    #expect(placement.targetTop == 1921)
    #expect(placement.frame.minX == 652)
    #expect(placement.frame.maxY == 1921)
}

@Test("Glass backing exposes five stable levels and rounds imported values")
func glassBackingLevelsAreStable() {
    #expect(GlassBackingLevel.allCases.map(\.rawValue) == [0, 25, 50, 75, 100])
    #expect(GlassBackingLevel(nearest: -20) == .clear)
    #expect(GlassBackingLevel(nearest: 18) == .light)
    #expect(GlassBackingLevel(nearest: 62) == .medium)
    #expect(GlassBackingLevel(nearest: 91) == .solid)
    #expect(GlassBackingLevel(migratingLegacyBlur: 0) == .clear)
    #expect(GlassBackingLevel(migratingLegacyBlur: 1) == .light)
    #expect(GlassBackingLevel(migratingLegacyBlur: 36) == .solid)
}

@Test("Liquid Glass configuration defaults to the Dock recipe")
func liquidGlassConfigurationUsesDockDefaults() {
    let configuration = LiquidGlassConfiguration(
        tint: 0.8,
        backingLevel: .medium,
        lensing: 99
    )

    #expect(configuration.variant == 2)
    #expect(configuration.lensing == 6)
    #expect(configuration.scrim == 0)
    #expect(configuration.subdued == 0)
    #expect(configuration.backingAlpha == 0.5)
    #expect(configuration.tintOpacity == 0.3)
}

@Test("Liquid Glass dispatch keeps variant before lensing and disables private path cleanly")
func liquidGlassDispatchPlanIsOrderedAndObservable() {
    let complete = LiquidGlassConfiguration(
        tint: 0.1,
        backingLevel: .clear,
        lensing: 6
    )
    let fallback = LiquidGlassConfiguration(
        tint: 0.1,
        backingLevel: .clear,
        lensing: 6,
        privateRefractionEnabled: false
    )

    #expect(complete.dispatchPlan.commands == [
        .variant(2), .contentLensing(6), .scrim(0), .subdued(0), .tint(0.1)
    ])
    #expect(fallback.dispatchPlan.commands[0...1].elementsEqual([.variant(2), .contentLensing(0)]))
}
