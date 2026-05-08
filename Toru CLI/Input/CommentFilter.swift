import Foundation

/// Strips line-leading `#` comments before sending input to the PTY.
///
/// Inline `#` (after command text) is preserved — only lines whose first
/// non-whitespace char is `#` are stripped. Returns `nil` if every line
/// was a comment (caller should send only a newline, not execute anything).
enum CommentFilter {
    static func filter(_ input: String) -> String? {
        let lines = input.components(separatedBy: "\n")
        let kept = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && !trimmed.hasPrefix("#")
        }
        return kept.isEmpty ? nil : kept.joined(separator: "\n")
    }

    /// Marks whether a single line is a visual comment (for rendering hints).
    static func isCommentLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("#")
    }
}
