import Foundation
import Testing
@testable import Fatigue

@MainActor
struct WorkoutStoreTests {
    @Test func startingARoutineOpensItAsAFreshWorkout() {
        let store = WorkoutStore()
        let routine = store.routines[0]
        store.start(routine)
        let active = try! #require(store.active)
        #expect(store.isShowingActive)
        #expect(active.title == routine.name)
        #expect(active.exercises.map(\.name) == routine.exercises.map(\.name))
        #expect(active.doneCount == 0)
        // Previous comes from the last Leg day in history, not the prebuilt workout's targets.
        #expect(active.exercises[0].sets[1].previous?.text(in: .kg) == "55 × 8 @8.5")
    }

    @Test func changesDuringTheWorkoutNeverReachTheRoutine() {
        let store = WorkoutStore()
        store.start(store.routines[0])
        store.active?.exercises[0].sets[0].weight = "100"
        #expect(store.routines[0].exercises[0].sets[0].weight == "50")
    }

    @Test func minimisingKeepsTheWorkoutRunning() {
        let store = WorkoutStore()
        store.startEmpty()
        store.isShowingActive = false
        #expect(store.active != nil)
    }

    @Test func discardingEndsTheWorkout() {
        let store = WorkoutStore()
        store.start(store.routines[1])
        store.discard()
        #expect(store.active == nil)
        #expect(store.isShowingActive == false)
    }

    @Test func aNewRoutineGetsThreeEmptyRepSetsPerExercise() {
        let exercise = RoutineExercise.new(named: "Leg Curl")
        #expect(exercise.sets.count == 3)
        #expect(exercise.sets.allSatisfy { $0.setup.kind == .reps && $0.weight.isEmpty })
    }

    @Test func anEmptyWorkoutTakesExercisesFromTheLibrary() {
        let store = WorkoutStore()
        store.startEmpty()
        store.active?.addExercises(named: ["Squat", "Leg Curl"])
        #expect(store.active?.exercises.map(\.name) == ["Squat", "Leg Curl"])
        // Squat is new, so it starts with one set. Leg Curl copies its two sets from last time.
        #expect(store.active?.setCount == 3)
    }
}
