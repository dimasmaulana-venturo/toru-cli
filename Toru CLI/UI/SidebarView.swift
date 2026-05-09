import SwiftUI
import AppKit

// MARK: - TabState (one shell)

@MainActor
final class TabState: Identifiable, ObservableObject {
    let id = UUID()
    @Published var title: String
    /// Title to revert to when the running command exits — preserves
    /// the original "Tab N" / user-renamed name across run cycles.
    let defaultTitle: String
    let createdAt = Date()

    let shellBridge = ShellBridge()
    let blockStore = BlockStore()
    let host: PaddedTerminalHost

    private var pollTimer: Timer?
    private var ptyWired = false
    private var lastCols: Int = -1
    private var lastRows: Int = -1
    let renderer = AnsiAttributedRenderer()

    init(title: String) {
        self.title = title
        self.defaultTitle = title
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
        shellBridge.renderer = renderer
        wirePtyTap()
        startPolling()
    }

    private func wirePtyTap() {
        let store = blockStore
        host.terminal.onPtyBytes = { [weak self] bytes in
            guard let self else { return }
            // Always feed bytes through the ANSI renderer and capture
            // them on the running block. SwiftTerm renders the same
            // bytes live in the visible terminal during `.running`; the
            // captured AttributedString is what survives as the block's
            // final output once the command exits.
            let bytesCopy = Array(bytes)
            Task { @MainActor in
                let attr = self.renderer.feed(bytesCopy)
                if !attr.characters.isEmpty {
                    store.appendToCurrent(attr)
                }
                if self.renderer.consumeCursorMoveFlag() {
                    store.markRunningBlockCursorPositioned()
                }
                if self.renderer.consumeAltScreenFlag() {
                    store.markRunningBlockAlternateScreen()
                }
            }
        }
    }

    private func startPolling() {
        pollTimer?.invalidate()
        let bridge = shellBridge
        let timer = Timer(timeInterval: 0.1, repeats: true) {
            [weak terminal = host.terminal] _ in
            guard let terminal = terminal else { return }
            let atPrompt = terminal.isShellAtPrompt()
            MainActor.assumeIsolated {
                bridge.recomputeMode(atPrompt: atPrompt)
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

// MARK: - Session

@MainActor
final class Session: Identifiable, ObservableObject {
    let id = UUID()
    @Published var title: String
    @Published var pinned: Bool = false
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

    /// Pinned first, then unpinned, both groups in original order. Used
    /// by the sidebar to display pinned sessions sticky at the top.
    var orderedSessions: [Session] {
        sessions.filter(\.pinned) + sessions.filter { !$0.pinned }
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

    func togglePin(_ id: UUID) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let s = self.sessions.first(where: { $0.id == id }) {
                s.pinned.toggle()
            }
        }
    }

    func rename(_ id: UUID, to newTitle: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let s = self.sessions.first(where: { $0.id == id }) {
                s.title = newTitle
            }
        }
    }
}

// MARK: - SidebarView

struct SidebarView: View {
    @ObservedObject var store: SessionStore
    @State private var renamingID: UUID? = nil
    @State private var draftTitle: String = ""

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
                ForEach(store.orderedSessions) { session in
                    SessionRow(
                        session: session,
                        renamingID: $renamingID,
                        draftTitle: $draftTitle,
                        onRequestDelete: { store.close(session.id) },
                        onTogglePin: { store.togglePin(session.id) },
                        onCommitRename: { newName in
                            store.rename(session.id, to: newName)
                            renamingID = nil
                        }
                    )
                    .tag(session.id)
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

private struct SessionRow: View {
    @ObservedObject var session: Session
    @Binding var renamingID: UUID?
    @Binding var draftTitle: String
    let onRequestDelete: () -> Void
    let onTogglePin: () -> Void
    let onCommitRename: (String) -> Void

    @State private var hovering = false
    @FocusState private var renameFocused: Bool

    private var isRenaming: Bool { renamingID == session.id }

    var body: some View {
        HStack(spacing: 6) {
            // Left affordance: hover-only delete icon for UNPINNED sessions.
            // Pinned sessions show a pin badge instead.
            ZStack {
                if session.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tint)
                } else if hovering {
                    Button(action: onRequestDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Close session")
                } else {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tint)
                }
            }
            .frame(width: 16, height: 16)
            .animation(.easeInOut(duration: 0.12), value: hovering)
            .animation(.easeInOut(duration: 0.12), value: session.pinned)

            // Title (label OR rename TextField).
            if isRenaming {
                TextField("Name", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .focused($renameFocused)
                    .onSubmit {
                        let trimmed = draftTitle.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            onCommitRename(trimmed)
                        } else {
                            renamingID = nil
                        }
                    }
                    .onAppear { renameFocused = true }
                    .onExitCommand { renamingID = nil }
            } else {
                Text(session.title)
                    .lineLimit(1)
                    .onTapGesture(count: 2) {
                        draftTitle = session.title
                        renamingID = session.id
                    }
            }

            Spacer()

            Text("\(session.tabs.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Rename") {
                draftTitle = session.title
                renamingID = session.id
            }
            Button(session.pinned ? "Unpin" : "Pin", action: onTogglePin)
            Divider()
            Button("Close session", role: .destructive, action: onRequestDelete)
        }
    }
}
