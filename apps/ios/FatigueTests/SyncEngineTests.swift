import Foundation
import Testing
@testable import Fatigue

/// A server in memory that follows the real one's rules: the later `updatedAt` wins, every saved item
/// takes the next version, and a pull returns what changed since the cursor, a page at a time.
nonisolated final class FakeSyncServer: SyncAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String: (item: SyncItem, version: Int64, schema: Int)] = [:]
    private var version: Int64 = 0

    /// How many items a pull returns at once.
    var pageSize = 100
    /// Thrown by the next calls, one per call, before anything else happens.
    var failures: [SyncAPIError] = []
    /// Thrown by a pull that asks for a later page, to stand in for a pull cut short. Cleared once thrown.
    var failOnLaterPage: SyncAPIError?
    /// Items the server refuses, by key, and how.
    var refusals: [String: PushResult.Status] = [:]
    /// Every item that was pushed, in order, by key.
    private(set) var pushedKeys: [String] = []
    private(set) var pushCalls = 0
    private(set) var pullCalls = 0

    var items: [SyncItem] { lock.withLock { stored.values.sorted { $0.version < $1.version }.map(\.item) } }

    func push(schema: Int, items: [SyncItem], token: String) async throws -> [PushResult] {
        try lock.withLock {
            if !failures.isEmpty { throw failures.removeFirst() }
            pushCalls += 1
            return items.map { item in
                pushedKeys.append(item.key)
                if let refusal = refusals[item.key] { return PushResult(kind: item.kind.rawValue, id: item.id, status: refusal, message: "Refused in the test.") }
                if let existing = stored[item.key], existing.item.updatedAt >= item.updatedAt {
                    return PushResult(kind: item.kind.rawValue, id: item.id, status: .older)
                }
                version += 1
                stored[item.key] = (item, version, schema)
                return PushResult(kind: item.kind.rawValue, id: item.id, status: .saved)
            }
        }
    }

    func pull(cursor: Int64, token: String) async throws -> PullPage {
        try lock.withLock {
            if !failures.isEmpty { throw failures.removeFirst() }
            if cursor > 0, let failure = failOnLaterPage {
                failOnLaterPage = nil
                throw failure
            }
            pullCalls += 1
            let changed = stored.values.filter { $0.version > cursor }.sorted { $0.version < $1.version }
            let page = Array(changed.prefix(pageSize))
            return PullPage(items: page.map(\.item), cursor: page.last?.version ?? cursor, more: changed.count > pageSize)
        }
    }
}

@MainActor
struct SyncEngineTests {
    /// A database with the sample routines and weeks of history, as a debug build starts with.
    private func seeded() throws -> AppDatabase {
        let database = try AppDatabase.inMemory()
        _ = WorkoutStore(database: database)
        return database
    }

    private func engine(_ database: AppDatabase, _ server: FakeSyncServer, batchSize: Int = 100, retryDelays: [Duration] = []) -> SyncEngine {
        SyncEngine(database: database, api: server, token: { "token" }, retryDelays: retryDelays, batchSize: batchSize)
    }

    private func store(_ database: AppDatabase) -> WorkoutStore { WorkoutStore(database: database) }

    /// Waits for something that happens on its own, such as a retry.
    private func eventually(_ condition: () -> Bool) async {
        for _ in 0..<400 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    // MARK: Two phones and one server

    @Test func aWorkoutFinishedOnOnePhoneShowsOnTheOther() async throws {
        let server = FakeSyncServer()
        let (first, second) = (try seeded(), try AppDatabase.inMemory())
        let (mine, theirs) = (engine(first, server), engine(second, server))

        await mine.sync()
        await theirs.sync()

        #expect(mine.status == .idle)
        #expect(mine.waiting == 0)
        #expect(mine.lastSynced != nil)
        #expect(try second.syncItems() == first.syncItems())
        #expect(store(second).history.map(\.id) == store(first).history.map(\.id))

        // A workout finished on the second phone reaches the first.
        let workouts = store(second)
        workouts.start(workouts.routines[0])
        workouts.finish(title: "Finished on the second phone", unticked: .count)
        await theirs.sync()
        await mine.sync()

        #expect(store(first).history.first?.title == "Finished on the second phone")
        #expect(try first.syncItems() == second.syncItems())
    }

    @Test func editingTheSameWorkoutOnTwoPhonesKeepsTheLaterEdit() async throws {
        let server = FakeSyncServer()
        let (first, second) = (try seeded(), try AppDatabase.inMemory())
        let (mine, theirs) = (engine(first, server), engine(second, server))
        await mine.sync()
        await theirs.sync()
        let id = store(first).history[0].id

        // Both edit it offline. The second phone's edit is the later one, and syncs first.
        store(first).rename(id, title: "Earlier, on the first phone", description: "")
        try await Task.sleep(for: .milliseconds(20))
        store(second).rename(id, title: "Later, on the second phone", description: "")
        await theirs.sync()
        await mine.sync()
        await theirs.sync()

        #expect(store(first).history.first { $0.id == id }?.title == "Later, on the second phone")
        #expect(store(second).history.first { $0.id == id }?.title == "Later, on the second phone")
        #expect(mine.waiting == 0)
        #expect(theirs.waiting == 0)
    }

    @Test func aDeleteOnOnePhoneAndALaterEditOnTheOtherBringsItBack() async throws {
        let server = FakeSyncServer()
        let (first, second) = (try seeded(), try AppDatabase.inMemory())
        let (mine, theirs) = (engine(first, server), engine(second, server))
        await mine.sync()
        await theirs.sync()
        let id = store(first).history[0].id

        store(first).deleteFromHistory(id)
        try await Task.sleep(for: .milliseconds(20))
        store(second).rename(id, title: "Edited after the delete", description: "")
        await mine.sync()
        await theirs.sync()
        await mine.sync()

        #expect(store(first).history.first { $0.id == id }?.title == "Edited after the delete")
        #expect(store(second).history.first { $0.id == id }?.title == "Edited after the delete")
    }

    // MARK: Batches and pages

    @Test func aBigPushGoesUpInBatchesAndABigPullComesDownInPages() async throws {
        let server = FakeSyncServer()
        server.pageSize = 7
        let (first, second) = (try seeded(), try AppDatabase.inMemory())
        let total = try first.pendingSyncItems().count
        #expect(total > 20)

        await engine(first, server, batchSize: 10).sync()
        await engine(second, server).sync()

        #expect(server.pushCalls == (total + 9) / 10)
        #expect(server.pullCalls > 3)
        #expect(server.items.count == total)
        #expect(try second.syncItems() == first.syncItems())
    }

    // MARK: Failures

    @Test func nothingIsLostWhileOfflineAndItGoesUpOnceBack() async throws {
        let server = FakeSyncServer()
        let database = try seeded()
        let sync = engine(database, server)
        let total = try database.pendingSyncItems().count

        server.failures = [.offline]
        await sync.sync()
        #expect(sync.status == .offline)
        #expect(server.items.isEmpty)
        #expect(try database.pendingSyncItems().count == total)

        await sync.sync()
        #expect(sync.status == .idle)
        #expect(server.items.count == total)
    }

    @Test func aServerErrorIsTriedAgainOnItsOwn() async throws {
        let server = FakeSyncServer()
        let database = try seeded()
        let sync = engine(database, server, retryDelays: [.milliseconds(20)])
        server.failures = [.server(500), .server(503)]

        await sync.sync()
        #expect(sync.status == .failed)

        await eventually { sync.status == .idle }
        #expect(sync.status == .idle)
        #expect(server.items.count == (try database.syncItems().count))
    }

    @Test func anEndedSessionStopsSyncAndKeepsTheData() async throws {
        let server = FakeSyncServer()
        let database = try seeded()
        let sync = engine(database, server, retryDelays: [.milliseconds(10)])
        var signedOut = 0
        sync.onSignedOut = { signedOut += 1 }
        let total = try database.pendingSyncItems().count
        server.failures = [.signedOut]

        await sync.sync()
        try await Task.sleep(for: .milliseconds(60))

        #expect(sync.status == .signedOut)
        #expect(signedOut == 1)
        // No retry was scheduled, and nothing was dropped.
        #expect(server.pushCalls == 0)
        #expect(try database.pendingSyncItems().count == total)
    }

    @Test func signedOutNeverCallsTheServer() async throws {
        let server = FakeSyncServer()
        let sync = SyncEngine(database: try seeded(), api: server, token: { nil })
        await sync.sync()
        #expect(sync.status == .signedOut)
        #expect(server.pushCalls + server.pullCalls == 0)
    }

    @Test func aPullCutShortWritesNothingAndIsAskedForAgain() async throws {
        let server = FakeSyncServer()
        server.pageSize = 5
        let (first, second) = (try seeded(), try AppDatabase.inMemory())
        await engine(first, server).sync()
        let theirs = engine(second, server)

        server.failOnLaterPage = .offline
        await theirs.sync()
        #expect(theirs.status == .offline)
        #expect(try second.syncItems().isEmpty)
        #expect(try second.syncCursor() == 0)

        await theirs.sync()
        #expect(try second.syncItems() == first.syncItems())
    }

    // MARK: Refused items

    @Test func oneRefusedItemDoesNotHoldUpTheRest() async throws {
        let server = FakeSyncServer()
        let database = try seeded()
        let sync = engine(database, server)
        let refused = try #require(try database.pendingSyncItems().first { $0.item.kind == .workout }).item.key
        let total = try database.pendingSyncItems().count
        server.refusals = [refused: .invalid]

        await sync.sync()

        #expect(sync.status == .idle)
        #expect(sync.refused == 1)
        #expect(sync.waiting == 0)
        #expect(server.items.count == total - 1)

        // It isn't sent again until it changes.
        await sync.sync()
        #expect(server.pushedKeys.filter { $0 == refused }.count == 1)
    }

    @Test func anItemFromANewerBuildAsksForAnUpdate() async throws {
        let server = FakeSyncServer()
        let database = try seeded()
        let sync = engine(database, server)
        let key = try #require(try database.pendingSyncItems().first { $0.item.kind == .workout }).item.key
        server.refusals = [key: .tooOld]

        await sync.sync()

        #expect(sync.needsUpdate)
        #expect(try database.syncFailures().map(\.key) == [key])
    }

    // MARK: Telling the app

    @Test func aPullThatWroteSomethingTellsTheApp() async throws {
        let server = FakeSyncServer()
        let (first, second) = (try seeded(), try AppDatabase.inMemory())
        await engine(first, server).sync()
        let theirs = engine(second, server)
        var pulls: [PullOutcome] = []
        theirs.onPulled = { pulls.append($0) }

        await theirs.sync()
        await theirs.sync()

        // Once: the second sync brought nothing new.
        #expect(pulls.count == 1)
        #expect(pulls[0].applied == server.items.count)
    }

    @Test func askingAgainWhileOneRunsRunsOnceMore() async throws {
        let server = FakeSyncServer()
        let database = try seeded()
        let sync = engine(database, server)

        async let running: Void = sync.sync()
        await sync.sync()
        await running

        #expect(sync.status == .idle)
        #expect(server.items.count == (try database.syncItems().count))
    }
}
