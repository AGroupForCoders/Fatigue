import Foundation
import GRDB

/// The SQLite database on the phone. Everything you log lives here, so it survives the app closing.
///
/// The tables follow the data model page:
/// - an exercise on a brand (`exercise_brand`) owns its settings (`setting`), and their values there
///   are what's filled in next time;
/// - a workout stores the value each setting had for the whole exercise (`workout_exercise_setting`)
///   and what a group of sets changed (`workout_set_override`), both by setting id, so renaming a
///   setting keeps its history;
/// - prebuilt workouts mirror that with `routine_*` tables.
///
/// The app's model never crosses into GRDB's closures. It's turned into the plain `Stored*` values
/// below first (see Mapping.swift), and those are what get read and written.
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
            // Synced tables carry updated_at and deleted_at, as the data model page says.
            func synced(_ t: TableDefinition) {
                t.column("updated_at", .integer).notNull().defaults(to: 0)
                t.column("deleted_at", .integer)
            }
            func parent(_ t: TableDefinition, _ table: String) {
                t.column("\(table)_id", .text).notNull().indexed().references(table, onDelete: .cascade)
            }

            try db.create(table: "exercise") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull().unique()
                t.column("equipment", .text).notNull()
                t.column("is_builtin", .boolean).notNull()
                synced(t)
            }
            try db.create(table: "exercise_muscle") { t in
                parent(t, "exercise")
                t.column("muscle", .text).notNull()
                t.column("share", .double).notNull()
                t.primaryKey(["exercise_id", "muscle"])
            }
            try db.create(table: "exercise_brand") { t in
                t.primaryKey("id", .text)
                parent(t, "exercise")
                t.column("brand", .text)
                t.column("label", .text)
                synced(t)
            }
            try db.create(table: "setting") { t in
                t.primaryKey("id", .text)
                parent(t, "exercise_brand")
                t.column("name", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("value", .double)
                t.column("text_value", .text)
                t.column("direction", .text)
                t.column("range_min", .double)
                t.column("range_max", .double)
                t.column("split_by_value", .boolean).notNull().defaults(to: false)
                t.column("position", .double).notNull()
                synced(t)
            }

            try db.create(table: "workout") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("note", .text)
                t.column("started_at", .integer).notNull()
                // Empty while the workout is running.
                t.column("finished_at", .integer)
                t.column("routine_id", .text)
                synced(t)
            }
            try db.create(table: "workout_exercise") { t in
                t.primaryKey("id", .text)
                parent(t, "workout")
                t.column("exercise_brand_id", .text).notNull().references("exercise_brand")
                t.column("position", .double).notNull()
                t.column("rest_seconds", .integer).notNull()
                synced(t)
            }
            // The app allows several notes per exercise, so they get rows of their own.
            try db.create(table: "workout_exercise_note") { t in
                t.primaryKey("id", .text)
                parent(t, "workout_exercise")
                t.column("position", .double).notNull()
                t.column("text", .text).notNull()
            }
            try db.create(table: "workout_exercise_setting") { t in
                parent(t, "workout_exercise")
                t.column("setting_id", .text).notNull().references("setting")
                t.column("value", .double)
                t.column("text_value", .text)
                t.primaryKey(["workout_exercise_id", "setting_id"])
            }
            try db.create(table: "workout_set") { t in
                t.primaryKey("id", .text)
                parent(t, "workout_exercise")
                t.column("position", .double).notNull()
                t.column("kind", .text).notNull()
                t.column("set_type", .text).notNull().defaults(to: "normal")
                t.column("weight_kg", .double)
                t.column("reps", .integer)
                t.column("duration_seconds", .integer)
                t.column("rpe", .double)
                t.column("completed_at", .integer)
                synced(t)
            }
            try db.create(table: "workout_set_override") { t in
                parent(t, "workout_set")
                t.column("setting_id", .text).notNull().references("setting")
                t.column("value", .double).notNull()
                t.primaryKey(["workout_set_id", "setting_id"])
            }

            try db.create(table: "routine") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("position", .double).notNull()
                synced(t)
            }
            try db.create(table: "routine_exercise") { t in
                t.primaryKey("id", .text)
                parent(t, "routine")
                t.column("exercise_brand_id", .text).notNull().references("exercise_brand")
                t.column("position", .double).notNull()
                t.column("rest_seconds", .integer).notNull()
                synced(t)
            }
            try db.create(table: "routine_exercise_setting") { t in
                parent(t, "routine_exercise")
                t.column("setting_id", .text).notNull().references("setting")
                t.column("value", .double)
                t.column("text_value", .text)
                t.primaryKey(["routine_exercise_id", "setting_id"])
            }
            try db.create(table: "routine_set") { t in
                t.primaryKey("id", .text)
                parent(t, "routine_exercise")
                t.column("position", .double).notNull()
                t.column("kind", .text).notNull()
                t.column("set_type", .text).notNull().defaults(to: "normal")
                t.column("weight_kg", .double)
                t.column("reps", .integer)
                t.column("duration_seconds", .integer)
                synced(t)
            }
            try db.create(table: "routine_set_override") { t in
                parent(t, "routine_set")
                t.column("setting_id", .text).notNull().references("setting")
                t.column("value", .double).notNull()
                t.primaryKey(["routine_set_id", "setting_id"])
            }
        }
        // How much harder a yes/no setting makes a set when it's on (ADR 0002). Null until you say it does.
        migrator.registerMigration("v2-setting-factor") { db in
            try db.alter(table: "setting") { t in t.add(column: "factor", .double) }
        }
        return migrator
    }
}

// MARK: - What's stored, without the app's model types

/// A setting with the value it has in one place: the library's next-time value, a workout's, or a routine's.
nonisolated struct StoredSetting: Sendable, Equatable {
    var id: String
    var name: String
    var kind: String
    var value: Double?
    var textValue: String?
    var direction: String?
    var rangeMin: Double?
    var rangeMax: Double?
    var splitByValue: Bool
    var factor: Double? = nil
}

nonisolated struct StoredSet: Sendable {
    var id: String
    var kind: String
    var weightKg: Double?
    var reps: Int?
    var durationSeconds: Int?
    var rpe: Double?
    var completedAt: Int64?
    /// Setting id to the value this set's group changes it to.
    var overrides: [String: Double]
}

nonisolated struct StoredNote: Sendable {
    var id: String
    var text: String
}

nonisolated struct StoredExercise: Sendable {
    var id: String
    var name: String
    var brand: String?
    var restSeconds: Int
    var settings: [StoredSetting]
    var notes: [StoredNote]
    var sets: [StoredSet]
}

nonisolated struct StoredWorkout: Sendable {
    var id: String
    var title: String
    var note: String?
    var startedAt: Date
    /// Nil while it's running.
    var finishedAt: Date?
    var routineId: String?
    var exercises: [StoredExercise]
}

nonisolated struct StoredRoutine: Sendable {
    var id: String
    var name: String
    var exercises: [StoredExercise]
}

nonisolated struct StoredMuscle: Sendable {
    var muscle: String
    var share: Double
}

nonisolated struct StoredExerciseInfo: Sendable {
    var name: String
    var equipment: String
    var isBuiltin: Bool
    var muscles: [StoredMuscle]
}

nonisolated struct StoredSetup: Sendable {
    var name: String
    var brand: String?
    /// With their next-time values.
    var settings: [StoredSetting]
}

nonisolated struct StoredLibrary: Sendable {
    var exercises: [StoredExerciseInfo] = []
    var setups: [StoredSetup] = []
}

// MARK: - Reading and writing

nonisolated extension AppDatabase {
    private static var now: Int64 { Int64(Date.now.timeIntervalSince1970 * 1000) }
    private static func millis(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1000).rounded()) }
    private static func date(_ millis: Int64) -> Date { Date(timeIntervalSince1970: Double(millis) / 1000) }

    // MARK: Exercises, brands and settings

    /// The id of an exercise on a brand, adding the exercise and the brand the first time.
    private static func exerciseBrandId(name: String, brand: String?, in db: Database) throws -> String {
        let exerciseId: String
        if let id = try String.fetchOne(db, sql: "SELECT id FROM exercise WHERE name = ?", arguments: [name]) {
            exerciseId = id
        } else {
            exerciseId = UUID().uuidString
            try db.execute(sql: "INSERT INTO exercise (id, name, equipment, is_builtin, updated_at) VALUES (?, ?, 'other', ?, ?)",
                           arguments: [exerciseId, name, ExerciseCatalogNames.builtIn.contains(name), now])
        }
        if let id = try String.fetchOne(db, sql: "SELECT id FROM exercise_brand WHERE exercise_id = ? AND brand IS ?", arguments: [exerciseId, brand]) {
            return id
        }
        let id = UUID().uuidString
        try db.execute(sql: "INSERT INTO exercise_brand (id, exercise_id, brand, updated_at) VALUES (?, ?, ?, ?)", arguments: [id, exerciseId, brand, now])
        return id
    }

    /// Adds a setting or updates its definition. Its next-time value is only written when `withValue` is set,
    /// so saving an old workout never overwrites what's filled in next time.
    private static func upsert(_ setting: StoredSetting, exerciseBrandId: String, position: Int, withValue: Bool, in db: Database) throws {
        try db.execute(sql: """
            INSERT INTO setting (id, exercise_brand_id, name, kind, value, text_value, direction, range_min, range_max, split_by_value, factor, position, updated_at, deleted_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)
            ON CONFLICT(id) DO UPDATE SET
                exercise_brand_id = excluded.exercise_brand_id, name = excluded.name, kind = excluded.kind,
                direction = excluded.direction, range_min = excluded.range_min, range_max = excluded.range_max,
                split_by_value = excluded.split_by_value, factor = excluded.factor, position = excluded.position, updated_at = excluded.updated_at,
                deleted_at = NULL\(withValue ? ", value = excluded.value, text_value = excluded.text_value" : "")
            """, arguments: [setting.id, exerciseBrandId, setting.name, setting.kind, setting.value, setting.textValue,
                             setting.direction, setting.rangeMin, setting.rangeMax, setting.splitByValue, setting.factor, position, now])
    }

    private static func settings(_ sql: String, owner: String, in db: Database) throws -> [StoredSetting] {
        try Row.fetchAll(db, sql: sql, arguments: [owner]).map { row in
            StoredSetting(
                id: row["id"], name: row["name"], kind: row["kind"], value: row["value"], textValue: row["text_value"],
                direction: row["direction"], rangeMin: row["range_min"], rangeMax: row["range_max"], splitByValue: row["split_by_value"],
                factor: row["factor"]
            )
        }
    }

    private static func overrides(_ sql: String, _ owner: String, in db: Database) throws -> [String: Double] {
        let rows = try Row.fetchAll(db, sql: sql, arguments: [owner])
        return Dictionary(rows.map { ($0["setting_id"] as String, $0["value"] as Double) }, uniquingKeysWith: { a, _ in a })
    }

    private static func sets(_ sql: String, owner: String, overrideSQL: String, in db: Database) throws -> [StoredSet] {
        try Row.fetchAll(db, sql: sql, arguments: [owner]).map { set in
            let setId: String = set["id"]
            return StoredSet(
                id: setId, kind: set["kind"], weightKg: set["weight_kg"], reps: set["reps"], durationSeconds: set["duration_seconds"],
                rpe: set["rpe"], completedAt: set["completed_at"], overrides: try overrides(overrideSQL, setId, in: db)
            )
        }
    }

    // MARK: Workouts

    /// Every workout, finished and running, newest first.
    func workouts() throws -> [StoredWorkout] {
        try writer.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM workout WHERE deleted_at IS NULL ORDER BY started_at DESC").map { row in
                let id: String = row["id"]
                let finished: Int64? = row["finished_at"]
                return StoredWorkout(
                    id: id, title: row["title"], note: row["note"], startedAt: Self.date(row["started_at"]),
                    finishedAt: finished.map(Self.date), routineId: row["routine_id"],
                    exercises: try Self.workoutExercises(of: id, in: db)
                )
            }
        }
    }

    private static func workoutExercises(of workoutId: String, in db: Database) throws -> [StoredExercise] {
        try Row.fetchAll(db, sql: """
            SELECT we.id, we.rest_seconds, e.name, eb.brand FROM workout_exercise we
            JOIN exercise_brand eb ON eb.id = we.exercise_brand_id JOIN exercise e ON e.id = eb.exercise_id
            WHERE we.workout_id = ? AND we.deleted_at IS NULL ORDER BY we.position
            """, arguments: [workoutId]).map { row in
            let id: String = row["id"]
            return StoredExercise(
                id: id, name: row["name"], brand: row["brand"], restSeconds: row["rest_seconds"],
                settings: try settings("""
                    SELECT s.id, s.name, s.kind, ws.value, ws.text_value, s.direction, s.range_min, s.range_max, s.split_by_value, s.factor
                    FROM workout_exercise_setting ws JOIN setting s ON s.id = ws.setting_id
                    WHERE ws.workout_exercise_id = ? ORDER BY s.position
                    """, owner: id, in: db),
                notes: try Row.fetchAll(db, sql: "SELECT id, text FROM workout_exercise_note WHERE workout_exercise_id = ? ORDER BY position", arguments: [id])
                    .map { StoredNote(id: $0["id"], text: $0["text"]) },
                sets: try sets("SELECT * FROM workout_set WHERE workout_exercise_id = ? AND deleted_at IS NULL ORDER BY position", owner: id,
                               overrideSQL: "SELECT setting_id, value FROM workout_set_override WHERE workout_set_id = ?", in: db)
            )
        }
    }

    /// Replaces one workout and everything under it.
    func save(_ workout: StoredWorkout) throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM workout WHERE id = ?", arguments: [workout.id])
            try db.execute(sql: "INSERT INTO workout (id, title, note, started_at, finished_at, routine_id, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
                           arguments: [workout.id, workout.title, workout.note, Self.millis(workout.startedAt), workout.finishedAt.map(Self.millis), workout.routineId, Self.now])
            for (position, exercise) in workout.exercises.enumerated() {
                let brandId = try Self.exerciseBrandId(name: exercise.name, brand: exercise.brand, in: db)
                try db.execute(sql: "INSERT INTO workout_exercise (id, workout_id, exercise_brand_id, position, rest_seconds, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
                               arguments: [exercise.id, workout.id, brandId, position, exercise.restSeconds, Self.now])
                for (index, setting) in exercise.settings.enumerated() {
                    try Self.upsert(setting, exerciseBrandId: brandId, position: index, withValue: false, in: db)
                    try db.execute(sql: "INSERT INTO workout_exercise_setting (workout_exercise_id, setting_id, value, text_value) VALUES (?, ?, ?, ?)",
                                   arguments: [exercise.id, setting.id, setting.value, setting.textValue])
                }
                for (index, note) in exercise.notes.enumerated() {
                    try db.execute(sql: "INSERT INTO workout_exercise_note (id, workout_exercise_id, position, text) VALUES (?, ?, ?, ?)",
                                   arguments: [note.id, exercise.id, index, note.text])
                }
                for (index, set) in exercise.sets.enumerated() {
                    try db.execute(sql: """
                        INSERT INTO workout_set (id, workout_exercise_id, position, kind, weight_kg, reps, duration_seconds, rpe, completed_at, updated_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """, arguments: [set.id, exercise.id, index, set.kind, set.weightKg, set.reps, set.durationSeconds, set.rpe, set.completedAt, Self.now])
                    for (settingId, value) in set.overrides {
                        try db.execute(sql: "INSERT INTO workout_set_override (workout_set_id, setting_id, value) VALUES (?, ?, ?)", arguments: [set.id, settingId, value])
                    }
                }
            }
        }
    }

    func deleteWorkout(id: String) throws {
        try writer.write { db in try db.execute(sql: "DELETE FROM workout WHERE id = ?", arguments: [id]) }
    }

    // MARK: Prebuilt workouts

    func routines() throws -> [StoredRoutine] {
        try writer.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM routine WHERE deleted_at IS NULL ORDER BY position").map { row in
                let id: String = row["id"]
                let exercises = try Row.fetchAll(db, sql: """
                    SELECT re.id, re.rest_seconds, e.name, eb.brand FROM routine_exercise re
                    JOIN exercise_brand eb ON eb.id = re.exercise_brand_id JOIN exercise e ON e.id = eb.exercise_id
                    WHERE re.routine_id = ? AND re.deleted_at IS NULL ORDER BY re.position
                    """, arguments: [id]).map { row in
                    let exerciseId: String = row["id"]
                    return StoredExercise(
                        id: exerciseId, name: row["name"], brand: row["brand"], restSeconds: row["rest_seconds"],
                        settings: try Self.settings("""
                            SELECT s.id, s.name, s.kind, rs.value, rs.text_value, s.direction, s.range_min, s.range_max, s.split_by_value, s.factor
                            FROM routine_exercise_setting rs JOIN setting s ON s.id = rs.setting_id
                            WHERE rs.routine_exercise_id = ? ORDER BY s.position
                            """, owner: exerciseId, in: db),
                        notes: [],
                        sets: try Self.sets("SELECT *, NULL AS rpe, NULL AS completed_at FROM routine_set WHERE routine_exercise_id = ? AND deleted_at IS NULL ORDER BY position",
                                            owner: exerciseId, overrideSQL: "SELECT setting_id, value FROM routine_set_override WHERE routine_set_id = ?", in: db)
                    )
                }
                return StoredRoutine(id: id, name: row["name"], exercises: exercises)
            }
        }
    }

    /// Replaces every prebuilt workout, keeping their order.
    func save(_ routines: [StoredRoutine]) throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM routine")
            for (position, routine) in routines.enumerated() {
                try db.execute(sql: "INSERT INTO routine (id, name, position, updated_at) VALUES (?, ?, ?, ?)", arguments: [routine.id, routine.name, position, Self.now])
                for (index, exercise) in routine.exercises.enumerated() {
                    let brandId = try Self.exerciseBrandId(name: exercise.name, brand: exercise.brand, in: db)
                    try db.execute(sql: "INSERT INTO routine_exercise (id, routine_id, exercise_brand_id, position, rest_seconds, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
                                   arguments: [exercise.id, routine.id, brandId, index, exercise.restSeconds, Self.now])
                    for (settingIndex, setting) in exercise.settings.enumerated() {
                        try Self.upsert(setting, exerciseBrandId: brandId, position: settingIndex, withValue: false, in: db)
                        try db.execute(sql: "INSERT INTO routine_exercise_setting (routine_exercise_id, setting_id, value, text_value) VALUES (?, ?, ?, ?)",
                                       arguments: [exercise.id, setting.id, setting.value, setting.textValue])
                    }
                    for (setIndex, set) in exercise.sets.enumerated() {
                        try db.execute(sql: """
                            INSERT INTO routine_set (id, routine_exercise_id, position, kind, weight_kg, reps, duration_seconds, updated_at)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                            """, arguments: [set.id, exercise.id, setIndex, set.kind, set.weightKg, set.reps, set.durationSeconds, Self.now])
                        for (settingId, value) in set.overrides {
                            try db.execute(sql: "INSERT INTO routine_set_override (routine_set_id, setting_id, value) VALUES (?, ?, ?)", arguments: [set.id, settingId, value])
                        }
                    }
                }
            }
        }
    }

    // MARK: Library

    func library() throws -> StoredLibrary {
        try writer.read { db in
            let muscles = Dictionary(grouping: try Row.fetchAll(db, sql: "SELECT exercise_id, muscle, share FROM exercise_muscle")) { $0["exercise_id"] as String }
            let exercises = try Row.fetchAll(db, sql: "SELECT * FROM exercise WHERE deleted_at IS NULL").map { row in
                StoredExerciseInfo(
                    name: row["name"], equipment: row["equipment"], isBuiltin: row["is_builtin"],
                    muscles: (muscles[row["id"] as String] ?? []).map { StoredMuscle(muscle: $0["muscle"], share: $0["share"]) }
                )
            }
            let setups = try Row.fetchAll(db, sql: """
                SELECT eb.id, e.name, eb.brand FROM exercise_brand eb JOIN exercise e ON e.id = eb.exercise_id WHERE eb.deleted_at IS NULL
                """).map { row in
                StoredSetup(name: row["name"], brand: row["brand"],
                            settings: try Self.settings("SELECT * FROM setting WHERE exercise_brand_id = ? AND deleted_at IS NULL ORDER BY position", owner: row["id"], in: db))
            }
            return StoredLibrary(exercises: exercises, setups: setups.filter { !$0.settings.isEmpty })
        }
    }

    /// The label on each exercise-and-brand that has one, keyed "Name|Brand" with an empty brand for no brand,
    /// the same way `ExerciseCatalog` keys setups. For the export, which is the only place labels show so far.
    func brandLabels() throws -> [String: String] {
        try writer.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT e.name, eb.brand, eb.label FROM exercise_brand eb JOIN exercise e ON e.id = eb.exercise_id
                WHERE eb.deleted_at IS NULL AND eb.label IS NOT NULL
                """)
            return Dictionary(rows.map { ("\($0["name"] as String)|\(($0["brand"] as String?) ?? "")", $0["label"] as String) }, uniquingKeysWith: { a, _ in a })
        }
    }

    /// Saves the library's exercises, and each exercise-and-brand's settings with their next-time values.
    /// A setting that's gone from an exercise is marked deleted rather than removed, so past workouts keep it.
    func save(_ library: StoredLibrary) throws {
        try writer.write { db in
            for exercise in library.exercises {
                let id = try String.fetchOne(db, sql: "SELECT id FROM exercise WHERE name = ?", arguments: [exercise.name]) ?? UUID().uuidString
                try db.execute(sql: """
                    INSERT INTO exercise (id, name, equipment, is_builtin, updated_at) VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET equipment = excluded.equipment, is_builtin = excluded.is_builtin, updated_at = excluded.updated_at
                    """, arguments: [id, exercise.name, exercise.equipment, exercise.isBuiltin, Self.now])
                try db.execute(sql: "DELETE FROM exercise_muscle WHERE exercise_id = ?", arguments: [id])
                for muscle in exercise.muscles {
                    try db.execute(sql: "INSERT INTO exercise_muscle (exercise_id, muscle, share) VALUES (?, ?, ?)", arguments: [id, muscle.muscle, muscle.share])
                }
            }
            for setup in library.setups {
                let brandId = try Self.exerciseBrandId(name: setup.name, brand: setup.brand, in: db)
                for (index, setting) in setup.settings.enumerated() {
                    try Self.upsert(setting, exerciseBrandId: brandId, position: index, withValue: true, in: db)
                }
                let kept = setup.settings.map(\.id)
                let placeholders = kept.isEmpty ? "''" : kept.map { _ in "?" }.joined(separator: ",")
                try db.execute(
                    sql: "UPDATE setting SET deleted_at = ? WHERE exercise_brand_id = ? AND deleted_at IS NULL AND id NOT IN (\(placeholders))",
                    arguments: StatementArguments([Self.now, brandId] as [any DatabaseValueConvertible] + kept.map { $0 as any DatabaseValueConvertible })
                )
            }
        }
    }
}

/// The built-in exercise names, readable off the main actor, so a new exercise row can be marked built in.
nonisolated enum ExerciseCatalogNames {
    static let builtIn: Set<String> = [
        "Abductors", "Adductors", "Bench Press", "Bicep Curl", "Cable Fly", "Calf Raise", "Chest Press", "Deadlift",
        "Hack Squat", "Hip Thrust", "Incline Dumbbell Press", "Lat Pulldown", "Lateral Raise", "Leg Curl",
        "Leg Extension", "Leg Press", "Pec Deck", "Preacher Curl", "Pull Up", "Rear Delt Fly", "Romanian Deadlift",
        "Seated Calf Raise", "Seated Row", "Shoulder Press", "Squat", "Triceps Pushdown",
    ]
}
