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

@Test("Island geometry keeps one surface while adapting to content and hardware")
func islandGeometryAdaptsToPresentationAndAttachment() {
    let coordinator = IslandCoordinator()

    #expect(coordinator.geometry(for: .music, attachment: .floatingCapsule) == IslandSurfaceGeometry(
        width: 420,
        height: 82,
        cornerRadius: 30,
        topCornerRadius: 30
    ))
    #expect(coordinator.geometry(for: .music, attachment: .notchAttached) == IslandSurfaceGeometry(
        width: 420,
        height: 82,
        cornerRadius: 30,
        topCornerRadius: 0
    ))
    #expect(coordinator.geometry(for: .idle, attachment: .notchAttached).height == 70)
    #expect(coordinator.geometry(for: .idle, attachment: .floatingCapsule).height == 54)
    #expect(coordinator.geometry(for: .meeting, attachment: .notchAttached).width == 440)
}

@Test("Reduce Motion removes surface and optical animation")
func reduceMotionStopsIslandAnimation() {
    let coordinator = IslandCoordinator()

    #expect(coordinator.motion(reduceMotion: false, materialMotionEnabled: true) == IslandMotionPolicy(
        transitionDuration: 0.28,
        animatesOpticalHighlight: true
    ))
    #expect(coordinator.motion(reduceMotion: true, materialMotionEnabled: true) == IslandMotionPolicy(
        transitionDuration: 0,
        animatesOpticalHighlight: false
    ))
    #expect(!coordinator.motion(reduceMotion: false, materialMotionEnabled: false).animatesOpticalHighlight)
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
