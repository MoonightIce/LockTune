import AppKit
import SwiftUI

struct MenuBarView: View {
    @Bindable var session: AppSession

    var body: some View {
        Text(session.currentTrackTitle)
        Divider()
        Button(session.isPlaying ? "player.pause" : "player.play") {
            session.isPlaying.toggle()
        }
        Button("menu.quit") {
            NSApplication.shared.terminate(nil)
        }
    }
}
