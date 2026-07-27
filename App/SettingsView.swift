import SwiftUI

struct SettingsView: View {
    @Bindable var session: AppSession
    @State private var isShowingDisconnectConfirmation = false

    var body: some View {
        Form {
            Section("settings.general") {
                Toggle(
                    "settings.islandEnabled",
                    isOn: Binding(
                        get: { session.isIslandEnabled },
                        set: { session.setIslandEnabled($0) }
                    )
                )
                Text("settings.islandDescription")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("settings.googleCalendar") {
                HStack {
                    Label(calendarStatusLabel, systemImage: calendarStatusImage)
                    Spacer()
                    if isCalendarConnected {
                        Button("calendar.disconnect", role: .destructive) {
                            isShowingDisconnectConfirmation = true
                        }
                        .disabled(session.calendarConnectionState == .syncing)
                    }
                }
                Text("settings.googleCalendarDescription")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("settings.privacy") {
                Label("settings.lockScreenPrivacy", systemImage: "lock.shield")
                Label("settings.localOnly", systemImage: "internaldrive")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 420)
        .confirmationDialog(
            "settings.disconnectConfirmationTitle",
            isPresented: $isShowingDisconnectConfirmation,
            titleVisibility: .visible
        ) {
            Button("calendar.disconnect", role: .destructive) {
                Task { await session.disconnectGoogleCalendar() }
            }
            Button("settings.cancel", role: .cancel) {}
        } message: {
            Text("settings.disconnectConfirmationMessage")
        }
    }

    private var isCalendarConnected: Bool {
        session.calendarConnectionState == .connected
            || session.calendarConnectionState == .syncing
    }

    private var calendarStatusLabel: LocalizedStringKey {
        switch session.calendarConnectionState {
        case .disconnected: "settings.googleCalendarDisconnected"
        case .connecting: "calendar.connecting"
        case .connected: "settings.googleCalendarConnected"
        case .syncing: "settings.googleCalendarSyncing"
        }
    }

    private var calendarStatusImage: String {
        switch session.calendarConnectionState {
        case .disconnected: "person.crop.circle.badge.xmark"
        case .connecting, .syncing: "arrow.triangle.2.circlepath"
        case .connected: "checkmark.circle.fill"
        }
    }
}
