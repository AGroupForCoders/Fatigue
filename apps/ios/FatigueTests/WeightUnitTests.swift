import Foundation
import Testing
@testable import Fatigue

@MainActor
struct WeightUnitTests {
    @Test(arguments: ["100", "135", "2.5", "45.5", "0.25", "1000"])
    func aWeightTypedInPoundsComesBackTheSame(typed: String) {
        let stored = WeightUnit.lb.kilogramsText(fromTyped: typed)
        #expect(WeightUnit.lb.text(fromKilogramsText: stored) == typed)
    }

    @Test func whatIsStoredIsKilogramsAtFullPrecision() {
        #expect(WeightUnit.lb.kilogramsText(fromTyped: "100") == "45.359237")
        #expect(WeightUnit.lb.kilograms(from: 1) == 0.45359237)
        #expect(WeightUnit.kg.kilogramsText(fromTyped: "57.5") == "57.5")
    }

    @Test func kilogramsAreLeftAlone() {
        #expect(WeightUnit.kg.text(fromKilogramsText: "57.5") == "57.5")
        #expect(WeightUnit.kg.text(fromKilograms: 60) == "60")
        #expect(WeightUnit.kg.labelled(57.5) == "57.5 kg")
    }

    @Test func storedKilogramsReadInPoundsToTwoDecimals() {
        #expect(WeightUnit.lb.text(fromKilograms: 60) == "132.28")
        #expect(WeightUnit.lb.labelled(45.359237) == "100 lb")
        #expect(WeightUnit.lb.wholeLabelled(4254) == "9,378 lb")
        #expect(WeightUnit.kg.wholeLabelled(4254) == "4,254 kg")
    }

    @Test func nothingTypedStaysUnloaded() {
        #expect(WeightUnit.lb.kilogramsText(fromTyped: "") == "")
        #expect(WeightUnit.lb.kilogramsText(fromTyped: " ") == "")
        #expect(WeightUnit.lb.kilogramsText(fromTyped: "abc") == "")
        #expect(WeightUnit.lb.text(fromKilogramsText: "") == "")
    }

    @Test func halfTypedDecimalsStillConvert() {
        #expect(WeightUnit.lb.kilogramsText(fromTyped: "10.") == WeightUnit.lb.kilogramsText(fromTyped: "10"))
    }

    @Test func previousReadsInThePickedUnit() {
        let previous = PreviousSet(kind: .reps, weightKg: 45.359237, amount: "8", rpe: 8.5)
        #expect(previous.text(in: .lb) == "100 × 8 @8.5")
        #expect(previous.text(in: .kg) == "45.36 × 8 @8.5")
        #expect(PreviousSet(kind: .hold, weightKg: nil, amount: "45").text(in: .lb) == "- × 45s")
    }

    @Test func setsAndRecordsReadInThePickedUnit() {
        let set = WorkoutSet(setup: SetSetup(kind: .reps), weight: "45.359237", amount: "8", isDone: true)
        #expect(ExerciseStats.describe(set, in: .lb) == "100 lb × 8")
        #expect(ExerciseStats.describe(set, in: .kg) == "45.36 kg × 8")

        func workout(_ day: Double, _ weight: String) -> FinishedWorkout {
            FinishedWorkout(title: "Legs", startedAt: Date(timeIntervalSince1970: day * 86_400), duration: 3600, exercises: [
                WorkoutExercise(name: "Leg Press", restSeconds: 90, sets: [WorkoutSet(setup: SetSetup(kind: .reps), weight: weight, amount: "10", isDone: true)]),
            ])
        }
        let beaten = ExerciseStats.beaten(by: workout(2, "100"), history: [workout(1, "90")], in: .lb)
        #expect(beaten[0].value == "220.5 lb")
        #expect(beaten.last?.value == "2,205 lb")
    }
}
