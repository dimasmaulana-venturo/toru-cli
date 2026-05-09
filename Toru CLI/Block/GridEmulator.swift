import Foundation
import SwiftUI

/// Tiny terminal-screen emulator built specifically to give the block
/// history correct *colored* output for cursor-positioned commands
/// (neofetch, ascii art, fancy progress).
///
/// SwiftTerm renders the live terminal authoritatively, but its
/// `Buffer.lines` is `internal` so we can't pull out colored cells
/// directly. The streaming `AnsiAttributedRenderer` flat-appends bytes
/// and drops cursor-move CSIs, which is fine for `ls` / `git status`
/// but mangles neofetch (its logo and info table are interleaved with
/// `ESC[<n>A` cursor-up + `ESC[<n>C` cursor-right writes).
///
/// `GridEmulator` keeps its own 2D `[[Cell]]` and applies the cursor
/// moves as SwiftTerm would. On finalize, `BlockStore` swaps the
/// streamed `AttributedString` for the grid render — same colors, same
/// layout the user actually saw on screen.
///
/// Scope is intentionally narrow: covers the ANSI sequences common to
/// CLI output (neofetch, lazygit, ascii banners, npm/bun progress
/// bars). Alt-screen TUIs (vim/htop/claude) are detected separately
/// and short-circuited to a single "(interactive session)" marker, so
/// we don't need scroll regions, save/restore cursor, line-edit, etc.
final class GridEmulator {

    // MARK: - Cell

    private struct Cell {
        var ch: Character = " "
        var fg: Color? = nil
        var bg: Color? = nil
        var bold: Bool = false
        var italic: Bool = false
        var underline: Bool = false

        static let blank = Cell()

        var hasContent: Bool {
            ch != " " || fg != nil || bg != nil || bold || italic || underline
        }
    }

    // MARK: - State

    private var rows: [[Cell]] = [[]]
    private var cursorRow: Int = 0
    private var cursorCol: Int = 0
    /// Active style applied to written cells. Driven by SGR (`ESC[…m`).
    private var fg: Color? = nil
    private var bg: Color? = nil
    private var bold: Bool = false
    private var italic: Bool = false
    private var underline: Bool = false

    private enum State { case text, esc, csi, osc }
    private var state: State = .text
    private var paramBuf: [UInt8] = []

    // MARK: - Lifecycle

    func reset() {
        rows = [[]]
        cursorRow = 0
        cursorCol = 0
        fg = nil; bg = nil
        bold = false; italic = false; underline = false
        state = .text
        paramBuf.removeAll(keepingCapacity: true)
    }

    // MARK: - Feed

    func feed(_ bytes: [UInt8]) {
        for b in bytes {
            switch state {
            case .text: handleText(b)
            case .esc:  handleEsc(b)
            case .csi:  handleCsi(b)
            case .osc:  handleOsc(b)
            }
        }
    }

    private func handleText(_ b: UInt8) {
        switch b {
        case 0x1B:
            state = .esc
        case 0x0A:  // LF
            cursorRow += 1
            ensureRow(cursorRow)
        case 0x0D:  // CR
            cursorCol = 0
        case 0x09:  // TAB → next 8-col stop
            let next = ((cursorCol / 8) + 1) * 8
            while cursorCol < next { writeCell(" "); }
        case 0x08:  // BS
            cursorCol = max(0, cursorCol - 1)
        case 0x07:  // BEL
            break
        default:
            guard b >= 0x20 else { return }
            // UTF-8 fast path: ASCII-only writes a single Character.
            // For multi-byte we accumulate via a tiny scalar buffer.
            if b < 0x80 {
                writeCell(Character(UnicodeScalar(b)))
            } else {
                accumulateUtf8(b)
            }
        }
    }

    // Tracking partial UTF-8 to assemble multi-byte scalars before
    // writing them as a single grid cell.
    private var utf8Buf: [UInt8] = []
    private func accumulateUtf8(_ b: UInt8) {
        utf8Buf.append(b)
        if let s = String(bytes: utf8Buf, encoding: .utf8), !s.isEmpty {
            for c in s { writeCell(c) }
            utf8Buf.removeAll(keepingCapacity: true)
        } else if utf8Buf.count > 4 {
            utf8Buf.removeAll(keepingCapacity: true)
        }
    }

    private func handleEsc(_ b: UInt8) {
        switch b {
        case 0x5B:
            state = .csi
            paramBuf.removeAll(keepingCapacity: true)
        case 0x5D:
            state = .osc
        default:
            state = .text
        }
    }

    private func handleCsi(_ b: UInt8) {
        if b >= 0x30 && b <= 0x3F {
            paramBuf.append(b)
            return
        }
        if b >= 0x40 && b <= 0x7E {
            applyCsi(final: b, params: paramBuf)
            state = .text
            paramBuf.removeAll(keepingCapacity: true)
        }
    }

    private func handleOsc(_ b: UInt8) {
        if b == 0x07 { state = .text }
        else if b == 0x1B { state = .esc }
    }

    private func parseParams(_ buf: [UInt8]) -> [Int] {
        guard let s = String(bytes: buf, encoding: .ascii), !s.isEmpty else {
            return []
        }
        return s.split(separator: ";", omittingEmptySubsequences: false)
                .map { Int($0) ?? 0 }
    }

    private func applyCsi(final: UInt8, params raw: [UInt8]) {
        // Skip private-mode params ('?', '>', '=' as first byte).
        if let first = raw.first,
           first == 0x3F || first == 0x3E || first == 0x3D {
            return
        }
        let params = parseParams(raw)
        let p1 = params.first ?? 0
        switch final {
        case 0x41: cursorRow = max(0, cursorRow - max(1, p1))                 // CUU 'A'
        case 0x42: cursorRow += max(1, p1); ensureRow(cursorRow)              // CUD 'B'
        case 0x43: cursorCol += max(1, p1)                                    // CUF 'C'
        case 0x44: cursorCol = max(0, cursorCol - max(1, p1))                 // CUB 'D'
        case 0x45: cursorRow += max(1, p1); cursorCol = 0; ensureRow(cursorRow) // CNL 'E'
        case 0x46: cursorRow = max(0, cursorRow - max(1, p1)); cursorCol = 0  // CPL 'F'
        case 0x47: cursorCol = max(0, p1 - 1)                                 // CHA 'G' (1-based)
        case 0x48, 0x66:                                                      // CUP 'H' / HVP 'f'
            let r = (params.count > 0 ? params[0] : 1)
            let c = (params.count > 1 ? params[1] : 1)
            cursorRow = max(0, r - 1)
            cursorCol = max(0, c - 1)
            ensureRow(cursorRow)
        case 0x4A:                                                            // ED 'J'
            eraseDisplay(mode: p1)
        case 0x4B:                                                            // EL 'K'
            eraseLine(mode: p1)
        case 0x6D:                                                            // SGR 'm'
            applySGR(params)
        default:
            break
        }
    }

    private func applySGR(_ params: [Int]) {
        let codes = params.isEmpty ? [0] : params
        var i = 0
        while i < codes.count {
            let p = codes[i]
            switch p {
            case 0:
                fg = nil; bg = nil
                bold = false; italic = false; underline = false
            case 1: bold = true
            case 3: italic = true
            case 4: underline = true
            case 22: bold = false
            case 23: italic = false
            case 24: underline = false
            case 30...37: fg = ansi8(p - 30, bright: false)
            case 90...97: fg = ansi8(p - 90, bright: true)
            case 40...47: bg = ansi8(p - 40, bright: false)
            case 100...107: bg = ansi8(p - 100, bright: true)
            case 38:
                if i + 2 < codes.count, codes[i+1] == 5 {
                    fg = ansi256(codes[i+2]); i += 2
                } else if i + 4 < codes.count, codes[i+1] == 2 {
                    fg = Color(red: Double(codes[i+2])/255,
                               green: Double(codes[i+3])/255,
                               blue: Double(codes[i+4])/255)
                    i += 4
                }
            case 48:
                if i + 2 < codes.count, codes[i+1] == 5 {
                    bg = ansi256(codes[i+2]); i += 2
                } else if i + 4 < codes.count, codes[i+1] == 2 {
                    bg = Color(red: Double(codes[i+2])/255,
                               green: Double(codes[i+3])/255,
                               blue: Double(codes[i+4])/255)
                    i += 4
                }
            case 39: fg = nil
            case 49: bg = nil
            default: break
            }
            i += 1
        }
    }

    private func ansi8(_ n: Int, bright: Bool) -> Color {
        let table: [Color] = [
            .black, .red, .green, .yellow, .blue,
            Color(red: 0.8, green: 0.0, blue: 0.8),
            .cyan, .white
        ]
        let base = table[max(0, min(7, n))]
        return bright ? base.opacity(1.0) : base
    }

    private func ansi256(_ code: Int) -> Color {
        if code < 16 { return ansi8(code & 7, bright: code >= 8) }
        if code >= 232 {
            let g = Double(code - 232) / 23.0
            return Color(red: g, green: g, blue: g)
        }
        let n = code - 16
        let r = Double((n / 36) % 6) / 5.0
        let g = Double((n / 6) % 6) / 5.0
        let b = Double(n % 6) / 5.0
        return Color(red: r, green: g, blue: b)
    }

    // MARK: - Grid mutation

    private func ensureRow(_ r: Int) {
        while rows.count <= r { rows.append([]) }
    }

    private func ensureCol(_ r: Int, _ c: Int) {
        ensureRow(r)
        while rows[r].count <= c { rows[r].append(.blank) }
    }

    private func writeCell(_ ch: Character) {
        ensureCol(cursorRow, cursorCol)
        rows[cursorRow][cursorCol] = Cell(
            ch: ch, fg: fg, bg: bg,
            bold: bold, italic: italic, underline: underline
        )
        cursorCol += 1
    }

    private func eraseLine(mode: Int) {
        ensureRow(cursorRow)
        switch mode {
        case 0:
            if cursorCol < rows[cursorRow].count {
                rows[cursorRow].removeSubrange(cursorCol..<rows[cursorRow].count)
            }
        case 1:
            for c in 0..<min(cursorCol + 1, rows[cursorRow].count) {
                rows[cursorRow][c] = .blank
            }
        case 2:
            rows[cursorRow] = []
        default: break
        }
    }

    private func eraseDisplay(mode: Int) {
        switch mode {
        case 0:
            eraseLine(mode: 0)
            for r in (cursorRow + 1)..<rows.count { rows[r] = [] }
        case 1:
            for r in 0..<cursorRow where r < rows.count { rows[r] = [] }
            eraseLine(mode: 1)
        case 2, 3:
            rows = [[]]
            cursorRow = 0
            cursorCol = 0
        default: break
        }
    }

    // MARK: - Render

    /// Render the grid as an `AttributedString`, trimming trailing
    /// blank rows and right-trimming each row's trailing spaces.
    func render(skipFirstLine: Bool = false) -> AttributedString {
        // Find last meaningful row.
        var lastRow = -1
        for (i, row) in rows.enumerated() where row.contains(where: { $0.hasContent }) {
            lastRow = i
        }
        if lastRow < 0 { return AttributedString() }

        var result = AttributedString()
        let startRow = skipFirstLine ? 1 : 0
        for r in startRow...lastRow {
            let row = rows[r]
            // Right-trim trailing blank cells.
            var end = row.count
            while end > 0 && !row[end - 1].hasContent { end -= 1 }

            var col = 0
            while col < end {
                let cell = row[col]
                var run = String(cell.ch)
                var c2 = col + 1
                while c2 < end &&
                      row[c2].fg == cell.fg &&
                      row[c2].bg == cell.bg &&
                      row[c2].bold == cell.bold &&
                      row[c2].italic == cell.italic &&
                      row[c2].underline == cell.underline {
                    run.append(row[c2].ch)
                    c2 += 1
                }
                var piece = AttributedString(run)
                if let fg = cell.fg { piece.foregroundColor = fg }
                if let bg = cell.bg { piece.backgroundColor = bg }
                var font = Font.system(size: 12, design: .monospaced)
                if cell.bold { font = font.weight(.bold) }
                if cell.italic { font = font.italic() }
                piece.font = font
                if cell.underline { piece.underlineStyle = .single }
                result.append(piece)
                col = c2
            }
            if r < lastRow { result.append(AttributedString("\n")) }
        }
        return result
    }
}
