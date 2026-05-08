import SwiftUI

struct GeneralPanel: View {
    @State private var detectedShell = PTYBridge.resolveShell()

    var body: some View {
        Form {
            Section {
                LabeledContent("Default shell") {
                    Text(detectedShell)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text("Detected from `$SHELL`. Falls back to `/bin/zsh` if unset.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Shell")
            }
        }
        .formStyle(.grouped)
    }
}
