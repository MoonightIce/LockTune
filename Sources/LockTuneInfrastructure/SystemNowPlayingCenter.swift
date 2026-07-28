import AppKit
import Foundation
import LockTuneDomain
import MediaPlayer

public enum SystemPlaybackCommand: Sendable {
    case play
    case pause
    case next
    case previous
    case seek(TimeInterval)
}

func makeSystemNowPlayingInfo(from snapshot: PlaybackSnapshot) -> [String: Any]? {
    guard snapshot.phase != .failed, let item = snapshot.currentItem else { return nil }

    var info: [String: Any] = [
        MPMediaItemPropertyTitle: item.title,
        MPNowPlayingInfoPropertyElapsedPlaybackTime: snapshot.elapsed,
        MPNowPlayingInfoPropertyPlaybackRate: snapshot.phase == .playing ? 1.0 : 0.0,
        MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
        MPNowPlayingInfoPropertyExternalContentIdentifier: item.locationID,
        MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
    ]
    if let artist = item.artist { info[MPMediaItemPropertyArtist] = artist }
    if let album = item.album { info[MPMediaItemPropertyAlbumTitle] = album }
    if let duration = snapshot.duration { info[MPMediaItemPropertyPlaybackDuration] = duration }
    return info
}

@MainActor
public final class SystemNowPlayingCenter {
    private let commandCenter: MPRemoteCommandCenter
    private let infoCenter: MPNowPlayingInfoCenter
    private let commandStream: AsyncStream<SystemPlaybackCommand>
    private let commandContinuation: AsyncStream<SystemPlaybackCommand>.Continuation

    public init(
        commandCenter: MPRemoteCommandCenter = .shared(),
        infoCenter: MPNowPlayingInfoCenter = .default()
    ) {
        self.commandCenter = commandCenter
        self.infoCenter = infoCenter
        let pair = AsyncStream.makeStream(of: SystemPlaybackCommand.self)
        commandStream = pair.stream
        commandContinuation = pair.continuation
        configureCommands()
    }

    public func commands() -> AsyncStream<SystemPlaybackCommand> {
        commandStream
    }

    public func update(_ snapshot: PlaybackSnapshot, artworkData: Data?) {
        guard var info = makeSystemNowPlayingInfo(from: snapshot) else {
            infoCenter.nowPlayingInfo = nil
            infoCenter.playbackState = .stopped
            updateCommandAvailability(hasItem: false, snapshot: snapshot)
            return
        }

        if let artworkData, let image = NSImage(data: artworkData) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }

        infoCenter.nowPlayingInfo = info
        switch snapshot.phase {
        case .playing: infoCenter.playbackState = .playing
        case .paused, .loading: infoCenter.playbackState = .paused
        case .idle, .failed: infoCenter.playbackState = .stopped
        }
        updateCommandAvailability(hasItem: true, snapshot: snapshot)
    }

    private func configureCommands() {
        commandCenter.playCommand.addTarget { [commandContinuation] _ in
            commandContinuation.yield(.play)
            return .success
        }
        commandCenter.pauseCommand.addTarget { [commandContinuation] _ in
            commandContinuation.yield(.pause)
            return .success
        }
        commandCenter.nextTrackCommand.addTarget { [commandContinuation] _ in
            commandContinuation.yield(.next)
            return .success
        }
        commandCenter.previousTrackCommand.addTarget { [commandContinuation] _ in
            commandContinuation.yield(.previous)
            return .success
        }
        commandCenter.changePlaybackPositionCommand.addTarget { [commandContinuation] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            commandContinuation.yield(.seek(event.positionTime))
            return .success
        }
        updateCommandAvailability(hasItem: false, snapshot: PlaybackSnapshot())
    }

    private func updateCommandAvailability(hasItem: Bool, snapshot: PlaybackSnapshot) {
        commandCenter.playCommand.isEnabled = hasItem
            && (snapshot.phase == .paused || snapshot.phase == .idle)
        commandCenter.pauseCommand.isEnabled = hasItem && snapshot.phase == .playing
        commandCenter.nextTrackCommand.isEnabled = hasItem && snapshot.canAdvance == true
        commandCenter.previousTrackCommand.isEnabled = hasItem
        commandCenter.changePlaybackPositionCommand.isEnabled = hasItem && snapshot.duration != nil
    }
}
