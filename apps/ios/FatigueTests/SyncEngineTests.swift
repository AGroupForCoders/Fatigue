import Foundation
import GRDB
import Testing
@testable import Fatigue

/// Stands in for the API's push and pull: keeps the latest copy of each item with a version from a counter,
/// and refuses the older of two edits, as `apps/api/src/modules/sync/sync.service.ts` does.
private final class FakeSyncServer: SyncAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: (item: SyncItem, version: Int64)] = [:]
    private var version: Int64 = 0
    /// Failures to answer with, one per call, before behaving normally.
    var failures: [SyncFailure] = []
    /// Items to answer with a fixed status instead of saving, by key.
    var statuses: [String: PushResult.Status] = [:]
    var pageSize = 100
    private(set) var pushes: [[SyncItem]] = []
    private(set) var pulls: [Int64] = []

    var stored: [SyncItem] { lock.withLock { items.values.map(\.item) } }

    func push(_ batch: [SyncItem], schema: Int, token: String) async throws(SyncFailure) -> [PushResult] {
        try save(batch)
    }

    func pull(after cursor: Int64, token: String) async throws(SyncFailure) -> PullPage {
        try page(after: cursor)
    }

    private func save(_ batch: [SyncItem]) throws(SyncFailure) -> [PushResult] {
        lock.lock()
        defer { lock.unlock() }
        do {
            if !failures.isEmpty { throw failures.removeFirst() }
            pushes.append(batch)
            return batch.map { item in
                if let status = statuses[item.key] { return PushResult(kind: item.kind.rawValue, id: item.id, status: status, message: "No") }
                if let existing = items[item.key], existing.item.updatedAt >= item.updatedAt {
                    return PushResult(kind: item.kind.rawValue, id: item.id, status: .older)
                }
                version += 1
                items[item.key] = (item, version)
                return PushResult(kind: item.kind.rawValue, id: item.id, status: .saved)
            }
        }
    }

    private func page(after cursor: Int64) throws(SyncFailure) -> PullPage {
        lock.lock()
        defer { lock.unlock() }
        do {
            if !failures.isEmpty { throw failures.removeFirst() }
            pulls.append(cursor)
            let newer = items.values.filter { $0.version > cursor }.sorted { $0.version < $1.version }
            let page = Array(newer.prefix(pageSize))
            return PullPage(items: page.map(\.item), cursor: page.last?.version ?? cursor, more: newer.count > pageSize)
        }
    }
}

/// Records the waits the engine asks for instead of waiting.
private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var waits: [Duration] = []
    var asked: [Duration] { lock.withLock { waits } }
    func sleep(_ duration: Duration) async throws {
        lock.withLock { waits.append(duration) }
        // Long enough that a test finishes before a retry fires.
        try await Task.sleep(for: .seconds(3600))
    }
}

@MainActor
struct SyncEngineTests {
    /// A phone with the sample routines and weeks of history, as a debug build starts with.
    private func phone() throws -> AppDatabase {
        let database = try AppDatabase.inMemory()
        _ = WorkoutStore(database: database)
        return database
    }

    private func engine(_ database: AppDatabase, _ server: FakeSyncServer, clock: Clock = Clock(), account: String? = "anton") -> SyncEngine {
        SyncEngine(database: database, account: account, api: server, token: { "token" }, sleep: { try await clock.sleep($0) })
    }

    @Test func aSecondPhoneGetsEverythingTheFirstPushed() async throws {
        let server = FakeSyncServer()
        let first = try phone()
        let second = try AppDatabase.inMemory()

        await engine(first, server).syncNow()
        let pulled = engine(second, server)
        var reloaded = 0
        pulled.onPulled = { _ in reloaded += 1 }
        await pulled.syncNow()

        #expect(try second.syncItems() == first.syncItems())
        #expect(try first.pendingSyncItems().isEmpty)
        #expect(try second.pendingSyncItems().isEmpty)
        #expect(reloaded == 1)
        #expect(WorkoutStore(database: second).history.map(\.id) == WorkoutStore(database: first).history.map(\.id))
    }

    @Test func pushesInPagesAndPullsUntilThereIsNoMore() async throws {
        let server = FakeSyncServer()
        server.pageSize = 3
        let first = try phone()
        let count = try first.pendingSyncItems().count

        await engine(first, server).syncNow()
        #expect(server.pushes.map(\.count).reduce(0, +) == count)
        #expect(server.pushes.allSatisfy { $0.count <= SyncEngine.pageSize })

        let second = try AppDatabase.inMemory()
        await engine(second, server).syncNow()
        #expect(server.pulls.count > 2)
        #expect(try second.syncItems().count == count)
    }

    @Test func aBrandEditedAfterItsWorkoutsStillReachesANewPhone() async throws {
        let server = FakeSyncServer()
        server.pageSize = 5
        let first = try phone()
        let one = engine(first, server)
        await one.syncNow()

        // Editing a brand gives it a later version than the workouts that use it, so a new phone is sent
        // those workouts pages before the brand they point at.
        try await first.writer.write { try $0.execute(sql: "UPDATE exercise_brand SET label = 'City gym' WHERE brand IS NOT NULL") }
        await one.syncNow()
        #expect(server.pushes.last?.contains { $0.kind == .brand } == true)

        let second = try AppDatabase.inMemory()
        await engine(second, server).syncNow()

        #expect(try second.syncItems() == first.syncItems())
        #expect(WorkoutStore(database: second).history.map(\.id) == WorkoutStore(database: first).history.map(\.id))
    }

    @Test func aChangeOnlyPushesWhenSomethingIsWaiting() async throws {
        let server = FakeSyncServer()
        let database = try phone()
        let sync = engine(database, server)
        await sync.syncNow()
        let pushes = server.pushes.count

        await sync.pushNow()
        #expect(server.pushes.count == pushes)
        #expect(server.pulls.count == 1)
    }

    @Test func noConnectionWaitsAndKeepsEverything() async throws {
        let server = FakeSyncServer()
        server.failures = [.offline]
        let database = try phone()
        let sync = engine(database, server)
        await sync.syncNow()
        #expect(sync.status == .offline)
        #expect(try !database.pendingSyncItems().isEmpty)

        await sync.syncNow()
        #expect(sync.status == .idle)
        #expect(try database.pendingSyncItems().isEmpty)
        #expect(sync.lastSynced != nil)
    }

    @Test func aServerErrorTriesAgainOnTheSchedule() async throws {
        let server = FakeSyncServer()
        server.failures = [.server("500"), .server("500")]
        let clock = Clock()
        let sync = engine(try phone(), server, clock: clock)

        await sync.syncNow()
        guard case .retrying = sync.status else { Issue.record("Expected a retry, got \(sync.status)"); return }
        await sync.syncNow()
        await Task.yield()
        #expect(clock.asked.prefix(2) == [.seconds(2), .seconds(8)])

        await sync.syncNow()
        #expect(sync.status == .idle)
    }

    @Test func anExpiredSessionStopsUntilSignIn() async throws {
        let server = FakeSyncServer()
        server.failures = [.unauthorized]
        let database = try phone()
        let sync = engine(database, server)
        await sync.syncNow()
        #expect(sync.status == .needsSignIn)
        #expect(try !database.pendingSyncItems().isEmpty)
    }

    @Test func oneRefusedItemDoesntHoldUpTheRest() async throws {
        let server = FakeSyncServer()
        let database = try phone()
        let waiting = try database.pendingSyncItems()
        let bad = try #require(waiting.first { $0.item.kind == .workout })
        server.statuses[bad.item.key] = .invalid

        await engine(database, server).syncNow()

        #expect(server.stored.count == waiting.count - 1)
        #expect(try database.syncFailures().map(\.key) == [bad.item.key])
        // Not offered again until it changes.
        #expect(try database.pendingSyncItems().isEmpty)
    }

    @Test func anItemFromANewerBuildAsksForAnUpdate() async throws {
        let server = FakeSyncServer()
        let database = try phone()
        let item = try #require(try database.pendingSyncItems().first)
        server.statuses[item.item.key] = .tooOld
        let sync = engine(database, server)
        await sync.syncNow()
        #expect(sync.updateNeeded)
        #expect(sync.status == .idle)
    }

    @Test func theFirstSyncAdoptsTheSignedInAccount() async throws {
        let database = try phone()
        await engine(database, FakeSyncServer()).syncNow()
        #expect(try database.syncOwner() == "anton")
    }

    @Test func anotherAccountNeverSyncsThisPhonesData() async throws {
        let database = try phone()
        try database.setSyncOwner("anton")
        let server = FakeSyncServer()
        let sync = engine(database, server, account: "jos")
        await sync.syncNow()
        #expect(sync.status == .otherAccount)
        #expect(server.pushes.isEmpty)
        #expect(server.pulls.isEmpty)
    }

    @Test func signedOutDoesNothing() async throws {
        let server = FakeSyncServer()
        await engine(try phone(), server, account: nil).syncNow()
        #expect(server.pushes.isEmpty)
        #expect(server.pulls.isEmpty)
    }

    @Test func aChangeWaitsAMomentBeforePushing() async throws {
        let clock = Clock()
        let sync = engine(try phone(), FakeSyncServer(), clock: clock)
        sync.changed()
        try await Task.sleep(for: .milliseconds(50))
        #expect(clock.asked.contains(SyncEngine.changeDelay))
    }

    @Test func theLaterEditWinsAcrossTwoPhones() async throws {
        let server = FakeSyncServer()
        let first = try phone()
        let second = try AppDatabase.inMemory()
        let one = engine(first, server)
        let two = engine(second, server)
        await one.syncNow()
        await two.syncNow()

        let workout = try #require(WorkoutStore(database: first).history.first)
        let id = workout.id.uuidString
        let now = Int64(Date.now.timeIntervalSince1970 * 1000)
        for (database, title, time) in [(first, "Earlier edit", now + 1_000), (second, "Later edit", now + 2_000)] {
            try await database.writer.write {
                try $0.execute(sql: "UPDATE workout SET title = ?, updated_at = ? WHERE id = ?", arguments: [title, time, id])
            }
        }
        await two.syncNow()
        await one.syncNow()
        await two.syncNow()

        let titles = [first, second].map { WorkoutStore(database: $0).history.first { $0.id == workout.id }?.title }
        #expect(titles == ["Later edit", "Later edit"])
    }

    // MARK: Signing out and another account

    @Test func signingOutWithEverythingBackedUpHasNothingToWarnAbout() async throws {
        let server = FakeSyncServer()
        let database = try phone()
        let sync = engine(database, server)
        let waiting = await sync.prepareSignOut()
        #expect(waiting.isEmpty)
        #expect(server.stored.count > 0)
    }

    @Test func signingOutOfflineCountsTheWorkoutsThatWouldBeLost() async throws {
        let server = FakeSyncServer()
        server.failures = [.offline]
        let database = try phone()
        let workouts = WorkoutStore(database: database).history.count
        let waiting = await engine(database, server).prepareSignOut()
        #expect(waiting.workouts == workouts)
        #expect(SignOutWarning(unsaved: waiting).title == "\(workouts) workouts aren't backed up yet")
    }

    @Test func wipingEmptiesThePhoneAndSigningInBringsItBack() async throws {
        let server = FakeSyncServer()
        let database = try phone()
        let sync = engine(database, server)
        await sync.syncNow()
        let before = try database.syncItems()
        var wiped = false
        sync.onWiped = { wiped = true }

        sync.wipe()
        #expect(wiped)
        #expect(try database.syncItems().isEmpty)
        #expect(try database.syncOwner() == nil)
        #expect(try database.syncCursor() == 0)

        await sync.syncNow()
        #expect(try database.syncItems() == before)
    }

    @Test func anotherAccountWithNothingWaitingTakesThePhoneOver() async throws {
        let database = try phone()
        await engine(database, FakeSyncServer()).syncNow()

        let theirs = FakeSyncServer()
        let sync = engine(database, theirs, account: "jos")
        var wiped = false
        sync.onWiped = { wiped = true }
        await sync.syncNow()

        #expect(wiped)
        #expect(sync.status == .idle)
        #expect(try database.syncOwner() == "jos")
        #expect(theirs.stored.isEmpty)
    }

    @Test func anotherAccountWithUnsentWorkoutsAsksAndCanTakeOver() async throws {
        let database = try phone()
        try database.setSyncOwner("anton")
        let theirs = FakeSyncServer()
        let sync = engine(database, theirs, account: "jos")
        await sync.syncNow()
        #expect(sync.status == .otherAccount)
        #expect(sync.otherAccountUnsaved.workouts > 0)

        sync.takeOver()
        await sync.syncNow()
        #expect(try database.syncOwner() == "jos")
        #expect(try database.syncItems().isEmpty)
        #expect(theirs.stored.isEmpty)
    }

    // What a wipe would lose besides changes waiting to go up.

    @Test func signingOutWarnsAboutAChangeTheServerRefused() async throws {
        let server = FakeSyncServer()
        let database = try phone()
        let refused = try #require(try database.pendingSyncItems().first { $0.item.kind == .workout }).item.key
        server.statuses = [refused: .invalid]

        let unsaved = await engine(database, server).prepareSignOut()

        // Nothing is waiting, since a refused item isn't offered again until it changes. It's still only here.
        #expect(unsaved.items == 0)
        #expect(unsaved.refused == 1)
        #expect(!unsaved.isEmpty)
        #expect(SignOutWarning(unsaved: unsaved).title == "1 change couldn't be backed up")
    }

    @Test func signingOutWarnsAboutARunningWorkout() async throws {
        let server = FakeSyncServer()
        let database = try phone()
        let workouts = WorkoutStore(database: database)
        workouts.startEmpty()
        workouts.saveActive()

        let unsaved = await engine(database, server).prepareSignOut()

        #expect(unsaved.running)
        #expect(!unsaved.isEmpty)
        #expect(SignOutWarning(unsaved: unsaved).title == "A workout is still running")
    }

    @Test func signingOutWarnsAboutPhotosAndVideos() async throws {
        let server = FakeSyncServer()
        let database = try phone()
        let workout = try #require(WorkoutStore(database: database).history.first).id.uuidString
        for second in 0..<2 {
            try database.insert(StoredMedia(id: UUID().uuidString, workoutId: workout, kind: "photo", fileName: "a.heic",
                                            createdAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(second))))
        }

        let unsaved = await engine(database, server).prepareSignOut()

        #expect(unsaved.media == 2)
        #expect(!unsaved.isEmpty)
        let warning = SignOutWarning(unsaved: unsaved)
        #expect(warning.title == "2 photos and videos are only on this phone")
        #expect(warning.message.hasSuffix("Everything else comes back when you sign in again."))
    }

    @Test func theWarningListsEverythingThatWouldBeLost() {
        let warning = SignOutWarning(unsaved: UnsavedOnPhone(items: 4, workouts: 3, refused: 1, running: true, media: 1))
        #expect(warning.lines == [
            "3 workouts aren't backed up yet", "A workout is still running", "1 change couldn't be backed up", "1 photo or video is only on this phone",
        ])
        #expect(warning.title == "3 workouts aren't backed up yet")
        #expect(warning.message.hasPrefix("A workout is still running. 1 change couldn't be backed up. 1 photo or video is only on this phone."))
    }

    @Test func anotherAccountAsksBeforeRemovingAPhotoNothingElseWouldLose() async throws {
        let database = try phone()
        await engine(database, FakeSyncServer()).syncNow()
        let workout = try #require(WorkoutStore(database: database).history.first).id.uuidString
        try database.insert(StoredMedia(id: UUID().uuidString, workoutId: workout, kind: "video", fileName: "a.mov", createdAt: .now))

        let sync = engine(database, FakeSyncServer(), account: "jos")
        await sync.syncNow()

        #expect(sync.status == .otherAccount)
        #expect(sync.otherAccountUnsaved.media == 1)
        #expect(try database.syncOwner() == "anton")
        #expect(SignOutWarning(unsaved: sync.otherAccountUnsaved).otherAccountMessage.contains("1 photo or video is only on this phone."))
    }

    @Test func aWipedPhoneIsNotFilledWithSamplesAgain() async throws {
        let database = try phone()
        let sync = engine(database, FakeSyncServer())
        await sync.syncNow()
        sync.wipe()

        #expect(try database.wasWiped())
        // As the app does on its next launch.
        let workouts = WorkoutStore(database: database)
        #expect(workouts.history.isEmpty)
        #expect(workouts.routines.isEmpty)
        #expect(ExerciseCatalog.load(from: database).savedSetups.isEmpty)
        #expect(try database.pendingSyncItems().isEmpty)
    }

    @Test func aWeightUnitPickedOnOnePhoneReachesTheOther() async throws {
        let server = FakeSyncServer()
        let first = try AppDatabase.inMemory()
        let second = try AppDatabase.inMemory()
        let one = engine(first, server)
        one.saveWeightUnit("lb")
        await one.syncNow()

        let two = engine(second, server)
        var unit: String?
        two.onPulled = { unit = $0.weightUnit }
        await two.syncNow()
        #expect(unit == "lb")
    }

    @Test func theSettingsLineSaysWhereBackupStands() async throws {
        let server = FakeSyncServer()
        let database = try phone()
        let sync = engine(database, server)
        sync.refreshCounts()
        #expect(SyncStatusLine.text(for: sync, now: .now).hasSuffix("workouts waiting to back up"))
        await sync.syncNow()
        #expect(SyncStatusLine.text(for: sync, now: .now) == "Backed up just now")
    }
}