import LockTuneCore
import LockTuneDomain
import Testing

@Test("An imminent meeting takes the island from normal music playback")
func imminentMeetingTakesPriorityOverNormalMusic() {
    let coordinator = IslandCoordinator()
    let context = IslandContext(
        isMusicPlaying: true,
        minutesUntilMeeting: 8
    )

    #expect(coordinator.presentation(for: context) == .meeting)
}

@Test("Normal music playback owns the island when no meeting is imminent")
func normalMusicOwnsTheIslandWithoutImminentMeeting() {
    let coordinator = IslandCoordinator()
    let context = IslandContext(
        isMusicPlaying: true,
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

@Test("Glass controls map to TokenClock's native refraction properties")
func glassControlsDriveLiveSurfaceAppearance() {
    let minimum = GlassMaterialAppearance(tint: 0, backingLevel: .clear, refraction: 0)
    let maximum = GlassMaterialAppearance(tint: 0.3, backingLevel: .solid, refraction: 6)

    #expect(minimum.tintOpacity == 0)
    #expect(maximum.tintOpacity == 0.3)
    #expect(minimum.backdropOpacity == 0)
    #expect(maximum.backdropOpacity == 1)
    #expect(minimum.variant == 2)
    #expect(maximum.variant == 2)
    #expect(minimum.lensing == 0)
    #expect(maximum.lensing == 6)
}

@Test("Glass appearance clamps persisted values to the supported laboratory range")
func glassAppearanceClampsPersistedValues() {
    let appearance = GlassMaterialAppearance(tint: 2, backingLevel: .light, refraction: 900)

    #expect(appearance.tintOpacity == 0.3)
    #expect(appearance.backdropOpacity == 0.25)
    #expect(appearance.refractionAmount == 6)
    #expect(appearance.lensing == 6)
}

@Test("Glass refraction rounds into the private 0 through 6 lensing range")
func glassRefractionMapsToPrivateLensingRange() {
    #expect(GlassMaterialAppearance(tint: 0, backingLevel: .clear, refraction: 1).lensing == 1)
    #expect(GlassMaterialAppearance(tint: 0, backingLevel: .clear, refraction: 3).lensing == 3)
    #expect(GlassMaterialAppearance(tint: 0, backingLevel: .clear, refraction: 5).lensing == 5)
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
    let complete = LiquidGlassConfiguration(tint: 0.1, backingLevel: .clear, lensing: 6)
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
