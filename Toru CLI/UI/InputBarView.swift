import SwiftUI
import AppKit

/// Idle-state input bar — only rendered while `terminalMode == .idle`.
/// On submit, calls `onSubmit`; the parent flips into `.running` and the
/// terminal takes over the bottom slot. `onCtrlC` is wired but only fires
/// inside this view; the global `.onKeyPress` on the parent handles ⌃C
/// once focus has moved to the terminal.
struct InputBarView: View {
    var onSubmit: (String) -> Void
    var onCtrlC: () -> Void

    @State private var text: String = ""
    @FocusState private var focused: Bool

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
        .help("⌘K clear  ·  ⌘⏎ new conversation  ·  ⌃C interrupt")
        .onAppear { focused = true }
    }

    private func submit() {
        let cmd = text.trimmingCharacters(in: .whitespaces)
        guard !cmd.isEmpty else { return }
        text = ""
        onSubmit(cmd)
    }
}
