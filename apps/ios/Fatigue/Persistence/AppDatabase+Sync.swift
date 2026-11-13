import Foundation
import GRDB

/// One column's value as it travels to and from the API. SQLite's storage classes, minus blobs.
nonisolated enum SyncValue: Sendable, Equatable, Codable {
    case text(String)
    case integer(Int64)
    case real(Double)
    case null

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .real(value)
        } else {
            self = .text(try container.decode(String.self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .real(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    init(_ value: DatabaseValue) {
        switch value.storage {
        case .null, .blob: self = .null
        case .int64(let value): self = .integer(value)
        case .double(let value): self = .real(value)
        case .string(let value): self = .text(value)
        }
    }

    var databaseValue: DatabaseValue {
        switch self {
        case .text(let value): value.databaseValue
        case .integer(let value): value.databaseValue
        case .real(let value): value.databaseValue
        case .null: .null
        }
    }

    var int64: Int64? {
        switch self {
        case .integer(let value): value
        case .real(let value): Int64(value)
        case .text(let value): Int64(value)
        case .null: nil
        }
    }

    var string: String? {
        if case .text(let value) = self { return value }
        return nil
    }
}

/// A row of one synced table, as the API sends and receives it.
nonisolated struct SyncRow: Sendable, Equatable, Codable {
    var table: String
    var row: [String: SyncValue]

    var id: String? { row["id"]?.string }
    var updatedAt: Int64 { row["updated_at"]?.int64 ?? 0 }
}

/// What the server said about one pushed row.
nonisolated struct SyncAck: Sendable, Equatable, Codable {
    var table: String
    var id: String
    var updated_at: Int64
}

nonisolated struct SyncRejection: Sendable, Equatable, Codable {
    var table: String
    var id: String?
    var reason: String
}

/// The outbox, the cursor and applying what the server sends. The rules are the ones on the tech stack page:
/// the latest `updated_at` wins, deletes are `deleted_at` markers, and a row the phone changed is never
/// overwritten by an older copy from the server.
nonisolated extension AppDatabase {
    private static let applyingKey = "applying"
    private static let cursorKey = "cursor"
    private static let accountKey = "account_id"
    private static let lastSyncKey = "last_sync_at"

    // MARK: Outbox

    /// How many rows are waiting to be pushed.
    func pendingCount() throws -> Int {
        try writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox") ?? 0 }
    }

    /// The next rows to push, parents before children. Outbox entries whose row is gone are dropped.
    func pendingChanges(limit: Int = 500) throws -> [SyncRow] {
        try writer.write { db in
            let entries = try Row.fetchAll(db, sql: "SELECT table_name, row_id FROM sync_outbox ORDER BY rowid")
                .map { ($0["table_name"] as String, $0["row_id"] as String) }
                .sorted { SyncTable.order(of: $0.0) < SyncTable.order(of: $1.0) }
            var changes: [SyncRow] = []
            for (table, id) in entries where changes.count < limit {
                guard SyncTable.named(table) != nil,
                      let row = try Row.fetchOne(db, sql: "SELECT * FROM \(table) WHERE id = ?", arguments: [id]) else {
                    try db.execute(sql: "DELETE FROM sync_outbox WHERE table_name = ? AND row_id = ?", arguments: [table, id])
                    continue
                }
                changes.append(SyncRow(table: table, row: Dictionary(uniqueKeysWithValues: row.columnNames.map { ($0, SyncValue(row[$0])) })))
            }
            return changes
        }
    }

    /// Clears outbox entries the server accepted, unless the row changed again while the push was in flight.
    /// When the server clamped a row's `updated_at` (a phone clock running ahead), the local copy takes the
    /// clamped value so both sides agree on it. Rejected rows leave the outbox too: pushing them again
    /// wouldn't change the answer.
    func acknowledge(_ sent: [SyncRow], accepted: [SyncAck], rejected: [SyncRejection]) throws {
        try writer.write { db in
            let sentAt = Dictionary(sent.compactMap { row in row.id.map { (Key(row.table, $0), row.updatedAt) } }, uniquingKeysWith: { a, _ in a })
            for ack in accepted {
                guard let sentValue = sentAt[Key(ack.table, ack.id)] else { continue }
                let current = try Int64.fetchOne(db, sql: "SELECT updated_at FROM \(ack.table) WHERE id = ?", arguments: [ack.id])
                guard current == sentValue else { continue }
                if ack.updated_at != sentValue {
                    try Self.suppressingOutbox(db) {
                        try db.execute(sql: "UPDATE \(ack.table) SET updated_at = ? WHERE id = ?", arguments: [ack.updated_at, ack.id])
                    }
                }
                try db.execute(sql: "DELETE FROM sync_outbox WHERE table_name = ? AND row_id = ?", arguments: [ack.table, ack.id])
            }
            for rejection in rejected {
                guard let id = rejection.id else { continue }
                try db.execute(sql: "DELETE FROM sync_outbox WHERE table_name = ? AND row_id = ?", arguments: [rejection.table, id])
            }
        }
    }

    private struct Key: Hashable {
        let table: String, id: String
        init(_ table: String, _ id: String) { self.table = table; self.id = id }
    }

    /// Runs `body` without the triggers adding to the outbox, for writes that came from the server.
    private static func suppressingOutbox(_ db: Database, _ body: () throws -> Void) throws {
        try db.execute(sql: "INSERT OR IGNORE INTO sync_state (key, value) VALUES (?, '1')", arguments: [applyingKey])
        defer { try? db.execute(sql: "DELETE FROM sync_state WHERE key = ?", arguments: [applyingKey]) }
        try body()
    }

    // MARK: Applying what was pulled

    /// Applies pulled rows in one transaction. A row the phone changed and hasn't pushed keeps its local copy
    /// when that copy is newer; otherwise the server's row lands and the outbox entry goes, since the server
    /// already has something at least as new. Ties go to the server so both phones settle on the same copy.
    /// Returns how many rows changed locally.
    @discardableResult
    func apply(_ rows: [SyncRow]) throws -> Int {
        try writer.write { db in
            var applied = 0
            try Self.suppressingOutbox(db) {
                try db.execute(sql: "PRAGMA defer_foreign_keys = ON")
                let known = try Dictionary(uniqueKeysWithValues: SyncTable.all.map { ($0.name, Set(try db.columns(in: $0.name).map(\.name))) })
                for incoming in rows.sorted(by: { SyncTable.order(of: $0.table) < SyncTable.order(of: $1.table) }) {
                    guard let id = incoming.id, let columns = known[incoming.table] else { continue }
                    let values = incoming.row.filter { columns.contains($0.key) }
                    let names = values.keys.sorted()
                    let arguments = StatementArguments(names.map { values[$0]!.databaseValue })

                    if let local = try Row.fetchOne(db, sql: "SELECT updated_at FROM \(incoming.table) WHERE id = ?", arguments: [id]) {
                        let localUpdatedAt: Int64 = local["updated_at"]
                        let dirty = try Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM sync_outbox WHERE table_name = ? AND row_id = ?)",
                                                      arguments: [incoming.table, id]) ?? false
                        if dirty && localUpdatedAt > incoming.updatedAt { continue }
                        try db.execute(sql: "UPDATE \(incoming.table) SET \(names.map { "\($0) = ?" }.joined(separator: ", ")) WHERE id = ?",
                                       arguments: arguments + [id])
                    } else {
                        try db.execute(sql: "INSERT OR REPLACE INTO \(incoming.table) (\(names.joined(separator: ", "))) VALUES (\(names.map { _ in "?" }.joined(separator: ", ")))",
                                       arguments: arguments)
                    }
                    try db.execute(sql: "DELETE FROM sync_outbox WHERE table_name = ? AND row_id = ?", arguments: [incoming.table, id])
                    applied += 1
                }
            }
            return applied
        }
    }

    // MARK: Cursor and account

    func cursor() throws -> Int64 {
        try writer.read { db in try Self.state(Self.cursorKey, in: db).flatMap(Int64.init) ?? 0 }
    }

    func setCursor(_ cursor: Int64) throws {
        try writer.write { db in try Self.setState(Self.cursorKey, String(cursor), in: db) }
    }

    func lastSyncedAt() throws -> Date? {
        try writer.read { db in try Self.state(Self.lastSyncKey, in: db).flatMap(Double.init).map(Date.init(timeIntervalSince1970:)) }
    }

    func setLastSyncedAt(_ date: Date) throws {
        try writer.write { db in try Self.setState(Self.lastSyncKey, String(date.timeIntervalSince1970), in: db) }
    }

    /// Which account the local data belongs to, so signing into another account doesn't merge two people's history.
    func syncAccountId() throws -> String? {
        try writer.read { db in try Self.state(Self.accountKey, in: db) }
    }

    func setSyncAccountId(_ id: String?) throws {
        try writer.write { db in try Self.setState(Self.accountKey, id, in: db) }
    }

    /// Removes every synced row along with the outbox and cursor, for switching accounts, deleting the
    /// account, or starting over from the server's copy.
    func wipeSyncedData() throws {
        try writer.write { db in
            try Self.suppressingOutbox(db) {
                for table in SyncTable.all.reversed() {
                    try db.execute(sql: "DELETE FROM \(table.name)")
                }
            }
            try db.execute(sql: "DELETE FROM sync_outbox")
            try db.execute(sql: "DELETE FROM sync_state")
        }
    }

    private static func state(_ key: String, in db: Database) throws -> String? {
        try String.fetchOne(db, sql: "SELECT value FROM sync_state WHERE key = ?", arguments: [key])
    }

    private static func setState(_ key: String, _ value: String?, in db: Database) throws {
        if let value {
            try db.execute(sql: "INSERT OR REPLACE INTO sync_state (key, value) VALUES (?, ?)", arguments: [key, value])
        } else {
            try db.execute(sql: "DELETE FROM sync_state WHERE key = ?", arguments: [key])
        }
    }
}
