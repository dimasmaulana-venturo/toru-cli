import SwiftUI

struct TerminalPaneView: View {
    @ObservedObject var themeManager: ThemeManager
    @State private var showHistorySearch = false

    var body: some View {
        ZStack(alignment: .top) {
            TorTerminalContainer(themeManager: themeManager)
                .background(Color(themeManager.current.backgroundColor))
                .ignoresSafeArea(edges: .bottom)

            if showHistorySearch {
                HistorySearchOverlay(
                    isPresented: $showHistorySearch,
                    onSelect: { _ in /* paste handled outside MVP */ }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(10)
            }
        }
        .animation(.easeOut(duration: 0.18), value: showHistorySearch)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Image(systemName: "terminal.fill")
                        .foregroundStyle(.tint)
                    Text("Toru CLI")
                        .font(.system(.body, design: .rounded).weight(.medium))
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showHistorySearch.toggle()
                } label: {
                    Label("History", systemImage: "magnifyingglass")
                }
                .help("History search (⌃R)")
                .keyboardShortcut("r", modifiers: [.control])
            }
        }
    }
}
