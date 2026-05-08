import SwiftUI
import AppKit

// MARK: - TabState (one shell)

/// One running shell instance — its own PTY, block store, and SwiftTerm
/// NSView. Lives inside a `Session` and is identified inside the tab bar.
@MainActor
final class TabState: Identifiable, ObservableObject {
    let id = UUID()
    @Published var title: String
    let createdAt = Date()

    let shellBridge = ShellBridge()
    let blockStore = BlockStore()
    let host: PaddedTerminalHost

    private var pollTimer: Timer?
    private var ptyWired = false
    private var tail: String = ""
    private var lastCols: Int = -1
    private var lastRows: Int = -1

    init(title: String) {
        self.title = title
        self.host = PaddedTerminalHost(
            insets: NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        )
    }

    func ensureStarted(themeManager: ThemeManager) {
        guard !ptyWired else { return }
        ptyWired = true
        host.terminal.applyTheme(themeManager.current)
        host.terminal.startShell()
        shellBridge.view = host.terminal
        shellBridge.blockStore = blockStore
        wirePtyTap()
        startPolling()
    }

    private func wirePtyTap() {
        let bridge = shellBridge
        let store = blockStore
        host.terminal.onPtyBytes = { [weak self] bytes in
            guard let self else { return }
            let chunk = String(decoding: bytes, as: UTF8.self)
            let scan = self.tail + chunk
            let altOn  = scan.contains("\u{1B}[?1049h")
                      || scan.contains("\u{1B}[?1047h")
                      || scan.contains("\u{1B}[?47h")
            let altOff = scan.contains("\u{1B}[?1049l")
                      || scan.contains("\u{1B}[?1047l")
                      || scan.contains("\u{1B}[?47l")
            self.tail = String(scan.suffix(16))

            if altOn {
                Task { @MainActor in
                    if !bridge.altScreenActive {
                        bridge.altScreenActive = true
                        store.clearAll()
                        bridge.terminalMode = .fullTUI
                    }
                }
            }
            if altOff {
                Task { @MainActor in
                    if bridge.altScreenActive {
                        bridge.altScreenActive = false
                        store.appendMarker("─── session resumed ───")
                    }
                }
            }

            let isFull = MainActor.assumeIsolated { bridge.terminalMode == .fullTUI }
            if isFull { return }

            let clean = AnsiStripper.strip(chunk)
            guard !clean.isEmpty else { return }
            Task { @MainActor in
                store.appendToCurrent(clean)
            }
        }
    }

    private func startPolling() {
        pollTimer?.invalidate()
        let bridge = shellBridge
        let timer = Timer(timeInterval: 0.2, repeats: true) {
            [weak terminal = host.terminal] _ in
            guard let terminal = terminal else { return }
            let atPrompt = terminal.isShellAtPrompt()
            let rawMode = terminal.childInRawMode()
            MainActor.assumeIsolated {
                bridge.recomputeMode(atPrompt: atPrompt, rawMode: rawMode)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func terminate() {
        pollTimer?.invalidate()
        pollTimer = nil
        host.terminal.process?.terminate()
    }

    func updateSize(width: CGFloat, height: CGFloat) {
        guard width > 0, height > 0 else { return }
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let charW = max(font.maximumAdvancement.width, 6)
        let lineH = font.ascender + abs(font.descender) + font.leading
        let cellH = max(lineH, 12)
        let usableW = max(0, width - 48)
        let usableH = max(0, height - 24)
        let cols = max(40, Int(usableW / charW))
        let rows = max(20, Int(usableH / cellH))
        if cols == lastCols && rows == lastRows { return }
        lastCols = cols
        lastRows = rows
        host.terminal.pinPtySize(cols: cols, rows: rows)
    }
}

// MARK: - Session (a group of tabs)

/// A user-named workspace containing one or more shell tabs. Sessions are
/// shown in the sidebar; tabs inside the active session are shown in the
/// tab bar at the top of the detail pane.
@MainActor
final class Session: Identifiable, ObservableObject {
    let id = UUID()
    @Published var title: String
    let createdAt = Date()
    @Published var tabs: [TabState]
    @Published var selectedTabID: UUID?

    init(title: String) {
        self.title = title
        let first = TabState(title: "Tab 1")
        self.tabs = [first]
        self.selectedTabID = first.id
    }

    var activeTab: TabState? {
        tabs.first { $0.id == selectedTabID }
    }

    func newTab() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let t = TabState(title: "Tab \(self.tabs.count + 1)")
            self.tabs.append(t)
            self.selectedTabID = t.id
        }
    }

    func closeTab(_ id: UUID) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let t = self.tabs.first(where: { $0.id == id }) {
                t.terminate()
            }
            self.tabs.removeAll { $0.id == id }
            if self.selectedTabID == id {
                self.selectedTabID = self.tabs.first?.id
            }
        }
    }

    func terminateAll() {
        for t in tabs { t.terminate() }
    }
}

// MARK: - SessionStore

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    @Published var selectedSessionID: UUID?

    init() {
        let s = Session(title: "Session 1")
        sessions.append(s)
        selectedSessionID = s.id
    }

    var activeSession: Session? {
        sessions.first { $0.id == selectedSessionID }
    }

    func newSession() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let s = Session(title: "Session \(self.sessions.count + 1)")
            self.sessions.append(s)
            self.selectedSessionID = s.id
        }
    }

    func close(_ id: UUID) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let s = self.sessions.first(where: { $0.id == id }) {
                s.terminateAll()
            }
            self.sessions.removeAll { $0.id == id }
            if self.selectedSessionID == id {
                self.selectedSessionID = self.sessions.first?.id
            }
        }
    }
}

// MARK: - SidebarView

struct SidebarView: View {
    @ObservedObject var store: SessionStore

    private var selectionBinding: Binding<UUID?> {
        Binding(
            get: { store.selectedSessionID },
            set: { newValue in
                DispatchQueue.main.async { store.selectedSessionID = newValue }
            }
        )
    }

    var body: some View {
        List(selection: selectionBinding) {
            Section("Sessions") {
                ForEach(store.sessions) { session in
                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.tint)
                        Text(session.title)
                        Spacer()
                        Text("\(session.tabs.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(session.id)
                    .contextMenu {
                        Button("Close session", role: .destructive) {
                            store.close(session.id)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.newSession()
                } label: {
                    Label("New Session", systemImage: "plus")
                }
                .help("New session (⌘N)")
                .keyboardShortcut("n", modifiers: [.command])
            }
        }
    }
}
