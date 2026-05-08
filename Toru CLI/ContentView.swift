import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var sessions: SessionStore
    @EnvironmentObject private var themeManager: ThemeManager
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .automatic

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            SidebarView(store: sessions)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            TerminalPaneView(themeManager: themeManager)
                .navigationSplitViewColumnWidth(min: 480, ideal: 720)
        }
        .navigationSplitViewStyle(.balanced)
        .background(Color(themeManager.current.backgroundColor))
    }
}

#Preview {
    ContentView()
        .environmentObject(SessionStore())
        .environmentObject(ThemeManager.shared)
        .environmentObject(SettingsStore.shared)
        .frame(width: 800, height: 500)
}
