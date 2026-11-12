import Foundation
import Testing
@testable import Fatigue

@MainActor
struct SettingsTests {
    @Test func aGroupOnlyShowsTheSettingsItChanges() {
        let adductors = WorkoutSession.sample().exercises[0]
        let hold = adductors.sets[0].setup
        #expect(adductors.labels(for: hold) == ["Notch 8"])
        #expect(adductors.labels(for: SetSetup(kind: .reps)) == [])
    }

    @Test func anOverrideThatMatchesTheExerciseIsIgnored() {
        let adductors = WorkoutSession.sample().exercises[0]
        #expect(adductors.labels(for: SetSetup(kind: .reps, values: ["Notch": 7])) == [])
    }

    @Test func yesNoOverridesReadNaturally() {
        let adductors = WorkoutSession.sample().exercises[0]
        #expect(adductors.labels(for: SetSetup(kind: .reps, values: ["Dead stop": 0])) == ["No dead stop"])
    }

    @Test func aSetUsesItsGroupsValueOrTheExercises() {
        let adductors = WorkoutSession.sample().exercises[0]
        let notch = adductors.settings[1]
        #expect(adductors.value(of: notch, in: adductors.sets[0].setup) == 8)
        #expect(adductors.value(of: notch, in: adductors.sets[1].setup) == 7)
    }

    @Test func onlyANumberWithADirectionAndRangeCounts() {
        #expect(ExerciseSetting(name: "Notch", value: "7", direction: .higher, rangeMin: 1, rangeMax: 10).isTracked)
        #expect(!ExerciseSetting(name: "Seat", value: "4").isTracked)
        #expect(!ExerciseSetting(name: "Notch", value: "7", direction: .higher, rangeMin: 10, rangeMax: 1).isTracked)
        #expect(!ExerciseSetting(name: "Grip", kind: .text, value: "wide", direction: .higher, rangeMin: 1, rangeMax: 2).isTracked)
    }

    @Test func renamingASettingKeepsGroupOverrides() {
        let session = WorkoutSession.sample()
        var settings = session.exercises[0].settings
        settings[1].name = "Range"
        session.applyEdit(to: 0, name: "Adductors", settings: settings, renamedSettings: ["Notch": "Range"])
        #expect(session.exercises[0].groups.map(\.heading) == ["Hold · Range 8", "Reps"])
    }

    @Test func settingsAreKeptPerBrand() {
        let catalog = ExerciseCatalog()
        let session = WorkoutSession.sample()
        session.changeBrand(of: 0, to: "Hammer Strength", catalog: catalog)
        #expect(session.exercises[0].settings.isEmpty)
        session.changeBrand(of: 0, to: "Technogym", catalog: catalog)
        #expect(session.exercises[0].settings.map(\.name) == ["Seat", "Notch", "Dead stop"])
    }

    @Test func aCreatedExerciseJoinsTheLibrary() {
        let catalog = ExerciseCatalog()
        catalog.save(ExerciseInfo(name: "Belt Squat", equipment: .machine, primaryMuscle: .quadriceps, isCustom: true), brand: nil, setup: BrandSetup())
        #expect(catalog.names.contains("Belt Squat"))
        #expect(catalog.info(named: "Belt Squat")?.isCustom == true)
    }

    @Test func emptySettingRowsAreDropped() {
        let session = WorkoutSession.sample()
        session.addSetting(to: 1)
        session.removeEmptySettings()
        #expect(session.exercises[1].settings.isEmpty)
    }
}
