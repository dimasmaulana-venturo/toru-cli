import Foundation
import AppKit

/// Two visible states for the terminal pane.
///
/// - `.idle`: block list + input bar. Default state when the shell is
///   sitting at its own prompt waiting for the next command.
/// - `.running`: SwiftTerm takes over the bottom of the pane. The user
///   interacts with the running command directly — types replies,
///   answers prompts, navigates TUI menus. When the shell returns to
///   its prompt, the captured output is committed to a block and the
///   pane flips back to `.idle`.
///
/// No whitelist, no ICANON-poll-driven distinction between "alt-screen"
/// and "raw mode" any more. Every command runs through the same
/// terminal surface.
enum TerminalMode: Equatable {
    case idle
    case running
}

@MainActor
final class ShellBridge: ObservableObject {
    @Published var terminalMode: TerminalMode = .idle

    /// Most recent submitted command's first token. Used for the window
    /// title while a command is running.
    @Published var activeCommand: String? = nil

    weak var view: TorTerminalView?
    weak var blockStore: BlockStore?
    /// Streaming + grid renderer owned by `TabState`. Used at finalize
    /// to render a corrected colored AttributedString from the grid
    /// emulator when the running block flagged cursor moves.
    weak var renderer: AnsiAttributedRenderer?

    // MARK: - PTY writes

    func send(command: String) {
        view?.send(txt: command + "\n")
    }

    func sendRaw(_ data: Data) {
        guard let view = view else { return }
        view.send(data: ArraySlice([UInt8](data)))
    }

    func isAtPrompt() -> Bool {
        view?.isShellAtPrompt() ?? true
    }

    // MARK: - Mode policy
    //
    // Driven by the 100ms poll on `tcgetpgrp`. Whenever the foreground
    // process group is the shell itself we go `.idle` and finalize the
    // running block; otherwise we transition to `.running`.
    //
    // No more `forceMode(.running)` on submit — instant commands (`ls`,
    // `cd`, `clear`) finish before the next poll, so they never enter
    // the running phase and the cell stays in idle the whole time. Only
    // commands that genuinely take >100ms see the live terminal swap in.
    func recomputeMode(atPrompt: Bool) {
        if atPrompt {
            applyGridSnapshotIfNeeded()
            blockStore?.markCurrentDone()
            if terminalMode != .idle {
                terminalMode = .idle
                activeCommand = nil
            }
        } else {
            if terminalMode != .running {
                terminalMode = .running
            }
        }
    }

    /// If the running block used cursor moves but stayed on the main
    /// screen (neofetch, ascii art, fancy progress), swap in the grid
    /// emulator's render — same colors as streamed but with the moves
    /// applied so the layout matches what the user saw.
    /// Alt-screen blocks are handled separately by
    /// `Block.markCurrentDone`.
    private func applyGridSnapshotIfNeeded() {
        guard let block = blockStore?.blocks.last(where: { $0.isRunning }) else { return }
        guard let renderer = renderer else { return }
        guard block.usedCursorMoves, !block.usedAlternateScreen else { return }
        // Skip the first line (echoed `command\n`) — the block header
        // already shows the command.
        let rendered = renderer.grid.render(skipFirstLine: true)
        if !rendered.characters.isEmpty {
            block.output = rendered
        }
    }

    /// Fire a one-shot recompute shortly after a command is submitted so
    /// medium-fast commands (~50–100ms) get the live terminal surface
    /// without waiting a full poll interval. `nudgeDelay` is short enough
    /// that instant commands have already finished by the time it runs,
    /// so `atPrompt` reads `true` and we stay in `.idle`.
    func nudgePoll(after delay: TimeInterval = 0.06) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, let view = self.view else { return }
            self.recomputeMode(atPrompt: view.isShellAtPrompt())
        }
    }
}
