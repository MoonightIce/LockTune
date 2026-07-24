import SwiftUI

@main
struct LockTuneApp: App {
    @State private var session = AppSession()

    var body: some Scene {
        WindowGroup {
            ContentView(session: session)
                .frame(minWidth: 920, minHeight: 620)
                .task { await session.restoreMusicLibrary() }
        }

        MenuBarExtra("LockTune", systemImage: "music.note") {
            MenuBarView(session: session)
        }

        Settings {
            SettingsView()
        }
    }
}
