import Foundation
import Testing
@testable import Fatigue

/// Notch 1 to 10 where lower is better, as in the requirements' worked example.
private let lowerNotch = ExerciseSetting(name: "Notch", value: "5", direction: .lower, rangeMin: 1, rangeMax: 10)

@MainActor
private func adductors(_ sets: [WorkoutSet], settings: [ExerciseSetting] = [lowerNotch], brand: String? = "Technogym") -> WorkoutExercise {
    WorkoutExercise(name: "Adductors", brand: brand, restSeconds: 90, settings: settings, sets: sets)
}

@MainActor
private func reps(_ weight: String, _ amount: String, notch: Double? = nil, done: Bool = true) -> WorkoutSet {
    WorkoutSet(setup: SetSetup(kind: .reps, values: notch.map { ["Notch": $0] } ?? [:]), weight: weight, amount: amount, isDone: done)
}

@MainActor
private func hold(_ weight: String, _ amount: String) -> WorkoutSet {
    WorkoutSet(setup: SetSetup(kind: .hold), weight: weight, amount: amount, isDone: true)
}

@MainActor
private func workout(daysAgo: Double, _ exercises: [WorkoutExercise]) -> FinishedWorkout {
    FinishedWorkout(title: "Leg day", startedAt: Date(timeIntervalSince1970: 1_000_000 - daysAgo * 86_400), duration: 3_600, exercises: exercises)
}

@MainActor
struct SetScoreTests {
    @Test func matchesTheWorkedExampleInTheRequirements() throws {
        let atFive = adductors([reps("50", "5")])
        let atFour = adductors([reps("50", "5", notch: 4)])
        #expect(try #require(SetScore.score(of: atFive.sets[0], in: atFive)).rounded() == 389)
        #expect(try #require(SetScore.score(of: atFour.sets[0], in: atFour)).rounded() == 417)
    }

    @Test func aHoldScoresWeightTimesSeconds() {
        let exercise = adductors([hold("40", "30")], settings: [])
        #expect(SetScore.score(of: exercise.sets[0], in: exercise) == 1_200)
    }

    @Test func anUnloadedSetCountsItsWeightAsOne() {
        let exercise = adductors([hold("", "30")], settings: [])
        #expect(SetScore.score(of: exercise.sets[0], in: exercise) == 30)
    }

    @Test func higherIsBetterRunsFromOneAtTheBottomToTwoAtTheTop() {
        let higher = ExerciseSetting(name: "Notch", value: "1", direction: .higher, rangeMin: 1, rangeMax: 10)
        let exercise = adductors([reps("10", "10"), reps("10", "10", notch: 10)], settings: [higher])
        #expect(SetScore.score(of: exercise.sets[0], in: exercise) == 100)
        #expect(SetScore.score(of: exercise.sets[1], in: exercise) == 200)
    }

    @Test func aValueOutsideTheRangeIsHeldAtItsEnds() {
        let exercise = adductors([reps("10", "10", notch: 0)])
        #expect(SetScore.score(of: exercise.sets[0], in: exercise) == 200)
    }

    @Test func untrackedSettingsLeaveTheScoreAlone() {
        let seat = ExerciseSetting(name: "Seat", value: "4")
        let deadStop = ExerciseSetting(name: "Dead stop", kind: .yesNo, value: "yes")
        let exercise = adductors([reps("10", "10")], settings: [seat, deadStop])
        #expect(SetScore.score(of: exercise.sets[0], in: exercise) == 100)
    }

    @Test func aSetWithNothingInItHasNoScore() {
        let exercise = adductors([reps("50", "")])
        #expect(SetScore.score(of: exercise.sets[0], in: exercise) == nil)
    }
}

@MainActor
struct SetShapeTests {
    @Test func holdsAndRepSetsAreDifferentShapes() {
        let exercise = adductors([reps("50", "5"), hold("50", "5")])
        #expect(SetShape(of: exercise.sets[0], in: exercise) != SetShape(of: exercise.sets[1], in: exercise))
    }

    @Test func loadedAndUnloadedAreDifferentShapes() {
        let exercise = adductors([reps("50", "5"), reps("", "5")])
        #expect(SetShape(of: exercise.sets[0], in: exercise) != SetShape(of: exercise.sets[1], in: exercise))
    }

    @Test func aTrackedSettingWithNoValueGivesADifferentShape() {
        let empty = ExerciseSetting(name: "Notch", value: "", direction: .lower, rangeMin: 1, rangeMax: 10)
        let exercise = adductors([reps("50", "5"), reps("50", "5", notch: 4)], settings: [empty])
        #expect(SetShape(of: exercise.sets[0], in: exercise) != SetShape(of: exercise.sets[1], in: exercise))
    }

    @Test func eachBrandHasItsOwnShapes() {
        let technogym = adductors([reps("50", "5")])
        let hammer = adductors([reps("50", "5")], brand: "Hammer Strength")
        #expect(SetShape(of: technogym.sets[0], in: technogym) != SetShape(of: hammer.sets[0], in: hammer))
    }

    @Test func ownProgressPerValueKeepsValuesApart() {
        var split = lowerNotch
        split.splitByValue = true
        let exercise = adductors([reps("50", "5", notch: 7), reps("50", "5", notch: 8)], settings: [split])
        let together = adductors(exercise.sets)
        #expect(SetShape(of: exercise.sets[0], in: exercise) != SetShape(of: exercise.sets[1], in: exercise))
        #expect(SetShape(of: together.sets[0], in: together) == SetShape(of: together.sets[1], in: together))
    }
}

@MainActor
struct RecordBookTests {
    @Test func aSetThatBeatsHistoryIsARecord() {
        let history = [workout(daysAgo: 3, [adductors([reps("50", "5")])])]
        let today = adductors([reps("55", "5")])
        let records = RecordBook(history: history).records(for: today.sets[0], in: today)
        #expect(records == [.weight, .score])
    }

    @Test func matchingTheBestIsNotARecord() {
        let history = [workout(daysAgo: 3, [adductors([reps("50", "5")])])]
        let today = adductors([reps("50", "5")])
        #expect(RecordBook(history: history).records(for: today.sets[0], in: today).isEmpty)
    }

    @Test func aDeeperNotchAtTheSameLoadIsANotchAndScoreRecord() {
        let history = [workout(daysAgo: 3, [adductors([reps("50", "5")])])]
        let today = adductors([reps("50", "5", notch: 4)])
        #expect(RecordBook(history: history).records(for: today.sets[0], in: today) == [.setting("Notch"), .score])
    }

    @Test func theFirstSetOfAShapeHasNothingToBeat() {
        let today = adductors([reps("50", "5")])
        #expect(RecordBook(history: []).records(for: today.sets[0], in: today).isEmpty)
    }

    @Test func aHoldIsNeverComparedWithARepSet() {
        let history = [workout(daysAgo: 3, [adductors([reps("50", "5")])])]
        let today = adductors([hold("60", "30")])
        #expect(RecordBook(history: history).records(for: today.sets[0], in: today).isEmpty)
    }

    @Test func aLongerHoldIsATimeRecord() {
        let history = [workout(daysAgo: 3, [adductors([hold("40", "30")])])]
        let today = adductors([hold("40", "45")])
        #expect(RecordBook(history: history).records(for: today.sets[0], in: today) == [.time, .score])
    }

    @Test func moreRepsIsARepsRecord() {
        let history = [workout(daysAgo: 3, [adductors([reps("50", "5")])])]
        let today = adductors([reps("50", "6")])
        #expect(RecordBook(history: history).records(for: today.sets[0], in: today) == [.reps, .score])
    }

    @Test func unloadedSetsNeverSetAWeightRecord() {
        let history = [workout(daysAgo: 3, [adductors([hold("", "30")])])]
        let today = adductors([hold("", "45")])
        #expect(!RecordBook(history: history).records(for: today.sets[0], in: today).contains(.weight))
    }

    @Test func ownProgressPerValueOnlyComparesTheSameValue() {
        var split = lowerNotch
        split.splitByValue = true
        let history = [workout(daysAgo: 3, [adductors([reps("60", "5", notch: 7)], settings: [split])])]
        let today = adductors([reps("50", "5", notch: 8)], settings: [split])
        // Nothing at notch 8 before, so there is nothing to beat, even though 50 kg is less than 60.
        #expect(RecordBook(history: history).records(for: today.sets[0], in: today).isEmpty)
    }

    @Test func marksCompareEachTickedSetWithTheOnesBeforeIt() {
        let history = [workout(daysAgo: 3, [adductors([reps("50", "5")])])]
        let today = adductors([reps("55", "5"), reps("60", "5"), reps("55", "5"), reps("70", "5", done: false)])
        let marks = RecordBook.marks(for: [today], after: history)
        #expect(marks[today.sets[0].id] == [.weight, .score])
        #expect(marks[today.sets[1].id] == [.weight, .score])
        #expect(marks[today.sets[2].id] == nil)
        #expect(marks[today.sets[3].id] == nil)
    }
}
