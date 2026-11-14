import Foundation
import Testing
@testable import Fatigue

@MainActor
struct SettingsTests {
    @Test func anEverySetSettingShowsAsTheSetsOwnValue() {
        let adductors = WorkoutSession.sample().exercises[0]
        #expect(adductors.everySetSettings.map(\.name) == ["Notch"])
        #expect(adductors.everySetLabels(for: adductors.sets[0]) == ["Notch 8"])
        #expect(adductors.everySetLabels(for: WorkoutSet(setup: SetSetup(kind: .reps), weight: "", amount: "")) == [])
    }

    @Test func aSetHasItsOwnEverySetValueAndTheExercisesForTheRest() {
        let adductors = WorkoutSession.sample().exercises[0]
        let notch = adductors.settings[1]
        let deadStop = adductors.settings[2]
        #expect(adductors.value(of: notch, in: adductors.sets[0].setup) == 8)
        #expect(adductors.value(of: notch, in: adductors.sets[1].setup) == 7)
        // A set from before Notch was typed on every set has none, rather than the exercise's.
        #expect(adductors.value(of: notch, in: SetSetup(kind: .reps)) == nil)
        #expect(adductors.value(of: deadStop, in: SetSetup(kind: .reps)) == 1)
    }

    @Test func onlyATrackedNumberCanBeTypedOnEverySet() {
        #expect(ExerciseSetting(name: "Notch", value: "7", direction: .higher, rangeMin: 1, rangeMax: 10, everySet: true).isMeasure)
        #expect(!ExerciseSetting(name: "Seat", value: "4", everySet: true).isMeasure)
        #expect(!ExerciseSetting(name: "Dead stop", kind: .yesNo, value: "yes", factor: 1.5, everySet: true).isMeasure)
    }

    @Test func anExerciseHasAtMostThreeMeasures() {
        let weightedReps = ExerciseMeasures()
        #expect(weightedReps.count(everySet: 0) == 2)
        #expect(weightedReps.fits(everySet: 1))
        #expect(!weightedReps.fits(everySet: 2))
        let time = ExerciseMeasures(amount: .hold, weighted: false)
        #expect(time.fits(everySet: 2))
        #expect(!time.fits(everySet: 3))
    }

    @Test func measuresReadBackFromTheirNames() {
        #expect(ExerciseMeasures(names: ["weight", "reps"]) == ExerciseMeasures())
        #expect(ExerciseMeasures(names: ["time"]) == ExerciseMeasures(amount: .hold, weighted: false))
        #expect(ExerciseMeasures(names: ["reps", "time"]) == nil)
        #expect(ExerciseMeasures(names: ["weight"]) == nil)
        #expect(ExerciseMeasures(stored: "weight,time")?.names == ["weight", "time"])
    }

    @Test func onlyANumberWithADirectionAndRangeCounts() {
        #expect(ExerciseSetting(name: "Notch", value: "7", direction: .higher, rangeMin: 1, rangeMax: 10).isTracked)
        #expect(!ExerciseSetting(name: "Seat", value: "4").isTracked)
        #expect(!ExerciseSetting(name: "Notch", value: "7", direction: .higher, rangeMin: 10, rangeMax: 1).isTracked)
        #expect(!ExerciseSetting(name: "Grip", kind: .text, value: "wide", direction: .higher, rangeMin: 1, rangeMax: 2).isTracked)
    }

    @Test func renamingASettingKeepsEachSetsValue() {
        let session = WorkoutSession.sample()
        var settings = session.exercises[0].settings
        settings[1].name = "Range"
        session.applyEdit(to: 0, name: "Adductors", settings: settings, renamedSettings: ["Notch": "Range"])
        #expect(session.exercises[0].everySetLabels(for: session.exercises[0].sets[0]) == ["Range 8"])
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

    @Test func settingsReadAsOneLine() {
        var adductors = WorkoutSession.sample().exercises[0]
        // Notch is typed on every set, so it isn't in the line.
        #expect(adductors.settingsSummary == "Seat 4 · Dead stop")
        adductors.settings[2].value = "no"
        adductors.settings.append(ExerciseSetting(name: "Grip"))
        #expect(adductors.settingsSummary == "Seat 4 · No dead stop · Grip")
    }
}
