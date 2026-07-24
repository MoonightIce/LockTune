import AppKit
import SwiftUI

struct MenuBarView: View {
    @Bindable var session: AppSession

    var body: some View {
        Text(session.currentTrackTitle)
        Divider()
        Button("player.unavailable") {}
            .disabled(true)
        Button("menu.quit") {
            NSApplication.shared.terminate(nil)
        }
    }
}
