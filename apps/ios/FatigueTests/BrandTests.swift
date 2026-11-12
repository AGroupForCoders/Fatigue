import Foundation
import Testing
@testable import Fatigue

@MainActor
struct BrandTests {
    private func workout(_ daysAgo: Double, brand: String?, weight: String, done: Bool = true) -> FinishedWorkout {
        FinishedWorkout(
            title: "Legs", startedAt: Date(timeIntervalSince1970: 1_000_000 - daysAgo * 86_400), duration: 3600,
            exercises: [WorkoutExercise(name: "Adductors", brand: brand, restSeconds: 90, sets: [
                WorkoutSet(setup: SetSetup(kind: .reps), weight: weight, amount: "8", previous: "", isDone: done),
            ])]
        )
    }

    @Test func brandsComeNewestFirstWithTheLastSetOnEach() {
        let history = [workout(14, brand: "Hammer Strength", weight: "50"), workout(3, brand: "Technogym", weight: "55"), workout(20, brand: "Technogym", weight: "40")]
        let brands = KnownBrand.list(for: "Adductors", history: history, saved: [], now: Date(timeIntervalSince1970: 1_000_000))
        #expect(brands.map(\.name) == ["Technogym", "Hammer Strength"])
        #expect(brands[0].lastSet == "55 × 8")
    }

    @Test func savedBrandsWithNoSetsComeLast() {
        let brands = KnownBrand.list(for: "Adductors", history: [workout(3, brand: nil, weight: "45")], saved: ["Matrix"])
        #expect(brands.map(\.name) == [nil, "Matrix"])
        #expect(brands[1].lastSet.isEmpty)
    }

    @Test func savingOtherBrandsKeepsEachOnesSettings() {
        let catalog = ExerciseCatalog(setups: [:])
        catalog.save([
            "Technogym": BrandSetup(settings: [ExerciseSetting(name: "Notch", value: "7")]),
            "": BrandSetup(settings: [ExerciseSetting(name: "Seat", value: "3")]),
        ], for: "Adductors")
        #expect(catalog.brands(for: "Adductors") == ["Technogym"])
        #expect(catalog.setup(for: "Adductors", brand: "Technogym").settings.map(\.name) == ["Notch"])
        #expect(catalog.setup(for: "Adductors", brand: nil).settings.map(\.name) == ["Seat"])
    }

    @Test func aCreatedExerciseStartsOnItsBrand() {
        let catalog = ExerciseCatalog(setups: ["Hip Abductor|Matrix": BrandSetup(settings: [ExerciseSetting(name: "Pad", value: "2")])])
        let session = WorkoutSession(title: "Legs", exercises: [], startedAt: .now)
        session.addExercises(named: ["Hip Abductor"], brands: ["Hip Abductor": "Matrix"], catalog: catalog)
        #expect(session.exercises[0].brand == "Matrix")
        #expect(session.exercises[0].settings.map(\.name) == ["Pad"])
    }
}
