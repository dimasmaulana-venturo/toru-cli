import Foundation
import AppKit

/// Two visible states for the terminal pane:
///   - `idle`: block list + input bar. Plain commands run here and their
///     output streams live into the active block. The embedded SwiftTerm
///     view is collapsed (zero height, opacity 0). No glitch on fast
///     commands like `ls` / `cd` because we never flip away from idle.
///   - `fullTUI`: SwiftTerm fills the entire pane. Block list hidden.
///     Triggered ONLY by genuine "needs full terminal" signals:
///     `\e[?1049h` alt-screen, ICANON cleared (raw-mode child), or a
///     whitelist hit at submit time. Reverts to `.idle` when the shell
///     is back at its own prompt.
enum TerminalMode: Equatable {
    case idle
    case fullTUI
}

@MainActor
final class ShellBridge: ObservableObject {
    @Published var terminalMode: TerminalMode = .idle

    /// Set by the alt-screen byte scanner.
    @Published var altScreenActive: Bool = false

    /// First token of the most recently submitted command. Used for the
    /// window title in `.fullTUI`.
    @Published var activeCommand: String? = nil

    weak var view: TorTerminalView?
    weak var blockStore: BlockStore?

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

    /// Drive `terminalMode` from the current poll signals. Called every
    /// 200 ms by `TorTerminalContainer`. Rule:
    ///
    ///   altScreenActive          → .fullTUI
    ///   rawMode  && !atPrompt    → .fullTUI  (child wants raw I/O)
    ///   atPrompt                 → markCurrentDone, .idle
    ///   else                     → unchanged (child running, no TUI signal
    ///                              — keep idle so `ls`, `cd`, `cat foo`
    ///                              don't flicker the UI)
    func recomputeMode(atPrompt: Bool, rawMode: Bool) {
        if altScreenActive {
            enterFullTUI()
            return
        }
        if rawMode && !atPrompt {
            enterFullTUI()
            return
        }
        if atPrompt {
            blockStore?.markCurrentDone()
            if terminalMode != .idle {
                terminalMode = .idle
                activeCommand = nil
            }
            return
        }
        // Plain command running, no TUI signal — leave the mode alone.
    }

    private func enterFullTUI() {
        guard terminalMode != .fullTUI else { return }
        terminalMode = .fullTUI
        // Wipe history when handing the pane to a TUI program so the
        // previous block output doesn't get interleaved underneath.
        blockStore?.clearAll()
    }

    /// Bypass the rule above. Used by the command-name whitelist to
    /// switch into `.fullTUI` instantly on submit. Wipes the block list
    /// when entering `.fullTUI` so the previous `ls` / `node -v` output
    /// doesn't sit underneath the TUI session in the user's history.
    func forceMode(_ mode: TerminalMode) {
        if terminalMode == mode { return }
        terminalMode = mode
        if mode == .fullTUI {
            blockStore?.clearAll()
        }
    }
}
