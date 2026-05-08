import Foundation
import SwiftUI

/// One command + its output. Output streams in via `append(_:)` while the
/// command runs (coalesced through a 60fps notify) and stops growing
/// after `markDone(exitCode:)`.
@MainActor
final class Block: Identifiable, ObservableObject {
    let id = UUID()
    let command: String
    let startedAt = Date()

    @Published var output: String = ""
    @Published var isRunning: Bool = true
    @Published var exitCode: Int? = nil

    private var notifyScheduled = false

    init(command: String, output: String = "", isRunning: Bool = true) {
        self.command = command
        self.output = output
        self.isRunning = isRunning
    }

    /// Append a chunk to `output`, coalescing notifies at ~60fps so the
    /// SwiftUI list isn't rebuilt on every PTY byte.
    func append(_ chunk: String) {
        guard !chunk.isEmpty else { return }
        output.append(chunk)
        scheduleNotify()
    }

    func markDone(exitCode: Int? = nil) {
        guard isRunning else { return }
        isRunning = false
        self.exitCode = exitCode
    }

    private func scheduleNotify() {
        if notifyScheduled { return }
        notifyScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0/60.0) { [weak self] in
            guard let self else { return }
            self.notifyScheduled = false
            self.objectWillChange.send()
        }
    }
}

@MainActor
final class BlockStore: ObservableObject {
    @Published private(set) var blocks: [Block] = []

    /// Coalesced stream-tick. SwiftUI views observing `BlockStore`
    /// (e.g. `BlockListView`) re-evaluate when `blocks` changes — but
    /// internal mutation of `Block.output` only fires that block's own
    /// `objectWillChange`, not the store's. Bumping this counter at
    /// ~10/sec gives `.onChange(of: streamTick)` a hook for things like
    /// auto-scroll-to-bottom while a long-running command streams.
    @Published private(set) var streamTick: Int = 0
    private var streamTickScheduled = false

    /// Open a new running block (output empty until bytes stream in).
    func startBlock(command: String) {
        blocks.append(Block(command: command))
    }

    /// Live-append a chunk into the most recent running block.
    func appendToCurrent(_ chunk: String) {
        blocks.last?.append(chunk)
        scheduleStreamTick()
    }

    private func scheduleStreamTick() {
        if streamTickScheduled { return }
        streamTickScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            self.streamTickScheduled = false
            self.streamTick &+= 1
        }
    }

    /// Mark the most recent block as finished. Republishes the store so
    /// SwiftUI observers (e.g. `InputBarView`) react.
    func markCurrentDone(exitCode: Int? = nil) {
        guard let cur = blocks.last, cur.isRunning else { return }
        cur.markDone(exitCode: exitCode)
        objectWillChange.send()
    }

    /// Replace the running block's output in one shot and mark it done.
    /// Currently unused; kept for parity with the old commit-on-finish
    /// flow in case a future change wants atomic capture.
    func finishCurrentBlock(output: String, exitCode: Int) {
        guard let cur = blocks.last, cur.isRunning else { return }
        cur.output = output
        cur.exitCode = exitCode
        cur.isRunning = false
        objectWillChange.send()
    }

    func remove(_ block: Block) {
        blocks.removeAll { $0.id == block.id }
    }

    func clearAll() {
        blocks.removeAll()
    }

    func clear() { clearAll() }

    /// "─── session resumed ───" divider after a fullTUI exit.
    func appendMarker(_ text: String) {
        blocks.append(Block(command: text, output: "", isRunning: false))
    }
}
