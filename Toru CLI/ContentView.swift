import SwiftUI
import AppKit

/// Hierarchy:
///   Sidebar (sessions) → TabBar (tabs in active session) → active tab pane
///
/// Sessions are top-level workspaces. Each session contains 1+ tabs; each
/// tab is its own shell. ⌘N adds a session, ⌘T adds a tab to the active
/// session.
struct ContentView: View {
    @EnvironmentObject private var sessions: SessionStore
    @EnvironmentObject private var themeManager: ThemeManager
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .automatic

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            SidebarView(store: sessions)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            Group {
                if let session = sessions.activeSession {
                    VStack(spacing: 0) {
                        TabBarView(session: session)

                        if let tab = session.activeTab {
                            SessionPaneView(tab: tab, themeManager: themeManager)
                                .id(tab.id)
                        } else {
                            Text("No tab")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                } else {
                    Text("No session")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationSplitViewColumnWidth(min: 480, ideal: 720)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 800, minHeight: 500)
    }
}

/// Detail pane for the *active tab* of the active session. Reads
/// `tab.shellBridge` / `tab.blockStore` / `tab.host`.
struct SessionPaneView: View {
    @ObservedObject var tab: TabState
    @ObservedObject var themeManager: ThemeManager

    private static let interactiveSingles: Set<String> = [
        "claude", "opencode",
        "vim", "nvim", "nano",
        "htop", "top", "btop", "atop",
        "less", "more", "man",
        "fzf", "lazygit", "lazydocker", "k9s",
        "tmux", "screen",
        "ssh", "telnet",
        "python", "python3", "irb", "pry", "node"
    ]
    private static let interactivePairs: Set<String> = [
        "npm init",
        "yarn create", "pnpm create", "bun create",
        "git rebase", "git commit", "git add",
        "docker run"
    ]

    private static func isInteractive(command cmd: String) -> Bool {
        let parts = cmd.trimmingCharacters(in: .whitespaces)
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        guard let first = parts.first else { return false }
        if interactiveSingles.contains(first) { return true }
        if parts.count >= 2 {
            let two = "\(first) \(parts[1])"
            if interactivePairs.contains(two) { return true }
        }
        return false
    }

    private var mode: TerminalMode { tab.shellBridge.terminalMode }

    var body: some View {
        VStack(spacing: 0) {
            BlockListView(
                blockStore: tab.blockStore,
                isLocked: false,
                onRerun: rerun,
                onDelete: deleteBlock
            )
            .frame(maxWidth: .infinity, maxHeight: mode == .idle ? .infinity : 0)
            .opacity(mode == .idle ? 1 : 0)
            .clipped()

            Divider()
                .opacity(mode == .idle ? 0.08 : 0)

            EmbeddedTerminalView(host: tab.host)
                .frame(maxWidth: .infinity, maxHeight: mode == .idle ? 0 : .infinity, alignment: .top)
                .opacity(mode == .idle ? 0 : 1)
                .allowsHitTesting(mode != .idle)
                .clipped()

            if mode == .idle {
                InputBarView(
                    onSubmit: handleSubmit,
                    onCtrlC: { tab.shellBridge.sendRaw(Data([0x03])) }
                )
                .frame(height: 44)
                .transition(.opacity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.easeInOut(duration: 0.2), value: mode)
        .background(
            GeometryReader { geo -> Color in
                let size = geo.size
                Task { @MainActor in
                    tab.updateSize(width: size.width, height: size.height)
                }
                return Color.clear
            }
        )
        .onAppear {
            tab.ensureStarted(themeManager: themeManager)
        }
        .onChange(of: mode) { _, new in
            handleModeChange(new)
        }
        .onKeyPress(KeyEquivalent("c"), phases: .down) { press in
            if press.modifiers.contains(.control) && mode != .idle {
                tab.shellBridge.sendRaw(Data([0x03]))
                return .handled
            }
            return .ignored
        }
        .background(hotkeyOverlay)
    }

    @ViewBuilder
    private var hotkeyOverlay: some View {
        Group {
            Button(action: clearBlocks) { EmptyView() }
                .keyboardShortcut("k", modifiers: [.command])
            Button(action: clearBlocks) { EmptyView() }
                .keyboardShortcut("l", modifiers: [.command])
            Button(action: newConversation) { EmptyView() }
                .keyboardShortcut(.return, modifiers: [.command])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    // MARK: - Submit

    private func handleSubmit(_ cmd: String) {
        DispatchQueue.main.async {
            let trimmed = cmd.trimmingCharacters(in: .whitespaces)
            if trimmed == "clear" || trimmed == "cls" {
                withAnimation(.easeOut(duration: 0.15)) {
                    tab.blockStore.clearAll()
                }
                tab.shellBridge.send(command: cmd)
                return
            }

            tab.blockStore.startBlock(command: cmd)
            tab.shellBridge.activeCommand =
                cmd.split(separator: " ").first.map(String.init)
            tab.shellBridge.send(command: cmd)
            if Self.isInteractive(command: cmd) {
                tab.shellBridge.forceMode(.fullTUI)
            }
        }
    }

    // MARK: - Mode / window title

    private func handleModeChange(_ new: TerminalMode) {
        DispatchQueue.main.async {
            switch new {
            case .fullTUI:
                if let v = tab.shellBridge.view {
                    v.window?.makeFirstResponder(v)
                    if let prog = tab.shellBridge.activeCommand {
                        v.window?.title = "Toru — \(prog)"
                    }
                }
            case .idle:
                tab.shellBridge.view?.window?.title = "Toru"
            }
        }
    }

    // MARK: - Hotkey actions

    private func clearBlocks() {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.15)) {
                tab.blockStore.clearAll()
            }
        }
    }

    private func newConversation() {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.15)) {
                tab.blockStore.clearAll()
            }
            tab.shellBridge.activeCommand = nil
        }
    }

    // MARK: - Block actions

    private func rerun(_ block: Block) {
        guard mode == .idle else { return }
        let cmd = block.command
        DispatchQueue.main.async {
            tab.blockStore.startBlock(command: cmd)
            tab.shellBridge.activeCommand =
                cmd.split(separator: " ").first.map(String.init)
            tab.shellBridge.send(command: cmd)
            if Self.isInteractive(command: cmd) {
                tab.shellBridge.forceMode(.fullTUI)
            }
        }
    }

    private func deleteBlock(_ block: Block) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.15)) {
                tab.blockStore.remove(block)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(SessionStore())
        .environmentObject(ThemeManager.shared)
        .environmentObject(SettingsStore.shared)
        .frame(width: 900, height: 600)
}
