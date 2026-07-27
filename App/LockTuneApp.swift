import AppKit
import SwiftUI

@main
struct LockTuneApp: App {
    @State private var session = AppSession()
    @State private var islandWindow = IslandWindowController()

    var body: some Scene {
        WindowGroup {
            ContentView(session: session)
                .frame(minWidth: 920, minHeight: 620)
                .task {
                    islandWindow.show(session: session)
                    await session.restoreMusicLibrary()
                    await session.restoreCalendar()
                }
                .onChange(of: session.isIslandEnabled) { _, enabled in
                    islandWindow.setEnabled(enabled)
                }
                .onReceive(
                    NSWorkspace.shared.notificationCenter.publisher(
                        for: NSWorkspace.didWakeNotification
                    )
                ) { _ in
                    Task { await session.resumeAfterWake() }
                }
        }

        MenuBarExtra("LockTune", systemImage: "music.note") {
            MenuBarView(session: session)
        }

        Settings {
            SettingsView(session: session)
        }
    }
}
