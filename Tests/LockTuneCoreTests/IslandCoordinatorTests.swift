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
}
