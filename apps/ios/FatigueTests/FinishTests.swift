import Foundation
import Testing
@testable import Fatigue

@MainActor
struct FinishTests {
    @Test func untickedSetsCanBeLeftOut() {
        let store = WorkoutStore(history: [])
        store.start(store.routines[1])
        store.active?.toggle(set: 0, in: 0)
        store.finish(unticked: .drop)
        #expect(store.history[0].setCount == 1)
    }

    @Test func untickedSetsCanBeCountedAsDone() {
        let store = WorkoutStore(history: [])
        store.start(store.routines[1])
        store.active?.toggle(set: 0, in: 0)
        store.finish(unticked: .count)
        #expect(store.history[0].setCount == 9)
    }

    @Test func theSummaryPreviewDoesNotTickAnything() {
        let session = Routine.samples[1].start()
        let preview = session.preview(unticked: .count, at: .now)
        #expect(preview.setCount == 9)
        #expect(session.doneCount == 0)
    }

    @Test func finishingSavesTheNameAndDescription() {
        let store = WorkoutStore(history: [])
        store.start(store.routines[1])
        store.finish(title: "  Push, deload ", description: "Light week.\n", unticked: .count)
        #expect(store.history[0].title == "Push, deload")
        #expect(store.history[0].description == "Light week.")
    }

    @Test func anUnchangedWorkoutDoesNotOfferToUpdateItsRoutine() {
        let routine = Routine.samples[1]
        let session = routine.start()
        #expect(!routine.differs(from: session))
        session.addSet(to: 0)
        #expect(routine.differs(from: session))
    }

    @Test func updatingTheRoutineTakesTodaysSets() {
        let store = WorkoutStore(history: [])
        let id = store.routines[1].id
        store.start(store.routines[1])
        store.active?.exercises[0].sets[0].weight = "75"
        store.active?.addSet(to: 2)
        store.finish(unticked: .count, updateRoutine: true)
        let routine = store.routines.first { $0.id == id }!
        #expect(routine.exercises[0].sets[0].weight == "75")
        #expect(routine.exercises[2].sets.count == 4)
    }

    @Test func notUpdatingLeavesTheRoutineAlone() {
        let store = WorkoutStore(history: [])
        let before = store.routines[1]
        store.start(before)
        store.active?.addSet(to: 0)
        store.finish(unticked: .count, updateRoutine: false)
        #expect(store.routines[1] == before)
    }

    @Test func aFinishedWorkoutCanBeRenamedLater() {
        let store = WorkoutStore()
        let id = store.history[0].id
        store.rename(id, title: "Pull, heavy", description: "PB on rows")
        #expect(store.history[0].title == "Pull, heavy")
        #expect(store.history[0].description == "PB on rows")
    }
}

@MainActor
struct EditingTests {
    @Test func editingAPrebuiltWorkoutKeepsItsPlace() {
        let store = WorkoutStore()
        var routine = store.routines[1]
        routine.name = "Push A"
        routine.exercises.move(fromOffsets: [2], toOffset: 0)
        store.update(routine)
        #expect(store.routines[1].name == "Push A")
        #expect(store.routines[1].exercises.first?.name == "Triceps Pushdown")
    }

    @Test func exercisesCanBeRemovedAndReorderedDuringAWorkout() {
        let session = WorkoutSession.sample()
        session.moveExercises(from: [2], to: 0)
        #expect(session.exercises.map(\.name) == ["Seated Calf Raise", "Adductors", "Leg Press"])
        session.removeExercise(at: 1)
        #expect(session.exercises.map(\.name) == ["Seated Calf Raise", "Leg Press"])
    }

    @Test func removingAnExerciseClosesItsRPEPanel() {
        let session = WorkoutSession.sample()
        session.openRPE = session.exercises[0].sets[2].id
        session.removeExercise(at: 0)
        #expect(session.openRPE == nil)
    }
}
