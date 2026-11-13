import Foundation
import SwiftUI
import Testing
@testable import Fatigue

@MainActor
struct SetBoxTests {
    @Test func everySetShowsTheSameBoxes() {
        let adductors = WorkoutSession.sample().exercises[0]
        #expect(adductors.setBoxes == [.weight, .amount, .setting(adductors.settings[1])])
        let legPress = WorkoutSession.sample().exercises[1]
        #expect(legPress.setBoxes == [.weight, .amount])
    }

    @Test func turningWeightOffHidesItsBox() {
        let session = WorkoutSession.sample()
        let settings = session.exercises[1].settings
        session.applyEdit(to: 1, name: "Leg Press", settings: settings, renamedSettings: [:], measures: ExerciseMeasures(weighted: false))
        #expect(session.exercises[1].setBoxes == [.amount])
        // What was typed stays on the sets; a new set starts without a weight.
        #expect(session.exercises[1].sets[0].weight == "160")
        session.addSet(to: 1)
        #expect(session.exercises[1].sets.last?.weight == "")
    }
}

@MainActor
struct WorkoutSessionTests {
    @Test func tickingASetStartsThatExercisesRest() {
        let start = Date(timeIntervalSince1970: 1_000)
        let session = WorkoutSession.sample(now: { start })
        session.toggle(set: 2, in: 0)
        #expect(session.exercises[0].sets[2].isDone)
        #expect(session.rest == RestTimer(endsAt: start.addingTimeInterval(120), total: 120, exerciseName: session.exercises[0].name))
    }

    @Test func untickingDoesNotStartRest() {
        let session = WorkoutSession.sample()
        session.toggle(set: 0, in: 0)
        #expect(session.exercises[0].sets[0].isDone == false)
        #expect(session.rest == nil)
    }

    @Test func restFinishesOnlyOnceItsTimeIsUp() {
        var now = Date(timeIntervalSince1970: 1_000)
        let session = WorkoutSession.sample(now: { now })
        session.toggle(set: 2, in: 0)
        now = now.addingTimeInterval(119)
        #expect(session.finishRestIfDue() == false)
        now = now.addingTimeInterval(1)
        #expect(session.finishRestIfDue())
        #expect(session.rest == nil)
    }

    @Test func addedSetCopiesTheLastSetButIsNotDone() {
        let session = WorkoutSession.sample()
        session.addSet(to: 0)
        let added = session.exercises[0].sets[3]
        #expect(added.kind == .reps)
        #expect(added.weight == "55")
        #expect(added.setup == SetSetup(kind: .reps, values: ["Notch": 7]))
        #expect(added.isDone == false)
        #expect(session.exercises[0].sets.count == 4)
    }

    @Test func aTimedExerciseAddsHolds() {
        let session = WorkoutSession(title: "Core", exercises: [
            WorkoutExercise(name: "Plank", restSeconds: 60, sets: [], measures: ExerciseMeasures(amount: .hold, weighted: false)),
        ])
        session.addSet(to: 0)
        #expect(session.exercises[0].sets.map(\.kind) == [.hold])
    }

    @Test func deletingTheOpenSetClosesItsRPEPanel() {
        let session = WorkoutSession.sample()
        let set = session.exercises[0].sets[2]
        session.openRPE = set.id
        session.deleteSet(set.id)
        #expect(session.exercises[0].sets.count == 2)
        #expect(session.openRPE == nil)
    }

    @Test func anExerciseWithNoSetsGetsAPlainRepSet() {
        let session = WorkoutSession.sample()
        for set in session.exercises[1].sets { session.deleteSet(set.id) }
        session.addSet(to: 1)
        #expect(session.exercises[1].sets.map(\.kind) == [.reps])
    }

    @Test func emptyNotesAreDropped() {
        let session = WorkoutSession.sample()
        session.addNote(to: 0)
        #expect(session.exercises[0].notes.count == 2)
        session.removeEmptyNotes()
        #expect(session.exercises[0].notes.map(\.text) == ["Pads on the widest setting."])
    }
}

struct ThemeTests {
    @Test func savedThemeIsDrawnAsItIs() {
        #expect(Theme.palette(for: "dark", systemScheme: .light).id == "dark")
        #expect(Theme.forcedScheme(for: "dark") == .dark)
    }

    @Test func systemFollowsThePhone() {
        #expect(Theme.palette(for: Theme.system, systemScheme: .dark).id == Palette.defaultDark.id)
        #expect(Theme.palette(for: Theme.system, systemScheme: .light).id == Palette.defaultLight.id)
        #expect(Theme.forcedScheme(for: Theme.system) == nil)
    }

    @Test func unknownThemeFallsBackToSystem() {
        #expect(Theme.palette(for: "removed-theme", systemScheme: .dark).id == Palette.defaultDark.id)
        #expect(Theme.forcedScheme(for: "removed-theme") == nil)
    }

    @Test func everyThemeIsOffered() {
        #expect(Theme.choices == [Theme.system] + Palette.all.map(\.id))
    }
}

@MainActor
struct SetPlaceTests {
    @Test func findsWhereASetIs() {
        let session = WorkoutSession.sample()
        let set = session.exercises[1].sets[2]
        let place = session.place(of: set.id)
        #expect(place?.exercise == 1)
        #expect(place?.set == 2)
    }
}
