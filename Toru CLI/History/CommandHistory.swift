import Foundation
import GRDB

struct CommandHistory: Codable, FetchableRecord, MutablePersistableRecord, Identifiable {
    var id: Int64?
    var command: String
    var rawInput: String
    var directory: String
    var exitCode: Int
    var executedAt: Date
    var sessionId: String

    static let databaseTableName = "commandHistory"

    enum Columns {
        static let id = Column("id")
        static let command = Column("command")
        static let rawInput = Column("rawInput")
        static let directory = Column("directory")
        static let exitCode = Column("exitCode")
        static let executedAt = Column("executedAt")
        static let sessionId = Column("sessionId")
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
