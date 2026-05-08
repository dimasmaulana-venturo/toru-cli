import SwiftUI
import AppKit

/// Wraps a pre-created `PaddedTerminalHost` so multiple `SessionState`
/// instances can each carry their own NSView (and therefore PTY / shell)
/// across tab switches without ever recreating the underlying SwiftTerm
/// view. PTY setup + byte-tap + poll timer live on `SessionState`.
struct EmbeddedTerminalView: NSViewRepresentable {
    let host: PaddedTerminalHost

    func makeNSView(context: Context) -> PaddedTerminalHost { host }
    func updateNSView(_ nsView: PaddedTerminalHost, context: Context) {}
}

/// AppKit container: insets a `TorTerminalView` inside the SwiftUI parent
/// frame. Used as the persistent NSView per session.
final class PaddedTerminalHost: NSView {
    let terminal = TorTerminalView(frame: .zero)
    var contentInsets: NSEdgeInsets

    init(insets: NSEdgeInsets) {
        self.contentInsets = insets
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        terminal.translatesAutoresizingMaskIntoConstraints = true
        terminal.autoresizingMask = []
        addSubview(terminal)
    }

    required init?(coder: NSCoder) {
        self.contentInsets = NSEdgeInsets()
        super.init(coder: coder)
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let b = bounds
        terminal.frame = NSRect(
            x: contentInsets.left,
            y: contentInsets.top,
            width: max(0, b.width - contentInsets.left - contentInsets.right),
            height: max(0, b.height - contentInsets.top - contentInsets.bottom)
        )
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(terminal)
        super.mouseDown(with: event)
    }
}
