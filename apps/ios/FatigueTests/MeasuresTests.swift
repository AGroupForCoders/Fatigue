import Foundation
import GRDB
import Testing
@testable import Fatigue

/// The move to per-exercise measures (ADR 0003): the phone migration that splits exercises mixing rep sets and
/// holds, and measures and every-set settings going through sync.
@MainActor
struct MeasuresMigrationTests {
    /// IDs as an older build would have made them.
    private static let shoulderPress = SyncID.exercise(named: "Shoulder Press")
    private static let hammer = "0B0C6F43-5E44-4C1D-9C5B-111111111111"
    private static let seat = "0B0C6F43-5E44-4C1D-9C5B-222222222222"
    private static let notch = "0B0C6F43-5E44-4C1D-9C5B-333333333333"
    private static let workout = "0B0C6F43-5E44-4C1D-9C5B-444444444444"
    private static let workoutExercise = "0B0C6F43-5E44-4C1D-9C5B-555555555555"
    private static let routine = "0B0C6F43-5E44-4C1D-9C5B-666666666666"
    private static let routineExercise = "0B0C6F43-5E44-4C1D-9C5B-777777777777"

    /// A database as a build before measures left it: Shoulder Press on Hammer Strength with Seat and a tracked
    /// Notch, and a workout and a routine that each have two rep sets at notch 7 and a hold that overrides it to 8.
    private func oldDatabase() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue, upTo: "v7-sync")
        try queue.write { db in
            try db.execute(sql: "INSERT INTO exercise (id, name, equipment, is_builtin, updated_at) VALUES (?, 'Shoulder Press', 'machine', 1, 1000)", arguments: [Self.shoulderPress])
            try db.execute(sql: "INSERT INTO exercise_muscle (exercise_id, muscle, share) VALUES (?, 'shoulders', 1)", arguments: [Self.shoulderPress])
            try db.execute(sql: "INSERT INTO exercise_brand (id, exercise_id, brand, updated_at) VALUES (?, ?, 'Hammer Strength', 1000)", arguments: [Self.hammer, Self.shoulderPress])
            try db.execute(sql: "INSERT INTO setting (id, exercise_brand_id, name, kind, value, position, updated_at) VALUES (?, ?, 'Seat', 'number', 4, 0, 1000)",
                           arguments: [Self.seat, Self.hammer])
            try db.execute(sql: """
                INSERT INTO setting (id, exercise_brand_id, name, kind, value, direction, range_min, range_max, position, updated_at)
                VALUES (?, ?, 'Notch', 'number', 7, 'higher', 1, 10, 1, 1000)
                """, arguments: [Self.notch, Self.hammer])

            try db.execute(sql: "INSERT INTO workout (id, title, started_at, finished_at, updated_at) VALUES (?, 'Push', 1000, 4000, 4000)", arguments: [Self.workout])
            try db.execute(sql: "INSERT INTO workout_exercise (id, workout_id, exercise_brand_id, position, rest_seconds, updated_at) VALUES (?, ?, ?, 0, 90, 4000)",
                           arguments: [Self.workoutExercise, Self.workout, Self.hammer])
            for (setting, value) in [(Self.seat, 4.0), (Self.notch, 7.0)] {
                try db.execute(sql: "INSERT INTO workout_exercise_setting (workout_exercise_id, setting_id, value) VALUES (?, ?, ?)",
                               arguments: [Self.workoutExercise, setting, value])
            }
            try db.execute(sql: "INSERT INTO routine (id, name, position, updated_at) VALUES (?, 'Push', 0, 4000)", arguments: [Self.routine])
            try db.execute(sql: "INSERT INTO routine_exercise (id, routine_id, exercise_brand_id, position, rest_seconds, updated_at) VALUES (?, ?, ?, 0, 90, 4000)",
                           arguments: [Self.routineExercise, Self.routine, Self.hammer])
            try db.execute(sql: "INSERT INTO routine_exercise_setting (routine_exercise_id, setting_id, value) VALUES (?, ?, 7)", arguments: [Self.routineExercise, Self.notch])

            for table in ["workout", "routine"] {
                let owner = table == "workout" ? Self.workoutExercise : Self.routineExercise
                let sets: [(kind: String, reps: Int?, seconds: Int?, weight: Double)] = [("hold", nil, 30, 40), ("reps", 10, nil, 50), ("reps", 8, nil, 55)]
                for (index, set) in sets.enumerated() {
                    let id = SyncID.uuid5("\(table)-set-\(index)").uuidString
                    try db.execute(sql: """
                        INSERT INTO \(table)_set (id, \(table)_exercise_id, position, kind, weight_kg, reps, duration_seconds, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, 4000)
                        """, arguments: [id, owner, index, set.kind, set.weight, set.reps, set.seconds])
                    if set.kind == "hold" {
                        try db.execute(sql: "INSERT INTO \(table)_set_override (\(table)_set_id, setting_id, value) VALUES (?, ?, 8)", arguments: [id, Self.notch])
                    }
                }
            }
        }
        return queue
    }

    @Test func aMixedExerciseSplitsIntoItsIsometricOne() throws {
        let database = try AppDatabase(try oldDatabase())
        let isometricId = SyncID.exercise(named: "Shoulder Press Isometric")

        let library = try database.library()
        let isometric = try #require(library.exercises.first { $0.name == "Shoulder Press Isometric" })
        #expect(isometric.measures == ExerciseMeasures(amount: .hold, weighted: true))
        #expect(isometric.equipment == "machine")
        #expect(isometric.muscles.map(\.muscle) == ["shoulders"])
        #expect(library.exercises.first { $0.name == "Shoulder Press" }?.measures == ExerciseMeasures())

        // The workout now has the rep sets on Shoulder Press, then the hold on its isometric exercise, on its own
        // Hammer Strength with the settings copied.
        let workout = try #require(try database.workouts().first)
        #expect(workout.exercises.map(\.name) == ["Shoulder Press", "Shoulder Press Isometric"])
        #expect(workout.exercises.map(\.brand) == ["Hammer Strength", "Hammer Strength"])
        #expect(workout.exercises[0].sets.map(\.kind) == ["reps", "reps"])
        #expect(workout.exercises[1].sets.map(\.kind) == ["hold"])
        #expect(workout.exercises[1].measures == ExerciseMeasures(amount: .hold, weighted: true))
        let copiedNotch = MeasuresMigration.copyId("setting", of: Self.notch)
        #expect(workout.exercises[1].settings.map(\.id) == [MeasuresMigration.copyId("setting", of: Self.seat), copiedNotch])
        #expect(workout.exercises[1].sets[0].overrides == [copiedNotch: 8])
        #expect(workout.exercises[1].id == MeasuresMigration.copyId("workout_exercise", of: Self.workoutExercise))

        // Notch was changed by a group, so it's now typed on every set, and the rep sets get notch 7 as their own.
        #expect(workout.exercises[0].settings.first { $0.name == "Notch" }?.everySet == true)
        #expect(workout.exercises[0].settings.first { $0.name == "Seat" }?.everySet == false)
        #expect(workout.exercises[0].sets.map { $0.overrides[Self.notch] } == [7, 7])

        let routine = try #require(try database.routines().first)
        #expect(routine.exercises.map(\.name) == ["Shoulder Press", "Shoulder Press Isometric"])
        #expect(routine.exercises[1].sets.map(\.kind) == ["hold"])
        #expect(try database.writer.read { try String.fetchOne($0, sql: "SELECT exercise_id FROM exercise_brand WHERE id = ?", arguments: [MeasuresMigration.copyId("exercise_brand", of: Self.hammer)]) } == isometricId)
    }

    @Test func twoPhonesMigratingTheSameHistoryAgree() throws {
        let one = try AppDatabase(try oldDatabase())
        let two = try AppDatabase(try oldDatabase())
        let first = try one.syncItems().map { "\($0.item.key) \($0.hash)" }.sorted()
        let second = try two.syncItems().map { "\($0.item.key) \($0.hash)" }.sorted()
        #expect(first == second)
        // The isometric exercise syncs; Shoulder Press itself is built in with its default measures, so it doesn't.
        #expect(first.contains { $0.hasPrefix("exercise:\(SyncID.exercise(named: "Shoulder Press Isometric").lowercased())") })
        #expect(!first.contains { $0.hasPrefix("exercise:\(Self.shoulderPress.lowercased())") })
    }

    @Test func anExerciseThatWasOnlyHoldsIsCountedInTime() throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue, upTo: "v7-sync")
        let wallSit = SyncID.exercise(named: "Hollow Hold")
        try queue.write { db in
            try db.execute(sql: "INSERT INTO exercise (id, name, equipment, is_builtin, updated_at) VALUES (?, 'Hollow Hold', 'bodyweight', 0, 1000)", arguments: [wallSit])
            try db.execute(sql: "INSERT INTO exercise_brand (id, exercise_id, updated_at) VALUES (?, ?, 1000)", arguments: [SyncID.noBrand(exerciseId: wallSit), wallSit])
            try db.execute(sql: "INSERT INTO workout (id, title, started_at, finished_at, updated_at) VALUES ('W', 'Core', 1000, 2000, 2000)")
            try db.execute(sql: "INSERT INTO workout_exercise (id, workout_id, exercise_brand_id, position, rest_seconds, updated_at) VALUES ('WE', 'W', ?, 0, 60, 2000)",
                           arguments: [SyncID.noBrand(exerciseId: wallSit)])
            try db.execute(sql: "INSERT INTO workout_set (id, workout_exercise_id, position, kind, duration_seconds, updated_at) VALUES ('S', 'WE', 0, 'hold', 60, 2000)")
        }
        let database = try AppDatabase(queue)
        #expect(try database.library().exercises.first?.measures == ExerciseMeasures(amount: .hold, weighted: false))
        #expect(try database.library().exercises.count == 1)
    }
}

@MainActor
struct MeasuresSyncTests {
    @Test func measuresAndEverySetSettingsGoThroughSync() throws {
        let one = try AppDatabase.inMemory()
        let catalog = ExerciseCatalog.load(from: one)
        let notch = ExerciseSetting(name: "Notch", value: "7", direction: .higher, rangeMin: 1, rangeMax: 10, everySet: true)
        catalog.save(ExerciseInfo(name: "Copenhagen Plank", equipment: .bodyweight, primaryMuscle: .adductors, isCustom: true,
                                  measures: ExerciseMeasures(amount: .hold, weighted: false)),
                     brand: nil, setup: BrandSetup(settings: [notch]))
        // A built-in exercise with weight turned on, unlike its default.
        let pullUp = try #require(catalog.info(named: "Pull Up"))
        var weighted = pullUp
        weighted.measures.weighted = true
        catalog.save(weighted, brand: nil, setup: BrandSetup())

        let items = try one.syncItems().map(\.item)
        let exercises = items.compactMap { item -> SyncItem.ExerciseBody? in if case .exercise(let body)? = item.body { body } else { nil } }
        #expect(exercises.first { $0.name == "Copenhagen Plank" }?.measures == ["time"])
        #expect(exercises.first { $0.name == "Pull Up" }?.measures == ["weight", "reps"])
        // Built-in exercises still on their defaults don't sync.
        #expect(!exercises.contains { $0.name == "Bench Press" })
        let settings = items.compactMap { item -> [SyncItem.Setting]? in if case .brand(let body)? = item.body { body.settings } else { nil } }.flatMap { $0 }
        #expect(settings.first { $0.name == "Notch" }?.everySet == true)

        let two = try AppDatabase.inMemory()
        try two.applyPulled(items, cursor: 1)
        let pulled = ExerciseCatalog.load(from: two)
        #expect(pulled.info(named: "Copenhagen Plank")?.measures == ExerciseMeasures(amount: .hold, weighted: false))
        #expect(pulled.info(named: "Pull Up")?.measures == ExerciseMeasures(weighted: true))
        #expect(pulled.info(named: "Pull Up")?.isCustom == false)
        #expect(pulled.setup(for: "Copenhagen Plank", brand: nil).settings.first?.everySet == true)
        // What arrived is what both now agree on, so there's nothing to push back.
        #expect(try two.pendingSyncItems().isEmpty)
    }

    @Test func anExerciseFromABuildBeforeMeasuresKeepsTheMeasuresItHas() throws {
        let one = try AppDatabase.inMemory()
        let catalog = ExerciseCatalog.load(from: one)
        catalog.save(ExerciseInfo(name: "Copenhagen Plank", equipment: .bodyweight, primaryMuscle: .adductors, isCustom: true,
                                  measures: ExerciseMeasures(amount: .hold, weighted: false)), brand: nil, setup: BrandSetup())
        var item = try #require(try one.syncItems().first { $0.item.kind == .exercise }?.item)
        guard case .exercise(var body)? = item.body else { Issue.record("Not an exercise"); return }
        body.measures = nil
        item.body = .exercise(body)
        item.updatedAt += 1
        try one.applyPulled([item], cursor: 2)
        #expect(ExerciseCatalog.load(from: one).info(named: "Copenhagen Plank")?.measures.amount == .hold)
    }

    @Test func aSettingWithoutEverySetReadsAsNotEverySet() throws {
        let json = #"{"id":"a","name":"Seat","kind":"number","splitByValue":false,"position":0}"#
        let setting = try JSONDecoder().decode(SyncItem.Setting.self, from: Data(json.utf8))
        #expect(setting.everySet == false)
    }
}
