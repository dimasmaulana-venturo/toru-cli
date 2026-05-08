import Foundation
import SwiftUI

/// One command + its attributed output. Output is an `AttributedString`
/// so per-run color attributes from the ANSI renderer are preserved when
/// SwiftUI's `Text` renders it.
@MainActor
final class Block: Identifiable, ObservableObject {
    let id = UUID()
    let command: String
    let startedAt = Date()

    @Published var output: AttributedString = AttributedString()
    @Published var isRunning: Bool = true
    @Published var exitCode: Int? = nil

    private var notifyScheduled = false

    init(command: String, output: AttributedString = AttributedString(), isRunning: Bool = true) {
        self.command = command
        self.output = output
        self.isRunning = isRunning
    }

    func append(_ chunk: AttributedString) {
        guard !chunk.characters.isEmpty else { return }
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

    @Published private(set) var streamTick: Int = 0
    private var streamTickScheduled = false

    func startBlock(command: String) {
        blocks.append(Block(command: command))
    }

    /// Live-append a styled chunk into the most recent running block.
    func appendToCurrent(_ chunk: AttributedString) {
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

    func markCurrentDone(exitCode: Int? = nil) {
        guard let cur = blocks.last, cur.isRunning else { return }
        cur.markDone(exitCode: exitCode)
        objectWillChange.send()
    }

    func remove(_ block: Block) {
        blocks.removeAll { $0.id == block.id }
    }

    func clearAll() {
        blocks.removeAll()
    }

    func clear() { clearAll() }

    /// Marker block ("─── session resumed ───" after fullTUI exit).
    /// Stored as plain attributed string with no styling.
    func appendMarker(_ text: String) {
        var styled = AttributedString(text)
        styled.foregroundColor = .secondary
        let m = Block(command: text, output: AttributedString(), isRunning: false)
        blocks.append(m)
        _ = styled
    }
}
