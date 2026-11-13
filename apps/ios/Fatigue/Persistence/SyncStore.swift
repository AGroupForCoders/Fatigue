import Foundation
import GRDB

/// An item as it is in the database now, with its fingerprint.
nonisolated struct LocalSyncItem: Equatable, Sendable {
    var item: SyncItem
    var hash: String
}

/// What's on the phone and nowhere else, so a wipe would lose it.
nonisolated struct UnsavedOnPhone: Equatable, Sendable {
    /// Changes waiting to go up.
    var items = 0
    /// How many of those are workouts.
    var workouts = 0
    /// Items the server refused.
    var refused = 0
    /// Whether a workout is running. It syncs only once it's finished.
    var running = false
    /// Photos and videos on workouts, which aren't backed up yet.
    var media = 0

    var isEmpty: Bool { items == 0 && refused == 0 && !running && media == 0 }
}

/// What applying a pull did.
nonisolated struct PullOutcome: Equatable, Sendable {
    /// Items written to the database.
    var applied = 0
    /// Items left alone because this phone has a later change of its own that hasn't been pushed yet.
    var keptLocal = 0
    /// The weight unit a pulled user setting carries, for the app to switch to.
    var weightUnit: String?
}

/// The sync side of the database: turning rows into items, finding the items that changed, and writing
/// the items a pull brings. The Sync docs page has the rules. Nothing here touches the network.
///
/// There is no queue of changes. To find what to push, the phone builds every item, takes its fingerprint
/// and compares it with the one in `sync_item`, kept from the last time the phone and the server agreed.
/// A save path can't forget to queue a change, because nothing is queued.
nonisolated extension AppDatabase {
    private static var nowMillis: Int64 { Int64(Date.now.timeIntervalSince1970 * 1000) }

    // MARK: What needs pushing

    /// Every item in the database: custom exercises, brands with their settings, routines, finished workouts
    /// and the user setting, deleted ones included. The running workout and built-in exercises never sync.
    func syncItems() throws -> [LocalSyncItem] {
        try writer.read { try Self.syncItems(in: $0) }
    }

    /// The items that differ from what the server last agreed to, in the order they have to be pushed.
    ///
    /// An item the server refused isn't offered again until it changes. One that was deleted before it was
    /// ever pushed is left out: the server never knew it.
    ///
    /// Some saves change what's under an item without touching its `updated_at`, such as deleting an
    /// exercise, which takes it out of every routine. Such an item is stamped with `now` here, or the
    /// server would see an edit no later than the one it has and skip it.
    func pendingSyncItems(now: Int64? = nil) throws -> [LocalSyncItem] {
        try writer.write { db in
            let agreed = try Self.agreed(in: db)
            var pending: [LocalSyncItem] = []
            for var local in try Self.syncItems(in: db) {
                let state = agreed[local.item.key]
                guard local.hash != state?.hash, local.hash != state?.failedHash else { continue }
                if state?.hash == nil, local.item.deletedAt != nil { continue }
                if let agreedAt = state?.updatedAt, local.item.updatedAt <= agreedAt {
                    let stamp = max(now ?? Self.nowMillis, agreedAt + 1)
                    try db.execute(sql: "UPDATE \(Self.table(local.item.kind)) SET updated_at = ? WHERE id = ?", arguments: [stamp, local.item.id.uppercased()])
                    local.item.updatedAt = stamp
                }
                pending.append(local)
            }
            return pending
        }
    }

    /// Records that the server has these items as they were when they were pushed: it saved them, or
    /// already had this edit or a later one.
    func markSynced(_ items: [LocalSyncItem]) throws {
        try writer.write { db in
            for local in items { try Self.agree(on: local, in: db) }
        }
    }

    /// Records that the server refused an item, so it isn't pushed again until it changes.
    func markFailed(_ local: LocalSyncItem, error: String) throws {
        try writer.write { db in
            try db.execute(sql: """
                INSERT INTO sync_item (kind, id, failed_hash, error) VALUES (?, ?, ?, ?)
                ON CONFLICT(kind, id) DO UPDATE SET failed_hash = excluded.failed_hash, error = excluded.error
                """, arguments: [local.item.kind.rawValue, local.item.id, local.hash, error])
        }
    }

    /// The items the server refused, with why, for Settings to show.
    func syncFailures() throws -> [(key: String, error: String)] {
        try writer.read { db in
            try Row.fetchAll(db, sql: "SELECT kind, id, error FROM sync_item WHERE failed_hash IS NOT NULL ORDER BY kind, id").map {
                (key: "\($0["kind"] as String):\($0["id"] as String)", error: ($0["error"] as String?) ?? "")
            }
        }
    }

    // MARK: Pulling

    /// The cursor from the last pull. Zero before the first one.
    func syncCursor() throws -> Int64 {
        try writer.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM sync_state WHERE key = 'cursor'").flatMap(Int64.init) ?? 0
        }
    }

    /// Writes what a pull brought and saves its cursor, all in one transaction, so a pull cut short writes
    /// nothing and is asked for again.
    ///
    /// An item with no unsent change on this phone is always replaced by the pulled copy. Times are only
    /// compared when the phone has changed it too, and then the later one stays.
    ///
    /// Foreign keys are checked at the end, because a workout can arrive before the brand it uses. If a row
    /// still points at something missing by then, this throws and nothing is written.
    @discardableResult
    func applyPulled(_ items: [SyncItem], cursor: Int64) throws -> PullOutcome {
        try writer.write { db in
            try db.execute(sql: "PRAGMA defer_foreign_keys = ON")
            let agreed = try Self.agreed(in: db)
            let before = Dictionary(try Self.syncItems(in: db).map { ($0.item.key, $0) }, uniquingKeysWith: { a, _ in a })
            var outcome = PullOutcome()
            var written: [SyncItem] = []
            for item in items {
                if let mine = before[item.key], mine.hash != agreed[item.key]?.hash, mine.item.updatedAt > item.updatedAt {
                    outcome.keptLocal += 1
                    continue
                }
                try Self.write(item, in: db)
                written.append(item)
                outcome.applied += 1
                if case .userSetting(let body)? = item.body, item.deletedAt == nil { outcome.weightUnit = body.weightUnit }
            }
            // What the phone and the server now agree on is the item as the database holds it, not as it
            // arrived: the two can differ in ways that don't matter, such as a setting kept here as deleted.
            let after = Dictionary(try Self.syncItems(in: db).map { ($0.item.key, $0) }, uniquingKeysWith: { a, _ in a })
            for item in written {
                guard let now = after[item.key] else { continue }
                try Self.agree(on: now, in: db)
            }
            try db.execute(sql: "INSERT INTO sync_state (key, value) VALUES ('cursor', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value", arguments: [String(cursor)])
            return outcome
        }
    }

    // MARK: Whose data this is

    /// The account the synced data on this phone belongs to, or nil before the first sync. The phone only
    /// ever syncs with this account, so one person's workouts can't end up in another's.
    func syncOwner() throws -> String? {
        try writer.read { db in try String.fetchOne(db, sql: "SELECT value FROM sync_state WHERE key = 'owner'") }
    }

    func setSyncOwner(_ userID: String) throws {
        try writer.write { db in
            try db.execute(sql: "INSERT INTO sync_state (key, value) VALUES ('owner', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value", arguments: [userID])
        }
    }

    /// Saves the weight unit to the account's settings row, so other phones pick it up. Only a change you
    /// make writes it: a fresh phone takes the unit the server has instead of pushing its default.
    func saveWeightUnit(_ unit: String, accountId: String) throws {
        let id = SyncID.userSetting(accountId: accountId)
        try writer.write { db in
            let stamp = max(Self.nowMillis, (try Int64.fetchOne(db, sql: "SELECT updated_at FROM user_setting WHERE id = ?", arguments: [id]) ?? 0) + 1)
            try db.execute(sql: """
                INSERT INTO user_setting (id, weight_unit, updated_at) VALUES (?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET weight_unit = excluded.weight_unit, updated_at = excluded.updated_at, deleted_at = NULL
                """, arguments: [id, unit, stamp])
        }
    }

    /// How many items are waiting to go up, and how many of them are workouts, for Settings and the
    /// sign-out warning.
    func waitingCounts() throws -> (items: Int, workouts: Int) {
        let waiting = try pendingSyncItems()
        return (waiting.count, waiting.filter { $0.item.kind == .workout }.count)
    }

    /// Everything a wipe would lose for good, because the server doesn't have it. Signing out and another
    /// account taking over both ask first when this isn't empty.
    func unsavedOnPhone() throws -> UnsavedOnPhone {
        let waiting = try waitingCounts()
        return try writer.read { db in
            UnsavedOnPhone(
                items: waiting.items,
                workouts: waiting.workouts,
                // Refused items aren't waiting, since they aren't offered again until they change, but the
                // server doesn't have them either.
                refused: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_item WHERE failed_hash IS NOT NULL") ?? 0,
                // The running workout never syncs. It goes up once it's finished.
                running: try Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM workout WHERE finished_at IS NULL AND deleted_at IS NULL)") ?? false,
                // Photos and videos on workouts stay on this phone until media backup is built.
                media: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM workout_media WHERE deleted_at IS NULL") ?? 0
            )
        }
    }

    /// Empties the phone: every workout, prebuilt workout, exercise, brand, setting and photo row, and what
    /// sync knew. For signing out and for a different account on this phone. The schema stays.
    ///
    /// It leaves one mark behind, so the app knows this database was emptied on purpose and doesn't fill it
    /// with samples again, which the next account to sign in would then back up as its own.
    func wipe() throws {
        try writer.write { db in
            try db.execute(sql: "PRAGMA defer_foreign_keys = ON")
            let tables = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'grdb_%'")
            for table in tables { try db.execute(sql: "DELETE FROM \(table)") }
            try db.execute(sql: "INSERT INTO sync_state (key, value) VALUES ('wiped', '1')")
        }
    }

    /// Whether this database was emptied by `wipe()`, rather than being new.
    func wasWiped() throws -> Bool {
        try writer.read { try Bool.fetchOne($0, sql: "SELECT EXISTS (SELECT 1 FROM sync_state WHERE key = 'wiped')") ?? false }
    }

    /// The tables under synced items. A commit that touches any of them may have something to push.
    static let syncedTables: Set<String> = [
        "exercise", "exercise_muscle", "exercise_brand", "setting",
        "routine", "routine_exercise", "routine_exercise_setting", "routine_set", "routine_set_override",
        "workout", "workout_exercise", "workout_exercise_note", "workout_exercise_setting", "workout_set", "workout_set_override",
        "user_setting",
    ]

    // MARK: - What the phone and the server agree on

    private struct Agreed {
        var hash: String?
        var failedHash: String?
        var updatedAt: Int64?
    }

    private static func agreed(in db: Database) throws -> [String: Agreed] {
        var all: [String: Agreed] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT kind, id, hash, failed_hash, updated_at FROM sync_item") {
            all["\(row["kind"] as String):\(row["id"] as String)"] = Agreed(hash: row["hash"], failedHash: row["failed_hash"], updatedAt: row["updated_at"])
        }
        return all
    }

    private static func agree(on local: LocalSyncItem, in db: Database) throws {
        try db.execute(sql: """
            INSERT INTO sync_item (kind, id, hash, updated_at) VALUES (?, ?, ?, ?)
            ON CONFLICT(kind, id) DO UPDATE SET hash = excluded.hash, updated_at = excluded.updated_at, failed_hash = NULL, error = NULL
            """, arguments: [local.item.kind.rawValue, local.item.id, local.hash, local.item.updatedAt])
    }

    private static func table(_ kind: SyncItem.Kind) -> String {
        switch kind {
        case .exercise: "exercise"
        case .brand: "exercise_brand"
        case .routine: "routine"
        case .workout: "workout"
        case .userSetting: "user_setting"
        }
    }

    // MARK: - Rows to items

    private static func lower(_ id: String) -> String { id.lowercased() }

    private static func grouped(_ rows: [Row], by column: String) -> [String: [Row]] {
        Dictionary(grouping: rows) { $0[column] as String }
    }

    private static func syncItems(in db: Database) throws -> [LocalSyncItem] {
        var items: [SyncItem] = []

        // Custom exercises.
        let muscles = grouped(try Row.fetchAll(db, sql: "SELECT * FROM exercise_muscle ORDER BY muscle"), by: "exercise_id")
        for row in try Row.fetchAll(db, sql: "SELECT * FROM exercise WHERE is_builtin = 0 ORDER BY id") {
            let id: String = row["id"]
            let body = SyncItem.ExerciseBody(
                name: row["name"], equipment: row["equipment"],
                muscles: (muscles[id] ?? []).map { SyncItem.Muscle(muscle: $0["muscle"], share: $0["share"]) }
            )
            items.append(SyncItem(kind: .exercise, id: lower(id), updatedAt: row["updated_at"], deletedAt: row["deleted_at"], body: .exercise(body)))
        }

        // Brands, with their settings. A deleted setting stays in the list.
        let settings = grouped(try Row.fetchAll(db, sql: "SELECT * FROM setting ORDER BY position, id"), by: "exercise_brand_id")
        for row in try Row.fetchAll(db, sql: "SELECT * FROM exercise_brand ORDER BY id") {
            let id: String = row["id"]
            let body = SyncItem.BrandBody(
                exerciseId: lower(row["exercise_id"]), brand: row["brand"], label: row["label"],
                settings: (settings[id] ?? []).map { s in
                    SyncItem.Setting(
                        id: lower(s["id"]), name: s["name"], kind: s["kind"], value: s["value"], textValue: s["text_value"],
                        direction: s["direction"], rangeMin: s["range_min"], rangeMax: s["range_max"], splitByValue: s["split_by_value"],
                        factor: s["factor"], position: s["position"], deletedAt: s["deleted_at"]
                    )
                }
            )
            items.append(SyncItem(kind: .brand, id: lower(id), updatedAt: row["updated_at"], deletedAt: row["deleted_at"], body: .brand(body)))
        }

        // Routines.
        let routineExercises = try exercises(
            in: db, exercise: "routine_exercise", parent: "routine_id", note: nil,
            value: "routine_exercise_setting", valueOwner: "routine_exercise_id",
            set: "routine_set", setOwner: "routine_exercise_id", override: "routine_set_override", overrideOwner: "routine_set_id"
        )
        for row in try Row.fetchAll(db, sql: "SELECT * FROM routine ORDER BY id") {
            let id: String = row["id"]
            let deleted: Int64? = row["deleted_at"]
            let body = SyncItem.RoutineBody(name: row["name"], position: row["position"], exercises: routineExercises[id] ?? [])
            items.append(SyncItem(kind: .routine, id: lower(id), updatedAt: row["updated_at"], deletedAt: deleted, body: deleted == nil ? .routine(body) : nil))
        }

        // Finished workouts. The running one stays on the phone.
        let workoutExercises = try exercises(
            in: db, exercise: "workout_exercise", parent: "workout_id", note: "workout_exercise_note",
            value: "workout_exercise_setting", valueOwner: "workout_exercise_id",
            set: "workout_set", setOwner: "workout_exercise_id", override: "workout_set_override", overrideOwner: "workout_set_id"
        )
        for row in try Row.fetchAll(db, sql: "SELECT * FROM workout WHERE finished_at IS NOT NULL ORDER BY id") {
            let id: String = row["id"]
            let deleted: Int64? = row["deleted_at"]
            let routineId: String? = row["routine_id"]
            let body = SyncItem.WorkoutBody(
                title: row["title"], note: row["note"], startedAt: row["started_at"], finishedAt: row["finished_at"],
                routineId: routineId.map(lower), importKey: row["import_key"],
                gymName: row["gym_name"], gymAddress: row["gym_address"], gymLatitude: row["gym_latitude"], gymLongitude: row["gym_longitude"],
                exercises: workoutExercises[id] ?? []
            )
            items.append(SyncItem(kind: .workout, id: lower(id), updatedAt: row["updated_at"], deletedAt: deleted, body: deleted == nil ? .workout(body) : nil))
        }

        for row in try Row.fetchAll(db, sql: "SELECT * FROM user_setting ORDER BY id") {
            let body = SyncItem.UserSettingBody(weightUnit: row["weight_unit"])
            items.append(SyncItem(kind: .userSetting, id: lower(row["id"]), updatedAt: row["updated_at"], deletedAt: row["deleted_at"], body: .userSetting(body)))
        }

        return items.map { LocalSyncItem(item: $0, hash: $0.contentHash) }
    }

    /// The exercises of every routine or every workout, by the routine or workout they belong to. Each
    /// table is read once and put together in memory, so the cost doesn't grow with a query per workout.
    private static func exercises(
        in db: Database, exercise: String, parent: String, note: String?, value: String, valueOwner: String,
        set: String, setOwner: String, override: String, overrideOwner: String
    ) throws -> [String: [SyncItem.Exercise]] {
        let notes = try note.map { grouped(try Row.fetchAll(db, sql: "SELECT * FROM \($0) ORDER BY position"), by: "workout_exercise_id") } ?? [:]
        let values = grouped(try Row.fetchAll(db, sql: "SELECT * FROM \(value) ORDER BY setting_id"), by: valueOwner)
        let sets = grouped(try Row.fetchAll(db, sql: "SELECT * FROM \(set) WHERE deleted_at IS NULL ORDER BY position"), by: setOwner)
        let overrides = grouped(try Row.fetchAll(db, sql: "SELECT * FROM \(override) ORDER BY setting_id"), by: overrideOwner)
        let inWorkout = note != nil

        var byParent: [String: [SyncItem.Exercise]] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT * FROM \(exercise) WHERE deleted_at IS NULL ORDER BY position") {
            let id: String = row["id"]
            let built = SyncItem.Exercise(
                id: lower(id), brandId: lower(row["exercise_brand_id"]), restSeconds: row["rest_seconds"],
                notes: (notes[id] ?? []).map { SyncItem.Note(id: lower($0["id"]), text: $0["text"]) },
                settings: (values[id] ?? []).map { SyncItem.SettingValue(settingId: lower($0["setting_id"]), value: $0["value"], textValue: $0["text_value"]) },
                sets: (sets[id] ?? []).map { s in
                    let setId: String = s["id"]
                    return SyncItem.WorkoutSet(
                        id: lower(setId), kind: s["kind"], setType: s["set_type"], weightKg: s["weight_kg"], reps: s["reps"],
                        durationSeconds: s["duration_seconds"], rpe: inWorkout ? s["rpe"] : nil, completedAt: inWorkout ? s["completed_at"] : nil,
                        overrides: (overrides[setId] ?? []).map { SyncItem.Override(settingId: lower($0["setting_id"]), value: $0["value"]) }
                    )
                }
            )
            byParent[row[parent] as String, default: []].append(built)
        }
        return byParent
    }

    // MARK: - Items to rows

    private static func upper(_ id: String) -> String { id.uppercased() }

    /// Built-in exercises by ID. A brand can arrive for one the phone has no row for yet, since those rows
    /// are made the first time an exercise is used.
    private static let builtInNames: [String: String] = Dictionary(
        ExerciseCatalogNames.builtIn.map { (SyncID.exercise(named: $0), $0) }, uniquingKeysWith: { a, _ in a }
    )

    private static func write(_ item: SyncItem, in db: Database) throws {
        let id = upper(item.id)
        switch item.body {
        case .exercise(let body):
            try db.execute(sql: """
                INSERT INTO exercise (id, name, equipment, is_builtin, updated_at, deleted_at) VALUES (?, ?, ?, 0, ?, ?)
                ON CONFLICT(id) DO UPDATE SET name = excluded.name, equipment = excluded.equipment, updated_at = excluded.updated_at, deleted_at = excluded.deleted_at
                """, arguments: [id, body.name, body.equipment, item.updatedAt, item.deletedAt])
            try db.execute(sql: "DELETE FROM exercise_muscle WHERE exercise_id = ?", arguments: [id])
            for muscle in body.muscles {
                try db.execute(sql: "INSERT INTO exercise_muscle (exercise_id, muscle, share) VALUES (?, ?, ?)", arguments: [id, muscle.muscle, muscle.share])
            }

        case .brand(let body):
            let exerciseId = upper(body.exerciseId)
            if let name = builtInNames[exerciseId], try !exists("exercise", id: exerciseId, in: db) {
                try db.execute(sql: "INSERT INTO exercise (id, name, equipment, is_builtin, updated_at) VALUES (?, ?, 'other', 1, ?)", arguments: [exerciseId, name, item.updatedAt])
            }
            try db.execute(sql: """
                INSERT INTO exercise_brand (id, exercise_id, brand, label, updated_at, deleted_at) VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET exercise_id = excluded.exercise_id, brand = excluded.brand, label = excluded.label,
                    updated_at = excluded.updated_at, deleted_at = excluded.deleted_at
                """, arguments: [id, exerciseId, body.brand, body.label, item.updatedAt, item.deletedAt])
            // A setting this phone has that the pulled brand doesn't is marked deleted, not removed: workouts
            // here may still point at it. One that moved to another brand arrives with that brand.
            let kept = body.settings.map { upper($0.id) }
            let placeholders = kept.isEmpty ? "''" : kept.map { _ in "?" }.joined(separator: ",")
            try db.execute(
                sql: "UPDATE setting SET deleted_at = ?, updated_at = ? WHERE exercise_brand_id = ? AND deleted_at IS NULL AND id NOT IN (\(placeholders))",
                arguments: StatementArguments([item.updatedAt, item.updatedAt, id] as [any DatabaseValueConvertible] + kept.map { $0 as any DatabaseValueConvertible })
            )
            for setting in body.settings {
                try db.execute(sql: """
                    INSERT INTO setting (id, exercise_brand_id, name, kind, value, text_value, direction, range_min, range_max, split_by_value, factor, position, updated_at, deleted_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET exercise_brand_id = excluded.exercise_brand_id, name = excluded.name, kind = excluded.kind,
                        value = excluded.value, text_value = excluded.text_value, direction = excluded.direction, range_min = excluded.range_min,
                        range_max = excluded.range_max, split_by_value = excluded.split_by_value, factor = excluded.factor, position = excluded.position,
                        updated_at = excluded.updated_at, deleted_at = excluded.deleted_at
                    """, arguments: [upper(setting.id), id, setting.name, setting.kind, setting.value, setting.textValue, setting.direction, setting.rangeMin,
                                     setting.rangeMax, setting.splitByValue, setting.factor, setting.position, item.updatedAt, setting.deletedAt])
            }

        case .routine(let body):
            try db.execute(sql: """
                INSERT INTO routine (id, name, position, updated_at, deleted_at) VALUES (?, ?, ?, ?, NULL)
                ON CONFLICT(id) DO UPDATE SET name = excluded.name, position = excluded.position, updated_at = excluded.updated_at, deleted_at = NULL
                """, arguments: [id, body.name, body.position, item.updatedAt])
            try db.execute(sql: "DELETE FROM routine_exercise WHERE routine_id = ?", arguments: [id])
            try insert(body.exercises, into: "routine", owner: id, updatedAt: item.updatedAt, in: db)

        case .workout(let body):
            try db.execute(sql: """
                INSERT INTO workout (id, title, note, started_at, finished_at, routine_id, import_key, gym_name, gym_address, gym_latitude, gym_longitude, updated_at, deleted_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)
                ON CONFLICT(id) DO UPDATE SET title = excluded.title, note = excluded.note, started_at = excluded.started_at, finished_at = excluded.finished_at,
                    routine_id = excluded.routine_id, import_key = excluded.import_key, gym_name = excluded.gym_name, gym_address = excluded.gym_address,
                    gym_latitude = excluded.gym_latitude, gym_longitude = excluded.gym_longitude, updated_at = excluded.updated_at, deleted_at = NULL
                """, arguments: [id, body.title, body.note, body.startedAt, body.finishedAt, body.routineId.map(upper), body.importKey,
                                 body.gymName, body.gymAddress, body.gymLatitude, body.gymLongitude, item.updatedAt])
            try db.execute(sql: "DELETE FROM workout_exercise WHERE workout_id = ?", arguments: [id])
            try insert(body.exercises, into: "workout", owner: id, updatedAt: item.updatedAt, in: db)

        case .userSetting(let body):
            try db.execute(sql: """
                INSERT INTO user_setting (id, weight_unit, updated_at, deleted_at) VALUES (?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET weight_unit = excluded.weight_unit, updated_at = excluded.updated_at, deleted_at = excluded.deleted_at
                """, arguments: [id, body.weightUnit, item.updatedAt, item.deletedAt])

        case nil:
            // A deleted routine or workout: the rows under it go, and the top row stays, marked deleted.
            // One this phone never had gets an empty row, so the deletion isn't asked for again.
            let deletedAt = item.deletedAt ?? item.updatedAt
            switch item.kind {
            case .routine:
                try db.execute(sql: "DELETE FROM routine_exercise WHERE routine_id = ?", arguments: [id])
                try db.execute(sql: """
                    INSERT INTO routine (id, name, position, updated_at, deleted_at) VALUES (?, '', 0, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at, deleted_at = excluded.deleted_at
                    """, arguments: [id, item.updatedAt, deletedAt])
            case .workout:
                try db.execute(sql: "DELETE FROM workout_exercise WHERE workout_id = ?", arguments: [id])
                try db.execute(sql: """
                    INSERT INTO workout (id, title, started_at, finished_at, updated_at, deleted_at) VALUES (?, '', 0, 0, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at, deleted_at = excluded.deleted_at
                    """, arguments: [id, item.updatedAt, deletedAt])
            case .exercise, .brand, .userSetting:
                break
            }
        }
    }

    /// Writes the exercises of a routine or a workout, with everything under them. `kind` is "routine" or "workout".
    private static func insert(_ exercises: [SyncItem.Exercise], into kind: String, owner: String, updatedAt: Int64, in db: Database) throws {
        for (position, exercise) in exercises.enumerated() {
            let exerciseId = upper(exercise.id)
            try db.execute(
                sql: "INSERT INTO \(kind)_exercise (id, \(kind)_id, exercise_brand_id, position, rest_seconds, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
                arguments: [exerciseId, owner, upper(exercise.brandId), position, exercise.restSeconds, updatedAt]
            )
            for (index, note) in exercise.notes.enumerated() where kind == "workout" {
                try db.execute(sql: "INSERT INTO workout_exercise_note (id, workout_exercise_id, position, text) VALUES (?, ?, ?, ?)",
                               arguments: [upper(note.id), exerciseId, index, note.text])
            }
            for value in exercise.settings {
                try db.execute(sql: "INSERT INTO \(kind)_exercise_setting (\(kind)_exercise_id, setting_id, value, text_value) VALUES (?, ?, ?, ?)",
                               arguments: [exerciseId, upper(value.settingId), value.value, value.textValue])
            }
            for (index, set) in exercise.sets.enumerated() {
                let setId = upper(set.id)
                if kind == "workout" {
                    try db.execute(sql: """
                        INSERT INTO workout_set (id, workout_exercise_id, position, kind, set_type, weight_kg, reps, duration_seconds, rpe, completed_at, updated_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """, arguments: [setId, exerciseId, index, set.kind, set.setType, set.weightKg, set.reps, set.durationSeconds, set.rpe, set.completedAt, updatedAt])
                } else {
                    try db.execute(sql: """
                        INSERT INTO routine_set (id, routine_exercise_id, position, kind, set_type, weight_kg, reps, duration_seconds, updated_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """, arguments: [setId, exerciseId, index, set.kind, set.setType, set.weightKg, set.reps, set.durationSeconds, updatedAt])
                }
                for override in set.overrides {
                    try db.execute(sql: "INSERT INTO \(kind)_set_override (\(kind)_set_id, setting_id, value) VALUES (?, ?, ?)",
                                   arguments: [setId, upper(override.settingId), override.value])
                }
            }
        }
    }
}
