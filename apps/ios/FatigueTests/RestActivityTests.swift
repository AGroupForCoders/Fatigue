import Foundation
import Testing
@testable import Fatigue

/// The rest timer outside the app: the saved copy, the Live Activity's state, and the buttons on it.
@MainActor
struct RestActivityTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    /// A fresh, empty UserDefaults for each test.
    private func defaults() throws -> UserDefaults {
        let name = "RestActivityTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func store(_ database: AppDatabase, _ defaults: UserDefaults, now: Date? = nil) -> WorkoutStore {
        let now = now ?? self.now
        return WorkoutStore(database: database, defaults: defaults, now: { now })
    }

    @Test func aSavedTimerComesBackTheSame() throws {
        let defaults = try defaults()
        let saved = SavedRest(workoutID: UUID(), rest: RestTimer(endsAt: now, total: 90, exerciseName: "Adductors"))
        SavedRest.save(saved, to: defaults)
        #expect(SavedRest.load(from: defaults) == saved)
        SavedRest.save(nil, to: defaults)
        #expect(SavedRest.load(from: defaults) == nil)
    }

    @Test func tickingASetSavesTheTimerAndSkippingClearsIt() throws {
        let defaults = try defaults()
        let store = store(try AppDatabase.inMemory(), defaults)
        store.start(store.routines[0])
        store.active?.toggle(set: 0, in: 0)
        let saved = try #require(SavedRest.load(from: defaults))
        #expect(saved.workoutID == store.active?.id)
        #expect(saved.rest == store.active?.rest)
        store.active?.skipRest()
        #expect(SavedRest.load(from: defaults) == nil)
    }

    @Test func aRunningTimerSurvivesARestartButAFinishedOneDoesNot() throws {
        let defaults = try defaults()
        let database = try AppDatabase.inMemory()
        let first = store(database, defaults)
        first.start(first.routines[0])
        first.active?.toggle(set: 0, in: 0)
        first.saveActive()
        let rest = try #require(first.active?.rest)

        let soon = store(database, defaults, now: now.addingTimeInterval(30))
        #expect(soon.active?.rest == rest)

        let later = store(database, defaults, now: rest.endsAt)
        #expect(later.active?.rest == nil)
    }

    @Test func aTimerFromAnotherWorkoutIsIgnored() throws {
        let defaults = try defaults()
        let database = try AppDatabase.inMemory()
        let first = store(database, defaults)
        first.start(first.routines[0])
        first.saveActive()
        SavedRest.save(SavedRest(workoutID: UUID(), rest: RestTimer(endsAt: now.addingTimeInterval(60), total: 60)), to: defaults)

        let reopened = store(database, defaults)
        #expect(reopened.active?.rest == nil)
    }

    @Test func finishingOrDeletingTheWorkoutEndsTheTimer() throws {
        let defaults = try defaults()
        let store = store(try AppDatabase.inMemory(), defaults)
        var reported: [RestTimer?] = []
        store.onRestChange = { rest, _ in reported.append(rest) }

        store.start(store.routines[0])
        store.active?.toggle(set: 0, in: 0)
        store.finish()
        #expect(reported.count == 2)
        #expect(reported.last == .some(nil))
        #expect(SavedRest.load(from: defaults) == nil)

        store.start(store.routines[0])
        store.active?.toggle(set: 0, in: 0)
        store.discard()
        #expect(reported.count == 4)
        #expect(reported.last == .some(nil))
        #expect(SavedRest.load(from: defaults) == nil)
    }

    @Test func theLiveActivityButtonsActOnTheRunningTimer() throws {
        let store = WorkoutStore(now: { self.now })
        store.start(store.routines[0])
        store.active?.toggle(set: 0, in: 0)
        let endsAt = try #require(store.active?.rest?.endsAt)

        store.perform(.extend(15))
        #expect(store.active?.rest?.endsAt == endsAt.addingTimeInterval(15))
        #expect(store.active?.rest?.total == 135)

        store.perform(.skip)
        #expect(store.active?.rest == nil)
    }

    @Test func theIntentsHandTheirActionToTheApp() async throws {
        let before = RestIntentHandler.perform
        defer { RestIntentHandler.perform = before }
        var actions: [RestAction] = []
        RestIntentHandler.perform = { actions.append($0) }

        _ = try await ExtendRestIntent().perform()
        _ = try await SkipRestIntent().perform()
        #expect(actions == [.extend(15), .skip])
    }

    @Test func theActivityShowsTheTimerAndWhereItStarted() {
        let rest = RestTimer(endsAt: now.addingTimeInterval(90), total: 120, exerciseName: "Adductors")
        let state = RestLiveActivity.state(for: rest)
        #expect(state.endsAt == rest.endsAt)
        #expect(state.exerciseName == "Adductors")
        #expect(state.startedAt == now.addingTimeInterval(-30))
        #expect(rest.startedAt == state.startedAt)
    }
}
