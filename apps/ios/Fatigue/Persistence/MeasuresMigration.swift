import Foundation
import GRDB

/// Moves the phone from set setups to per-exercise measures (ADR 0003). Runs once as the `v8-measures`
/// migration, and its first two steps run again after every pull, since a phone on an older build can still
/// push workouts that mix rep sets and holds on one exercise.
///
/// Every row it makes gets an ID built from the row it came from, so two phones that each migrate the same
/// history end up with the same rows, and sync sees one exercise, one brand and one workout exercise rather
/// than two of each.
nonisolated enum MeasuresMigration {
    /// The whole migration: split mixed exercises, fill in measures, then make the settings that groups of sets
    /// used to change into every-set settings.
    static func run(in db: Database) throws {
        // Read first: splitting moves the holds' overrides onto the copied settings.
        let overridden = Set(try String.fetchAll(db, sql: "SELECT setting_id FROM workout_set_override UNION SELECT setting_id FROM routine_set_override"))
        try splitMixedExercises(in: db)
        try fillMissingMeasures(in: db)
        try markEverySetSettings(overridden.union(overridden.map { copyId("setting", of: $0) }), in: db)
    }

    /// What a pull needs: the same split and fill, for whatever an older build sent.
    static func tidyPulled(in db: Database) throws {
        try splitMixedExercises(in: db)
        try fillMissingMeasures(in: db)
    }

    /// The name of the exercise a mixed exercise's holds move to, such as "Shoulder Press Isometric".
    static func isometricName(of name: String) -> String { "\(name) Isometric" }

    /// The ID of a row copied from another one, the same on every phone.
    static func copyId(_ table: String, of id: String) -> String {
        SyncID.uuid5("measures:\(table):\(id.lowercased())").uuidString
    }

    // MARK: - Splitting

    private struct Usage {
        var reps = false
        var holds = false
        var weight = false
    }

    /// What the sets logged and planned on each exercise are: rep sets, holds, and whether any has a weight.
    private static func usage(in db: Database) throws -> [String: Usage] {
        var usage: [String: Usage] = [:]
        let rows = try Row.fetchAll(db, sql: """
            SELECT eb.exercise_id, s.kind, s.weight_kg FROM workout_set s
            JOIN workout_exercise we ON we.id = s.workout_exercise_id JOIN exercise_brand eb ON eb.id = we.exercise_brand_id
            WHERE s.deleted_at IS NULL
            UNION ALL
            SELECT eb.exercise_id, s.kind, s.weight_kg FROM routine_set s
            JOIN routine_exercise re ON re.id = s.routine_exercise_id JOIN exercise_brand eb ON eb.id = re.exercise_brand_id
            WHERE s.deleted_at IS NULL
            """)
        for row in rows {
            let id: String = row["exercise_id"]
            if (row["kind"] as String) == SetKind.hold.rawValue { usage[id, default: Usage()].holds = true } else { usage[id, default: Usage()].reps = true }
            if (row["weight_kg"] as Double?) != nil { usage[id, default: Usage()].weight = true }
        }
        return usage
    }

    /// Moves the holds out of every exercise counted in reps that has both, into "<Name> Isometric", which is
    /// made with the same equipment and muscles if it isn't there yet. Each brand the holds were done on comes
    /// along with its settings, and every workout and routine exercise with holds gets a second exercise
    /// straight after it, which the holds and their setting values move to.
    static func splitMixedExercises(in db: Database) throws {
        let usage = try usage(in: db)
        for row in try Row.fetchAll(db, sql: "SELECT * FROM exercise ORDER BY id") {
            let id: String = row["id"]
            guard let use = usage[id], use.reps, use.holds else { continue }
            let measures = ExerciseMeasures(stored: row["measures"])
            guard measures?.amount ?? .reps == .reps else { continue }
            let isometric = try isometricExercise(of: row, in: db)
            for table in ["workout", "routine"] {
                let owners = try Row.fetchAll(db, sql: """
                    SELECT DISTINCT x.* FROM \(table)_exercise x JOIN exercise_brand eb ON eb.id = x.exercise_brand_id
                    JOIN \(table)_set s ON s.\(table)_exercise_id = x.id
                    WHERE eb.exercise_id = ? AND s.kind = 'hold' ORDER BY x.id
                    """, arguments: [id])
                for owner in owners {
                    let brand = try copyBrand(owner["exercise_brand_id"], to: isometric, in: db)
                    try moveHolds(of: owner, in: table, to: brand, in: db)
                }
            }
        }
    }

    /// The isometric exercise for `exercise`, made if it doesn't exist yet. Returns its ID.
    private static func isometricExercise(of exercise: Row, in db: Database) throws -> String {
        let name = isometricName(of: exercise["name"])
        let built = SyncID.exercise(named: name)
        if let id = try String.fetchOne(db, sql: "SELECT id FROM exercise WHERE name = ? OR id = ? ORDER BY name = ? DESC", arguments: [name, built, name]) {
            return id
        }
        let source: String = exercise["id"]
        try db.execute(sql: """
            INSERT INTO exercise (id, name, equipment, is_builtin, updated_at, deleted_at) VALUES (?, ?, ?, ?, ?, ?)
            """, arguments: [built, name, exercise["equipment"], ExerciseCatalogNames.builtIn.contains(name), exercise["updated_at"], exercise["deleted_at"]])
        try db.execute(sql: "INSERT INTO exercise_muscle (exercise_id, muscle, share) SELECT ?, muscle, share FROM exercise_muscle WHERE exercise_id = ?",
                       arguments: [built, source])
        return built
    }

    /// The isometric exercise's row for the same brand and label as `brandId`, with that brand's settings copied
    /// over. Returns the new brand's ID and, for each copied setting, its new ID.
    private static func copyBrand(_ brandId: String, to exerciseId: String, in db: Database) throws -> (id: String, settings: [String: String]) {
        guard let brand = try Row.fetchOne(db, sql: "SELECT * FROM exercise_brand WHERE id = ?", arguments: [brandId]) else { return (brandId, [:]) }
        let name: String? = brand["brand"]
        let label: String? = brand["label"]
        let id: String
        if let existing = try String.fetchOne(db, sql: "SELECT id FROM exercise_brand WHERE exercise_id = ? AND brand IS ? AND label IS ?", arguments: [exerciseId, name, label]) {
            id = existing
        } else {
            id = name == nil && label == nil ? SyncID.noBrand(exerciseId: exerciseId) : copyId("exercise_brand", of: brandId)
            try db.execute(sql: "INSERT INTO exercise_brand (id, exercise_id, brand, label, updated_at, deleted_at) VALUES (?, ?, ?, ?, ?, ?)",
                           arguments: [id, exerciseId, name, label, brand["updated_at"], brand["deleted_at"]])
        }
        let there = try Row.fetchAll(db, sql: "SELECT id, name FROM setting WHERE exercise_brand_id = ?", arguments: [id])
        let thereByName = Dictionary(there.map { (($0["name"] as String).lowercased(), $0["id"] as String) }, uniquingKeysWith: { a, _ in a })
        var settings: [String: String] = [:]
        for setting in try Row.fetchAll(db, sql: "SELECT * FROM setting WHERE exercise_brand_id = ? ORDER BY position, id", arguments: [brandId]) {
            let old: String = setting["id"]
            if let match = thereByName[(setting["name"] as String).lowercased()] {
                settings[old] = match
                continue
            }
            let new = copyId("setting", of: old)
            try db.execute(sql: """
                INSERT OR IGNORE INTO setting (id, exercise_brand_id, name, kind, value, text_value, direction, range_min, range_max, split_by_value, factor, every_set, position, updated_at, deleted_at)
                SELECT ?, ?, name, kind, value, text_value, direction, range_min, range_max, split_by_value, factor, every_set, position, updated_at, deleted_at
                FROM setting WHERE id = ?
                """, arguments: [new, id, old])
            settings[old] = new
        }
        return (id, settings)
    }

    /// Moves the holds of one workout or routine exercise into a new one on the isometric brand, just after it,
    /// with the exercise's setting values and the holds' own values pointed at the copied settings. When nothing
    /// is left behind, the new one takes the old one's place and notes.
    private static func moveHolds(of owner: Row, in table: String, to brand: (id: String, settings: [String: String]), in db: Database) throws {
        let old: String = owner["id"]
        let new = copyId("\(table)_exercise", of: old)
        let position: Double = owner["position"]
        try db.execute(sql: """
            INSERT OR IGNORE INTO \(table)_exercise (id, \(table)_id, exercise_brand_id, position, rest_seconds, updated_at, deleted_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """, arguments: [new, owner["\(table)_id"], brand.id, position + 0.5, owner["rest_seconds"], owner["updated_at"], owner["deleted_at"]])
        for value in try Row.fetchAll(db, sql: "SELECT * FROM \(table)_exercise_setting WHERE \(table)_exercise_id = ?", arguments: [old]) {
            let setting: String = value["setting_id"]
            try db.execute(sql: "INSERT OR IGNORE INTO \(table)_exercise_setting (\(table)_exercise_id, setting_id, value, text_value) VALUES (?, ?, ?, ?)",
                           arguments: [new, brand.settings[setting] ?? setting, value["value"], value["text_value"]])
        }
        let holds = try String.fetchAll(db, sql: "SELECT id FROM \(table)_set WHERE \(table)_exercise_id = ? AND kind = 'hold'", arguments: [old])
        for hold in holds {
            try db.execute(sql: "UPDATE \(table)_set SET \(table)_exercise_id = ? WHERE id = ?", arguments: [new, hold])
            for (from, to) in brand.settings where from != to {
                try db.execute(sql: "UPDATE OR REPLACE \(table)_set_override SET setting_id = ? WHERE \(table)_set_id = ? AND setting_id = ?", arguments: [to, hold, from])
            }
        }
        let left = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)_set WHERE \(table)_exercise_id = ?", arguments: [old]) ?? 0
        if left == 0 {
            if table == "workout" {
                try db.execute(sql: "UPDATE workout_exercise_note SET workout_exercise_id = ? WHERE workout_exercise_id = ?", arguments: [new, old])
            }
            try db.execute(sql: "DELETE FROM \(table)_exercise WHERE id = ?", arguments: [old])
            try db.execute(sql: "UPDATE \(table)_exercise SET position = ? WHERE id = ?", arguments: [position, new])
        }
    }

    // MARK: - Measures

    /// Gives every exercise without measures the ones its history shows: time if every set is a hold, reps
    /// otherwise, and weight if any set has one or it isn't a bodyweight exercise. One with no history gets its
    /// defaults (see `ExerciseCatalogNames.defaultMeasures`).
    static func fillMissingMeasures(in db: Database) throws {
        let usage = try usage(in: db)
        for row in try Row.fetchAll(db, sql: "SELECT id, name, equipment FROM exercise WHERE measures IS NULL") {
            let id: String = row["id"]
            let equipment: String = row["equipment"]
            let measures: ExerciseMeasures
            if let use = usage[id] {
                measures = ExerciseMeasures(amount: use.holds && !use.reps ? .hold : .reps, weighted: use.weight || equipment != "bodyweight")
            } else {
                measures = ExerciseCatalogNames.defaultMeasures(name: row["name"], equipment: equipment)
            }
            try db.execute(sql: "UPDATE exercise SET measures = ? WHERE id = ?", arguments: [measures.stored, id])
        }
    }

    // MARK: - Every-set settings

    /// A tracked number setting that a group of sets changed somewhere in history (`overridden`, which includes
    /// the copies made for isometric exercises) becomes an every-set setting, as long as it fits in the
    /// exercise's measures. Sets that used the exercise's value get it as their own, so their history reads the
    /// same as before.
    static func markEverySetSettings(_ overridden: Set<String>, in db: Database) throws {
        let candidates = try Row.fetchAll(db, sql: """
            SELECT s.id, s.exercise_brand_id, e.measures FROM setting s
            JOIN exercise_brand eb ON eb.id = s.exercise_brand_id JOIN exercise e ON e.id = eb.exercise_id
            WHERE s.kind = 'number' AND s.direction IS NOT NULL AND s.range_min IS NOT NULL AND s.range_max IS NOT NULL AND s.range_max > s.range_min
            ORDER BY s.exercise_brand_id, s.position, s.id
            """).filter { overridden.contains($0["id"]) }
        var taken: [String: Int] = [:]
        for row in candidates {
            let id: String = row["id"]
            let brand: String = row["exercise_brand_id"]
            let measures = ExerciseMeasures(stored: row["measures"]) ?? ExerciseMeasures()
            guard measures.fits(everySet: taken[brand, default: 0] + 1) else { continue }
            taken[brand, default: 0] += 1
            try db.execute(sql: "UPDATE setting SET every_set = 1 WHERE id = ?", arguments: [id])
            for table in ["workout", "routine"] {
                try db.execute(sql: """
                    INSERT INTO \(table)_set_override (\(table)_set_id, setting_id, value)
                    SELECT s.id, v.setting_id, v.value FROM \(table)_set s
                    JOIN \(table)_exercise_setting v ON v.\(table)_exercise_id = s.\(table)_exercise_id
                    WHERE v.setting_id = ? AND v.value IS NOT NULL
                      AND NOT EXISTS (SELECT 1 FROM \(table)_set_override o WHERE o.\(table)_set_id = s.id AND o.setting_id = v.setting_id)
                    """, arguments: [id])
            }
        }
    }
}
