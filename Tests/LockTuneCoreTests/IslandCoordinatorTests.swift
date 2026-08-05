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
        #expect(coordinator.geometry(for: .idle, attachment: attachment, expansionState: .collapsed).height == 42)
        #expect(coordinator.geometry(for: .idle, attachment: attachment, expansionState: .hovered).height == 47)
        #expect(coordinator.geometry(for: .idle, attachment: attachment, expansionState: .expanded).height == 132)
    }

    #expect(coordinator.geometry(for: .idle, attachment: .floatingCapsule, expansionState: .collapsed) == IslandSurfaceGeometry(
        width: 196, height: 42, cornerRadius: 21, topCornerRadius: 21
    ))
    #expect(coordinator.geometry(for: .idle, attachment: .floatingCapsule, expansionState: .hovered) == IslandSurfaceGeometry(
        width: 208, height: 47, cornerRadius: 23.5, topCornerRadius: 23.5
    ))
    #expect(coordinator.geometry(for: .music, attachment: .floatingCapsule, expansionState: .expanded) == IslandSurfaceGeometry(
        width: 420, height: 132, cornerRadius: 32, topCornerRadius: 32
    ))
    #expect(coordinator.geometry(for: .music, attachment: .notchAttached, expansionState: .collapsed) == IslandSurfaceGeometry(
        width: 0, height: 42, cornerRadius: 21, topCornerRadius: 10, notchSideInset: 20
    ))
    #expect(coordinator.geometry(for: .music, attachment: .notchAttached, expansionState: .hovered) == IslandSurfaceGeometry(
        width: 0, height: 47, cornerRadius: 23, topCornerRadius: 11, notchSideInset: 32
    ))
    #expect(coordinator.geometry(for: .meeting, attachment: .notchAttached, expansionState: .expanded) == IslandSurfaceGeometry(
        width: 440, height: 132, cornerRadius: 26, topCornerRadius: 12, notchSideInset: 24
    ))
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
    ) == 200)
    #expect(coordinator.resolvedWidth(
        for: collapsed,
        attachment: .notchAttached,
        hardwareNotchWidth: 260
    ) == 280)
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
