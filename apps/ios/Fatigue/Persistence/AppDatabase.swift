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
        // Gets every table ready to sync, and adds the outbox and the cursor.
        migrator.registerMigration("v3-sync") { db in
            // Two phones can each add an exercise with the same name while offline, and a pull must be able
            // to bring the other one in. The library reads by name, so duplicates are harmless; the unique
            // constraint isn't. SQLite can't drop a constraint, so the table is rebuilt without it.
            try db.create(table: "exercise_new") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull().indexed()
                t.column("equipment", .text).notNull()
                t.column("is_builtin", .boolean).notNull()
                t.column("updated_at", .integer).notNull().defaults(to: 0)
                t.column("deleted_at", .integer)
            }
            try db.execute(sql: "INSERT INTO exercise_new SELECT id, name, equipment, is_builtin, updated_at, deleted_at FROM exercise")
            try db.drop(table: "exercise")
            try db.rename(table: "exercise_new", to: "exercise")

            // Rows keyed by their parent and setting get an id built from both (see SyncID), so sync can
            // treat them like every other row, plus the two sync columns.
            for (table, parent, other, kind) in [
                ("exercise_muscle", "exercise_id", "muscle", "exercise_muscle"),
                ("workout_exercise_setting", "workout_exercise_id", "setting_id", "setting_value"),
                ("workout_set_override", "workout_set_id", "setting_id", "override"),
                ("routine_exercise_setting", "routine_exercise_id", "setting_id", "setting_value"),
                ("routine_set_override", "routine_set_id", "setting_id", "override"),
            ] {
                try db.alter(table: table) { t in
                    t.add(column: "id", .text)
                    t.add(column: "updated_at", .integer).notNull().defaults(to: 0)
                    t.add(column: "deleted_at", .integer)
                }
                for row in try Row.fetchAll(db, sql: "SELECT \(parent) AS parent, \(other) AS other FROM \(table)") {
                    let parentId: String = row["parent"]
                    let otherId: String = row["other"]
                    try db.execute(sql: "UPDATE \(table) SET id = ? WHERE \(parent) = ? AND \(other) = ?",
                                   arguments: [SyncID.uuid(kind, parentId, otherId), parentId, otherId])
                }
                try db.create(indexOn: table, columns: ["id"], options: .unique)
            }
            try db.alter(table: "workout_exercise_note") { t in
                t.add(column: "updated_at", .integer).notNull().defaults(to: 0)
                t.add(column: "deleted_at", .integer)
            }

            // Rows changed since the last push, and the cursor from the last pull.
            try db.create(table: "sync_outbox") { t in
                t.column("table_name", .text).notNull()
                t.column("row_id", .text).notNull()
                t.column("updated_at", .integer).notNull()
                t.primaryKey(["table_name", "row_id"])
            }
            try db.create(table: "sync_state") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }

            // Every insert and every change to updated_at lands in the outbox, whichever code wrote it.
            // Applying pulled rows sets the "applying" flag so they don't go straight back out.
            for table in SyncTable.all.map(\.name) {
                let quiet = "NOT EXISTS (SELECT 1 FROM sync_state WHERE key = 'applying')"
                let queue = "INSERT OR REPLACE INTO sync_outbox (table_name, row_id, updated_at) VALUES ('\(table)', NEW.id, NEW.updated_at);"
                try db.execute(sql: "CREATE TRIGGER sync_\(table)_insert AFTER INSERT ON \(table) WHEN \(quiet) BEGIN \(queue) END")
                try db.execute(sql: "CREATE TRIGGER sync_\(table)_update AFTER UPDATE ON \(table) WHEN NEW.updated_at IS NOT OLD.updated_at AND \(quiet) BEGIN \(queue) END")
                // What was saved before sync existed goes up on the first push.
                try db.execute(sql: "INSERT OR REPLACE INTO sync_outbox (table_name, row_id, updated_at) SELECT '\(table)', id, updated_at FROM \(table)")
            }
        }
        return migrator
    }
}

/// A table that syncs: its name and the columns that identify a row, parents before children.
nonisolated struct SyncTable: Sendable, Equatable {
    let name: String
    /// The primary key. `id` on most tables; rows keyed by their parent and setting keep that key and carry `id` beside it.
    let key: [String]

    static let all: [SyncTable] = [
        SyncTable(name: "exercise", key: ["id"]),
        SyncTable(name: "exercise_muscle", key: ["exercise_id", "muscle"]),
        SyncTable(name: "exercise_brand", key: ["id"]),
        SyncTable(name: "setting", key: ["id"]),
        SyncTable(name: "workout", key: ["id"]),
        SyncTable(name: "workout_exercise", key: ["id"]),
        SyncTable(name: "workout_exercise_note", key: ["id"]),
        SyncTable(name: "workout_exercise_setting", key: ["workout_exercise_id", "setting_id"]),
        SyncTable(name: "workout_set", key: ["id"]),
        SyncTable(name: "workout_set_override", key: ["workout_set_id", "setting_id"]),
        SyncTable(name: "routine", key: ["id"]),
        SyncTable(name: "routine_exercise", key: ["id"]),
        SyncTable(name: "routine_exercise_setting", key: ["routine_exercise_id", "setting_id"]),
        SyncTable(name: "routine_set", key: ["id"]),
        SyncTable(name: "routine_set_override", key: ["routine_set_id", "setting_id"]),
    ]

    static func named(_ name: String) -> SyncTable? { all.first { $0.name == name } }
    static func order(of name: String) -> Int { all.firstIndex { $0.name == name } ?? all.count }
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
    static var now: Int64 { Int64(Date.now.timeIntervalSince1970 * 1000) }
    private static func millis(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1000).rounded()) }
    private static func date(_ millis: Int64) -> Date { Date(timeIntervalSince1970: Double(millis) / 1000) }

    // MARK: Writing rows that sync

    /// Inserts a row, or updates it in place and brings it back if it was marked deleted.
    ///
    /// `updated_at` only moves when a value actually changed, so saving a workout again doesn't push every
    /// row under it. When it moves, it lands strictly after the row's last value even if the clock hasn't
    /// ticked, so a second save in the same millisecond never ties with the server's copy and gets dropped.
    /// Columns in `onlyOnInsert` are written for a new row and left alone on an existing one.
    static func upsert(_ table: String, key: [String] = ["id"], onlyOnInsert: Set<String> = [],
                       _ values: KeyValuePairs<String, (any DatabaseValueConvertible)?>, in db: Database) throws {
        let columns = values.map(\.key)
        let updated = columns.filter { !key.contains($0) && !onlyOnInsert.contains($0) }
        let unchanged = (["\(table).deleted_at IS NULL"] + updated.map { "\(table).\($0) IS excluded.\($0)" }).joined(separator: " AND ")
        try db.execute(sql: """
            INSERT INTO \(table) (\(columns.joined(separator: ", ")), updated_at, deleted_at)
            VALUES (\(columns.map { _ in "?" }.joined(separator: ", ")), ?, NULL)
            ON CONFLICT(\(key.joined(separator: ", "))) DO UPDATE SET
                \(updated.map { "\($0) = excluded.\($0)" }.joined(separator: ", "))\(updated.isEmpty ? "" : ",")
                deleted_at = NULL,
                updated_at = CASE WHEN \(unchanged) THEN \(table).updated_at ELSE MAX(excluded.updated_at, \(table).updated_at + 1) END
            """, arguments: StatementArguments(values.map(\.value) + [now]))
    }

    /// Marks rows deleted instead of removing them, so the deletion syncs. Rows already marked are left as they are.
    static func markDeleted(_ table: String, where condition: String, arguments: StatementArguments = [], in db: Database) throws {
        try db.execute(sql: "UPDATE \(table) SET deleted_at = ?, updated_at = MAX(?, updated_at + 1) WHERE deleted_at IS NULL AND (\(condition))",
                       arguments: [now, now] + arguments)
    }

    /// Marks deleted every live row in `table` under `parent` whose `column` isn't one of `kept`.
    private static func markDeleted(_ table: String, parent: String, _ parentId: String, keeping kept: [String], by column: String = "id", in db: Database) throws {
        let placeholders = kept.isEmpty ? "''" : kept.map { _ in "?" }.joined(separator: ", ")
        try markDeleted(table, where: "\(parent) = ? AND \(column) NOT IN (\(placeholders))",
                        arguments: StatementArguments([parentId] + kept), in: db)
    }

    /// Marks deleted every live row whose parent is marked deleted, down a workout's or a routine's tree.
    /// Deleting a workout marks its exercises, setting values, notes, sets and overrides too, so any table
    /// can be read without checking its parents.
    private static func cascadeDeletes(workout prefix: String, in db: Database) throws {
        let exercise = "\(prefix)_exercise"
        try markDeleted(exercise, where: "\(prefix)_id IN (SELECT id FROM \(prefix) WHERE deleted_at IS NOT NULL)", in: db)
        let deadExercises = "\(exercise)_id IN (SELECT id FROM \(exercise) WHERE deleted_at IS NOT NULL)"
        try markDeleted("\(exercise)_setting", where: deadExercises, in: db)
        if prefix == "workout" { try markDeleted("workout_exercise_note", where: deadExercises, in: db) }
        try markDeleted("\(prefix)_set", where: deadExercises, in: db)
        try markDeleted("\(prefix)_set_override", where: "\(prefix)_set_id IN (SELECT id FROM \(prefix)_set WHERE deleted_at IS NOT NULL)", in: db)
    }

    // MARK: Exercises, brands and settings

    /// The id of an exercise on a brand, adding the exercise and the brand the first time.
    /// New ids are built from the name and the brand, so two phones adding the same one offline agree.
    private static func exerciseBrandId(name: String, brand: String?, in db: Database) throws -> String {
        let exerciseId: String
        if let id = try String.fetchOne(db, sql: "SELECT id FROM exercise WHERE name = ? AND deleted_at IS NULL ORDER BY id LIMIT 1", arguments: [name]) {
            exerciseId = id
        } else {
            exerciseId = SyncID.exercise(named: name)
            try upsert("exercise", onlyOnInsert: ["equipment", "is_builtin"],
                       ["id": exerciseId, "name": name, "equipment": "other", "is_builtin": ExerciseCatalogNames.builtIn.contains(name)], in: db)
        }
        if let id = try String.fetchOne(db, sql: "SELECT id FROM exercise_brand WHERE exercise_id = ? AND brand IS ? AND deleted_at IS NULL ORDER BY id LIMIT 1",
                                        arguments: [exerciseId, brand]) {
            return id
        }
        let id = SyncID.exerciseBrand(exerciseId: exerciseId, brand: brand)
        try upsert("exercise_brand", onlyOnInsert: ["label"], ["id": id, "exercise_id": exerciseId, "brand": brand, "label": nil], in: db)
        return id
    }

    /// Adds a setting or updates its definition. Its next-time value is only written when `withValue` is set,
    /// so saving an old workout never overwrites what's filled in next time.
    private static func upsert(_ setting: StoredSetting, exerciseBrandId: String, position: Int, withValue: Bool, in db: Database) throws {
        try upsert("setting", onlyOnInsert: withValue ? [] : ["value", "text_value"], [
            "id": setting.id, "exercise_brand_id": exerciseBrandId, "name": setting.name, "kind": setting.kind,
            "value": setting.value, "text_value": setting.textValue, "direction": setting.direction,
            "range_min": setting.rangeMin, "range_max": setting.rangeMax, "split_by_value": setting.splitByValue,
            "factor": setting.factor, "position": Double(position),
        ], in: db)
    }

    /// Writes the value each setting has in a workout exercise or a routine exercise, and drops the rest.
    private static func saveSettingValues(_ settings: [StoredSetting], table: String, parent: String, _ parentId: String, in db: Database) throws {
        for setting in settings {
            try upsert(table, key: [parent, "setting_id"], [
                "id": SyncID.settingValue(ownerId: parentId, settingId: setting.id), parent: parentId, "setting_id": setting.id,
                "value": setting.value, "text_value": setting.textValue,
            ], in: db)
        }
        try markDeleted(table, parent: parent, parentId, keeping: settings.map(\.id), by: "setting_id", in: db)
    }

    private static func saveOverrides(_ overrides: [String: Double], table: String, parent: String, _ setId: String, in db: Database) throws {
        for (settingId, value) in overrides {
            try upsert(table, key: [parent, "setting_id"], [
                "id": SyncID.override(setId: setId, settingId: settingId), parent: setId, "setting_id": settingId, "value": value,
            ], in: db)
        }
        try markDeleted(table, parent: parent, setId, keeping: Array(overrides.keys), by: "setting_id", in: db)
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
                    WHERE ws.workout_exercise_id = ? AND ws.deleted_at IS NULL ORDER BY s.position
                    """, owner: id, in: db),
                notes: try Row.fetchAll(db, sql: "SELECT id, text FROM workout_exercise_note WHERE workout_exercise_id = ? AND deleted_at IS NULL ORDER BY position", arguments: [id])
                    .map { StoredNote(id: $0["id"], text: $0["text"]) },
                sets: try sets("SELECT * FROM workout_set WHERE workout_exercise_id = ? AND deleted_at IS NULL ORDER BY position", owner: id,
                               overrideSQL: "SELECT setting_id, value FROM workout_set_override WHERE workout_set_id = ? AND deleted_at IS NULL", in: db)
            )
        }
    }

    /// Saves one workout and everything under it. Rows that are gone from it are marked deleted.
    func save(_ workout: StoredWorkout) throws {
        try writer.write { db in
            try Self.upsert("workout", [
                "id": workout.id, "title": workout.title, "note": workout.note, "started_at": Self.millis(workout.startedAt),
                "finished_at": workout.finishedAt.map(Self.millis), "routine_id": workout.routineId,
            ], in: db)
            for (position, exercise) in workout.exercises.enumerated() {
                let brandId = try Self.exerciseBrandId(name: exercise.name, brand: exercise.brand, in: db)
                try Self.upsert("workout_exercise", [
                    "id": exercise.id, "workout_id": workout.id, "exercise_brand_id": brandId, "position": Double(position), "rest_seconds": exercise.restSeconds,
                ], in: db)
                for (index, setting) in exercise.settings.enumerated() {
                    try Self.upsert(setting, exerciseBrandId: brandId, position: index, withValue: false, in: db)
                }
                try Self.saveSettingValues(exercise.settings, table: "workout_exercise_setting", parent: "workout_exercise_id", exercise.id, in: db)
                for (index, note) in exercise.notes.enumerated() {
                    try Self.upsert("workout_exercise_note", ["id": note.id, "workout_exercise_id": exercise.id, "position": Double(index), "text": note.text], in: db)
                }
                try Self.markDeleted("workout_exercise_note", parent: "workout_exercise_id", exercise.id, keeping: exercise.notes.map(\.id), in: db)
                for (index, set) in exercise.sets.enumerated() {
                    try Self.upsert("workout_set", [
                        "id": set.id, "workout_exercise_id": exercise.id, "position": Double(index), "kind": set.kind, "set_type": "normal",
                        "weight_kg": set.weightKg, "reps": set.reps, "duration_seconds": set.durationSeconds, "rpe": set.rpe, "completed_at": set.completedAt,
                    ], in: db)
                    try Self.saveOverrides(set.overrides, table: "workout_set_override", parent: "workout_set_id", set.id, in: db)
                }
                try Self.markDeleted("workout_set", parent: "workout_exercise_id", exercise.id, keeping: exercise.sets.map(\.id), in: db)
            }
            try Self.markDeleted("workout_exercise", parent: "workout_id", workout.id, keeping: workout.exercises.map(\.id), in: db)
            try Self.cascadeDeletes(workout: "workout", in: db)
        }
    }

    func deleteWorkout(id: String) throws {
        try writer.write { db in
            try Self.markDeleted("workout", where: "id = ?", arguments: [id], in: db)
            try Self.cascadeDeletes(workout: "workout", in: db)
        }
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
                            WHERE rs.routine_exercise_id = ? AND rs.deleted_at IS NULL ORDER BY s.position
                            """, owner: exerciseId, in: db),
                        notes: [],
                        sets: try Self.sets("SELECT *, NULL AS rpe, NULL AS completed_at FROM routine_set WHERE routine_exercise_id = ? AND deleted_at IS NULL ORDER BY position",
                                            owner: exerciseId, overrideSQL: "SELECT setting_id, value FROM routine_set_override WHERE routine_set_id = ? AND deleted_at IS NULL", in: db)
                    )
                }
                return StoredRoutine(id: id, name: row["name"], exercises: exercises)
            }
        }
    }

    /// Saves every prebuilt workout, keeping their order. Ones that are gone from the list are marked deleted.
    func save(_ routines: [StoredRoutine]) throws {
        try writer.write { db in
            for (position, routine) in routines.enumerated() {
                try Self.upsert("routine", ["id": routine.id, "name": routine.name, "position": Double(position)], in: db)
                for (index, exercise) in routine.exercises.enumerated() {
                    let brandId = try Self.exerciseBrandId(name: exercise.name, brand: exercise.brand, in: db)
                    try Self.upsert("routine_exercise", [
                        "id": exercise.id, "routine_id": routine.id, "exercise_brand_id": brandId, "position": Double(index), "rest_seconds": exercise.restSeconds,
                    ], in: db)
                    for (settingIndex, setting) in exercise.settings.enumerated() {
                        try Self.upsert(setting, exerciseBrandId: brandId, position: settingIndex, withValue: false, in: db)
                    }
                    try Self.saveSettingValues(exercise.settings, table: "routine_exercise_setting", parent: "routine_exercise_id", exercise.id, in: db)
                    for (setIndex, set) in exercise.sets.enumerated() {
                        try Self.upsert("routine_set", [
                            "id": set.id, "routine_exercise_id": exercise.id, "position": Double(setIndex), "kind": set.kind, "set_type": "normal",
                            "weight_kg": set.weightKg, "reps": set.reps, "duration_seconds": set.durationSeconds,
                        ], in: db)
                        try Self.saveOverrides(set.overrides, table: "routine_set_override", parent: "routine_set_id", set.id, in: db)
                    }
                    try Self.markDeleted("routine_set", parent: "routine_exercise_id", exercise.id, keeping: exercise.sets.map(\.id), in: db)
                }
                try Self.markDeleted("routine_exercise", parent: "routine_id", routine.id, keeping: routine.exercises.map(\.id), in: db)
            }
            let kept = routines.map(\.id)
            try Self.markDeleted("routine", where: "id NOT IN (\(kept.isEmpty ? "''" : kept.map { _ in "?" }.joined(separator: ", ")))",
                                 arguments: StatementArguments(kept), in: db)
            try Self.cascadeDeletes(workout: "routine", in: db)
        }
    }

    // MARK: Library

    func library() throws -> StoredLibrary {
        try writer.read { db in
            let muscles = Dictionary(grouping: try Row.fetchAll(db, sql: "SELECT exercise_id, muscle, share FROM exercise_muscle WHERE deleted_at IS NULL")) { $0["exercise_id"] as String }
            let exercises = try Row.fetchAll(db, sql: "SELECT * FROM exercise WHERE deleted_at IS NULL ORDER BY name, id").map { row in
                StoredExerciseInfo(
                    name: row["name"], equipment: row["equipment"], isBuiltin: row["is_builtin"],
                    muscles: (muscles[row["id"] as String] ?? []).map { StoredMuscle(muscle: $0["muscle"], share: $0["share"]) }
                )
            }
            let setups = try Row.fetchAll(db, sql: """
                SELECT eb.id, e.name, eb.brand FROM exercise_brand eb JOIN exercise e ON e.id = eb.exercise_id
                WHERE eb.deleted_at IS NULL AND e.deleted_at IS NULL ORDER BY e.name, eb.brand, eb.id
                """).map { row in
                StoredSetup(name: row["name"], brand: row["brand"],
                            settings: try Self.settings("SELECT * FROM setting WHERE exercise_brand_id = ? AND deleted_at IS NULL ORDER BY position", owner: row["id"], in: db))
            }
            return StoredLibrary(exercises: exercises, setups: setups.filter { !$0.settings.isEmpty })
        }
    }

    /// Saves the library's exercises, and each exercise-and-brand's settings with their next-time values.
    /// A setting that's gone from an exercise is marked deleted rather than removed, so past workouts keep it.
    func save(_ library: StoredLibrary) throws {
        try writer.write { db in
            for exercise in library.exercises {
                let id = try String.fetchOne(db, sql: "SELECT id FROM exercise WHERE name = ? ORDER BY deleted_at IS NOT NULL, id LIMIT 1", arguments: [exercise.name])
                    ?? SyncID.exercise(named: exercise.name)
                try Self.upsert("exercise", ["id": id, "name": exercise.name, "equipment": exercise.equipment, "is_builtin": exercise.isBuiltin], in: db)
                for muscle in exercise.muscles {
                    try Self.upsert("exercise_muscle", key: ["exercise_id", "muscle"], [
                        "id": SyncID.muscle(exerciseId: id, muscle: muscle.muscle), "exercise_id": id, "muscle": muscle.muscle, "share": muscle.share,
                    ], in: db)
                }
                try Self.markDeleted("exercise_muscle", parent: "exercise_id", id, keeping: exercise.muscles.map(\.muscle), by: "muscle", in: db)
            }
            for setup in library.setups {
                let brandId = try Self.exerciseBrandId(name: setup.name, brand: setup.brand, in: db)
                for (index, setting) in setup.settings.enumerated() {
                    try Self.upsert(setting, exerciseBrandId: brandId, position: index, withValue: true, in: db)
                }
                try Self.markDeleted("setting", parent: "exercise_brand_id", brandId, keeping: setup.settings.map(\.id), in: db)
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
