import Foundation
import SwiftUI
import Testing
@testable import Fatigue

@MainActor
struct SetGroupTests {
    @Test func groupsSplitWhereTheSetupChanges() {
        let adductors = WorkoutSession.sample().exercises[0]
        #expect(adductors.groups.map(\.heading) == ["Hold · Notch 8", "Reps · Notch 7 · Dead stop"])
        #expect(adductors.groups.map(\.setIndices) == [[0], [1, 2]])
    }

    @Test func plainRepSetsGetNoHeading() {
        let legPress = WorkoutSession.sample().exercises[1]
        #expect(legPress.groups == [SetGroup(heading: "", setIndices: [0, 1, 2])])
    }
}

@MainActor
struct WorkoutSessionTests {
    @Test func tickingASetStartsThatExercisesRest() {
        let start = Date(timeIntervalSince1970: 1_000)
        let session = WorkoutSession.sample(now: { start })
        session.toggle(set: 2, in: 0)
        #expect(session.exercises[0].sets[2].isDone)
        #expect(session.rest == RestTimer(endsAt: start.addingTimeInterval(120), total: 120))
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
        #expect(added.setup == ["Notch 7", "Dead stop"])
        #expect(added.isDone == false)
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

struct NumberTextTests {
    @Test func stepsUpAndDown() {
        #expect(NumberText.adjust("55", by: 2.5) == "57.5")
        #expect(NumberText.adjust("57.5", by: -2.5) == "55")
        #expect(NumberText.adjust("", by: 2.5) == "2.5")
    }

    @Test func neverGoesBelowZero() {
        #expect(NumberText.adjust("1", by: -2.5) == "0")
    }
}

@MainActor
struct KeyboardOrderTests {
    @Test func nextMovesFromWeightToAmountToTheNextSet() {
        let session = WorkoutSession.sample()
        let first = session.exercises[0].sets[0].id
        let second = session.exercises[0].sets[1].id
        #expect(session.cell(after: .weight(first)) == .amount(first))
        #expect(session.cell(after: .amount(first)) == .weight(second))
    }

    @Test func lastFieldHasNoNext() {
        let session = WorkoutSession.sample()
        let last = session.exercises.last!.sets.last!.id
        #expect(session.cell(after: .amount(last)) == nil)
    }

    @Test func stepUsesFiveSecondsForHolds() {
        let session = WorkoutSession.sample()
        let hold = session.exercises[0].sets[0]
        session.step(.amount(hold.id), up: true)
        #expect(session.exercises[0].sets[0].amount == "55")
        session.step(.weight(hold.id), up: false)
        #expect(session.exercises[0].sets[0].weight == "37.5")
    }
}
