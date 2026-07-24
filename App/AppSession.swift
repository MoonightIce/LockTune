import Observation
import LockTuneCore

@MainActor
@Observable
final class AppSession {
    let islandCoordinator = IslandCoordinator()
    var currentTrackTitle = String(localized: "player.nothingPlaying")
    var nextMeetingTitle: String?
}
