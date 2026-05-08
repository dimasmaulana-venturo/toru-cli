import Foundation

protocol HistorySuggesting {
    func mostRecentMatching(prefix: String) -> String?
}

extension HistoryDatabase: HistorySuggesting {}

final class AutocompleteEngine {
    private let history: HistorySuggesting
    private(set) var suppressed: Bool = false
    var minPrefixLength: Int = 2

    init(history: HistorySuggesting = HistoryDatabase.shared) {
        self.history = history
    }

    /// Returns suffix to render as ghost text, or nil.
    func suggest(for input: String) -> String? {
        guard !suppressed else { return nil }
        guard input.count >= minPrefixLength else { return nil }
        guard let match = history.mostRecentMatching(prefix: input) else { return nil }
        guard match.count > input.count else { return nil }
        return String(match.dropFirst(input.count))
    }

    func onBackspace() { suppressed = true }
    func onCharInput() { suppressed = false }
    func reset()       { suppressed = false }
}
