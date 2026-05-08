import XCTest
@testable import Toru_CLI

final class HistoryDatabaseTests: XCTestCase {

    func makeDB() throws -> HistoryDatabase { try HistoryDatabase.inMemory() }

    func testInsertAndFetchRecent() throws {
        let db = try makeDB()
        XCTAssertTrue(db.record(rawInput: "ls", executed: "ls", directory: "/", sessionId: "s1"))
        XCTAssertTrue(db.record(rawInput: "pwd", executed: "pwd", directory: "/", sessionId: "s1"))
        let recent = db.recent(limit: 10)
        XCTAssertEqual(recent.count, 2)
    }

    func testDedupConsecutive() throws {
        let db = try makeDB()
        XCTAssertTrue(db.record(rawInput: "ls", executed: "ls", directory: "/", sessionId: "s1"))
        XCTAssertFalse(db.record(rawInput: "ls", executed: "ls", directory: "/", sessionId: "s1"))
        XCTAssertEqual(db.recent().count, 1)
    }

    func testLeadingSpaceSkipped() throws {
        let db = try makeDB()
        XCTAssertFalse(db.record(rawInput: " ls", executed: "ls", directory: "/", sessionId: "s1"))
        XCTAssertEqual(db.recent().count, 0)
    }

    func testPrefixMatch() throws {
        let db = try makeDB()
        _ = db.record(rawInput: "bun build", executed: "bun build", directory: "/", sessionId: "s1")
        _ = db.record(rawInput: "bun run dev", executed: "bun run dev", directory: "/", sessionId: "s1")
        _ = db.record(rawInput: "git status", executed: "git status", directory: "/", sessionId: "s1")
        XCTAssertEqual(db.mostRecentMatching(prefix: "bun"), "bun run dev")
        XCTAssertEqual(db.mostRecentMatching(prefix: "git"), "git status")
        XCTAssertNil(db.mostRecentMatching(prefix: "zzz"))
    }

    func testSearchSubstring() throws {
        let db = try makeDB()
        _ = db.record(rawInput: "ls -la", executed: "ls -la", directory: "/", sessionId: "s1")
        _ = db.record(rawInput: "git log", executed: "git log", directory: "/", sessionId: "s1")
        let results = db.search(query: "log")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.command, "git log")
    }

    func testClear() throws {
        let db = try makeDB()
        _ = db.record(rawInput: "ls", executed: "ls", directory: "/", sessionId: "s1")
        db.clear()
        XCTAssertEqual(db.recent().count, 0)
    }
}
