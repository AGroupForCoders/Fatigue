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
        let countBefore = first.history.count
        first.rename(id, title: "Pull, heavy", description: "PB")
        first.deleteFromHistory(first.history[1].id)

        let reopened = store(database)
        #expect(reopened.history.count == countBefore - 1)
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

    @Test func renamingACustomExerciseKeepsOneExerciseWithItsHistory() throws {
        let database = try AppDatabase.inMemory()
        let (workouts, catalog) = try beltSquat(in: database)
        let logged = workouts.history.count { $0.exercises.contains { $0.name == "Belt Squat" } }
        #expect(logged > 0)

        catalog.save(ExerciseInfo(name: "Hip Belt Squat", equipment: .machine, primaryMuscle: .quadriceps, isCustom: true),
                     renamedFrom: "Belt Squat", brand: nil, setup: catalog.setup(for: "Belt Squat", brand: nil))
        workouts.renameExercise(from: "Belt Squat", to: "Hip Belt Squat")

        // Straight away, without a restart.
        #expect(workouts.history.count { $0.exercises.contains { $0.name == "Hip Belt Squat" } } == logged)
        #expect(!workouts.routines.contains { $0.exercises.contains { $0.name == "Belt Squat" } })

        // And after one: the old name is gone from the library, and the history and settings came along.
        let reopenedCatalog = ExerciseCatalog.load(from: database)
        #expect(reopenedCatalog.names.filter { $0.contains("Belt Squat") } == ["Hip Belt Squat"])
        #expect(reopenedCatalog.setup(for: "Hip Belt Squat", brand: nil).settings.map(\.name) == catalog.setup(for: "Hip Belt Squat", brand: nil).settings.map(\.name))
        let reopened = store(database)
        #expect(reopened.history.count { $0.exercises.contains { $0.name == "Hip Belt Squat" } } == logged)
        #expect(!reopened.history.contains { $0.exercises.contains { $0.name == "Belt Squat" } })
        #expect(reopened.routines.contains { $0.exercises.contains { $0.name == "Hip Belt Squat" } })
        let rows = try database.writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM exercise WHERE name LIKE '%Belt Squat'") }
        #expect(rows == 1)
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
        #expect(row.sets.map { $0.previous?.text(in: .kg) } == ["60 × 10 @8", "60 × 10 @8.5", "60 × 10 @9"])
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

    // MARK: Moving history between brands

    /// A workout on Adductors, Hammer Strength, with Seat at 2 and Pad at 3 for the exercise and a hold group at seat 5.
    private func hammerStrengthAdductors(_ settings: [ExerciseSetting], daysAgo: Double = 1) -> FinishedWorkout {
        FinishedWorkout(title: "Legs", startedAt: Date.now.addingTimeInterval(-daysAgo * 86_400), duration: 3600, exercises: [
            WorkoutExercise(name: "Adductors", brand: "Hammer Strength", restSeconds: 90, settings: settings, sets: [
                WorkoutSet(setup: SetSetup(kind: .hold, values: ["Seat": 5]), weight: "30", amount: "40", isDone: true),
                WorkoutSet(setup: SetSetup(kind: .reps), weight: "45", amount: "10", isDone: true),
            ]),
        ])
    }

    /// Sets up Hammer Strength adductors with Seat and Pad, next to the sample Technogym ones, and one workout on it.
    private func addHammerStrength(to database: AppDatabase) throws -> ExerciseCatalog {
        let catalog = ExerciseCatalog.load(from: database)
        let saved = [ExerciseSetting(name: "Seat", value: "2"), ExerciseSetting(name: "Pad", value: "3")]
        catalog.save(ExerciseInfo(name: "Adductors", equipment: .machine, primaryMuscle: .adductors), brand: "Hammer Strength", setup: BrandSetup(settings: saved))
        try database.save(hammerStrengthAdductors(saved).stored)
        return catalog
    }

    @Test func renamingABrandKeepsItsHistorySettingsAndRecords() throws {
        let database = try AppDatabase.inMemory()
        let before = store(database)
        let catalog = ExerciseCatalog.load(from: database)
        before.moveBrand(exercise: "Adductors", from: "Technogym", to: "Technogym Pure")
        catalog.moveBrand(for: "Adductors", from: "Technogym", to: "Technogym Pure")

        let legDay = try #require(before.history.first { $0.title == "Leg day" })
        #expect(legDay.exercises[0].brand == "Technogym Pure")
        #expect(legDay.exercises[0].settings.map(\.name) == ["Seat", "Notch", "Dead stop"])
        #expect(legDay.exercises[0].groups.first?.heading == "Hold · Notch 8")
        #expect(before.routines[0].exercises[0].brand == "Technogym Pure")
        #expect(catalog.setup(for: "Adductors", brand: "Technogym Pure").settings.map(\.name) == ["Seat", "Notch", "Dead stop"])
        #expect(catalog.setup(for: "Adductors", brand: "Technogym").settings.isEmpty)

        let reopened = store(database)
        #expect(reopened.history.first { $0.title == "Leg day" }?.exercises[0].brand == "Technogym Pure")
        #expect(reopened.previousSets(name: "Adductors", brand: "Technogym Pure").count == 3)
        #expect(reopened.previousSets(name: "Adductors", brand: "Technogym").isEmpty)
        #expect(ExerciseStats.brands(for: "Adductors", in: reopened.history) == ["Technogym Pure"])
    }

    @Test func addingABrandToNoBrandHistoryMovesItOntoTheBrand() throws {
        let database = try AppDatabase.inMemory()
        let workouts = store(database)
        #expect(workouts.previousSets(name: "Lat Pulldown", brand: nil).count == 3)
        workouts.moveBrand(exercise: "Lat Pulldown", from: nil, to: "Matrix")

        let reopened = store(database)
        #expect(reopened.previousSets(name: "Lat Pulldown", brand: nil).isEmpty)
        #expect(reopened.previousSets(name: "Lat Pulldown", brand: "Matrix").map(\.weight) == ["65", "65", "65"])
        #expect(KnownBrand.list(for: "Lat Pulldown", history: reopened.history, saved: [], unit: .kg).map(\.brand) == ["Matrix"])
    }

    @Test func mergingBrandsKeepsTheDestinationsSettingWhenBothHaveIt() throws {
        let database = try AppDatabase.inMemory()
        let catalog = try addHammerStrength(to: database)
        let workouts = store(database)
        workouts.moveBrand(exercise: "Adductors", from: "Hammer Strength", to: "Technogym")
        catalog.moveBrand(for: "Adductors", from: "Hammer Strength", to: "Technogym")

        // Technogym's Seat stays as it was, next-time value included; Hammer Strength's is gone.
        let technogym = catalog.setup(for: "Adductors", brand: "Technogym").settings
        #expect(technogym.first { $0.name == "Seat" }?.value == "4")
        #expect(technogym.filter { $0.name == "Seat" }.count == 1)
        #expect(catalog.setup(for: "Adductors", brand: "Hammer Strength").settings.isEmpty)
        #expect(!catalog.brands(for: "Adductors").contains("Hammer Strength"))

        // The moved workout keeps the seat it was done at, and its hold group's override, under Technogym's Seat.
        let moved = try #require(workouts.history.first { $0.title == "Legs" }?.exercises[0])
        #expect(moved.brand == "Technogym")
        #expect(moved.settings.first { $0.name == "Seat" }?.id == technogym.first { $0.name == "Seat" }?.id)
        #expect(moved.settings.first { $0.name == "Seat" }?.value == "2")
        #expect(moved.groups.first?.heading == "Hold · Seat 5")
        #expect(ExerciseStats.brands(for: "Adductors", in: workouts.history) == ["Technogym"])
        #expect(workouts.previousSets(name: "Adductors", brand: "Hammer Strength").isEmpty)
    }

    @Test func mergingBrandsBringsOverSettingsOnlyTheSourceHas() throws {
        let database = try AppDatabase.inMemory()
        // Open the store first, so the sample history (with Leg day) is seeded into the empty database.
        _ = store(database)
        let catalog = try addHammerStrength(to: database)
        let workouts = store(database)
        workouts.moveBrand(exercise: "Adductors", from: "Hammer Strength", to: "Technogym")
        catalog.moveBrand(for: "Adductors", from: "Hammer Strength", to: "Technogym")

        let technogym = catalog.setup(for: "Adductors", brand: "Technogym").settings
        #expect(technogym.map(\.name) == ["Seat", "Notch", "Dead stop", "Pad"])
        #expect(technogym.last?.value == "3")
        let moved = try #require(store(database).history.first { $0.title == "Legs" }?.exercises[0])
        #expect(moved.settings.map(\.name) == ["Seat", "Pad"])
        #expect(moved.settings.last?.value == "3")
        // Untouched by the merge: Leg day was on Technogym already and never had a Pad.
        let legDay = try #require(workouts.history.first { $0.title == "Leg day" })
        #expect(legDay.exercises[0].settings.map(\.name) == ["Seat", "Notch", "Dead stop"])
    }

    @Test func aMergedBrandStartsFreshWhenPickedAgain() throws {
        let database = try AppDatabase.inMemory()
        let catalog = try addHammerStrength(to: database)
        let workouts = store(database)
        workouts.moveBrand(exercise: "Adductors", from: "Hammer Strength", to: "Technogym")
        catalog.moveBrand(for: "Adductors", from: "Hammer Strength", to: "Technogym")
        // Doing it again changes nothing, so the store and catalog can each ask for it.
        workouts.moveBrand(exercise: "Adductors", from: "Hammer Strength", to: "Technogym")
        #expect(workouts.history.filter { $0.title == "Legs" }.count == 1)

        try database.save(hammerStrengthAdductors([ExerciseSetting(name: "Pad", value: "1")], daysAgo: 0).stored)
        let reopened = store(database)
        #expect(reopened.previousSets(name: "Adductors", brand: "Hammer Strength").count == 2)
        #expect(reopened.previousSets(name: "Adductors", brand: "Technogym").count == 2)
        #expect(ExerciseCatalog.load(from: database).setup(for: "Adductors", brand: "Hammer Strength").settings.map(\.name) == ["Pad"])
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
