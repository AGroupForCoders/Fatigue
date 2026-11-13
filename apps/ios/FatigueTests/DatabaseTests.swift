import Foundation
import Testing
@testable import Fatigue

@MainActor
struct DatabaseTests {
    private func store(_ database: AppDatabase) -> WorkoutStore { WorkoutStore(database: database) }

    @Test func aFinishedWorkoutComesBackExactly() throws {
        let database = try AppDatabase.inMemory()
        let original = FinishedWorkout.samples()[2]
        try database.save(original.stored)
        let loaded = FinishedWorkout(stored: try #require(try database.workouts().first))
        #expect(loaded.id == original.id)
        #expect(loaded.title == original.title)
        #expect(loaded.exercises.map(\.name) == original.exercises.map(\.name))
        #expect(loaded.exercises[0].settings == original.exercises[0].settings)
        #expect(loaded.exercises[0].sets.map(\.setup) == original.exercises[0].sets.map(\.setup))
        #expect(loaded.exercises[0].sets.map(\.weight) == original.exercises[0].sets.map(\.weight))
        #expect(loaded.exercises[0].sets.map(\.rpe) == original.exercises[0].sets.map(\.rpe))
        #expect(loaded.volume == original.volume)
    }

    @Test func aRunningWorkoutSurvivesARestart() throws {
        let database = try AppDatabase.inMemory()
        let first = store(database)
        first.start(first.routines[0])
        first.active?.exercises[0].sets[2].weight = "57.5"
        first.active?.toggle(set: 0, in: 0)
        first.active?.exercises[0].notes.append(ExerciseNote(text: "Felt strong"))
        first.saveActive()

        let reopened = store(database)
        let session = try #require(reopened.active)
        #expect(session.id == first.active?.id)
        #expect(session.routineID == first.routines[0].id)
        #expect(session.exercises[0].sets[2].weight == "57.5")
        #expect(session.exercises[0].sets[0].isDone)
        #expect(session.exercises[0].notes.last?.text == "Felt strong")
    }

    @Test func finishingMovesTheWorkoutIntoHistory() throws {
        let database = try AppDatabase.inMemory()
        let first = store(database)
        let historyBefore = first.history.count
        first.start(first.routines[1])
        first.finish(title: "Push", description: "Easy day", unticked: .count)

        let reopened = store(database)
        #expect(reopened.active == nil)
        #expect(reopened.history.count == historyBefore + 1)
        #expect(reopened.history.first?.description == "Easy day")
    }

    @Test func discardingLeavesNothingBehind() throws {
        let database = try AppDatabase.inMemory()
        let first = store(database)
        first.startEmpty()
        first.discard()
        #expect(store(database).active == nil)
    }

    @Test func prebuiltWorkoutsKeepTheirOrderAndSetups() throws {
        let database = try AppDatabase.inMemory()
        let first = store(database)
        var routine = first.routines[0]
        routine.name = "Legs A"
        first.update(routine)
        first.routines.move(fromOffsets: [2], toOffset: 0)

        let reopened = store(database)
        #expect(reopened.routines.map(\.name) == ["Pull", "Legs A", "Push"])
        #expect(reopened.routines[1].exercises[0].sets[0].setup == SetSetup(kind: .hold, values: ["Notch": 8]))
        #expect(reopened.routines[1].exercises[0].settings.map(\.name) == ["Seat", "Notch", "Dead stop"])
    }

    @Test func historyEditsAndDeletesAreSaved() throws {
        let database = try AppDatabase.inMemory()
        let first = store(database)
        let id = first.history[0].id
        first.rename(id, title: "Pull, heavy", description: "PB")
        first.deleteFromHistory(first.history[1].id)

        let reopened = store(database)
        #expect(reopened.history.count == 2)
        #expect(reopened.history[0].title == "Pull, heavy")
    }

    @Test func customExercisesAndSettingsAreSaved() throws {
        let database = try AppDatabase.inMemory()
        let catalog = ExerciseCatalog.load(from: database)
        catalog.save(ExerciseInfo(name: "Belt Squat", equipment: .machine, primaryMuscle: .quadriceps, secondaryMuscles: [.glutes], isCustom: true), brand: nil, setup: BrandSetup(settings: [ExerciseSetting(name: "Belt", value: "3")]))

        let reopened = ExerciseCatalog.load(from: database)
        let info = try #require(reopened.info(named: "Belt Squat"))
        #expect(info.isCustom)
        #expect(info.secondaryMuscles == [.glutes])
        #expect(reopened.setup(for: "Belt Squat", brand: nil).settings.map(\.name) == ["Belt"])
        #expect(reopened.setup(for: "Adductors", brand: "Technogym").settings.map(\.name) == ["Seat", "Notch", "Dead stop"])
    }

    @Test func previousComesFromTheLastTimeOnThatBrand() throws {
        let database = try AppDatabase.inMemory()
        let workouts = store(database)
        workouts.start(workouts.routines[2])
        // The sample Pull history has Seated Row on Life Fitness at 60 × 10 @8, 8.5 and 9.
        let row = try #require(workouts.active?.exercises.first { $0.name == "Seated Row" })
        #expect(row.sets.map(\.previous) == ["60 × 10 @8", "60 × 10 @8.5", "60 × 10 @9"])
    }

    @Test func renamingASettingKeepsItsHistory() throws {
        let database = try AppDatabase.inMemory()
        let workouts = store(database)
        let catalog = ExerciseCatalog.load(from: database)
        var settings = catalog.setup(for: "Adductors", brand: "Technogym").settings
        settings[1].name = "Range"
        catalog.save(ExerciseInfo(name: "Adductors", equipment: .machine, primaryMuscle: .adductors), brand: "Technogym", setup: BrandSetup(settings: settings))

        // The sample Leg day's hold group overrides Notch to 8. It's stored by setting id, so it follows the rename.
        let legDay = try #require(store(database).history.first { $0.title == "Leg day" })
        #expect(legDay.exercises[0].settings.map(\.name) == ["Seat", "Range", "Dead stop"])
        #expect(legDay.exercises[0].groups.first?.heading == "Hold · Range 8")
        _ = workouts
    }

    @Test func savingAnOldWorkoutDoesNotChangeNextTimesValues() throws {
        let database = try AppDatabase.inMemory()
        let workouts = store(database)
        var old = try #require(workouts.history.first { $0.title == "Leg day" })
        old.exercises[0].settings[0].value = "9"
        workouts.replace(old)
        #expect(ExerciseCatalog.load(from: database).setup(for: "Adductors", brand: "Technogym").settings[0].value == "4")
    }

    @Test func aBrandAndLabelPickTheirOwnRow() throws {
        let database = try AppDatabase.inMemory()
        let (plain, labelled, plainAgain) = try database.writer.write { db in
            (try AppDatabase.exerciseBrandId(name: "Adductors", brand: "Technogym", label: nil, in: db),
             try AppDatabase.exerciseBrandId(name: "Adductors", brand: "Technogym", label: "City gym", in: db),
             try AppDatabase.exerciseBrandId(name: "Adductors", brand: "Technogym", label: nil, in: db))
        }
        #expect(plain != labelled)
        // Clearing the label goes back to the row without one.
        #expect(plainAgain == plain)
    }

    @Test func theLabelSurvivesSavingAndLoading() throws {
        let database = try AppDatabase.inMemory()
        let cityGym = Brand(name: "Technogym", label: "City gym")
        let catalog = ExerciseCatalog.load(from: database)
        catalog.save(ExerciseInfo(name: "Adductors", equipment: .machine, primaryMuscle: .adductors), brand: cityGym, setup: BrandSetup(settings: [ExerciseSetting(name: "Pad", value: "2")]))

        var workout = FinishedWorkout.samples()[2]
        workout.exercises[0].brand = cityGym
        workout.exercises[0].settings = []
        try database.save(workout.stored)

        let reopened = ExerciseCatalog.load(from: database)
        #expect(reopened.setup(for: "Adductors", brand: cityGym).settings.map(\.name) == ["Pad"])
        #expect(reopened.setup(for: "Adductors", brand: "Technogym").settings.map(\.name) == ["Seat", "Notch", "Dead stop"])
        let loaded = FinishedWorkout(stored: try #require(try database.workouts().first))
        #expect(loaded.exercises[0].brand == cityGym)
    }
}
