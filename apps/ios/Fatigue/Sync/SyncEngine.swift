import Foundation

/// One round of sync: push what's in the outbox, then pull what changed on the server since last time.
///
/// Push goes first so the server has this phone's edits before deciding which copy of a row is newer;
/// the pull then brings back whatever won. Both loop: the outbox in batches, the pull page by page
/// while the server says there's more. The cursor moves after each page lands, so a round cut short by
/// a lost connection picks up where it left off.
nonisolated actor SyncEngine {
    static let batchSize = 500

    private let database: AppDatabase
    private let api: any SyncAPI

    init(database: AppDatabase, api: any SyncAPI) {
        self.database = database
        self.api = api
    }

    /// Runs one round. Returns whether the pull changed any local rows, so the app knows to reload.
    @discardableResult
    func sync(token: String) async throws -> Bool {
        try await push(token: token)
        return try await pull(token: token)
    }

    private func push(token: String) async throws {
        while true {
            let changes = try database.pendingChanges(limit: Self.batchSize)
            if changes.isEmpty { return }
            let response = try await api.push(changes, token: token)
            try database.acknowledge(changes, accepted: response.accepted, rejected: response.rejected)
            // A row edited mid-push stays in the outbox; it goes next round rather than looping here.
            if response.accepted.count + response.rejected.count < changes.count { return }
            if changes.count < Self.batchSize { return }
        }
    }

    private func pull(token: String) async throws -> Bool {
        var changed = false
        var cursor = try database.cursor()
        while true {
            let page = try await api.pull(since: cursor, limit: Self.batchSize, token: token)
            let applied = try database.apply(page.rows.map { SyncRow(table: $0.table, row: $0.row) })
            changed = changed || applied > 0
            if page.next != cursor {
                cursor = page.next
                try database.setCursor(cursor)
            }
            if !page.hasMore { break }
        }
        try database.setLastSyncedAt(.now)
        return changed
    }
}
