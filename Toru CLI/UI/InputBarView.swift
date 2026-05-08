import SwiftUI
import AppKit

/// Idle-state input bar. Behaviors:
///   - Submit on ⏎ → calls `onSubmit`.
///   - Submit on ⌃C → calls `onCtrlC` (parent forwards ETX to PTY).
///   - ↑ / ↓ recall history, prefix-filtered: type "bun" then ↑ cycles
///     through past commands starting with "bun" only (Warp-style).
struct InputBarView: View {
    var onSubmit: (String) -> Void
    var onCtrlC: () -> Void
    /// Returns the current cwd of the running shell (for tab-completion).
    var cwdProvider: () -> String = { NSHomeDirectory() }

    @State private var text: String = ""
    @FocusState private var focused: Bool

    // Prefix-history navigation state.
    @State private var historyMatches: [String] = []
    @State private var historyIndex: Int = -1   // -1 = original prefix
    @State private var historyPrefix: String = ""
    @State private var navigatingHistory: Bool = false

    // Tab-completion popover state. First Tab does inline completion;
    // second consecutive Tab opens a popover above the input listing all
    // matching folders / files at the current cwd.
    @State private var tabPressCount: Int = 0
    @State private var showCompletions: Bool = false
    @State private var completions: [CompletionEntry] = []
    @State private var completionSelection: Int = 0

    private struct CompletionEntry: Identifiable {
        let id = UUID()
        let name: String
        let isDir: Bool
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(">")
                .foregroundStyle(Color.teal)
                .font(.system(size: 13, design: .monospaced).weight(.semibold))

            TextField("Type a command…", text: $text)
                .font(.system(size: 13, design: .monospaced))
                .textFieldStyle(.plain)
                .foregroundStyle(Color(nsColor: .labelColor))
                .focused($focused)
                .onSubmit(submit)
                .onKeyPress(KeyEquivalent("c"), phases: .down) { press in
                    if press.modifiers.contains(.control) {
                        onCtrlC()
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(.upArrow, phases: .down) { _ in
                    historyUp()
                    return .handled
                }
                .onKeyPress(.downArrow, phases: .down) { _ in
                    historyDown()
                    return .handled
                }
                .onKeyPress(.tab, phases: .down) { _ in
                    handleTab()
                    return .handled
                }
                .onKeyPress(.escape, phases: .down) { _ in
                    if showCompletions {
                        showCompletions = false
                        return .handled
                    }
                    return .ignored
                }
                .onChange(of: text) { _, _ in
                    if !navigatingHistory {
                        resetHistoryState()
                    }
                    // Any text edit also resets the Tab counter so the
                    // next Tab starts a fresh single-completion attempt.
                    tabPressCount = 0
                    showCompletions = false
                }
                .popover(
                    isPresented: $showCompletions,
                    attachmentAnchor: .point(.top),
                    arrowEdge: .bottom
                ) {
                    completionsPopover
                }

            Button(action: submit) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(text.isEmpty ? Color.gray : Color.teal)
            }
            .buttonStyle(.plain)
            .disabled(text.isEmpty)
            .help("Send (⏎)")
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
        }
        .help("⌘K clear  ·  ⌘⏎ new conversation  ·  ⌃C interrupt  ·  ↑/↓ history")
        .onAppear { focused = true }
    }

    private func submit() {
        let cmd = text.trimmingCharacters(in: .whitespaces)
        guard !cmd.isEmpty else { return }
        text = ""
        resetHistoryState()
        onSubmit(cmd)
    }

    // MARK: - History navigation

    private func historyUp() {
        if !navigatingHistory {
            historyPrefix = text
            historyMatches = HistoryDatabase.shared.recentMatching(prefix: text)
            historyIndex = -1
            navigatingHistory = true
        }
        guard !historyMatches.isEmpty else { return }
        let next = min(historyIndex + 1, historyMatches.count - 1)
        if next == historyIndex { return }
        historyIndex = next
        applyHistoryEntry()
    }

    private func historyDown() {
        guard navigatingHistory else { return }
        if historyIndex <= 0 {
            historyIndex = -1
            navigatingHistory = true
            // Restore the original prefix.
            applyText(historyPrefix)
            return
        }
        historyIndex -= 1
        applyHistoryEntry()
    }

    private func applyHistoryEntry() {
        guard historyIndex >= 0, historyIndex < historyMatches.count else { return }
        applyText(historyMatches[historyIndex])
    }

    private func applyText(_ s: String) {
        // Set without triggering history reset — the .onChange handler
        // checks `navigatingHistory` to know we're driving the change.
        let wasNav = navigatingHistory
        navigatingHistory = true
        text = s
        // Defer the flag flip to the next runloop so `.onChange(of: text)`
        // fires with `navigatingHistory == true`.
        DispatchQueue.main.async {
            navigatingHistory = wasNav
        }
    }

    private func resetHistoryState() {
        navigatingHistory = false
        historyMatches = []
        historyIndex = -1
        historyPrefix = ""
    }

    // MARK: - Tab completion

    /// Tab key handler. First press inline-completes the longest unique
    /// prefix. Second consecutive press opens a popover listing all
    /// matches above the input.
    private func handleTab() {
        tabPressCount += 1
        if tabPressCount >= 2 {
            openCompletionsPopover()
        } else {
            completePath()
        }
    }

    private func openCompletionsPopover() {
        let entries = listCompletions()
        guard !entries.isEmpty else { return }
        completions = entries
        completionSelection = 0
        showCompletions = true
    }

    private func listCompletions() -> [CompletionEntry] {
        let parts = text.split(separator: " ", omittingEmptySubsequences: false)
        let lastPart = parts.last.map(String.init) ?? ""
        let dirPart = (lastPart as NSString).deletingLastPathComponent
        let basePart = (lastPart as NSString).lastPathComponent
        let baseLower = basePart.lowercased()

        let cwd = cwdProvider()
        let searchDir: String
        if dirPart.isEmpty {
            searchDir = cwd
        } else if dirPart.hasPrefix("/") {
            searchDir = dirPart
        } else if dirPart.hasPrefix("~") {
            searchDir = NSString(string: dirPart).expandingTildeInPath
        } else {
            searchDir = "\(cwd)/\(dirPart)"
        }

        let fm = FileManager.default
        guard let raw = try? fm.contentsOfDirectory(atPath: searchDir) else { return [] }
        let filtered = baseLower.isEmpty
            ? raw
            : raw.filter { $0.lowercased().hasPrefix(baseLower) }

        return filtered
            .map { name -> CompletionEntry in
                var isDir: ObjCBool = false
                fm.fileExists(atPath: "\(searchDir)/\(name)", isDirectory: &isDir)
                return CompletionEntry(name: name, isDir: isDir.boolValue)
            }
            .sorted { lhs, rhs in
                if lhs.isDir != rhs.isDir { return lhs.isDir && !rhs.isDir }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private func applyCompletion(_ entry: CompletionEntry) {
        let parts = text.split(separator: " ", omittingEmptySubsequences: false)
        let lastPart = parts.last.map(String.init) ?? ""
        let dirPart = (lastPart as NSString).deletingLastPathComponent
        let suffix = entry.name + (entry.isDir ? "/" : "")
        let prefixLen = text.count - lastPart.count
        let textPrefix = String(text.prefix(prefixLen))
        let completedToken = dirPart.isEmpty ? suffix : "\(dirPart)/\(suffix)"
        text = textPrefix + completedToken
        showCompletions = false
        tabPressCount = 0
    }

    private var completionsPopover: some View {
        let maxVisible = 8
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(completions.enumerated()), id: \.element.id) { idx, entry in
                    HStack(spacing: 8) {
                        Image(systemName: entry.isDir ? "folder.fill" : "doc")
                            .foregroundStyle(entry.isDir ? Color.cyan : .secondary)
                            .font(.system(size: 11))
                            .frame(width: 14)
                        Text(entry.name)
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(idx == completionSelection
                                  ? Color.accentColor.opacity(0.25)
                                  : Color.clear)
                            .padding(.horizontal, 4)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        applyCompletion(entry)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(
            minWidth: 280,
            maxHeight: CGFloat(min(completions.count, maxVisible)) * 28 + 8
        )
    }

    // MARK: - First-Tab LCP completion
    //
    // Bash-style: first Tab advances to the longest common prefix of all
    // matches. If the prefix is already at the LCP (no further advance
    // possible), it's a no-op so the user can press Tab again to open
    // the popover. If exactly one entry matches, it's fully applied.

    private func completePath() {
        let entries = listCompletions()
        guard !entries.isEmpty else { return }

        // Single match — apply fully (auto-trailing-slash for dirs).
        if entries.count == 1 {
            applyCompletion(entries[0])
            return
        }

        let parts = text.split(separator: " ", omittingEmptySubsequences: false)
        let lastPart = parts.last.map(String.init) ?? ""
        let dirPart = (lastPart as NSString).deletingLastPathComponent
        let basePart = (lastPart as NSString).lastPathComponent

        // Empty basePart (e.g. "cd Documents/") → no LCP to advance to;
        // require a second Tab to open the popover.
        guard !basePart.isEmpty else { return }

        let names = entries.map { $0.name }
        let lcp = Self.longestCommonPrefix(names)

        // No advance possible (already at LCP) → leave text alone so the
        // next Tab opens the popover.
        guard lcp.count > basePart.count else { return }

        let prefixLen = text.count - lastPart.count
        let textPrefix = String(text.prefix(prefixLen))
        let completedToken = dirPart.isEmpty ? lcp : "\(dirPart)/\(lcp)"
        text = textPrefix + completedToken
    }

    /// Case-insensitive longest common prefix that returns the first
    /// string truncated to that length (preserving its casing).
    private static func longestCommonPrefix(_ strings: [String]) -> String {
        guard var prefix = strings.first else { return "" }
        for s in strings.dropFirst() {
            while !s.lowercased().hasPrefix(prefix.lowercased()) {
                prefix = String(prefix.dropLast())
                if prefix.isEmpty { return "" }
            }
        }
        return prefix
    }
}
