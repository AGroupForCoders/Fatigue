import Foundation
import GRDB
import Testing
@testable import Fatigue

/// The phone's half of sync: the outbox, the acknowledgement rule, applying pulled rows with
/// last-writer-wins, and the engine's push-then-pull round. Two in-memory databases stand in for
/// two phones. The server's half is tested in apps/api.
@MainActor
struct SyncTests {
    private func sample() -> StoredWorkout { FinishedWorkout.samples()[0].stored }

    private func outbox(_ database: AppDatabase) throws -> [(table: String, id: String)] {
        try database.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT table_name, row_id FROM sync_outbox ORDER BY table_name, row_id")
                .map { ($0["table_name"] as String, $0["row_id"] as String) }
        }
    }

    private func updatedAt(_ database: AppDatabase, _ table: String, _ id: String) throws -> Int64? {
        try database.writer.read { db in try Int64.fetchOne(db, sql: "SELECT updated_at FROM \(table) WHERE id = ?", arguments: [id]) }
    }

    private func setUpdatedAt(_ database: AppDatabase, _ table: String, _ id: String, to value: Int64) throws {
        try database.writer.write { db in try db.execute(sql: "UPDATE \(table) SET updated_at = ? WHERE id = ?", arguments: [value, id]) }
    }

    /// Acknowledges every pending row as the server would when it's the only writer.
    private func pushEverything(_ database: AppDatabase) throws {
        let sent = try database.pendingChanges()
        try database.acknowledge(sent, accepted: sent.map { SyncAck(table: $0.table, id: $0.id!, updated_at: $0.updatedAt) }, rejected: [])
    }

    // MARK: Outbox

    @Test func savingPutsEveryRowInTheOutboxParentsFirst() throws {
        let database = try AppDatabase.inMemory()
        let workout = sample()
        try database.save(workout)

        let pending = try database.pendingChanges()
        let tables = pending.map(\.table)
        #expect(tables.contains("workout"))
        #expect(tables.contains("workout_set"))
        #expect(try #require(tables.firstIndex(of: "exercise")) < try #require(tables.firstIndex(of: "workout_exercise")))
        #expect(try #require(tables.firstIndex(of: "workout_exercise")) < try #require(tables.firstIndex(of: "workout_set")))
        #expect(pending.contains { $0.table == "workout" && $0.id == workout.id })
        #expect(pending.allSatisfy { $0.row["updated_at"] != nil && $0.row["deleted_at"] != nil })
    }

    @Test func savingTheSameThingAgainLeavesTheOutboxEmpty() throws {
        let database = try AppDatabase.inMemory()
        let workout = sample()
        try database.save(workout)
        try pushEverything(database)
        #expect(try outbox(database).isEmpty)

        try database.save(workout)
        #expect(try outbox(database).isEmpty)

        var renamed = workout
        renamed.title = "Different"
        try database.save(renamed)
        #expect(try outbox(database).map(\.id) == [workout.id])
    }

    @Test func everySaveMovesUpdatedAtForward() throws {
        let database = try AppDatabase.inMemory()
        var workout = sample()
        try database.save(workout)
        let first = try #require(try updatedAt(database, "workout", workout.id))
        workout.title = "Again"
        try database.save(workout)
        let second = try #require(try updatedAt(database, "workout", workout.id))
        #expect(second > first)
    }

    @Test func deletingAWorkoutLeavesAMarkerThatSyncs() throws {
        let database = try AppDatabase.inMemory()
        let workout = sample()
        try database.save(workout)
        try pushEverything(database)
        try database.deleteWorkout(id: workout.id)

        #expect(try database.workouts().isEmpty)
        let pending = try database.pendingChanges()
        let marker = try #require(pending.first { $0.table == "workout" && $0.id == workout.id })
        #expect(marker.row["deleted_at"] != .null)
        // Its sets go with it, so another phone can read any table on its own.
        #expect(pending.contains { $0.table == "workout_set" && $0.row["deleted_at"] != .null })
    }

    // MARK: Acknowledging a push

    @Test func anAcknowledgedRowLeavesTheOutboxUnlessItChangedMeanwhile() throws {
        let database = try AppDatabase.inMemory()
        var workout = sample()
        try database.save(workout)
        let sent = try database.pendingChanges()
        let sentWorkout = try #require(sent.first { $0.table == "workout" })

        // Edited while the push was in flight.
        workout.title = "Edited mid-push"
        try database.save(workout)

        try database.acknowledge(sent, accepted: sent.map { SyncAck(table: $0.table, id: $0.id!, updated_at: $0.updatedAt) }, rejected: [])
        #expect(try outbox(database).map(\.id) == [workout.id])
        #expect(try updatedAt(database, "workout", workout.id) != sentWorkout.updatedAt)
    }

    @Test func aClampedUpdatedAtIsTakenFromTheServer() throws {
        let database = try AppDatabase.inMemory()
        let workout = sample()
        try database.save(workout)
        let sent = try database.pendingChanges()
        let clamped = try #require(sent.first { $0.table == "workout" }).updatedAt - 10_000
        try database.acknowledge(sent, accepted: [SyncAck(table: "workout", id: workout.id, updated_at: clamped)], rejected: [])

        #expect(try updatedAt(database, "workout", workout.id) == clamped)
        #expect(!(try outbox(database).contains { $0.table == "workout" }))
    }

    @Test func aRejectedRowLeavesTheOutbox() throws {
        let database = try AppDatabase.inMemory()
        let workout = sample()
        try database.save(workout)
        let sent = try database.pendingChanges()
        try database.acknowledge(sent, accepted: [], rejected: [SyncRejection(table: "workout", id: workout.id, reason: "This row belongs to another account.")])
        #expect(!(try outbox(database).contains { $0.table == "workout" }))
        #expect(try outbox(database).contains { $0.table == "workout_set" })
    }

    // MARK: Applying a pull

    @Test func aWorkoutFinishedOnOnePhoneShowsOnAnother() throws {
        let a = try AppDatabase.inMemory()
        let b = try AppDatabase.inMemory()
        let workout = sample()
        try a.save(workout)

        try b.apply(try a.pendingChanges())
        let onB = try #require(try b.workouts().first)
        #expect(onB.id == workout.id)
        #expect(onB.exercises.map(\.name) == workout.exercises.map(\.name))
        #expect(onB.exercises[0].sets.map(\.weightKg) == workout.exercises[0].sets.map(\.weightKg))
        #expect(try outbox(b).isEmpty, "rows that came from the server aren't pushed back")
    }

    @Test func theLaterEditWinsOnBothPhones() throws {
        let a = try AppDatabase.inMemory()
        let b = try AppDatabase.inMemory()
        var workout = sample()
        try a.save(workout)
        try b.apply(try rows(of: a))
        try pushEverything(a)

        workout.title = "A's title"
        try a.save(workout)
        try setUpdatedAt(a, "workout", workout.id, to: 2_000)
        workout.title = "B's title"
        try b.save(workout)
        try setUpdatedAt(b, "workout", workout.id, to: 1_000)

        // A is dirty and newer, so B's older copy doesn't land there.
        try a.apply(try b.pendingChanges().filter { $0.table == "workout" })
        #expect(try a.workouts().first?.title == "A's title")
        #expect(try outbox(a).contains { $0.table == "workout" })

        // B is dirty but older, so A's copy lands and B stops trying to push its own.
        try b.apply(try a.pendingChanges().filter { $0.table == "workout" })
        #expect(try b.workouts().first?.title == "A's title")
        #expect(!(try outbox(b).contains { $0.table == "workout" }))
    }

    @Test func aTieGoesToTheServer() throws {
        let a = try AppDatabase.inMemory()
        let b = try AppDatabase.inMemory()
        var workout = sample()
        try a.save(workout)
        try b.apply(try rows(of: a))

        workout.title = "A's title"
        try a.save(workout)
        try setUpdatedAt(a, "workout", workout.id, to: 5_000)
        workout.title = "B's title"
        try b.save(workout)
        try setUpdatedAt(b, "workout", workout.id, to: 5_000)

        try b.apply(try a.pendingChanges().filter { $0.table == "workout" })
        #expect(try b.workouts().first?.title == "A's title")
    }

    @Test func aDeleteMarkerHidesTheWorkoutOnTheOtherPhone() throws {
        let a = try AppDatabase.inMemory()
        let b = try AppDatabase.inMemory()
        let workout = sample()
        try a.save(workout)
        try b.apply(try rows(of: a))
        try pushEverything(a)

        try a.deleteWorkout(id: workout.id)
        try b.apply(try a.pendingChanges())
        #expect(try b.workouts().isEmpty)
    }

    @Test func wipingClearsEverythingSynced() throws {
        let database = try AppDatabase.inMemory()
        try database.save(sample())
        try database.setCursor(42)
        try database.wipeSyncedData()
        #expect(try database.workouts().isEmpty)
        #expect(try database.pendingCount() == 0)
        #expect(try database.cursor() == 0)
    }

    private func rows(of database: AppDatabase) throws -> [SyncRow] {
        try database.pendingChanges()
    }

    // MARK: Deterministic ids

    @Test func derivedIdsAreStableAndLookLikeUUIDs() {
        let id = SyncID.exercise(named: "Belt Squat")
        #expect(id == SyncID.exercise(named: "Belt Squat"))
        #expect(id != SyncID.exercise(named: "Belt squat"))
        #expect(UUID(uuidString: id) != nil)
        #expect(id[id.index(id.startIndex, offsetBy: 14)] == "5")
        #expect(SyncID.exerciseBrand(exerciseId: id, brand: nil) != SyncID.exerciseBrand(exerciseId: id, brand: "Technogym"))
    }

    @Test func twoPhonesAddingTheSameExerciseAgreeOnItsId() throws {
        let a = try AppDatabase.inMemory()
        let b = try AppDatabase.inMemory()
        let library = StoredLibrary(exercises: [StoredExerciseInfo(name: "Belt Squat", equipment: "machine", isBuiltin: false, muscles: [])], setups: [])
        try a.save(library)
        try b.save(library)
        let idOnA = try rows(of: a).first { $0.table == "exercise" }?.id
        let idOnB = try rows(of: b).first { $0.table == "exercise" }?.id
        #expect(idOnA != nil)
        #expect(idOnA == idOnB)
    }

    // MARK: The engine

    @Test func aRoundPushesThenPullsAndKeepsTheCursor() async throws {
        let server = FakeServer()
        let a = try AppDatabase.inMemory()
        let b = try AppDatabase.inMemory()
        let workout = sample()
        try a.save(workout)

        try await SyncEngine(database: a, api: server).sync(token: "a")
        #expect(try a.pendingCount() == 0)
        #expect(try a.cursor() > 0)
        #expect(await server.pushes == 1)

        let changed = try await SyncEngine(database: b, api: server).sync(token: "b")
        #expect(changed)
        #expect(try b.workouts().first?.id == workout.id)
        #expect(try b.cursor() == a.cursor())

        // Nothing new: the next round changes nothing and the cursor stays.
        let again = try await SyncEngine(database: b, api: server).sync(token: "b")
        #expect(!again)
    }

    @Test func pullingLoopsWhileTheServerHasMore() async throws {
        let server = FakeServer(pageSize: 3)
        let a = try AppDatabase.inMemory()
        let b = try AppDatabase.inMemory()
        try a.save(sample())
        try await SyncEngine(database: a, api: server).sync(token: "a")

        try await SyncEngine(database: b, api: server).sync(token: "b")
        #expect(await server.pulls > 2)
        #expect(try b.workouts().count == 1)
        #expect(try b.cursor() == a.cursor())
    }

    @Test func anOutdatedAppIsToldToUpdate() async throws {
        let server = FakeServer(outdated: true)
        let database = try AppDatabase.inMemory()
        try database.save(sample())
        let store = SyncStore(database: database, api: server, token: { "token" }, accountId: { "user" })

        await store.resetAndRedownload()
        #expect(store.status == .outdated)
        #expect(store.statusText == "Update the app to sync")
    }

    @Test func aResetDropsLocalChangesAndReportsOffline() async throws {
        let server = FakeServer(offline: true)
        let database = try AppDatabase.inMemory()
        let store = SyncStore(database: database, api: server, token: { "token" }, accountId: { "user" })
        try database.save(sample())
        #expect(try database.pendingCount() > 0)

        await store.resetAndRedownload()
        #expect(store.status == .offline)
        #expect(store.statusText == "Offline")
        #expect(try database.workouts().isEmpty)
        #expect(store.pendingCount == 0)
    }
}

/// A server that keeps rows in memory and hands out sequence numbers like the real one.
private actor FakeServer: SyncAPI {
    private var rows: [String: (seq: Int64, row: SyncRow)] = [:]
    private var seq: Int64 = 0
    private(set) var pushes = 0
    private(set) var pulls = 0
    private let pageSize: Int
    private let outdated: Bool
    private let offline: Bool

    init(pageSize: Int = 500, outdated: Bool = false, offline: Bool = false) {
        self.pageSize = pageSize
        self.outdated = outdated
        self.offline = offline
    }

    private func check() throws {
        if offline { throw SyncError.offline }
        if outdated { throw SyncError.outdated }
    }

    func push(_ changes: [SyncRow], token: String) async throws -> SyncPushResponse {
        try check()
        pushes += 1
        var accepted: [SyncAck] = []
        for change in changes {
            guard let id = change.id else { continue }
            let key = "\(change.table)/\(id)"
            if let existing = rows[key], existing.row.updatedAt >= change.updatedAt {
                accepted.append(SyncAck(table: change.table, id: id, updated_at: change.updatedAt))
                continue
            }
            seq += 1
            rows[key] = (seq, change)
            accepted.append(SyncAck(table: change.table, id: id, updated_at: change.updatedAt))
        }
        return SyncPushResponse(accepted: accepted, rejected: [])
    }

    func pull(since: Int64, limit: Int, token: String) async throws -> SyncPullResponse {
        try check()
        pulls += 1
        let all = rows.values.filter { $0.seq > since }.sorted { $0.seq < $1.seq }
        let page = all.prefix(min(limit, pageSize))
        return SyncPullResponse(
            rows: page.map { SyncPullResponse.Entry(table: $0.row.table, seq: $0.seq, row: $0.row.row) },
            next: page.last?.seq ?? since,
            hasMore: all.count > page.count
        )
    }
}
