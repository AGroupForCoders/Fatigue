import Foundation
import Testing
@testable import Fatigue

@MainActor
struct HevyImportTests {
    /// Three workouts as Hevy writes them: a quoted description with a comma and a line break, every set type,
    /// a hold, an alias, two names nothing built in matches, and a distance-only set that gets left out.
    static let fixture = """
    title,start_time,end_time,description,exercise_title,superset_id,exercise_notes,set_index,set_type,weight_kg,reps,distance_km,duration_seconds,rpe
    Push,"13 Nov 2025, 07:30","13 Nov 2025, 08:25","Felt good, PR on bench.
    Shoulder a bit tight",Bench Press (Barbell),,"Paused reps, long rest",0,warmup,40,10,,,
    Push,"13 Nov 2025, 07:30","13 Nov 2025, 08:25","Felt good, PR on bench.
    Shoulder a bit tight",Bench Press (Barbell),,"Paused reps, long rest",1,normal,80,5,,,8
    Push,"13 Nov 2025, 07:30","13 Nov 2025, 08:25","Felt good, PR on bench.
    Shoulder a bit tight",Bench Press (Barbell),,"Paused reps, long rest",2,failure,80,4,,,10
    Push,"13 Nov 2025, 07:30","13 Nov 2025, 08:25","Felt good, PR on bench.
    Shoulder a bit tight",Lateral Raise (Dumbbell),,,0,normal,10,12,,,
    Push,"13 Nov 2025, 07:30","13 Nov 2025, 08:25","Felt good, PR on bench.
    Shoulder a bit tight",Lateral Raise (Dumbbell),,,1,dropset,7.5,10,,,9
    Push,"13 Nov 2025, 07:30","13 Nov 2025, 08:25","Felt good, PR on bench.
    Shoulder a bit tight",Plank,,,0,normal,,,,60,
    Pull,"11 Nov 2025, 18:05","11 Nov 2025, 19:00",,Lat Pulldown (Cable),,,0,normal,60,10,,,
    Pull,"11 Nov 2025, 18:05","11 Nov 2025, 19:00",,Lat Pulldown (Cable),,,1,normal,60,10,,,8.5
    Pull,"11 Nov 2025, 18:05","11 Nov 2025, 19:00",,Chin Up (Weighted),,,0,normal,10,6,,,
    Pull,"11 Nov 2025, 18:05","11 Nov 2025, 19:00",,Seated Cable Row,,,0,normal,55,10,,,
    Legs,"9 Nov 2025, 06:45","9 Nov 2025, 07:40",,Walking,,,0,normal,,,1.5,,
    Legs,"9 Nov 2025, 06:45","9 Nov 2025, 07:40",,Squat (Barbell),,,0,normal,100,5,,,8

    """

    static let poundsFixture = """
    title,start_time,end_time,description,exercise_title,superset_id,exercise_notes,set_index,set_type,weight_lbs,reps,distance_miles,duration_seconds,rpe
    Push,"5 Jan 2026, 17:00","5 Jan 2026, 18:00",,Bench Press (Barbell),,,0,normal,135,5,,,
    """

    private func components(_ date: Date) -> (Int, Int, Int, Int, Int) {
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return (c.year!, c.month!, c.day!, c.hour!, c.minute!)
    }

    // MARK: CSV

    @Test func csvHandlesQuotesLineBreaksAndCRLF() {
        let rows = CSV.parse("\u{FEFF}a,b,c\r\n1,\"x, y\",\"say \"\"hi\"\"\"\r\n2,\"two\nlines\",\r\n")
        #expect(rows == [["a", "b", "c"], ["1", "x, y", "say \"hi\""], ["2", "two\nlines", ""]])
    }

    @Test func csvFieldsAreQuotedOnlyWhenTheyNeedIt() {
        #expect(CSV.line(["Push", "Felt good, PR", "say \"hi\"", "two\nlines", "80"]) == "Push,\"Felt good, PR\",\"say \"\"hi\"\"\",\"two\nlines\",80")
        #expect(CSV.parse(CSV.line(["a,b", "c\"d", "e\nf"])) == [["a,b", "c\"d", "e\nf"]])
    }

    // MARK: Parsing

    @Test func parsesWorkoutsExercisesAndSets() throws {
        let workouts = try HevyImport.parse(Self.fixture)
        #expect(workouts.map(\.title) == ["Push", "Pull", "Legs"])

        let push = workouts[0]
        #expect(components(push.startedAt) == (2025, 11, 13, 7, 30))
        #expect(push.finishedAt.timeIntervalSince(push.startedAt) == 55 * 60)
        #expect(push.description == "Felt good, PR on bench.\nShoulder a bit tight")
        #expect(push.exercises.map(\.title) == ["Bench Press (Barbell)", "Lateral Raise (Dumbbell)", "Plank"])
        #expect(push.exercises[0].notes == "Paused reps, long rest")
        #expect(push.exercises[0].sets.map(\.weightKg) == [40, 80, 80])
        #expect(push.exercises[0].sets.map(\.reps) == [10, 5, 4])
        #expect(push.exercises[0].sets.map(\.rpe) == [nil, 8, 10])

        let legs = workouts[2]
        #expect(components(legs.startedAt) == (2025, 11, 9, 6, 45))
        // Walking only had a distance, so it's gone.
        #expect(legs.exercises.map(\.title) == ["Squat (Barbell)"])
    }

    @Test func everySetTypeAndKindComesThrough() throws {
        let push = try HevyImport.parse(Self.fixture)[0]
        #expect(push.exercises[0].sets.map(\.type) == ["warmup", "normal", "failure"])
        #expect(push.exercises[1].sets.map(\.type) == ["normal", "drop"])
        let plank = push.exercises[2].sets[0]
        #expect(plank.kind == "hold")
        #expect(plank.durationSeconds == 60)
        #expect(plank.reps == nil)
        #expect(plank.weightKg == nil)
    }

    @Test func poundsAreStoredAsKilograms() throws {
        let workouts = try HevyImport.parse(Self.poundsFixture)
        #expect(workouts[0].exercises[0].sets[0].weightKg == 61.23)
    }

    @Test func aFileThatIsNotFromHevyIsRefused() {
        #expect(throws: HevyImportError.missingColumns(["start_time", "exercise_title", "set_index"])) {
            try HevyImport.parse("title,date\nPush,2025")
        }
        #expect(throws: HevyImportError.empty) { try HevyImport.parse("") }
    }

    @Test func theSameWorkoutAlwaysGetsTheSameId() throws {
        let first = try HevyImport.parse(Self.fixture)[0]
        let again = try HevyImport.parse(Self.fixture)[0]
        #expect(first.id == again.id)
        #expect(first.stored(exerciseName: { $0 }).exercises[0].sets[1].id == again.stored(exerciseName: { $0 }).exercises[0].sets[1].id)
        let pull = try HevyImport.parse(Self.fixture)[1]
        #expect(first.id != pull.id)
    }

    // MARK: Matching

    @Test func hevyNamesMatchBuiltInExercises() {
        let names = ExerciseCatalog().names
        #expect(HevyExerciseMatcher.match("Bench Press (Barbell)", among: names) == "Bench Press")
        #expect(HevyExerciseMatcher.match("bench press", among: names) == "Bench Press")
        #expect(HevyExerciseMatcher.match("Lat Pulldown (Cable)", among: names) == "Lat Pulldown")
        #expect(HevyExerciseMatcher.match("Seated Cable Row", among: names) == "Seated Row")
        #expect(HevyExerciseMatcher.match("Lying Leg Curl (Machine)", among: names) == "Leg Curl")
        #expect(HevyExerciseMatcher.match("Incline Bench Press (Dumbbell)", among: names) == "Incline Dumbbell Press")
        #expect(HevyExerciseMatcher.match("Chin Up (Weighted)", among: names) == nil)
        #expect(HevyExerciseMatcher.match("Plank", among: names) == nil)
    }

    @Test func aCustomExerciseFromAnEarlierImportMatchesAgain() {
        let names = ExerciseCatalog().names + ["Chin Up (Weighted)"]
        #expect(HevyExerciseMatcher.match("Chin Up (Weighted)", among: names) == "Chin Up (Weighted)")
    }

    @Test func unmatchedNamesGetKitAndAMuscleFromTheirWords() {
        let chinUp = HevyExerciseMatcher.customExercise(named: "Chin Up (Weighted)")
        #expect(chinUp.isCustom)
        #expect(chinUp.equipment == .bodyweight)
        #expect(chinUp.primaryMuscle == .lats)
        #expect(HevyExerciseMatcher.customExercise(named: "Hammer Curl (Dumbbell)").primaryMuscle == .biceps)
        #expect(HevyExerciseMatcher.customExercise(named: "Plank").primaryMuscle == .abdominals)
        #expect(HevyExerciseMatcher.customExercise(named: "Front Squat (Barbell)").equipment == .barbell)
    }

    // MARK: Importing

    @Test func importingPutsWorkoutsInHistoryAndAddsCustomExercises() throws {
        let store = WorkoutStore(history: [])
        let catalog = ExerciseCatalog()
        let result = try store.importHevy(csv: Self.fixture, catalog: catalog)
        #expect(result == HevyImportResult(imported: 3, alreadyThere: 0, newExercises: ["Plank", "Chin Up (Weighted)"]))
        #expect(store.history.map(\.title) == ["Push", "Pull", "Legs"])

        let push = store.history[0]
        #expect(components(push.startedAt) == (2025, 11, 13, 7, 30))
        #expect(push.duration == 55 * 60)
        #expect(push.description == "Felt good, PR on bench.\nShoulder a bit tight")
        #expect(push.exercises.map(\.name) == ["Bench Press", "Lateral Raise", "Plank"])
        #expect(push.exercises[0].sets.map(\.weight) == ["40", "80", "80"])
        #expect(push.exercises[0].sets.map(\.amount) == ["10", "5", "4"])
        let allTicked = push.exercises[0].sets.allSatisfy(\.isDone)
        #expect(allTicked)
        #expect(push.exercises[0].notes.map(\.text) == ["Paused reps, long rest"])
        #expect(push.exercises[1].sets.map(\.weight) == ["10", "7.5"])
        #expect(push.exercises[2].sets[0].kind == .hold)
        #expect(push.exercises[2].sets[0].amount == "60")
        #expect(store.history[1].exercises.map(\.name) == ["Lat Pulldown", "Chin Up (Weighted)", "Seated Row"])
        #expect(catalog.info(named: "Plank")?.isCustom == true)
        #expect(catalog.info(named: "Chin Up (Weighted)")?.isCustom == true)
    }

    @Test func importingTheSameFileTwiceAddsNothing() throws {
        let store = WorkoutStore()
        let catalog = ExerciseCatalog()
        let before = store.history.count
        try store.importHevy(csv: Self.fixture, catalog: catalog)
        let exercisesAfterFirst = catalog.names
        let again = try store.importHevy(csv: Self.fixture, catalog: catalog)
        #expect(again == HevyImportResult(imported: 0, alreadyThere: 3, newExercises: []))
        #expect(store.history.count == before + 3)
        #expect(catalog.names == exercisesAfterFirst)
    }

    @Test func importedWorkoutsSurviveARestartAndAreNotImportedAgain() throws {
        let database = try AppDatabase.inMemory()
        let first = WorkoutStore(database: database)
        let before = first.history.count
        try first.importHevy(csv: Self.fixture, catalog: ExerciseCatalog.load(from: database))

        let reopened = WorkoutStore(database: database)
        #expect(reopened.history.count == before + 3)
        let push = try #require(reopened.history.first { $0.title == "Push" && $0.exercises.first?.name == "Bench Press" })
        #expect(push.exercises[0].sets.map(\.weight) == ["40", "80", "80"])
        #expect(ExerciseCatalog.load(from: database).info(named: "Plank")?.isCustom == true)

        let stored = try #require(try database.workouts().first { $0.id == push.id.uuidString })
        #expect(stored.importKey == "hevy|13 Nov 2025, 07:30|Push")
        #expect(stored.exercises[0].sets.map(\.setType) == ["warmup", "normal", "failure"])

        let again = try reopened.importHevy(csv: Self.fixture, catalog: ExerciseCatalog.load(from: database))
        #expect(again.imported == 0)
        #expect(again.alreadyThere == 3)
        #expect(try database.workouts().count == before + 3)
    }

    @Test func editingAnImportedWorkoutKeepsWhereItCameFrom() throws {
        let database = try AppDatabase.inMemory()
        let store = WorkoutStore(database: database)
        try store.importHevy(csv: Self.fixture, catalog: ExerciseCatalog.load(from: database))
        let push = try #require(store.history.first { $0.title == "Push" && $0.exercises.first?.name == "Bench Press" })
        store.rename(push.id, title: "Push, heavy", description: "")
        let stored = try #require(try database.workouts().first { $0.id == push.id.uuidString })
        #expect(stored.title == "Push, heavy")
        #expect(stored.importKey == "hevy|13 Nov 2025, 07:30|Push")
    }
}
