import SwiftUI

struct TorMenuCommands: Commands {
    @ObservedObject var sessions: SessionStore
    var onIncreaseFont: () -> Void
    var onDecreaseFont: () -> Void
    var onClearBuffer: () -> Void

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Tab") { sessions.newSession() }
                .keyboardShortcut("t", modifiers: .command)
        }

        CommandGroup(after: .newItem) {
            Button("Close Tab") {
                if let id = sessions.selectedID { sessions.close(id) }
            }
            .keyboardShortcut("w", modifiers: .command)
        }

        CommandMenu("View") {
            Button("Increase Font Size") { onIncreaseFont() }
                .keyboardShortcut("+", modifiers: .command)
            Button("Decrease Font Size") { onDecreaseFont() }
                .keyboardShortcut("-", modifiers: .command)
            Divider()
            Button("Clear Buffer") { onClearBuffer() }
                .keyboardShortcut("k", modifiers: .command)
        }
    }
}
