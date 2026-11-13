import Foundation
import Testing
@testable import Fatigue

/// Two phones and the real API in one test, as the Sync docs page asks: two in-memory phone databases
/// sync through the API running on an in-memory Postgres (`pnpm --filter @fatigue/api test:server`).
///
/// Runs only when `FATIGUE_TEST_API` names that server. CI starts it and passes it in with
/// `TEST_RUNNER_FATIGUE_TEST_API=http://localhost:8788`. Locally, start the server and do the same.
private enum TestAPI {
    static let server = ProcessInfo.processInfo.environment["FATIGUE_TEST_API"].flatMap(URL.init(string:))
}

@MainActor
@Suite(.enabled(if: TestAPI.server != nil, "Set FATIGUE_TEST_API to a running test server"), .serialized)
struct SyncTwoPhoneTests {
    private static var server: URL? { TestAPI.server }

    private var auth: LiveAuthAPI { LiveAuthAPI(baseURL: Self.server!) }

    /// A new account on the test server, with its session token.
    private func signUp() async throws -> (account: Account, token: String, password: String) {
        let password = "password-\(UUID().uuidString.prefix(8))"
        let (account, token) = try await auth.signUp(name: "Tester", email: "sync-\(UUID().uuidString.lowercased())@example.test", password: password)
        return (account, token, password)
    }

    /// A phone signed in to `account`. With `seeded`, it starts with the sample routines and weeks of history.
    private func phone(_ account: (account: Account, token: String, password: String), seeded: Bool = false) throws -> (database: AppDatabase, sync: SyncEngine) {
        let database = try AppDatabase.inMemory()
        if seeded { _ = WorkoutStore(database: database) }
        let token = account.token
        let sync = SyncEngine(database: database, account: account.account.id, api: LiveSyncAPI(baseURL: Self.server!), token: { token })
        return (database, sync)
    }

    /// Finished workouts straight from the database, newest first. Not through `WorkoutStore`, which fills an
    /// empty database with sample workouts in debug builds.
    private func history(_ database: AppDatabase) -> [FinishedWorkout] {
        ((try? database.workouts()) ?? []).filter { $0.finishedAt != nil }.map(FinishedWorkout.init(stored:)).sorted { $0.startedAt > $1.startedAt }
    }

    private func edit(_ database: AppDatabase, workout id: UUID, title: String, at time: Int64) async throws {
        try await database.writer.write {
            try $0.execute(sql: "UPDATE workout SET title = ?, updated_at = ? WHERE id = ?", arguments: [title, time, id.uuidString])
        }
    }

    private var now: Int64 { Int64(Date.now.timeIntervalSince1970 * 1000) }

    @Test func aWorkoutFinishedOnOnePhoneShowsOnTheOther() async throws {
        let me = try await signUp()
        let first = try phone(me, seeded: true)
        let second = try phone(me)

        await first.sync.syncNow()
        await second.sync.syncNow()

        #expect(first.sync.status == .idle)
        #expect(second.sync.status == .idle)
        #expect(history(second.database).map(\.id) == history(first.database).map(\.id))
        #expect(history(second.database).map(\.setCount) == history(first.database).map(\.setCount))
        #expect(try second.database.syncItems() == first.database.syncItems())
    }

    @Test func offlineEditsOnBothPhonesKeepTheLaterOne() async throws {
        let me = try await signUp()
        let first = try phone(me, seeded: true)
        let second = try phone(me)
        await first.sync.syncNow()
        await second.sync.syncNow()
        let workout = try #require(history(first.database).first)

        // Both edit while offline, the second phone later.
        try await edit(first.database, workout: workout.id, title: "Edited on the first phone", at: now + 1_000)
        try await edit(second.database, workout: workout.id, title: "Edited on the second phone", at: now + 2_000)

        // The first comes online first, then the second, then the first again.
        await first.sync.syncNow()
        await second.sync.syncNow()
        await first.sync.syncNow()

        for database in [first.database, second.database] {
            #expect(history(database).first { $0.id == workout.id }?.title == "Edited on the second phone")
            #expect(try database.pendingSyncItems().isEmpty)
        }
    }

    @Test func anEditAfterADeleteOnAnotherPhoneBringsTheWorkoutBack() async throws {
        let me = try await signUp()
        let first = try phone(me, seeded: true)
        let second = try phone(me)
        await first.sync.syncNow()
        await second.sync.syncNow()
        let workout = try #require(history(first.database).first)

        WorkoutStore(database: first.database).deleteFromHistory(workout.id)
        await first.sync.syncNow()
        #expect(history(first.database).contains { $0.id == workout.id } == false)

        // The second phone edits it later, without having pulled the delete.
        try await edit(second.database, workout: workout.id, title: "Still wanted", at: now + 60_000)
        await second.sync.syncNow()
        await first.sync.syncNow()

        #expect(history(first.database).first { $0.id == workout.id }?.title == "Still wanted")
    }

    @Test func aDeleteReachesThePhoneThatDidntMakeIt() async throws {
        let me = try await signUp()
        let first = try phone(me, seeded: true)
        let second = try phone(me)
        await first.sync.syncNow()
        await second.sync.syncNow()
        let workout = try #require(history(first.database).first)

        WorkoutStore(database: first.database).deleteFromHistory(workout.id)
        await first.sync.syncNow()
        await second.sync.syncNow()

        #expect(history(second.database).contains { $0.id == workout.id } == false)
    }

    @Test func signingOutAndInAgainBringsEverythingBack() async throws {
        let me = try await signUp()
        let phone = try phone(me, seeded: true)
        await phone.sync.syncNow()
        let before = history(phone.database).map(\.id)

        let waiting = await phone.sync.prepareSignOut()
        #expect(waiting.items == 0)
        phone.sync.wipe()
        #expect(history(phone.database).isEmpty)

        await phone.sync.syncNow()
        #expect(history(phone.database).map(\.id) == before)
    }

    @Test func oneAccountNeverSeesAnothersWorkouts() async throws {
        let me = try await signUp()
        let someoneElse = try await signUp()
        let mine = try phone(me, seeded: true)
        let theirs = try phone(someoneElse)

        await mine.sync.syncNow()
        await theirs.sync.syncNow()

        #expect(history(theirs.database).isEmpty)
        #expect(try theirs.database.syncItems().isEmpty)
    }

    @Test func deletingTheAccountRemovesTheServersCopy() async throws {
        let me = try await signUp()
        let phone = try phone(me, seeded: true)
        await phone.sync.syncNow()

        try await auth.deleteAccount(password: me.password, token: me.token)

        // The old session is gone with the account.
        await phone.sync.syncNow()
        #expect(phone.sync.status == .needsSignIn)
        // And a new account starts empty.
        let fresh = try self.phone(try await signUp())
        await fresh.sync.syncNow()
        #expect(history(fresh.database).isEmpty)
    }
}
