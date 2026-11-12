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
