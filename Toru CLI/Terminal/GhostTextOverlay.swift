import AppKit

final class GhostTextOverlay: NSTextField {
    private(set) var suffix: String?

    init() {
        super.init(frame: .zero)
        isEditable = false
        isSelectable = false
        isBordered = false
        drawsBackground = false
        backgroundColor = .clear
        textColor = .tertiaryLabelColor
        focusRingType = .none
        cell?.isScrollable = false
        cell?.usesSingleLineMode = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(suffix: String, font: NSFont, color: NSColor, anchor: CGPoint) {
        self.suffix = suffix
        stringValue = suffix
        self.font = font
        self.textColor = color
        sizeToFit()
        setFrameOrigin(anchor)
        isHidden = false
    }
}
