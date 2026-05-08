import AppKit

struct Theme: Codable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let background: String
    let foreground: String
    let cursor: String
    let ansi: [String]

    var backgroundColor: NSColor { NSColor(hex: background) ?? .black }
    var foregroundColor: NSColor { NSColor(hex: foreground) ?? .white }
    var cursorColor: NSColor { NSColor(hex: cursor) ?? .white }
    var ansiColors: [NSColor] { ansi.map { NSColor(hex: $0) ?? .gray } }
}

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        let r = CGFloat((v >> 16) & 0xFF) / 255.0
        let g = CGFloat((v >> 8)  & 0xFF) / 255.0
        let b = CGFloat( v        & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }
}
