import Foundation
import Testing
@testable import Fatigue

@MainActor
struct HistoryTests {
    @Test func finishingKeepsOnlyTickedSets() {
        let start = Date(timeIntervalSince1970: 0)
        let session = WorkoutSession.sample(now: { start })
        let finished = session.finished(at: start.addingTimeInterval(3_000))
        // The sample has sets 1 and 2 of Adductors ticked and nothing else.
        #expect(finished.exercises.map(\.name) == ["Adductors"])
        #expect(finished.setCount == 2)
        #expect(finished.duration == 3_000)
    }

    @Test func countingWorkoutsThatUseAnExerciseIgnoresTheBrand() {
        let history = FinishedWorkout.samples()
        // Chest Press is in the Push sample on Technogym; Adductors in Leg day on Technogym.
        #expect(history.count(using: "Chest Press") == 1)
        #expect(history.count(using: "Adductors") == 1)
        #expect(history.count(using: "Belt Squat") == 0)
        #expect(([FinishedWorkout]()).count(using: "Chest Press") == 0)
    }

    @Test func deleteMessageSaysHowManyWorkoutsUseIt() {
        #expect(ExerciseEditor.deleteMessage(workoutsUsingIt: 0) == "It's removed from the picker and your prebuilt workouts.")
        #expect(ExerciseEditor.deleteMessage(workoutsUsingIt: 1).hasPrefix("1 finished workout uses it and keeps its sets."))
        #expect(ExerciseEditor.deleteMessage(workoutsUsingIt: 3).hasPrefix("3 finished workouts use it and keep their sets."))
    }

    @Test func removingAnExerciseFromPrebuiltWorkoutsLeavesHistoryAlone() {
        let store = WorkoutStore()
        let before = store.history.map(\.setCount)
        store.removeFromRoutines(exerciseNamed: "Adductors")
        #expect(!store.routines.flatMap(\.exercises).contains { $0.name == "Adductors" })
        #expect(store.routines.count == Routine.samples.count)
        #expect(store.history.map(\.setCount) == before)
    }

    @Test func volumeCountsRepSetsOnly() {
        let finished = WorkoutSession.sample().finished(at: .now)
        // The 40 kg hold is left out, the 55 × 8 rep set counts.
        #expect(finished.volume == 440)
    }

    @Test func finishingPutsTheWorkoutAtTheTopOfHistory() {
        let store = WorkoutStore(history: [])
        store.start(store.routines[0])
        store.active?.toggle(set: 0, in: 1)
        store.finish()
        #expect(store.history.map(\.title) == ["Leg day"])
        #expect(store.active == nil)
    }

    @Test func aWorkoutWithNothingTickedIsNotSaved() {
        let store = WorkoutStore(history: [])
        store.startEmpty()
        store.finish()
        #expect(store.history.isEmpty)
    }

    @Test func historyRowsSayWhenAndHowMuch() {
        let now = Date(timeIntervalSince1970: 1_794_500_000)
        #expect(HistoryRow.when(now, now: now) == "Today")
        #expect(HistoryRow.when(now.addingTimeInterval(-86_400), now: now) == "Yesterday")
        var workout = FinishedWorkout.samples(now: now)[0]
        workout.startedAt = now
        #expect(HistoryRow.summary(workout, unit: .kg, now: now) == "Today · 52 min · 9 sets · \(Int(workout.volume.rounded()).formatted()) kg")
        #expect(HistoryRow.duration(74) == "1 h 14 min")
    }

    @Test func rowsShowFiveExercisesThenSayHowManyMore() {
        let samples = FinishedWorkout.samples()
        #expect(HistoryRow.hiddenCount(samples[0]) == nil)
        #expect(samples[2].exercises.count == 7)
        #expect(HistoryRow.hiddenCount(samples[2]) == 2)
    }

    @Test func editingAPastWorkoutKeepsItsPlaceAndDate() {
        let store = WorkoutStore()
        let original = store.history[1]
        let session = original.editingSession()
        #expect(session.startsRestWhenTicked == false)
        session.exercises[0].sets[0].weight = "75"
        session.toggle(set: 1, in: 0)
        #expect(session.rest == nil)
        store.replace(original.updated(from: session))
        let edited = store.history[1]
        #expect(edited.id == original.id)
        #expect(edited.startedAt == original.startedAt)
        #expect(edited.exercises[0].sets.map(\.weight) == ["75", "70"])
    }

    @Test func savingAPastWorkoutAsAPrebuiltOne() {
        let routine = FinishedWorkout.samples()[2].asRoutine()
        #expect(routine.name == "Leg day")
        #expect(routine.exercises.count == 7)
        #expect(routine.exercises[0].sets[0].setup == SetSetup(kind: .hold, values: ["Notch": 8]))
    }
}
