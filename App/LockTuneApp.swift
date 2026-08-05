import AppKit
import SwiftUI

@main
struct LockTuneApp: App {
    @State private var session = AppSession()
    @State private var islandWindow = IslandWindowController()

    var body: some Scene {
        WindowGroup {
            ContentView(session: session)
                .frame(minWidth: 1_180, minHeight: 720)
                .task {
                    islandWindow.show(session: session)
                    await session.restoreMusicLibrary()
                    await session.restoreCalendar()
                }
                .onChange(of: session.isIslandEnabled) { _, enabled in
                    islandWindow.setEnabled(enabled)
                }
                .onChange(of: session.preferredIslandDisplayID) { _, _ in
                    islandWindow.reposition()
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
