import Foundation

/// What one sync did.
nonisolated struct SyncReport: Equatable, Sendable {
    /// Items the server took.
    var pushed = 0
    /// Items the server refused as malformed. They wait until they change.
    var refused = 0
    /// Whether the server refused an item because a newer build wrote it last.
    var needsUpdate = false
    var pulled = PullOutcome()
}

/// One sync: push what changed, then pull what's new. The Sync docs page has the rules.
///
/// It has no state of its own. Everything it needs to pick up where a failed run stopped is in the
/// database: an item counts as pushed only once the server has answered for it, and the cursor moves only
/// when a whole pull has been written.
nonisolated struct SyncRun: Sendable {
    /// The schema this build writes. Raise it with every phone migration that adds something synced, so
    /// the server can stop older builds from overwriting items that use it.
    static let schema = 1

    let database: AppDatabase
    let api: any SyncAPI
    let token: String
    /// How many items go in one push. The server takes at most 100.
    var batchSize = 100

    func run() async throws -> SyncReport {
        var report = SyncReport()
        try forgetRefusalsFromAnOlderBuild()

        // Push. The items come in the order they depend on each other, and are sent in that order.
        let pending = try database.pendingSyncItems()
        for start in stride(from: 0, to: pending.count, by: batchSize) {
            let batch = Array(pending[start..<min(start + batchSize, pending.count)])
            let results = try await api.push(schema: Self.schema, items: batch.map(\.item), token: token)
            guard results.count == batch.count else { throw SyncAPIError.server(200) }
            var agreed: [LocalSyncItem] = []
            for (local, result) in zip(batch, results) {
                switch result.status {
                case .saved:
                    report.pushed += 1
                    agreed.append(local)
                case .older:
                    // The server's copy is the one to keep. The pull below brings it.
                    agreed.append(local)
                case .tooOld:
                    report.needsUpdate = true
                    try database.markFailed(local, error: result.message ?? "Update the app to change this.")
                case .invalid:
                    report.refused += 1
                    try database.markFailed(local, error: result.message ?? "The server could not save this item.")
                }
            }
            try database.markSynced(agreed)
        }

        // Pull every page first, then write them in one go, so a pull cut short writes nothing.
        let start = try database.syncCursor()
        var cursor = start
        var items: [SyncItem] = []
        while true {
            let page = try await api.pull(cursor: cursor, token: token)
            items += page.items
            cursor = page.cursor
            if !page.more { break }
        }
        if cursor != start || !items.isEmpty {
            report.pulled = try database.applyPulled(items, cursor: cursor)
        }
        return report
    }

    /// After an update, the items the server refused from the old build get another go.
    private func forgetRefusalsFromAnOlderBuild() throws {
        let current = String(Self.schema)
        guard try database.syncState("schema") != current else { return }
        try database.clearSyncFailures()
        try database.setSyncState("schema", current)
    }
}
