import Foundation
import Testing
@testable import Fatigue

@MainActor
struct GymTests {
    private let cityGym = Gym(name: "City Gym", address: "1 High St", latitude: 51.5, longitude: -0.12)!
    private let home = Gym(name: "Home")!

    private func workout(daysAgo: Double, gym: Gym?) -> FinishedWorkout {
        FinishedWorkout(title: "Legs", startedAt: Date(timeIntervalSince1970: 1_000_000 - daysAgo * 86_400), duration: 3600, gym: gym, exercises: [
            WorkoutExercise(name: "Leg Press", restSeconds: 90, sets: [WorkoutSet(setup: SetSetup(kind: .reps), weight: "100", amount: "10", isDone: true)]),
        ])
    }

    @Test func aBlankNameIsNoGym() {
        #expect(Gym(name: "   ") == nil)
        #expect(Gym(name: " Home ")?.name == "Home")
        #expect(home.coordinate == nil)
        #expect(cityGym.coordinate?.latitude == 51.5)
    }

    @Test func recentGymsComeNewestFirstAndOnce() {
        let history = [workout(daysAgo: 5, gym: home), workout(daysAgo: 1, gym: cityGym), workout(daysAgo: 3, gym: home), workout(daysAgo: 2, gym: nil)]
        #expect(Gym.recent(in: history) == [cityGym, home])
    }

    @Test func theGymIsSavedAndComesBack() throws {
        let database = try AppDatabase.inMemory()
        try database.save(workout(daysAgo: 1, gym: cityGym).stored)
        try database.save(workout(daysAgo: 2, gym: home).stored)
        try database.save(workout(daysAgo: 3, gym: nil).stored)
        let loaded = try database.workouts().map(FinishedWorkout.init(stored:))
        #expect(loaded.map(\.gym) == [cityGym, home, nil])
    }

    @Test func finishingSavesTheGymAndItCanBeChangedLater() throws {
        let database = try AppDatabase.inMemory()
        let store = WorkoutStore(database: database)
        store.start(Routine.samples[0])
        store.active?.toggle(set: 0, in: 0)
        store.finish(gym: home)
        let id = try #require(store.history.first?.id)
        #expect(store.history.first?.gym == home)
        #expect(store.lastGym == home)

        store.setGym(cityGym, of: id)
        #expect(WorkoutStore(database: database).history.first { $0.id == id }?.gym == cityGym)
        store.setGym(nil, of: id)
        #expect(WorkoutStore(database: database).history.first { $0.id == id }?.gym == nil)
    }

    @Test func editingAPastWorkoutKeepsItsGym() {
        let past = workout(daysAgo: 1, gym: cityGym)
        #expect(past.updated(from: past.editingSession()).gym == cityGym)
    }
}
