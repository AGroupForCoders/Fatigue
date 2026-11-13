import Foundation
import Testing
@testable import Fatigue

@MainActor
struct BrandTests {
    private func workout(_ daysAgo: Double, brand: Brand?, weight: String, done: Bool = true) -> FinishedWorkout {
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
        #expect(brands.map(\.brand) == ["Technogym", "Hammer Strength"])
        #expect(brands[0].lastSet == "55 × 8")
    }

    @Test func savedBrandsWithNoSetsComeLast() {
        let brands = KnownBrand.list(for: "Adductors", history: [workout(3, brand: nil, weight: "45")], saved: ["Matrix"])
        #expect(brands.map(\.brand) == [nil, "Matrix"])
        #expect(brands[1].lastSet.isEmpty)
    }

    @Test func savingOtherBrandsKeepsEachOnesSettings() {
        let catalog = ExerciseCatalog(setups: [:])
        catalog.save([
            "Technogym": BrandSetup(settings: [ExerciseSetting(name: "Notch", value: "7")]),
            nil: BrandSetup(settings: [ExerciseSetting(name: "Seat", value: "3")]),
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

    @Test func aLabelShowsAfterTheBrandWithAMiddleDot() {
        #expect(Brand(name: "Technogym", label: "City gym")?.display == "Technogym · City gym")
        #expect(Brand(name: "Technogym")?.display == "Technogym")
        #expect(Brand(name: "Technogym", label: "  ")?.label == nil)
        #expect(Brand(name: " Technogym ", label: " City gym ") == Brand(name: "Technogym", label: "City gym"))
    }

    @Test func aLabelAloneIsNoBrand() {
        #expect(Brand(name: nil, label: "City gym") == nil)
        #expect(Brand(name: "", label: "City gym") == nil)
    }

    @Test func aBrandReadsBackFromItsKey() throws {
        let labelled = try #require(Brand(name: "Technogym", label: "City gym"))
        #expect(labelled.key == "Technogym|City gym")
        #expect(Brand(key: labelled.key) == labelled)
        #expect(Brand(key: "Technogym") == "Technogym")
        #expect(Brand(key: "") == nil)
        #expect(ExerciseCatalog.parse(key: ExerciseCatalog.key("Adductors", labelled)) == ("Adductors", labelled))
        #expect(ExerciseCatalog.parse(key: ExerciseCatalog.key("Adductors", nil)) == ("Adductors", nil))
    }

    @Test func theSameBrandWithAnotherLabelIsAnotherBrand() {
        let cityGym = Brand(name: "Technogym", label: "City gym")
        let history = [workout(3, brand: cityGym, weight: "55"), workout(5, brand: "Technogym", weight: "40")]
        let brands = KnownBrand.list(for: "Adductors", history: history, saved: [], now: Date(timeIntervalSince1970: 1_000_000))
        #expect(brands.map(\.brand) == [cityGym, "Technogym"])
        #expect(ExerciseStats(name: "Adductors", brand: cityGym, history: history).sessions.count == 1)
        #expect(ExerciseStats.brands(for: "Adductors", in: history).count == 2)
    }

    @Test func settingsAreKeptPerBrandAndLabel() {
        let catalog = ExerciseCatalog(setups: [:])
        let cityGym = Brand(name: "Technogym", label: "City gym")
        catalog.save(ExerciseInfo(name: "Adductors", equipment: .machine, primaryMuscle: .adductors), brand: cityGym, setup: BrandSetup(settings: [ExerciseSetting(name: "Notch", value: "7")]))
        catalog.save(ExerciseInfo(name: "Adductors", equipment: .machine, primaryMuscle: .adductors), brand: "Technogym", setup: BrandSetup(settings: [ExerciseSetting(name: "Seat", value: "3")]))
        #expect(Set(catalog.brands(for: "Adductors")) == [cityGym!, "Technogym"])
        #expect(catalog.setup(for: "Adductors", brand: cityGym).settings.map(\.name) == ["Notch"])
        #expect(catalog.setup(for: "Adductors", brand: "Technogym").settings.map(\.name) == ["Seat"])
    }
}
