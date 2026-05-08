import SwiftUI

struct AutocompletePanel: View {
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        Form {
            Section {
                Toggle("Fish-style ghost text", isOn: $settings.ghostTextEnabled)
                Toggle("Tab completion popup", isOn: $settings.tabCompletionEnabled)
            } header: {
                Text("Suggestions")
            } footer: {
                Text("Ghost text appears after typing 2+ chars. Press → or Tab to accept, Escape to dismiss.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
