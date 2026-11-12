import Foundation
import GRDB

/// The SQLite database on the phone. Everything you log lives here, so it survives the app closing.
///
/// Rows follow the data model page: text ids made on the phone, and `updated_at` and `deleted_at`
/// on the tables that will sync. Until sync exists, deletes remove rows outright.
///
/// Reads and writes run synchronously and are small, so the app calls them on the main actor.
/// The model types never cross into GRDB's closures: they're turned into the plain records below first.
nonisolated final class AppDatabase: Sendable {
    let writer: any DatabaseWriter

    init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// The database file in Application Support.
    static func onDisk() throws -> AppDatabase {
        let folder = URL.applicationSupportDirectory
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try AppDatabase(DatabasePool(path: folder.appending(path: "fatigue.sqlite").path(percentEncoded: false)))
    }

    /// An empty database in memory, for tests and previews.
    static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        #if DEBUG
        // Rebuild from scratch when a migration changes during development, instead of failing.
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1") { db in
            try db.create(table: "workout") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("description", .text).notNull().defaults(to: "")
                t.column("started_at", .datetime).notNull()
                t.column("duration_seconds", .double).notNull()
                t.column("routine_id", .text)
                // The running workout is a workout row with is_active set, saved on every change.
                t.column("is_active", .boolean).notNull().defaults(to: false)
                t.column("updated_at", .integer).notNull()
                t.column("deleted_at", .integer)
            }
            try db.create(table: "workout_exercise") { t in
                t.primaryKey("id", .text)
                t.column("workout_id", .text).notNull().indexed().references("workout", onDelete: .cascade)
                t.column("position", .integer).notNull()
                t.column("name", .text).notNull()
                t.column("brand", .text)
                t.column("rest_seconds", .integer).notNull()
                t.column("updated_at", .integer).notNull()
                t.column("deleted_at", .integer)
            }
            try db.create(table: "workout_set") { t in
                t.primaryKey("id", .text)
                t.column("workout_exercise_id", .text).notNull().indexed().references("workout_exercise", onDelete: .cascade)
                t.column("position", .integer).notNull()
                t.column("kind", .text).notNull()
                t.column("weight_kg", .double)
                // Reps for a rep set, seconds for a hold.
                t.column("amount", .double)
                t.column("rpe", .double)
                t.column("is_done", .boolean).notNull()
                t.column("previous", .text).notNull().defaults(to: "")
                t.column("updated_at", .integer).notNull()
                t.column("deleted_at", .integer)
            }
            // A group's override of a setting, such as notch 8 for a hold. Only overrides are stored.
            try db.create(table: "workout_set_value") { t in
                t.column("workout_set_id", .text).notNull().indexed().references("workout_set", onDelete: .cascade)
                t.column("setting_name", .text).notNull()
                t.column("value", .double).notNull()
                t.primaryKey(["workout_set_id", "setting_name"])
            }
            try db.create(table: "exercise_note") { t in
                t.primaryKey("id", .text)
                t.column("workout_exercise_id", .text).notNull().indexed().references("workout_exercise", onDelete: .cascade)
                t.column("position", .integer).notNull()
                t.column("text", .text).notNull()
            }

            try db.create(table: "routine") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("position", .integer).notNull()
                t.column("updated_at", .integer).notNull()
                t.column("deleted_at", .integer)
            }
            try db.create(table: "routine_exercise") { t in
                t.primaryKey("id", .text)
                t.column("routine_id", .text).notNull().indexed().references("routine", onDelete: .cascade)
                t.column("position", .integer).notNull()
                t.column("name", .text).notNull()
                t.column("brand", .text)
                t.column("rest_seconds", .integer).notNull()
            }
            try db.create(table: "routine_set") { t in
                t.primaryKey("id", .text)
                t.column("routine_exercise_id", .text).notNull().indexed().references("routine_exercise", onDelete: .cascade)
                t.column("position", .integer).notNull()
                t.column("kind", .text).notNull()
                t.column("weight_kg", .double)
                t.column("amount", .double)
            }
            try db.create(table: "routine_set_value") { t in
                t.column("routine_set_id", .text).notNull().indexed().references("routine_set", onDelete: .cascade)
                t.column("setting_name", .text).notNull()
                t.column("value", .double).notNull()
                t.primaryKey(["routine_set_id", "setting_name"])
            }

            // Settings belong to a workout exercise, a routine exercise, or an exercise on a brand
            // in the library ("library:Adductors|Technogym"). `owner_id` says which.
            // A setting keeps its id when it's copied from the library into a workout or a prebuilt
            // workout, so the id is only unique within its owner.
            try db.create(table: "setting") { t in
                t.column("id", .text).notNull()
                t.column("owner_id", .text).notNull().indexed()
                t.column("position", .integer).notNull()
                t.column("name", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("value", .text).notNull()
                t.column("direction", .text)
                t.column("range_min", .double)
                t.column("range_max", .double)
                t.column("split_by_value", .boolean).notNull()
                t.primaryKey(["owner_id", "id"])
            }
            // Custom exercises, and any changes to a built-in one's equipment or muscles.
            try db.create(table: "exercise") { t in
                t.primaryKey("name", .text)
                t.column("equipment", .text).notNull()
                t.column("is_builtin", .boolean).notNull()
            }
            try db.create(table: "exercise_muscle") { t in
                t.column("exercise_name", .text).notNull().references("exercise", onDelete: .cascade)
                t.column("muscle", .text).notNull()
                // 1 for the main muscle, 0.5 for the others to start.
                t.column("share", .double).notNull()
                t.primaryKey(["exercise_name", "muscle"])
            }
        }
        return migrator
    }
}

// MARK: - Records

/// Plain rows as stored. Snake case in the database, camel case in Swift.
nonisolated protocol Row: Codable, Sendable, FetchableRecord, PersistableRecord {}

nonisolated extension Row {
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }
}

nonisolated struct WorkoutRow: Row {
    static let databaseTableName = "workout"
    var id: String
    var title: String
    var description: String
    var startedAt: Date
    var durationSeconds: Double
    var routineId: String?
    var isActive: Bool
    var updatedAt: Int64
    var deletedAt: Int64?
}

nonisolated struct WorkoutExerciseRow: Row {
    static let databaseTableName = "workout_exercise"
    var id: String
    var workoutId: String
    var position: Int
    var name: String
    var brand: String?
    var restSeconds: Int
    var updatedAt: Int64
    var deletedAt: Int64?
}

nonisolated struct WorkoutSetRow: Row {
    static let databaseTableName = "workout_set"
    var id: String
    var workoutExerciseId: String
    var position: Int
    var kind: String
    var weightKg: Double?
    var amount: Double?
    var rpe: Double?
    var isDone: Bool
    var previous: String
    var updatedAt: Int64
    var deletedAt: Int64?
}

nonisolated struct SetValueRow: Row, Hashable {
    /// `workout_set_value` or `routine_set_value`; the two tables have the same shape.
    var setId: String
    var settingName: String
    var value: Double
}

nonisolated struct NoteRow: Row {
    static let databaseTableName = "exercise_note"
    var id: String
    var workoutExerciseId: String
    var position: Int
    var text: String
}

nonisolated struct RoutineRow: Row {
    static let databaseTableName = "routine"
    var id: String
    var name: String
    var position: Int
    var updatedAt: Int64
    var deletedAt: Int64?
}

nonisolated struct RoutineExerciseRow: Row {
    static let databaseTableName = "routine_exercise"
    var id: String
    var routineId: String
    var position: Int
    var name: String
    var brand: String?
    var restSeconds: Int
}

nonisolated struct RoutineSetRow: Row {
    static let databaseTableName = "routine_set"
    var id: String
    var routineExerciseId: String
    var position: Int
    var kind: String
    var weightKg: Double?
    var amount: Double?
}

nonisolated struct SettingRow: Row {
    static let databaseTableName = "setting"
    var id: String
    var ownerId: String
    var position: Int
    var name: String
    var kind: String
    var value: String
    var direction: String?
    var rangeMin: Double?
    var rangeMax: Double?
    var splitByValue: Bool
}

nonisolated struct ExerciseRow: Row {
    static let databaseTableName = "exercise"
    var name: String
    var equipment: String
    var isBuiltin: Bool
}

nonisolated struct ExerciseMuscleRow: Row {
    static let databaseTableName = "exercise_muscle"
    var exerciseName: String
    var muscle: String
    var share: Double
}

/// Everything stored for a set of workouts, read or written in one go.
nonisolated struct WorkoutRows: Sendable {
    var workouts: [WorkoutRow] = []
    var exercises: [WorkoutExerciseRow] = []
    var sets: [WorkoutSetRow] = []
    var values: [SetValueRow] = []
    var notes: [NoteRow] = []
    var settings: [SettingRow] = []
}

/// Everything stored for the prebuilt workouts.
nonisolated struct RoutineRows: Sendable {
    var routines: [RoutineRow] = []
    var exercises: [RoutineExerciseRow] = []
    var sets: [RoutineSetRow] = []
    var values: [SetValueRow] = []
    var settings: [SettingRow] = []
}

/// The library's saved exercises and the settings saved per exercise and brand.
nonisolated struct LibraryRows: Sendable {
    var exercises: [ExerciseRow] = []
    var muscles: [ExerciseMuscleRow] = []
    var settings: [SettingRow] = []
}

// MARK: - Reading and writing

nonisolated extension AppDatabase {
    private static var now: Int64 { Int64(Date.now.timeIntervalSince1970 * 1000) }

    /// Every workout, finished and running, with all their rows.
    func workoutRows() throws -> WorkoutRows {
        try writer.read { db in
            let workouts = try WorkoutRow.order(Column("started_at").desc).fetchAll(db)
            let exercises = try WorkoutExerciseRow.order(Column("position")).fetchAll(db)
            let sets = try WorkoutSetRow.order(Column("position")).fetchAll(db)
            let values = try SetValueRow.fetchAll(db, sql: "SELECT workout_set_id AS set_id, setting_name, value FROM workout_set_value")
            let notes = try NoteRow.order(Column("position")).fetchAll(db)
            let exerciseIds = Set(exercises.map(\.id))
            let settings = try SettingRow.order(Column("position")).fetchAll(db).filter { exerciseIds.contains($0.ownerId) }
            return WorkoutRows(workouts: workouts, exercises: exercises, sets: sets, values: values, notes: notes, settings: settings)
        }
    }

    /// Replaces one workout and everything under it.
    func saveWorkout(_ rows: WorkoutRows) throws {
        try writer.write { db in
            for workout in rows.workouts {
                try Self.deleteWorkout(id: workout.id, in: db)
                var workout = workout
                workout.updatedAt = Self.now
                try workout.insert(db)
            }
            for row in rows.exercises { var row = row; row.updatedAt = Self.now; try row.insert(db) }
            for row in rows.sets { var row = row; row.updatedAt = Self.now; try row.insert(db) }
            for row in rows.values {
                try db.execute(sql: "INSERT INTO workout_set_value (workout_set_id, setting_name, value) VALUES (?, ?, ?)", arguments: [row.setId, row.settingName, row.value])
            }
            for row in rows.notes { try row.insert(db) }
            for row in rows.settings { try row.insert(db) }
        }
    }

    func deleteWorkout(id: String) throws {
        try writer.write { db in try Self.deleteWorkout(id: id, in: db) }
    }

    private static func deleteWorkout(id: String, in db: Database) throws {
        // Settings point at their owner by id with no foreign key, so they're removed by hand.
        try db.execute(sql: "DELETE FROM setting WHERE owner_id IN (SELECT id FROM workout_exercise WHERE workout_id = ?)", arguments: [id])
        try db.execute(sql: "DELETE FROM workout WHERE id = ?", arguments: [id])
    }

    func routineRows() throws -> RoutineRows {
        try writer.read { db in
            let exercises = try RoutineExerciseRow.order(Column("position")).fetchAll(db)
            let exerciseIds = Set(exercises.map(\.id))
            return RoutineRows(
                routines: try RoutineRow.order(Column("position")).fetchAll(db),
                exercises: exercises,
                sets: try RoutineSetRow.order(Column("position")).fetchAll(db),
                values: try SetValueRow.fetchAll(db, sql: "SELECT routine_set_id AS set_id, setting_name, value FROM routine_set_value"),
                settings: try SettingRow.order(Column("position")).fetchAll(db).filter { exerciseIds.contains($0.ownerId) }
            )
        }
    }

    /// Replaces every prebuilt workout, keeping their order.
    func saveRoutines(_ rows: RoutineRows) throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM setting WHERE owner_id IN (SELECT id FROM routine_exercise)")
            try db.execute(sql: "DELETE FROM routine")
            for row in rows.routines { var row = row; row.updatedAt = Self.now; try row.insert(db) }
            for row in rows.exercises { try row.insert(db) }
            for row in rows.sets { try row.insert(db) }
            for row in rows.values {
                try db.execute(sql: "INSERT INTO routine_set_value (routine_set_id, setting_name, value) VALUES (?, ?, ?)", arguments: [row.setId, row.settingName, row.value])
            }
            for row in rows.settings { try row.insert(db) }
        }
    }

    func libraryRows() throws -> LibraryRows {
        try writer.read { db in
            LibraryRows(
                exercises: try ExerciseRow.fetchAll(db),
                muscles: try ExerciseMuscleRow.fetchAll(db),
                settings: try SettingRow.filter(Column("owner_id").like("library:%")).order(Column("position")).fetchAll(db)
            )
        }
    }

    /// Replaces the library's saved exercises and settings.
    func saveLibrary(_ rows: LibraryRows) throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM setting WHERE owner_id LIKE 'library:%'")
            try db.execute(sql: "DELETE FROM exercise")
            for row in rows.exercises { try row.insert(db) }
            for row in rows.muscles { try row.insert(db) }
            for row in rows.settings { try row.insert(db) }
        }
    }
}
