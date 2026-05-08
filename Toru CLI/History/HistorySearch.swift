import Foundation

struct HistorySearch {
    let db: HistoryDatabase

    func suggest(prefix: String) -> String? {
        db.mostRecentMatching(prefix: prefix)
    }

    func search(_ query: String) -> [CommandHistory] {
        db.search(query: query, limit: 8)
    }
}
