import SwiftUI

struct AppearancePanel: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var themes = ThemeManager.shared

    var body: some View {
        Form {
            Section("Font") {
                TextField("Font name", text: $settings.fontName)
                Stepper("Size: \(settings.fontSize) pt",
                        value: $settings.fontSize, in: 9...24)
            }

            Section("Theme") {
                Picker("Theme", selection: $settings.themeName) {
                    ForEach(themes.themes) { theme in
                        Text(theme.name).tag(theme.name)
                    }
                }
                .onChange(of: settings.themeName) { _, new in
                    themes.select(name: new)
                }
            }

            Section("Cursor") {
                Picker("Style", selection: $settings.cursorStyle) {
                    Text("Block").tag("block")
                    Text("Beam").tag("beam")
                    Text("Underline").tag("underline")
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
    }
}
