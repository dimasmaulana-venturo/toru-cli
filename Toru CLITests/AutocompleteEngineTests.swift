import XCTest
@testable import Toru_CLI

private final class StubHistory: HistorySuggesting {
    var entries: [String] = []
    func mostRecentMatching(prefix: String) -> String? {
        entries.reversed().first { $0.hasPrefix(prefix) }
    }
}

final class AutocompleteEngineTests: XCTestCase {

    func testNoSuggestionUnderMinLength() {
        let h = StubHistory(); h.entries = ["bun build"]
        let e = AutocompleteEngine(history: h)
        XCTAssertNil(e.suggest(for: "b"))
    }

    func testPrefixMatchReturnsSuffix() {
        let h = StubHistory(); h.entries = ["bun build"]
        let e = AutocompleteEngine(history: h)
        XCTAssertEqual(e.suggest(for: "bun"), " build")
    }

    func testSuppressedAfterBackspace() {
        let h = StubHistory(); h.entries = ["bun build"]
        let e = AutocompleteEngine(history: h)
        e.onBackspace()
        XCTAssertNil(e.suggest(for: "bun"))
        e.onCharInput()
        XCTAssertEqual(e.suggest(for: "bun"), " build")
    }

    func testNoSuggestionWhenInputEqualsHistory() {
        let h = StubHistory(); h.entries = ["bun"]
        let e = AutocompleteEngine(history: h)
        XCTAssertNil(e.suggest(for: "bun"))
    }

    func testNoSuggestionWhenNoMatch() {
        let h = StubHistory(); h.entries = ["git status"]
        let e = AutocompleteEngine(history: h)
        XCTAssertNil(e.suggest(for: "bun"))
    }
}
