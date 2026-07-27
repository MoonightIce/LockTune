import SwiftUI

struct SettingsView: View {
    @Bindable var session: AppSession

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
            Section("settings.privacy") {
                Label("settings.lockScreenPrivacy", systemImage: "lock.shield")
                Label("settings.localOnly", systemImage: "internaldrive")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 320)
    }
}
