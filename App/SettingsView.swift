import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Section("settings.general") {
                Text("settings.preview")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 260)
    }
}
