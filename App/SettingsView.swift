import SwiftUI
import LockTuneDomain

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
            Section {
                GlassLaboratoryView(session: session)
            } header: {
                Label("settings.glassLaboratory", systemImage: "slider.horizontal.3")
            } footer: {
                Text("settings.glassBoundaryNote")
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
        .frame(width: 620, height: 760)
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

private struct GlassLaboratoryView: View {
    @Bindable var session: AppSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassLabPreview(session: session)
                .frame(height: 86)
                .padding(.bottom, 6)
            glassSlider(
                title: "settings.glassTint",
                value: Binding(get: { session.glassTint }, set: { session.setGlassTint($0) }),
                range: 0...0.3,
                step: 0.01,
                valueLabel: { String(format: "%.2f", $0) }
            )
            glassSlider(
                title: "settings.glassBlur",
                value: Binding(get: { session.glassBlur }, set: { session.setGlassBlur($0) }),
                range: 0...36,
                step: 1,
                valueLabel: { "\(Int($0)) px" }
            )
            glassSlider(
                title: "settings.glassRefraction",
                value: Binding(get: { session.glassRefraction }, set: { session.setGlassRefraction($0) }),
                range: 0...160,
                step: 1,
                valueLabel: { "\(Int($0))" }
            )
            Toggle(
                "settings.glassMotion",
                isOn: Binding(
                    get: { session.glassMotionEnabled },
                    set: { session.setGlassMotionEnabled($0) }
                )
            )
        }
    }

    private func glassSlider(
        title: LocalizedStringKey,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        valueLabel: @escaping (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(valueLabel(value.wrappedValue))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: step)
        }
    }
}

private struct GlassLabPreview: View {
    @Bindable var session: AppSession

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.blue.opacity(0.72), .purple.opacity(0.55), .orange.opacity(0.65)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(Capsule())
            Color.white.opacity(session.glassTint)
                .clipShape(Capsule())
            GlassEdgeMaterial(session: session, cornerRadius: 43)
                .clipShape(Capsule())
            HStack(spacing: 10) {
                Image(systemName: "waveform")
                    .frame(width: 30, height: 30)
                    .background(.white.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("settings.glassLaboratory").font(.headline)
                    Text("settings.glassContentClear")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                }
                Spacer()
                Image(systemName: "sparkles")
                    .foregroundStyle(.white.opacity(0.82))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
        }
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
    }
}
