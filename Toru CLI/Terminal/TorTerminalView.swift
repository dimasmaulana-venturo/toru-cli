import AppKit
import SwiftTerm

/// SwiftTerm wrapper.
///
/// Input pipeline (Approach C — local NSEvent monitor):
/// We attach an `NSEvent.addLocalMonitorForEvents` while this view is first
/// responder. The monitor maintains a per-line buffer, runs CommentFilter on
/// Enter, drives ghost-text via AutocompleteEngine, and accepts ghost suffix
/// on Tab / Right Arrow. Pasted input is filtered via NSText paste hook is
/// out of scope for v1; v1 strips at Enter only.
final class TorTerminalView: LocalProcessTerminalView {

    // MARK: - State
    private let sessionId: String = UUID().uuidString
    private var lineBuffer: String = ""
    private let autocomplete = AutocompleteEngine()
    private let tabCompleter = TabCompleter()
    private let history = HistoryDatabase.shared
    private let ghost = GhostTextOverlay()
    private var currentTheme: Theme = ThemeManager.shared.current
    private var keyMonitor: Any?
    private lazy var procDelegate = TorProcessDelegate(owner: self)

    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    deinit {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
    }

    private func configure() {
        processDelegate = procDelegate
        applyTheme(currentTheme)
        addSubview(ghost)
        ghost.isHidden = true
        tabCompleter.warmUp()
        configureFont()
        installKeyMonitor()
    }

    private func configureFont() {
        let size = CGFloat(SettingsStore.shared.fontSize)
        if let f = NSFont(name: SettingsStore.shared.fontName, size: size) ??
                   NSFont(name: "Menlo", size: size) {
            font = f
        }
    }

    func startShell() {
        let shell = PTYBridge.resolveShell()
        let env = PTYBridge.envArray()
        startProcess(executable: shell, args: ["-l"], environment: env, execName: shell)
    }

    // MARK: - Theme
    func applyTheme(_ theme: Theme) {
        currentTheme = theme
        nativeBackgroundColor = theme.backgroundColor
        nativeForegroundColor = theme.foregroundColor

        let cs = theme.ansiColors
        if cs.count == 16 {
            installColors(cs.map {
                Color(red:   UInt16($0.redComponent   * 65535),
                      green: UInt16($0.greenComponent * 65535),
                      blue:  UInt16($0.blueComponent  * 65535))
            })
        }
        wantsLayer = true
        layer?.backgroundColor = theme.backgroundColor.cgColor
    }

    // MARK: - Key intercept (NSEvent local monitor)
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // Only intercept when our window is key and we are (or contain) first responder.
            guard event.window === self.window,
                  self.window?.firstResponder === self || self.containsResponder(self.window?.firstResponder)
            else { return event }
            return self.handleKey(event)
        }
    }

    private func containsResponder(_ r: NSResponder?) -> Bool {
        var cur = r
        while let c = cur {
            if c === self { return true }
            cur = c.nextResponder
        }
        return false
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        let chars = event.charactersIgnoringModifiers ?? ""

        // Enter / Return — record history (PTY still receives, normal behavior)
        if event.keyCode == 36 || chars == "\r" || chars == "\n" {
            executeCurrentLine()
            lineBuffer.removeAll()
            ghost.isHidden = true
            autocomplete.reset()
            return event
        }

        // Tab or Right-Arrow → accept ghost text (consume, send suffix)
        if (event.keyCode == 48 || event.keyCode == 124),
           !ghost.isHidden, let suffix = ghost.suffix, !suffix.isEmpty {
            send(txt: suffix)
            lineBuffer += suffix
            ghost.isHidden = true
            return nil
        }

        // Escape — dismiss ghost (let PTY also see it)
        if event.keyCode == 53 {
            ghost.isHidden = true
            return event
        }

        // Backspace
        if event.keyCode == 51 {
            if !lineBuffer.isEmpty { lineBuffer.removeLast() }
            autocomplete.onBackspace()
            ghost.isHidden = true
            return event
        }

        // Printable ASCII
        let isPrintable = chars.unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value < 0x7F }
        if isPrintable && !chars.isEmpty {
            lineBuffer += chars
            autocomplete.onCharInput()
            DispatchQueue.main.async { [weak self] in self?.updateGhost() }
        }
        return event
    }

    private func updateGhost() {
        guard SettingsStore.shared.ghostTextEnabled else {
            ghost.isHidden = true; return
        }
        guard let suffix = autocomplete.suggest(for: lineBuffer) else {
            ghost.isHidden = true; return
        }
        ghost.show(suffix: suffix, font: font, color: .tertiaryLabelColor, anchor: caretPoint())
    }

    private func caretPoint() -> CGPoint {
        let charWidth = font.maximumAdvancement.width
        let lineHeight = font.ascender + abs(font.descender) + font.leading
        let cols = CGFloat(lineBuffer.count)
        let x = cols * charWidth + 6
        let y = max(2, bounds.height - lineHeight - 4)
        return CGPoint(x: x, y: y)
    }

    private func executeCurrentLine() {
        let raw = lineBuffer
        guard let executed = CommentFilter.filter(raw) else { return }
        history.record(rawInput: raw, executed: executed,
                       directory: NSHomeDirectory(),
                       sessionId: sessionId)
    }

    fileprivate func updateWindowTitle(_ title: String) {
        window?.title = title.isEmpty ? "Toru CLI" : title
    }
}

final class TorProcessDelegate: NSObject, LocalProcessTerminalViewDelegate {
    weak var owner: TorTerminalView?
    init(owner: TorTerminalView) { self.owner = owner }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        owner?.updateWindowTitle(title)
    }
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func processTerminated(source: TerminalView, exitCode: Int32?) {}
}
