import SwiftUI
import AppKit

struct TorTerminalContainer: NSViewRepresentable {
    @ObservedObject var themeManager: ThemeManager

    func makeNSView(context: Context) -> TorTerminalView {
        let v = TorTerminalView(frame: .zero)
        v.applyTheme(themeManager.current)
        v.startShell()
        return v
    }

    func updateNSView(_ nsView: TorTerminalView, context: Context) {
        nsView.applyTheme(themeManager.current)
    }
}
