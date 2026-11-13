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

    @Test func theSetsBehindAPointComeWithTheirSums() {
        let stats = ExerciseStats(name: "Adductors", brand: "Technogym", history: [workout(day: 1, [set("55", "8", notch: 10), set("60", "8")])])
        let best = stats.detail(of: .setVolume, weighted: true, at: Date(timeIntervalSince1970: 86_400))
        #expect(best?.value == 880)
        #expect(best?.breakdowns.map(\.text) == ["440 × 2 = 880"])
        let day = stats.detail(of: .sessionVolume, weighted: false, at: Date(timeIntervalSince1970: 86_400))
        #expect(day?.breakdowns.count == 2)
        #expect(stats.detail(of: .weight, weighted: false, at: Date(timeIntervalSince1970: 86_400))?.breakdowns.map(\.set) == ["60 kg × 8"])
        #expect(stats.detail(of: .weight, weighted: false, at: Date(timeIntervalSince1970: 3 * 86_400)) == nil)
    }
}

@MainActor
struct PinnedSettingTests {
    private let notch = ExerciseSetting(name: "Notch", value: "7", direction: .higher, rangeMin: 1, rangeMax: 10)
    private let deadStop = ExerciseSetting(name: "Dead stop", kind: .yesNo, value: "no", factor: 1.5)

    private func set(_ weight: String, _ reps: String, notch: Double? = nil, deadStop: Bool? = nil) -> WorkoutSet {
        var values: [String: Double] = [:]
        if let notch { values["Notch"] = notch }
        if let deadStop { values["Dead stop"] = deadStop ? 1 : 0 }
        return WorkoutSet(setup: SetSetup(kind: .reps, values: values), weight: weight, amount: reps, previous: "", isDone: true)
    }

    private func workout(day: Double, _ sets: [WorkoutSet], settings: [ExerciseSetting]? = nil) -> FinishedWorkout {
        FinishedWorkout(title: "Legs", startedAt: Date(timeIntervalSince1970: day * 86_400), duration: 3600, exercises: [
            WorkoutExercise(name: "Adductors", brand: "Technogym", restSeconds: 90, settings: settings ?? [notch, deadStop], sets: sets),
        ])
    }

    @Test func aPinnedSettingKeepsOnlyTheSetsOnItsLine() {
        let stats = ExerciseStats(name: "Adductors", brand: "Technogym", history: [
            workout(day: 1, [set("50", "10", notch: 8, deadStop: true), set("60", "10", notch: 8), set("70", "10", notch: 7, deadStop: true)]),
        ])
        #expect(stats.filterableSettings(splitBy: "Notch") == ["Dead stop"])
        let pinned = ["Dead stop": "Dead stop"]
        #expect(stats.seriesNames(splitBy: "Notch", pinned: pinned) == ["Notch 7", "Notch 8"])
        #expect(stats.points(.weight, weighted: false, splitBy: "Notch", pinned: pinned).map(\.value) == [70, 50])
        #expect(stats.records(splitBy: "Notch", series: "Notch 8", pinned: pinned).heaviestWeight?.value == 50)
        #expect(stats.records(splitBy: "Notch", series: "Notch 8").heaviestWeight?.value == 60)
        #expect(stats.points(.weight, weighted: false, pinned: ["Dead stop": "No dead stop"]).map(\.value) == [60])
    }

    @Test func aWorkoutWithoutThePinnedSettingIsLeftOut() {
        let stats = ExerciseStats(name: "Adductors", brand: "Technogym", history: [
            workout(day: 1, [set("50", "10")], settings: [notch]),
            workout(day: 2, [set("55", "10", deadStop: true)]),
        ])
        #expect(stats.points(.weight, weighted: false, pinned: ["Dead stop": "Dead stop"]).map(\.value) == [55])
    }

    @Test func theSumNamesEachFactor() {
        let exercise = WorkoutExercise(name: "Adductors", brand: "Technogym", restSeconds: 90, settings: [notch, deadStop], sets: [])
        let sum = ScoreBreakdown(of: set("57.5", "8", notch: 8, deadStop: true), in: exercise)!
        #expect(sum.load == 460)
        #expect(sum.terms.map(\.label) == ["Notch 8", "Dead stop"])
        #expect(sum.terms.map(\.factor).map { ScoreBreakdown.format(factor: $0) } == ["1.78", "1.5"])
        #expect(sum.text == "460 × 1.78 × 1.5 = 1,227")
        #expect(!sum.isCapped)
        let off = ScoreBreakdown(of: set("57.5", "8", notch: 1), in: exercise)!
        #expect(off.terms.map(\.label) == ["Notch 1"])
        #expect(off.text == "460 × 1 = 460")
    }

    @Test func theSumSaysWhenTheFactorsAreCapped() {
        let exercise = WorkoutExercise(name: "Adductors", brand: "Technogym", restSeconds: 90, settings: [
            notch, ExerciseSetting(name: "Dead stop", kind: .yesNo, value: "yes", factor: 2),
        ], sets: [])
        let sum = ScoreBreakdown(of: set("57.5", "8", notch: 10), in: exercise)!
        #expect(sum.isCapped)
        #expect(sum.text == "460 × 2 × 2, capped at ×3 = 1,380")
    }

    @Test func aPointOffersTheYesNoSettingsThatWereOn() {
        let stats = ExerciseStats(name: "Adductors", brand: "Technogym", history: [
            workout(day: 1, [set("50", "10", deadStop: true)], settings: [notch, ExerciseSetting(name: "Dead stop", kind: .yesNo, value: "no")]),
            workout(day: 2, [set("55", "10")]),
        ])
        #expect(stats.detail(of: .setVolume, weighted: true, at: Date(timeIntervalSince1970: 86_400))?.adjustable.map(\.name) == ["Dead stop"])
        #expect(stats.detail(of: .setVolume, weighted: true, at: Date(timeIntervalSince1970: 2 * 86_400))?.adjustable.isEmpty == true)
    }

    @Test func changingAFactorRescoresEveryPastSetOnThatBrand() {
        let history = [
            workout(day: 1, [set("50", "10", deadStop: true)], settings: [deadStop]),
            FinishedWorkout(title: "Legs", startedAt: Date(timeIntervalSince1970: 2 * 86_400), duration: 3600, exercises: [
                WorkoutExercise(name: "Adductors", brand: "Matrix", restSeconds: 90, settings: [deadStop], sets: [set("50", "10", deadStop: true)]),
            ]),
        ]
        let rescored = ExerciseStats.rescored(history, exercise: "Adductors", brand: "Technogym", setting: "Dead stop", factor: 1.25)
        #expect(rescored[0].exercises[0].settings.map(\.factor) == [1.25])
        #expect(rescored[1].exercises[0].settings.map(\.factor) == [1.5])
        let before = ExerciseStats(name: "Adductors", brand: "Technogym", history: history).points(.setVolume, weighted: true).map(\.value)
        let after = ExerciseStats(name: "Adductors", brand: "Technogym", history: rescored).points(.setVolume, weighted: true).map(\.value)
        #expect(before == [750])
        #expect(after == [625])
        let store = WorkoutStore(routines: [], history: history)
        store.setFactor(nil, ofSetting: "Dead stop", exercise: "Adductors", brand: "Technogym")
        #expect(store.history[0].exercises[0].settings[0].factor == nil)
        #expect(store.history[1].exercises[0].settings[0].factor == 1.5)
    }

    @Test func theFinishSummaryNamesTheLineARecordWasOn() {
        let history = [workout(day: 1, [set("50", "10", notch: 8), set("60", "10", notch: 7)])]
        let today = workout(day: 2, [set("55", "10", notch: 8, deadStop: true)])
        let plain = ExerciseStats.beaten(by: today, history: history)
        #expect(plain.map(\.record) == ["Best set volume, weighted"])
        let split = ExerciseStats.beaten(by: today, history: history, splitBy: { $0 == "Adductors" ? "Notch" : nil })
        #expect(split.map(\.record) == [
            "Heaviest weight at notch 8", "Best 1RM at notch 8", "Best set volume at notch 8", "Best session volume at notch 8",
            "Best set volume at notch 8, weighted", "Best session volume at notch 8, weighted",
        ])
        #expect(split[0].value == "55 kg")
        let byDeadStop = ExerciseStats.beaten(by: today, history: history, splitBy: { _ in "Dead stop" })
        #expect(byDeadStop.isEmpty)
        #expect(ExerciseStats.describeLine("No dead stop", of: deadStop) == "with no dead stop")
    }

    @Test func theSplitIsRememberedPerExercise() {
        let defaults = UserDefaults(suiteName: "fatigue-tests-\(UUID())")!
        ExerciseSplit.remember("Notch", for: "Adductors", defaults: defaults)
        #expect(ExerciseSplit.remembered(for: "Adductors", defaults: defaults) == "Notch")
        #expect(ExerciseSplit.remembered(for: "Leg Press", defaults: defaults) == nil)
        ExerciseSplit.remember(nil, for: "Adductors", defaults: defaults)
        #expect(ExerciseSplit.remembered(for: "Adductors", defaults: defaults) == nil)
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
