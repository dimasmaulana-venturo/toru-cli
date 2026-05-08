import SwiftUI
import AppKit
import Darwin

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
                    SessionDetailView(session: session, themeManager: themeManager)
                        .id(session.id)
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

/// Wraps the active `Session` so SwiftUI re-renders when `session.tabs`
/// changes (adding / closing a tab while we're showing this session).
struct SessionDetailView: View {
    @ObservedObject var session: Session
    @ObservedObject var themeManager: ThemeManager

    var body: some View {
        VStack(spacing: 0) {
            if session.tabs.count > 1 {
                TabStripView(session: session)
            }

            if let tab = session.activeTab {
                SessionPaneView(tab: tab, themeManager: themeManager)
                    .id(tab.id)
            } else {
                Text("No tab")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Image(systemName: "terminal.fill")
                        .foregroundStyle(.tint)
                    Text("Toru CLI")
                        .font(.system(.body, design: .rounded).weight(.medium))
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    session.newTab()
                } label: {
                    Image(systemName: "plus")
                }
                .help("New tab (⌘T)")
                .keyboardShortcut("t", modifiers: [.command])
            }
        }
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
        "python", "python3", "irb", "pry", "node",
        "expo", "metro"
    ]
    private static let interactivePairs: Set<String> = [
        "npm init",
        "yarn create", "pnpm create", "bun create",
        "git rebase", "git commit", "git add",
        "docker run",
        // Dev servers: bun start / npm run dev / etc — they read raw
        // keystrokes (s = switch dev client, r = reload, a/i = open
        // device, etc.) so users need a real terminal surface.
        "bun start", "bun dev", "bun run",
        "npm start", "npm run", "npm test",
        "pnpm start", "pnpm run", "pnpm dev", "pnpm test",
        "yarn start", "yarn run", "yarn dev", "yarn test",
        "expo start", "npx expo", "bunx expo",
        "vite", "next dev", "next start",
        "rails server", "rails console", "rails s", "rails c",
        "mix phx.server", "iex"
    ]

    /// Live cwd for the foreground process of `tab`'s shell, queried via
    /// `tcgetpgrp` + `proc_pidinfo`. Falls back to `$HOME` when the shell
    /// isn't ready yet.
    private static func cwd(for tab: TabState) -> String {
        guard let proc = tab.host.terminal.process, proc.shellPid > 0 else {
            return NSHomeDirectory()
        }
        let fg = tcgetpgrp(proc.childfd)
        let pid = (fg > 0) ? fg : proc.shellPid
        var info = proc_vnodepathinfo()
        let size = MemoryLayout<proc_vnodepathinfo>.stride
        let n = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, Int32(size))
        guard n == Int32(size) else { return NSHomeDirectory() }
        let pathTuple = info.pvi_cdir.vip_path
        return withUnsafeBytes(of: pathTuple) { raw -> String in
            guard let base = raw.baseAddress else { return NSHomeDirectory() }
            let cstr = base.assumingMemoryBound(to: CChar.self)
            let s = String(cString: cstr)
            return s.isEmpty ? NSHomeDirectory() : s
        }
    }

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

    @State private var searchQuery: String = ""
    @State private var showSearch: Bool = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if showSearch {
                searchBar
            }

            BlockListView(
                blockStore: tab.blockStore,
                isLocked: false,
                searchQuery: showSearch ? searchQuery : "",
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
                StatusRowView(tab: tab)
                    .transition(.opacity)
                InputBarView(
                    onSubmit: handleSubmit,
                    onCtrlC: { tab.shellBridge.sendRaw(Data([0x03])) },
                    cwdProvider: { Self.cwd(for: tab) }
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
            Button(action: toggleSearch) { EmptyView() }
                .keyboardShortcut("f", modifiers: [.command])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
            TextField("Search blocks…", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .focused($searchFocused)
                .onSubmit { /* keep open; just commit query */ }
                .onKeyPress(.escape, phases: .down) { _ in
                    closeSearch()
                    return .handled
                }
            if !searchQuery.isEmpty {
                Text(matchCountLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Button(action: closeSearch) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Close search (⎋)")
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
    }

    private var matchCountLabel: String {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return "" }
        let count = tab.blockStore.blocks.filter { block in
            block.command.lowercased().contains(q) ||
            String(block.output.characters).lowercased().contains(q)
        }.count
        return "\(count) match\(count == 1 ? "" : "es")"
    }

    private func toggleSearch() {
        DispatchQueue.main.async {
            if showSearch {
                closeSearch()
            } else {
                showSearch = true
                searchFocused = true
            }
        }
    }

    private func closeSearch() {
        DispatchQueue.main.async {
            showSearch = false
            searchQuery = ""
        }
    }

    // MARK: - Submit

    private func handleSubmit(_ cmd: String) {
        DispatchQueue.main.async {
            let trimmed = cmd.trimmingCharacters(in: .whitespaces)

            // Persist to SQLite history (deduped + skips ` `-leading rawInput).
            HistoryDatabase.shared.record(
                rawInput: cmd,
                executed: trimmed,
                directory: NSHomeDirectory(),
                sessionId: tab.id.uuidString
            )

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
