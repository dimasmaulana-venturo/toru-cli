import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralPanel()
                .tabItem { Label("General", systemImage: "gear") }
            AppearancePanel()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            AutocompletePanel()
                .tabItem { Label("Autocomplete", systemImage: "text.cursor") }
            KeyboardPanel()
                .tabItem { Label("Keyboard", systemImage: "keyboard") }
            AdvancedPanel()
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 520, height: 380)
        .padding(20)
    }
}
