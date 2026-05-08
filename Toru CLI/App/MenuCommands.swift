import SwiftUI

struct TorMenuCommands: Commands {
    @ObservedObject var sessions: SessionStore
    var onIncreaseFont: () -> Void
    var onDecreaseFont: () -> Void
    var onClearBuffer: () -> Void

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Tab") {
                sessions.activeSession?.newTab()
            }
            .keyboardShortcut("t", modifiers: [.command])

            Button("New Session") {
                sessions.newSession()
            }
            .keyboardShortcut("n", modifiers: [.command])
        }

        CommandGroup(after: .newItem) {
            Button("Close Tab") {
                if let session = sessions.activeSession,
                   let tabID = session.selectedTabID {
                    session.closeTab(tabID)
                }
            }
            .keyboardShortcut("w", modifiers: [.command])

            Button("Close Session") {
                if let id = sessions.selectedSessionID {
                    sessions.close(id)
                }
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
        }

        CommandMenu("View") {
            Button("Increase Font Size") { onIncreaseFont() }
                .keyboardShortcut("+", modifiers: [.command])
            Button("Decrease Font Size") { onDecreaseFont() }
                .keyboardShortcut("-", modifiers: [.command])
            Divider()
            Button("Clear Buffer") { onClearBuffer() }
                .keyboardShortcut("k", modifiers: [.command])
        }
    }
}
