import Foundation
import Testing
@testable import Fatigue

@MainActor
struct ExerciseStatsTests {
    private let notch = ExerciseSetting(name: "Notch", value: "7", direction: .higher, rangeMin: 1, rangeMax: 10, splitByValue: true)

    private func set(_ weight: String, _ reps: String, notch: Double? = nil, hold: Bool = false) -> WorkoutSet {
        WorkoutSet(setup: SetSetup(kind: hold ? .hold : .reps, values: notch.map { ["Notch": $0] } ?? [:]), weight: weight, amount: reps, previous: "", isDone: true)
    }

    private func workout(day: Double, brand: String? = "Technogym", _ sets: [WorkoutSet]) -> FinishedWorkout {
        FinishedWorkout(title: "Legs", startedAt: Date(timeIntervalSince1970: day * 86_400), duration: 3600, exercises: [
            WorkoutExercise(name: "Adductors", brand: brand, restSeconds: 90, settings: [notch], sets: sets),
        ])
    }

    @Test func eachMetricHasOnePointPerWorkout() {
        let stats = ExerciseStats(name: "Adductors", brand: "Technogym", history: [
            workout(day: 2, [set("60", "6"), set("55", "8")]),
            workout(day: 1, [set("50", "10")]),
        ])
        #expect(stats.points(.setVolume, weighted: false).map(\.value) == [500, 440])
        #expect(stats.points(.sessionVolume, weighted: false).map(\.value) == [500, 800])
        #expect(stats.points(.weight, weighted: false).map(\.value) == [50, 60])
        #expect(stats.points(.oneRepMax, weighted: false).last?.value == 60 * 1.2)
    }

    @Test func brandsAreNeverMixed() {
        let stats = ExerciseStats(name: "Adductors", brand: "Technogym", history: [
            workout(day: 1, [set("50", "10")]), workout(day: 2, brand: "Matrix", [set("90", "10")]),
        ])
        #expect(stats.sessions.count == 1)
        #expect(stats.records().heaviestWeight?.value == 50)
    }

    @Test func holdsHaveNoVolume() {
        let stats = ExerciseStats(name: "Adductors", brand: "Technogym", history: [workout(day: 1, [set("40", "45", hold: true), set("50", "8")])])
        #expect(stats.points(.sessionVolume, weighted: false).map(\.value) == [400])
    }

    @Test func splittingDrawsALinePerValue() {
        let stats = ExerciseStats(name: "Adductors", brand: "Technogym", history: [workout(day: 1, [set("55", "8", notch: 8), set("60", "8")])])
        #expect(stats.seriesNames(splitBy: "Notch") == ["Notch 7", "Notch 8"])
        #expect(stats.points(.setVolume, weighted: false, splitBy: "Notch").map(\.value) == [480, 440])
        #expect(stats.records(splitBy: "Notch", series: "Notch 8").heaviestWeight?.value == 55)
    }

    @Test func theWeightedBestCanBeALighterSetOnAHarderNotch() {
        let stats = ExerciseStats(name: "Adductors", brand: "Technogym", history: [workout(day: 1, [set("55", "8", notch: 10), set("60", "8")])])
        let records = stats.records()
        #expect(records.bestSetVolume?.value == 480)
        #expect(records.weightedSetVolume?.detail == "55 kg × 8 · Notch 10")
    }
}

@MainActor
struct ScoreFactorTests {
    private func exercise(_ settings: [ExerciseSetting], values: [String: Double] = [:]) -> (WorkoutSet, WorkoutExercise) {
        let set = WorkoutSet(setup: SetSetup(kind: .reps, values: values), weight: "57.5", amount: "8", previous: "", isDone: true)
        return (set, WorkoutExercise(name: "Adductors", brand: "Technogym", restSeconds: 90, settings: settings, sets: [set]))
    }

    private let notch = ExerciseSetting(name: "Notch", value: "8", direction: .higher, rangeMin: 1, rangeMax: 10)

    @Test func aDeadStopCountsWithItsFactor() {
        let (set, exercise) = exercise([notch, ExerciseSetting(name: "Dead stop", kind: .yesNo, value: "yes", factor: 1.5)])
        let score = SetScore.score(of: set, in: exercise)!
        #expect(abs(score - 460 * (1 + 7.0 / 9) * 1.5) < 0.001)
    }

    @Test func anOffOrUncountedYesNoSettingIsTimesOne() {
        let (off, exercise) = exercise([ExerciseSetting(name: "Dead stop", kind: .yesNo, value: "no", factor: 1.5)])
        #expect(SetScore.score(of: off, in: exercise) == 460)
        let (on, uncounted) = self.exercise([ExerciseSetting(name: "Dead stop", kind: .yesNo, value: "yes")])
        #expect(SetScore.score(of: on, in: uncounted) == 460)
    }

    @Test func theFactorsAreCappedAtTimesThree() {
        let top = ExerciseSetting(name: "Notch", value: "10", direction: .higher, rangeMin: 1, rangeMax: 10)
        let (set, exercise) = exercise([top, ExerciseSetting(name: "Dead stop", kind: .yesNo, value: "yes", factor: 2)])
        #expect(abs(SetScore.score(of: set, in: exercise)! - 460 * 3) < 0.001)
        #expect(SetScore.factor(of: set, in: exercise) == SetScore.maxFactor)
    }

    @Test func aGroupCanTurnTheDeadStopOff() {
        let (set, exercise) = exercise([ExerciseSetting(name: "Dead stop", kind: .yesNo, value: "yes", factor: 1.5)], values: ["Dead stop": 0])
        #expect(SetScore.score(of: set, in: exercise) == 460)
    }

    @Test func theFinishSummaryListsTheRecordsYouBeat() {
        func workout(_ day: Double, _ weight: String) -> FinishedWorkout {
            FinishedWorkout(title: "Legs", startedAt: Date(timeIntervalSince1970: day * 86_400), duration: 3600, exercises: [
                WorkoutExercise(name: "Leg Press", restSeconds: 90, sets: [WorkoutSet(setup: SetSetup(kind: .reps), weight: weight, amount: "10", previous: "", isDone: true)]),
            ])
        }
        let beaten = ExerciseStats.beaten(by: workout(2, "170"), history: [workout(1, "160")])
        #expect(beaten.map(\.record) == ["Heaviest weight", "Best 1RM", "Best set volume", "Best session volume"])
        #expect(beaten[0].value == "170 kg")
        #expect(ExerciseStats.beaten(by: workout(1, "160"), history: []).isEmpty)
    }
}
