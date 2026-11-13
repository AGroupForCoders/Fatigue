import Foundation
import GRDB
import Testing
@testable import Fatigue

/// Sync between two phone databases with no server in between: what one phone would push is handed
/// straight to the other as a pull.
@MainActor
struct SyncStoreTests {
    /// A database with the sample routines and weeks of history, as a debug build starts with.
    private func seeded() throws -> AppDatabase {
        let database = try AppDatabase.inMemory()
        _ = WorkoutStore(database: database)
        return database
    }

    private func store(_ database: AppDatabase) -> WorkoutStore { WorkoutStore(database: database) }

    /// Pushes everything waiting on `from` into `to`, as a push followed by the other phone's pull would.
    @discardableResult
    private func sync(from: AppDatabase, to: AppDatabase, cursor: Int64 = 1) throws -> PullOutcome {
        let pending = try from.pendingSyncItems()
        try from.markSynced(pending)
        return try to.applyPulled(pending.map(\.item), cursor: cursor)
    }

    /// A time after anything the tests have saved, `seconds` from now.
    private func later(_ seconds: Int64) -> Int64 { Int64(Date.now.timeIntervalSince1970 * 1000) + seconds * 1000 }

    private func setUpdatedAt(_ time: Int64, workout id: UUID, in database: AppDatabase) throws {
        try database.writer.write { try $0.execute(sql: "UPDATE workout SET updated_at = ? WHERE id = ?", arguments: [time, id.uuidString]) }
    }

    // MARK: Two phones

    @Test func aSecondPhoneEndsUpWithEverythingTheFirstHas() throws {
        let first = try seeded()
        let second = try AppDatabase.inMemory()

        let outcome = try sync(from: first, to: second)

        #expect(outcome.applied > 0)
        #expect(outcome.keptLocal == 0)
        #expect(try second.syncItems() == first.syncItems())
        #expect(try second.syncCursor() == 1)
        // And nothing on the second phone needs pushing back.
        #expect(try second.pendingSyncItems().isEmpty)

        let (mine, theirs) = (store(first), store(second))
        #expect(theirs.history.map(\.id) == mine.history.map(\.id))
        #expect(theirs.history.map(\.title) == mine.history.map(\.title))
        #expect(theirs.history.map { $0.exercises.map(\.name) } == mine.history.map { $0.exercises.map(\.name) })
        #expect(theirs.history.map(\.setCount) == mine.history.map(\.setCount))
        #expect(theirs.routines == mine.routines)
    }

    @Test func nothingIsWaitingOnceEverythingIsPushed() throws {
        let database = try seeded()
        #expect(try !database.pendingSyncItems().isEmpty)
        try database.markSynced(try database.pendingSyncItems())
        #expect(try database.pendingSyncItems().isEmpty)
    }

    @Test func itemsGoUpInTheOrderTheyDependOnEachOther() throws {
        let kinds = try seeded().pendingSyncItems().map(\.item.kind)
        let order = SyncItem.Kind.allCases
        #expect(kinds == kinds.sorted { order.firstIndex(of: $0)! < order.firstIndex(of: $1)! })
        #expect(Set(kinds).isSuperset(of: [.brand, .routine, .workout]))
    }

    @Test func onlyTheWorkoutThatChangedIsWaiting() throws {
        let database = try seeded()
        try database.markSynced(try database.pendingSyncItems())

        let workouts = store(database)
        let edited = workouts.history[2].id
        workouts.rename(edited, title: "Pull, heavy", description: "")

        #expect(try database.pendingSyncItems().map(\.item.key) == ["workout:\(edited.uuidString.lowercased())"])
    }

    @Test func savingEveryRoutineUnchangedLeavesNothingWaiting() throws {
        let database = try seeded()
        try database.markSynced(try database.pendingSyncItems())

        // Reordering saves all of them. Putting them back saves all of them again, with new times and the same contents.
        let workouts = store(database)
        let routines = workouts.routines
        workouts.routines = routines.reversed()
        workouts.routines = routines

        #expect(try database.pendingSyncItems().isEmpty)
    }

    @Test func theRunningWorkoutNeverSyncs() throws {
        let database = try seeded()
        try database.markSynced(try database.pendingSyncItems())

        let workouts = store(database)
        workouts.startEmpty()
        workouts.active?.addExercises(named: ["Chest Press"])
        workouts.saveActive()

        // Adding an exercise can make its no-brand row, which is an item of its own. The workout isn't one yet.
        #expect(try !database.pendingSyncItems().contains { $0.item.kind == .workout })
    }

    // MARK: Deleting

    @Test func aDeletedWorkoutGoesFromTheOtherPhoneToo() throws {
        let first = try seeded()
        let second = try AppDatabase.inMemory()
        try sync(from: first, to: second)

        let workouts = store(first)
        let deleted = workouts.history[1].id
        workouts.deleteFromHistory(deleted)
        let pending = try first.pendingSyncItems()
        #expect(pending.map(\.item.key) == ["workout:\(deleted.uuidString.lowercased())"])
        #expect(pending[0].item.body == nil)
        #expect(pending[0].item.deletedAt != nil)

        try sync(from: first, to: second, cursor: 2)

        #expect(!store(second).history.contains { $0.id == deleted })
        #expect(try second.deletedWorkoutIds() == [deleted.uuidString])
        #expect(try second.pendingSyncItems().isEmpty)
    }

    @Test func somethingDeletedBeforeItWasEverPushedIsNotPushed() throws {
        let database = try seeded()
        let workouts = store(database)
        let deleted = workouts.history[0].id
        workouts.deleteFromHistory(deleted)

        #expect(try !database.pendingSyncItems().contains { $0.item.id == deleted.uuidString.lowercased() })
    }

    @Test func aDeletionTheOtherPhoneNeverHadLeavesAMarkedRow() throws {
        let database = try AppDatabase.inMemory()
        let gone = SyncItem(kind: .workout, id: UUID().uuidString.lowercased(), updatedAt: 2000, deletedAt: 2000, body: nil)

        try database.applyPulled([gone], cursor: 5)

        #expect(try database.deletedWorkoutIds() == [gone.id.uppercased()])
        #expect(try database.workouts().isEmpty)
        #expect(try database.pendingSyncItems().isEmpty)
    }

    // MARK: Both phones changed it

    @Test func aLaterUnsentEditOnThisPhoneSurvivesAPull() throws {
        let first = try seeded()
        let second = try AppDatabase.inMemory()
        try sync(from: first, to: second)
        let id = store(first).history[0].id

        store(first).rename(id, title: "From the first phone", description: "")
        try setUpdatedAt(later(60), workout: id, in: first)
        store(second).rename(id, title: "From the second phone, later", description: "")
        try setUpdatedAt(later(120), workout: id, in: second)

        let outcome = try sync(from: first, to: second, cursor: 2)

        #expect(outcome.keptLocal == 1)
        #expect(store(second).history.first { $0.id == id }?.title == "From the second phone, later")
        // It still needs pushing, and goes to the first phone, where it wins.
        #expect(try second.pendingSyncItems().map(\.item.key) == ["workout:\(id.uuidString.lowercased())"])
        try sync(from: second, to: first, cursor: 2)
        #expect(store(first).history.first { $0.id == id }?.title == "From the second phone, later")
    }

    @Test func anEarlierUnsentEditOnThisPhoneGivesWayToAPull() throws {
        let first = try seeded()
        let second = try AppDatabase.inMemory()
        try sync(from: first, to: second)
        let id = store(first).history[0].id

        store(second).rename(id, title: "From the second phone, earlier", description: "")
        try setUpdatedAt(later(60), workout: id, in: second)
        store(first).rename(id, title: "From the first phone, later", description: "")
        try setUpdatedAt(later(120), workout: id, in: first)

        let outcome = try sync(from: first, to: second, cursor: 2)

        #expect(outcome.keptLocal == 0)
        #expect(store(second).history.first { $0.id == id }?.title == "From the first phone, later")
        #expect(try second.pendingSyncItems().isEmpty)
    }

    @Test func anUnchangedItemTakesThePulledCopyWhateverItsTimeSays() throws {
        let first = try seeded()
        let second = try AppDatabase.inMemory()
        try sync(from: first, to: second)
        let id = store(first).history[0].id

        // The second phone's row has a later time but no change of its own, as saving all routines leaves behind.
        try setUpdatedAt(9_000_000_000_000, workout: id, in: second)
        store(first).rename(id, title: "Edited on the first phone", description: "")

        try sync(from: first, to: second, cursor: 2)

        #expect(store(second).history.first { $0.id == id }?.title == "Edited on the first phone")
    }

    // MARK: Changes that don't move the time

    @Test func aChangeThatLeftTheTimeAloneIsStampedSoTheServerTakesIt() throws {
        let database = try seeded()
        let catalog = ExerciseCatalog.load(from: database)
        catalog.save(ExerciseInfo(name: "Belt Squat", equipment: .machine, primaryMuscle: .quadriceps, isCustom: true), brand: nil, setup: BrandSetup())
        let workouts = store(database)
        var routine = workouts.routines[0]
        routine.exercises.append(.new(named: "Belt Squat"))
        workouts.update(routine)
        let agreed = try database.pendingSyncItems()
        try database.markSynced(agreed)
        let agreedAt = try #require(agreed.first { $0.item.id == routine.id.uuidString.lowercased() }).item.updatedAt

        // Deleting the exercise takes it out of the routine without touching the routine's own row.
        try database.deleteExercise(named: "Belt Squat")

        let pending = try database.pendingSyncItems(now: agreedAt + 60_000)
        let pushed = try #require(pending.first { $0.item.kind == .routine })
        #expect(pushed.item.id == routine.id.uuidString.lowercased())
        #expect(pushed.item.updatedAt == agreedAt + 60_000)
    }

    // MARK: Refused items

    @Test func aRefusedItemWaitsUntilItChanges() throws {
        let database = try seeded()
        try database.markSynced(try database.pendingSyncItems())
        let workouts = store(database)
        let id = workouts.history[0].id
        workouts.rename(id, title: "Refused", description: "")
        let refused = try #require(try database.pendingSyncItems().first)

        try database.markFailed(refused, error: "Update the app to change this.")

        #expect(try database.pendingSyncItems().isEmpty)
        #expect(try database.syncFailures().map(\.error) == ["Update the app to change this."])

        store(database).rename(id, title: "Changed again", description: "")
        #expect(try database.pendingSyncItems().map(\.item.id) == [id.uuidString.lowercased()])
        try database.markSynced(try database.pendingSyncItems())
        #expect(try database.syncFailures().isEmpty)
    }

    // MARK: A pull that can't be applied

    @Test func aPullThatPointsAtSomethingMissingWritesNothing() throws {
        let database = try AppDatabase.inMemory()
        // A brand of a custom exercise that never arrived.
        let orphan = SyncItem(
            kind: .brand, id: UUID().uuidString.lowercased(), updatedAt: 1000,
            body: .brand(SyncItem.BrandBody(exerciseId: UUID().uuidString.lowercased(), brand: "Technogym", label: nil, settings: []))
        )
        let fine = SyncItem(kind: .userSetting, id: UUID().uuidString.lowercased(), updatedAt: 1000, body: .userSetting(SyncItem.UserSettingBody(weightUnit: "lb")))

        #expect(throws: (any Error).self) { try database.applyPulled([fine, orphan], cursor: 7) }

        #expect(try database.syncItems().isEmpty)
        #expect(try database.syncCursor() == 0)
    }

    @Test func aBrandOfABuiltInExerciseMakesTheExerciseRowItNeeds() throws {
        let database = try AppDatabase.inMemory()
        let brand = SyncItem(
            kind: .brand, id: UUID().uuidString.lowercased(), updatedAt: 1000,
            body: .brand(SyncItem.BrandBody(exerciseId: SyncID.exercise(named: "Chest Press").lowercased(), brand: "Technogym", label: nil, settings: []))
        )

        #expect(try database.applyPulled([brand], cursor: 1).applied == 1)

        let name = try database.writer.read { try String.fetchOne($0, sql: "SELECT name FROM exercise WHERE is_builtin = 1") }
        #expect(name == "Chest Press")
    }

    @Test func aPulledUserSettingSaysWhichUnitToSwitchTo() throws {
        let database = try AppDatabase.inMemory()
        let setting = SyncItem(kind: .userSetting, id: UUID().uuidString.lowercased(), updatedAt: 1000, body: .userSetting(SyncItem.UserSettingBody(weightUnit: "lb")))
        #expect(try database.applyPulled([setting], cursor: 1).weightUnit == "lb")
        #expect(try database.syncItems().map(\.item) == [setting])
    }

    // MARK: The wire

    @Test func anItemReadsBackFromTheJSONTheServerSends() throws {
        let json = """
        {"kind":"workout","id":"7a1c0000-0000-4000-8000-000000000001","updatedAt":2000,"deletedAt":null,"body":{
          "title":"Push","note":null,"startedAt":1000,"finishedAt":1500,"routineId":null,"importKey":null,
          "gymName":"City Gym","gymAddress":null,"gymLatitude":null,"gymLongitude":null,
          "exercises":[{"id":"7a1c0000-0000-4000-8000-000000000002","brandId":"7a1c0000-0000-4000-8000-000000000003","restSeconds":90,
            "notes":[],"settings":[{"settingId":"7a1c0000-0000-4000-8000-000000000004","value":4,"textValue":null}],
            "sets":[{"id":"7a1c0000-0000-4000-8000-000000000005","kind":"reps","setType":"normal","weightKg":80,"reps":8,
              "durationSeconds":null,"rpe":8.5,"completedAt":1200,"overrides":[]}]}]}}
        """
        let item = try JSONDecoder().decode(SyncItem.self, from: Data(json.utf8))

        guard case .workout(let body)? = item.body else {
            Issue.record("The body isn't a workout")
            return
        }
        #expect(body.gymName == "City Gym")
        #expect(body.exercises[0].sets[0].rpe == 8.5)
        #expect(body.exercises[0].settings[0].value == 4)
        // And what it sends back reads as the same item.
        #expect(try JSONDecoder().decode(SyncItem.self, from: JSONEncoder().encode(item)) == item)

        let gone = try JSONDecoder().decode(SyncItem.self, from: Data(#"{"kind":"routine","id":"7a1c0000-0000-4000-8000-000000000009","updatedAt":3,"deletedAt":3,"body":null}"#.utf8))
        #expect(gone.body == nil)
        #expect(String(decoding: try JSONEncoder().encode(gone), as: UTF8.self).contains(#""kind":"routine""#))
    }

    @Test func theFingerprintIgnoresWhenAndFollowsWhat() {
        var item = SyncItem(kind: .userSetting, id: "a", updatedAt: 1, body: .userSetting(SyncItem.UserSettingBody(weightUnit: "kg")))
        let hash = item.contentHash
        item.updatedAt = 99
        #expect(item.contentHash == hash)
        item.body = .userSetting(SyncItem.UserSettingBody(weightUnit: "lb"))
        #expect(item.contentHash != hash)
        item.body = .userSetting(SyncItem.UserSettingBody(weightUnit: "kg"))
        item.deletedAt = 5
        #expect(item.contentHash != hash)
    }
}
