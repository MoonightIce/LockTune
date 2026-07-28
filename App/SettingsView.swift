import SwiftUI

struct SettingsView: View {
    @Bindable var session: AppSession
    @State private var isShowingDisconnectConfirmation = false
    @State private var folderPendingRemoval: URL?
    @State private var isShowingClearFoldersConfirmation = false

    var body: some View {
        Form {
            Section("settings.musicFolders") {
                if session.musicFolders.isEmpty {
                    Text("settings.musicFoldersEmpty")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(session.musicFolders, id: \.standardizedFileURL) { folder in
                        HStack(spacing: 10) {
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(folder.lastPathComponent)
                                Text(folder.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Button("settings.musicFolderRemove", role: .destructive) {
                                folderPendingRemoval = folder
                            }
                            .disabled(session.isScanningMusic)
                        }
                    }
                }
                HStack {
                    Button("library.addFolder", systemImage: "folder.badge.plus") {
                        Task { await session.chooseMusicFolder() }
                    }
                    .disabled(session.isScanningMusic)
                    Spacer()
                    if !session.musicFolders.isEmpty {
                        Button("settings.musicFoldersClear", role: .destructive) {
                            isShowingClearFoldersConfirmation = true
                        }
                        .disabled(session.isScanningMusic)
                    }
                }
            }
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
        .frame(width: 620, height: 560)
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
        .confirmationDialog(
            "settings.musicFolderRemoveConfirmation",
            isPresented: Binding(
                get: { folderPendingRemoval != nil },
                set: { if !$0 { folderPendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let folderPendingRemoval {
                Button("settings.musicFolderRemove", role: .destructive) {
                    Task { await session.removeMusicFolder(folderPendingRemoval) }
                    self.folderPendingRemoval = nil
                }
            }
            Button("settings.cancel", role: .cancel) {
                folderPendingRemoval = nil
            }
        } message: {
            Text("settings.musicFolderRemoveMessage")
        }
        .confirmationDialog(
            "settings.musicFoldersClearConfirmation",
            isPresented: $isShowingClearFoldersConfirmation,
            titleVisibility: .visible
        ) {
            Button("settings.musicFoldersClear", role: .destructive) {
                Task { await session.clearMusicFolders() }
            }
            Button("settings.cancel", role: .cancel) {}
        } message: {
            Text("settings.musicFoldersClearMessage")
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
