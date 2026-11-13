import Foundation
import GRDB
import Testing
@testable import Fatigue

@MainActor
struct SyncIDTests {
    private func workout(_ exercise: String, brand: String? = nil) -> StoredWorkout {
        StoredWorkout(
            id: UUID().uuidString, title: "Push", note: nil, startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            finishedAt: Date(timeIntervalSince1970: 1_700_003_600), routineId: nil,
            exercises: [StoredExercise(
                id: UUID().uuidString, name: exercise, brand: brand, restSeconds: 90, settings: [], notes: [],
                sets: [StoredSet(id: UUID().uuidString, kind: "reps", weightKg: 80, reps: 8, completedAt: 1_700_000_100_000, overrides: [:])]
            )]
        )
    }

    private func exerciseId(_ name: String, in database: AppDatabase) throws -> String? {
        try database.writer.read { try String.fetchOne($0, sql: "SELECT id FROM exercise WHERE name = ?", arguments: [name]) }
    }

    private func brandIds(_ exercise: String, brand: String?, in database: AppDatabase) throws -> [String] {
        try database.writer.read {
            try String.fetchAll($0, sql: """
                SELECT eb.id FROM exercise_brand eb JOIN exercise e ON e.id = eb.exercise_id
                WHERE e.name = ? AND eb.brand IS ? AND eb.deleted_at IS NULL
                """, arguments: [exercise, brand])
        }
    }

    @Test func aBuiltIdMatchesThePublishedUUIDv5Example() throws {
        let dns = try #require(UUID(uuidString: "6ba7b810-9dad-11d1-80b4-00c04fd430c8"))
        #expect(SyncID.uuid5("python.org", in: dns).uuidString.lowercased() == "886313e1-3b8a-5372-9b90-0c9aee199e5d")
    }

    @Test func caseAndSurroundingSpacesDoNotChangeAnExercisesId() {
        #expect(SyncID.exercise(named: "Chest Press") == SyncID.exercise(named: "  chest press "))
        #expect(SyncID.exercise(named: "Chest Press") != SyncID.exercise(named: "Leg Press"))
    }

    @Test func twoPhonesGiveTheSameExerciseTheSameId() throws {
        let first = try AppDatabase.inMemory()
        let second = try AppDatabase.inMemory()
        try first.save(workout("Chest Press"))
        try second.save(workout("Chest Press"))

        let id = try #require(try exerciseId("Chest Press", in: first))
        #expect(id == SyncID.exercise(named: "Chest Press"))
        #expect(try exerciseId("Chest Press", in: second) == id)
    }

    @Test func aCustomExerciseSavedFromTheLibraryGetsABuiltId() throws {
        let database = try AppDatabase.inMemory()
        try database.save(StoredLibrary(exercises: [
            StoredExerciseInfo(name: "Sissy Squat", equipment: "bodyweight", isBuiltin: false, muscles: [StoredMuscle(muscle: "quadriceps", share: 1)]),
        ]))
        #expect(try exerciseId("Sissy Squat", in: database) == SyncID.exercise(named: "Sissy Squat"))
    }

    @Test func theNoBrandRowIsTheSameOnTwoPhonesAndANamedBrandIsNot() throws {
        let first = try AppDatabase.inMemory()
        let second = try AppDatabase.inMemory()
        for database in [first, second] {
            try database.save(workout("Chest Press"))
            try database.save(workout("Chest Press", brand: "Technogym"))
        }
        let expected = SyncID.noBrand(exerciseId: SyncID.exercise(named: "Chest Press"))
        #expect(try brandIds("Chest Press", brand: nil, in: first) == [expected])
        #expect(try brandIds("Chest Press", brand: nil, in: second) == [expected])
        #expect(try brandIds("Chest Press", brand: "Technogym", in: first) != brandIds("Chest Press", brand: "Technogym", in: second))
    }

    @Test func movingNoBrandHistoryOntoABrandLeavesTheNoBrandIdFree() throws {
        let database = try AppDatabase.inMemory()
        try database.save(workout("Chest Press"))
        try database.moveBrand(exercise: "Chest Press", from: nil, to: Brand(name: "Technogym"))

        #expect(try brandIds("Chest Press", brand: nil, in: database).isEmpty)
        let technogym = try brandIds("Chest Press", brand: "Technogym", in: database)
        #expect(technogym.count == 1)
        #expect(technogym != [SyncID.noBrand(exerciseId: SyncID.exercise(named: "Chest Press"))])
        #expect(try database.workouts().map { $0.exercises[0].brand } == ["Technogym"])

        // Logging on no brand again takes the built ID back.
        try database.save(workout("Chest Press"))
        #expect(try brandIds("Chest Press", brand: nil, in: database) == [SyncID.noBrand(exerciseId: SyncID.exercise(named: "Chest Press"))])
        #expect(try database.workouts().count == 2)
    }

    @Test func movingABrandsHistoryOntoNoBrandUsesTheBuiltId() throws {
        let database = try AppDatabase.inMemory()
        try database.save(workout("Chest Press", brand: "Technogym"))
        try database.moveBrand(exercise: "Chest Press", from: Brand(name: "Technogym"), to: nil)

        #expect(try brandIds("Chest Press", brand: "Technogym", in: database).isEmpty)
        #expect(try brandIds("Chest Press", brand: nil, in: database) == [SyncID.noBrand(exerciseId: SyncID.exercise(named: "Chest Press"))])
        let saved = try database.workouts()
        #expect(saved.count == 1)
        #expect(saved[0].exercises[0].brand == nil)
        #expect(saved[0].exercises[0].sets.count == 1)
    }

    @Test func rowsMadeBeforeBuiltIdsAreGivenThemAndKeepTheirHistory() throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue, upTo: "v5-workout-gym")
        try queue.write { db in
            try db.execute(sql: "INSERT INTO exercise (id, name, equipment, is_builtin, updated_at) VALUES ('OLD-EX', 'Chest Press', 'machine', 1, 1)")
            try db.execute(sql: "INSERT INTO exercise_muscle (exercise_id, muscle, share) VALUES ('OLD-EX', 'chest', 1)")
            try db.execute(sql: "INSERT INTO exercise_brand (id, exercise_id, brand, label, updated_at) VALUES ('OLD-NONE', 'OLD-EX', NULL, NULL, 1)")
            try db.execute(sql: "INSERT INTO exercise_brand (id, exercise_id, brand, label, updated_at) VALUES ('OLD-TECHNO', 'OLD-EX', 'Technogym', NULL, 1)")
            try db.execute(sql: """
                INSERT INTO setting (id, exercise_brand_id, name, kind, value, position, updated_at) VALUES ('SEAT', 'OLD-NONE', 'Seat', 'number', 4, 0, 1)
                """)
            try db.execute(sql: "INSERT INTO workout (id, title, started_at, finished_at, updated_at) VALUES ('W1', 'Push', 1000, 2000, 1)")
            try db.execute(sql: "INSERT INTO workout_exercise (id, workout_id, exercise_brand_id, position, rest_seconds, updated_at) VALUES ('WE1', 'W1', 'OLD-NONE', 0, 90, 1)")
            try db.execute(sql: "INSERT INTO workout_exercise (id, workout_id, exercise_brand_id, position, rest_seconds, updated_at) VALUES ('WE2', 'W1', 'OLD-TECHNO', 1, 90, 1)")
            try db.execute(sql: "INSERT INTO workout_exercise_setting (workout_exercise_id, setting_id, value) VALUES ('WE1', 'SEAT', 4)")
            try db.execute(sql: "INSERT INTO routine (id, name, position, updated_at) VALUES ('R1', 'Push day', 0, 1)")
            try db.execute(sql: "INSERT INTO routine_exercise (id, routine_id, exercise_brand_id, position, rest_seconds, updated_at) VALUES ('RE1', 'R1', 'OLD-NONE', 0, 90, 1)")
        }

        let database = try AppDatabase(queue)
        let exercise = SyncID.exercise(named: "Chest Press")
        let noBrand = SyncID.noBrand(exerciseId: exercise)
        try database.writer.read { db in
            try #expect(try String.fetchAll(db, sql: "SELECT id FROM exercise") == [exercise])
            try #expect(try String.fetchAll(db, sql: "SELECT exercise_id FROM exercise_muscle") == [exercise])
            try #expect(try String.fetchOne(db, sql: "SELECT id FROM exercise_brand WHERE brand IS NULL") == noBrand)
            // A named brand keeps its ID and follows the exercise.
            try #expect(try String.fetchOne(db, sql: "SELECT exercise_id FROM exercise_brand WHERE id = 'OLD-TECHNO'") == exercise)
            try #expect(try String.fetchOne(db, sql: "SELECT exercise_brand_id FROM setting WHERE id = 'SEAT'") == noBrand)
            try #expect(try String.fetchOne(db, sql: "SELECT exercise_brand_id FROM workout_exercise WHERE id = 'WE1'") == noBrand)
            try #expect(try String.fetchOne(db, sql: "SELECT exercise_brand_id FROM routine_exercise WHERE id = 'RE1'") == noBrand)
        }
        let saved = try #require(try database.workouts().first)
        #expect(saved.exercises.map(\.name) == ["Chest Press", "Chest Press"])
        #expect(saved.exercises.map(\.brand) == [nil, "Technogym"])
        #expect(saved.exercises[0].settings.map(\.name) == ["Seat"])
        #expect(try database.routines().first?.exercises.map(\.name) == ["Chest Press"])
    }
}
