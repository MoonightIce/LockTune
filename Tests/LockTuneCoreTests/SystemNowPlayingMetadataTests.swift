import Foundation
import LockTuneDomain
@testable import LockTuneInfrastructure
import MediaPlayer
import Testing

@Test("System Now Playing info includes album and current playback state")
func systemNowPlayingInfoIncludesAlbum() {
    let item = PlaybackItem(
        trackID: UUID(),
        locationID: "location",
        url: URL(fileURLWithPath: "/tmp/slow-motion.m4a"),
        title: "Slow Motion",
        artist: "Mira Coast",
        album: "Afterimage",
        duration: 227
    )
    let snapshot = PlaybackSnapshot(
        queue: [item],
        currentIndex: 0,
        phase: .playing,
        elapsed: 86,
        duration: 227
    )

    let info = makeSystemNowPlayingInfo(from: snapshot)

    #expect(info?[MPMediaItemPropertyTitle] as? String == "Slow Motion")
    #expect(info?[MPMediaItemPropertyArtist] as? String == "Mira Coast")
    #expect(info?[MPMediaItemPropertyAlbumTitle] as? String == "Afterimage")
    #expect(info?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? TimeInterval == 86)
    #expect(info?[MPMediaItemPropertyPlaybackDuration] as? TimeInterval == 227)
    #expect(info?[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 1)
    #expect(info?[MPNowPlayingInfoPropertyExternalContentIdentifier] as? String == "location")
}

@Test("System Now Playing info clears when the queue has no current item")
func systemNowPlayingInfoClearsWithoutCurrentItem() {
    #expect(makeSystemNowPlayingInfo(from: PlaybackSnapshot()) == nil)
}

@MainActor
@Test("System Now Playing clears stale state and follows queue command semantics")
func systemNowPlayingCenterClearsStaleStateAndFollowsQueueSemantics() {
    let item = PlaybackItem(
        trackID: UUID(),
        locationID: "stale-location",
        url: URL(fileURLWithPath: "/tmp/missing.m4a"),
        title: "Stale Song"
    )
    let snapshot = PlaybackSnapshot(
        queue: [item],
        currentIndex: 0,
        phase: .failed,
        elapsed: 0
    )

    let infoCenter = MPNowPlayingInfoCenter.default()
    let commandCenter = MPRemoteCommandCenter.shared()
    let center = SystemNowPlayingCenter(
        commandCenter: commandCenter,
        infoCenter: infoCenter
    )
    infoCenter.nowPlayingInfo = [MPMediaItemPropertyTitle: "Previously Playing"]
    infoCenter.playbackState = .playing

    center.update(snapshot, artworkData: nil)

    #expect(infoCenter.nowPlayingInfo == nil)
    #expect(infoCenter.playbackState == .stopped)
    #expect(commandCenter.playCommand.isEnabled == false)
    #expect(commandCenter.pauseCommand.isEnabled == false)
    #expect(commandCenter.nextTrackCommand.isEnabled == false)
    #expect(commandCenter.previousTrackCommand.isEnabled == false)
    #expect(commandCenter.changePlaybackPositionCommand.isEnabled == false)

    let loadingSnapshot = PlaybackSnapshot(
        queue: [item],
        currentIndex: 0,
        phase: .loading,
        elapsed: 0,
        canAdvance: false
    )
    center.update(loadingSnapshot, artworkData: nil)
    #expect(commandCenter.playCommand.isEnabled == false)
    #expect(commandCenter.pauseCommand.isEnabled == false)

    let loopingSnapshot = PlaybackSnapshot(
        queue: [item],
        currentIndex: 0,
        phase: .playing,
        elapsed: 0,
        repeatMode: .all,
        canAdvance: true
    )
    center.update(loopingSnapshot, artworkData: nil)
    #expect(commandCenter.nextTrackCommand.isEnabled)

    let secondItem = PlaybackItem(
        trackID: UUID(),
        locationID: "second-location",
        url: URL(fileURLWithPath: "/tmp/second.m4a"),
        title: "Second Song"
    )
    let shuffledSnapshot = PlaybackSnapshot(
        queue: [item, secondItem],
        currentIndex: 1,
        phase: .playing,
        elapsed: 0,
        order: .shuffled,
        canAdvance: true
    )
    center.update(shuffledSnapshot, artworkData: nil)
    #expect(commandCenter.nextTrackCommand.isEnabled)

    infoCenter.nowPlayingInfo = nil
    infoCenter.playbackState = .stopped
}
