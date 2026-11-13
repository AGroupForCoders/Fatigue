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

    @Test func aRestoredWorkoutOpensFullScreen() throws {
        let database = try AppDatabase.inMemory()
        let first = store(database)
        first.startEmpty()
        first.isShowingActive = false
        first.saveActive()

        // Relaunching opens the workout, even though it was minimised when the app closed.
        #expect(store(database).isShowingActive)
    }

    @Test func noRunningWorkoutOpensOnTheTabs() throws {
        let database = try AppDatabase.inMemory()
        let reopened = store(database)
        #expect(reopened.active == nil)
        #expect(reopened.isShowingActive == false)
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

    /// A custom "Belt Squat" with a setting, logged in one finished workout and planned in one prebuilt workout.
    private func beltSquat(in database: AppDatabase) throws -> (WorkoutStore, ExerciseCatalog) {
        let workouts = store(database)
        let catalog = ExerciseCatalog.load(from: database)
        catalog.save(ExerciseInfo(name: "Belt Squat", equipment: .machine, primaryMuscle: .quadriceps, isCustom: true), brand: nil,
                     setup: BrandSetup(settings: [ExerciseSetting(name: "Belt", value: "3")]))
        workouts.startEmpty()
        workouts.active?.addExercises(named: ["Belt Squat"], catalog: catalog)
        workouts.active?.exercises[0].sets[0].weight = "80"
        workouts.active?.exercises[0].sets[0].amount = "10"
        workouts.active?.toggle(set: 0, in: 0)
        workouts.finish(title: "Legs")
        var routine = workouts.routines[0]
        routine.exercises.append(.new(named: "Belt Squat"))
        workouts.update(routine)
        return (workouts, catalog)
    }

    @Test func deletingACustomExerciseHidesItAndKeepsItsHistory() throws {
        let database = try AppDatabase.inMemory()
        let (workouts, catalog) = try beltSquat(in: database)
        #expect(workouts.history.count(using: "Belt Squat") == 1)

        #expect(catalog.delete(exerciseNamed: "Belt Squat"))
        workouts.removeFromRoutines(exerciseNamed: "Belt Squat")
        #expect(catalog.info(named: "Belt Squat") == nil)
        #expect(catalog.setup(for: "Belt Squat", brand: nil).settings.isEmpty)

        let reopened = store(database)
        let reopenedCatalog = ExerciseCatalog.load(from: database)
        #expect(!reopenedCatalog.names.contains("Belt Squat"))
        #expect(reopenedCatalog.savedSetups["Belt Squat|"] == nil)
        #expect(!reopened.routines.flatMap(\.exercises).contains { $0.name == "Belt Squat" })
        let legs = try #require(reopened.history.first { $0.title == "Legs" })
        #expect(legs.exercises.map(\.name) == ["Belt Squat"])
        #expect(legs.exercises[0].sets.map(\.weight) == ["80"])
        #expect(legs.exercises[0].settings.map(\.name) == ["Belt"])
    }

    @Test func builtInExercisesCannotBeDeleted() throws {
        let database = try AppDatabase.inMemory()
        let catalog = ExerciseCatalog.load(from: database)
        #expect(!catalog.delete(exerciseNamed: "Adductors"))
        #expect(catalog.info(named: "Adductors") != nil)
        #expect(ExerciseCatalog.load(from: database).setup(for: "Adductors", brand: "Technogym").settings.count == 3)
    }

    @Test func creatingAnExerciseWithADeletedNameBringsItBack() throws {
        let database = try AppDatabase.inMemory()
        let (_, catalog) = try beltSquat(in: database)
        catalog.delete(exerciseNamed: "Belt Squat")
        catalog.save(ExerciseInfo(name: "Belt Squat", equipment: .barbell, primaryMuscle: .quadriceps, isCustom: true), brand: nil,
                     setup: BrandSetup(settings: [ExerciseSetting(name: "Pin", value: "2")]))

        let reopened = ExerciseCatalog.load(from: database)
        #expect(reopened.info(named: "Belt Squat")?.equipment == .barbell)
        #expect(reopened.setup(for: "Belt Squat", brand: nil).settings.map(\.name) == ["Pin"])
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
}
