import AppKit
import SwiftUI

struct MenuBarView: View {
    @Bindable var session: AppSession

    var body: some View {
        Text(session.currentTrackTitle)
        if let artist = session.playback.currentItem?.artist {
            Text(artist).foregroundStyle(.secondary)
        }
        Divider()
        HStack {
            Button("player.previous", systemImage: "backward.fill") {
                Task { await session.playPrevious() }
            }
            Button(
                session.playback.phase == .playing ? "player.pause" : "player.play",
                systemImage: session.playback.phase == .playing ? "pause.fill" : "play.fill"
            ) {
                Task { await session.togglePlayPause() }
            }
            Button("player.next", systemImage: "forward.fill") {
                Task { await session.playNext() }
            }
        }
        .disabled(session.playback.currentItem == nil || session.playback.phase == .loading)
        Button("menu.quit") {
            NSApplication.shared.terminate(nil)
        }
    }
}
