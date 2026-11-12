import Foundation

// Turns the app's model into database rows and back. Runs on the main actor, where the model lives.

private func number(_ text: String) -> Double? { Double(text.trimmingCharacters(in: .whitespaces)) }
private func text(_ number: Double?) -> String { number.map(PlainNumber.string) ?? "" }
private func uuid(_ text: String) -> UUID { UUID(uuidString: text) ?? UUID() }

// MARK: Settings

extension ExerciseSetting {
    /// How the kind is written in the database, matching the data model's `number` and `yes_no`.
    var kindName: String {
        switch kind {
        case .number: "number"
        case .yesNo: "yes_no"
        case .text: "text"
        }
    }

    func row(owner: String, position: Int) -> SettingRow {
        SettingRow(
            id: id.uuidString, ownerId: owner, position: position, name: name,
            kind: kindName,
            value: value,
            direction: direction.map { $0 == .higher ? "higher" : "lower" },
            rangeMin: rangeMin, rangeMax: rangeMax, splitByValue: splitByValue
        )
    }

    init(row: SettingRow) {
        self.init(
            id: uuid(row.id), name: row.name,
            kind: row.kind == "yes_no" ? .yesNo : row.kind == "text" ? .text : .number,
            value: row.value,
            direction: row.direction.map { $0 == "lower" ? .lower : .higher },
            rangeMin: row.rangeMin, rangeMax: row.rangeMax, splitByValue: row.splitByValue
        )
    }
}

private func settingRows(_ settings: [ExerciseSetting], owner: String) -> [SettingRow] {
    settings.enumerated().map { $1.row(owner: owner, position: $0) }
}

private func valueRows(_ setup: SetSetup, setId: String) -> [SetValueRow] {
    setup.values.map { SetValueRow(setId: setId, settingName: $0.key, value: $0.value) }
}

private func setup(kind: String, values: [SetValueRow]) -> SetSetup {
    SetSetup(kind: SetKind(rawValue: kind) ?? .reps, values: Dictionary(values.map { ($0.settingName, $0.value) }, uniquingKeysWith: { a, _ in a }))
}

// MARK: Workouts

extension WorkoutRows {
    /// Rows for one workout, finished or running.
    init(id: UUID, title: String, description: String, startedAt: Date, duration: TimeInterval, routineID: UUID?, isActive: Bool, exercises: [WorkoutExercise]) {
        self.init()
        workouts = [WorkoutRow(
            id: id.uuidString, title: title, description: description, startedAt: startedAt,
            durationSeconds: duration, routineId: routineID?.uuidString, isActive: isActive, updatedAt: 0, deletedAt: nil
        )]
        for (position, exercise) in exercises.enumerated() {
            let exerciseId = exercise.id.uuidString
            self.exercises.append(WorkoutExerciseRow(
                id: exerciseId, workoutId: id.uuidString, position: position, name: exercise.name,
                brand: exercise.brand, restSeconds: exercise.restSeconds, updatedAt: 0, deletedAt: nil
            ))
            settings += settingRows(exercise.settings, owner: exerciseId)
            notes += exercise.notes.enumerated().map { NoteRow(id: $1.id.uuidString, workoutExerciseId: exerciseId, position: $0, text: $1.text) }
            for (setPosition, set) in exercise.sets.enumerated() {
                let setId = set.id.uuidString
                sets.append(WorkoutSetRow(
                    id: setId, workoutExerciseId: exerciseId, position: setPosition, kind: set.kind.rawValue,
                    weightKg: number(set.weight), amount: number(set.amount), rpe: set.rpe,
                    isDone: set.isDone, previous: set.previous, updatedAt: 0, deletedAt: nil
                ))
                values += valueRows(set.setup, setId: setId)
            }
        }
    }

    /// The exercises under one workout row, rebuilt.
    func exercises(of workoutId: String) -> [WorkoutExercise] {
        let setsByExercise = Dictionary(grouping: sets, by: \.workoutExerciseId)
        let valuesBySet = Dictionary(grouping: values, by: \.setId)
        let settingsByOwner = Dictionary(grouping: settings, by: \.ownerId)
        let notesByExercise = Dictionary(grouping: notes, by: \.workoutExerciseId)
        return exercises.filter { $0.workoutId == workoutId }.sorted { $0.position < $1.position }.map { row in
            WorkoutExercise(
                id: uuid(row.id), name: row.name, brand: row.brand, restSeconds: row.restSeconds,
                notes: (notesByExercise[row.id] ?? []).sorted { $0.position < $1.position }.map { ExerciseNote(id: uuid($0.id), text: $0.text) },
                settings: (settingsByOwner[row.id] ?? []).sorted { $0.position < $1.position }.map(ExerciseSetting.init(row:)),
                sets: (setsByExercise[row.id] ?? []).sorted { $0.position < $1.position }.map { set in
                    WorkoutSet(
                        id: uuid(set.id), setup: setup(kind: set.kind, values: valuesBySet[set.id] ?? []),
                        weight: text(set.weightKg), amount: text(set.amount), rpe: set.rpe,
                        previous: set.previous, isDone: set.isDone
                    )
                }
            )
        }
    }

    /// Finished workouts, newest first.
    var history: [FinishedWorkout] {
        workouts.filter { !$0.isActive }.sorted { $0.startedAt > $1.startedAt }.map { row in
            FinishedWorkout(
                id: uuid(row.id), title: row.title, description: row.description,
                startedAt: row.startedAt, duration: row.durationSeconds, exercises: exercises(of: row.id)
            )
        }
    }

    /// The workout that was running when the app last closed, if any.
    var active: WorkoutSession? {
        guard let row = workouts.first(where: \.isActive) else { return nil }
        let session = WorkoutSession(title: row.title, exercises: exercises(of: row.id), startedAt: row.startedAt)
        session.id = uuid(row.id)
        session.routineID = row.routineId.map(uuid)
        return session
    }
}

extension FinishedWorkout {
    var rows: WorkoutRows {
        WorkoutRows(id: id, title: title, description: description, startedAt: startedAt, duration: duration, routineID: nil, isActive: false, exercises: exercises)
    }
}

extension WorkoutSession {
    var rows: WorkoutRows {
        WorkoutRows(id: id, title: title, description: "", startedAt: startedAt, duration: Date.now.timeIntervalSince(startedAt), routineID: routineID, isActive: true, exercises: exercises)
    }
}

// MARK: Prebuilt workouts

extension RoutineRows {
    init(_ routines: [Routine]) {
        self.init()
        for (position, routine) in routines.enumerated() {
            let routineId = routine.id.uuidString
            self.routines.append(RoutineRow(id: routineId, name: routine.name, position: position, updatedAt: 0, deletedAt: nil))
            for (exercisePosition, exercise) in routine.exercises.enumerated() {
                let exerciseId = exercise.id.uuidString
                exercises.append(RoutineExerciseRow(
                    id: exerciseId, routineId: routineId, position: exercisePosition,
                    name: exercise.name, brand: exercise.brand, restSeconds: exercise.restSeconds
                ))
                settings += settingRows(exercise.settings, owner: exerciseId)
                for (setPosition, set) in exercise.sets.enumerated() {
                    // Planned sets have no id of their own in the app, so one is made per save.
                    let setId = UUID().uuidString
                    sets.append(RoutineSetRow(
                        id: setId, routineExerciseId: exerciseId, position: setPosition,
                        kind: set.setup.kind.rawValue, weightKg: number(set.weight), amount: number(set.amount)
                    ))
                    values += valueRows(set.setup, setId: setId)
                }
            }
        }
    }

    var routinesInOrder: [Routine] {
        let exercisesByRoutine = Dictionary(grouping: exercises, by: \.routineId)
        let setsByExercise = Dictionary(grouping: sets, by: \.routineExerciseId)
        let valuesBySet = Dictionary(grouping: values, by: \.setId)
        let settingsByOwner = Dictionary(grouping: settings, by: \.ownerId)
        return routines.sorted { $0.position < $1.position }.map { row in
            Routine(
                id: uuid(row.id), name: row.name,
                exercises: (exercisesByRoutine[row.id] ?? []).sorted { $0.position < $1.position }.map { exercise in
                    RoutineExercise(
                        id: uuid(exercise.id), name: exercise.name, brand: exercise.brand, restSeconds: exercise.restSeconds,
                        settings: (settingsByOwner[exercise.id] ?? []).sorted { $0.position < $1.position }.map(ExerciseSetting.init(row:)),
                        sets: (setsByExercise[exercise.id] ?? []).sorted { $0.position < $1.position }.map { set in
                            RoutineSet(setup: setup(kind: set.kind, values: valuesBySet[set.id] ?? []), weight: text(set.weightKg), amount: text(set.amount))
                        }
                    )
                }
            )
        }
    }
}

// MARK: Library

extension ExerciseCatalog {
    /// Rows for every exercise and every exercise-and-brand's settings.
    var rows: LibraryRows {
        var rows = LibraryRows()
        for info in exercises {
            rows.exercises.append(ExerciseRow(name: info.name, equipment: info.equipment.rawValue, isBuiltin: !info.isCustom))
            rows.muscles.append(ExerciseMuscleRow(exerciseName: info.name, muscle: info.primaryMuscle.rawValue, share: 1))
            rows.muscles += info.secondaryMuscles.map { ExerciseMuscleRow(exerciseName: info.name, muscle: $0.rawValue, share: 0.5) }
        }
        for (key, setup) in savedSetups {
            rows.settings += settingRows(setup.settings, owner: "library:\(key)")
        }
        return rows
    }

    /// The library from saved rows, on top of the built-in exercises.
    convenience init(rows: LibraryRows) {
        let musclesByExercise = Dictionary(grouping: rows.muscles, by: \.exerciseName)
        var exercises = Dictionary(ExerciseCatalog.builtIn.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        for row in rows.exercises {
            let muscles = musclesByExercise[row.name] ?? []
            let primary = muscles.first { $0.share == 1 }.flatMap { Muscle(rawValue: $0.muscle) } ?? exercises[row.name]?.primaryMuscle ?? .chest
            exercises[row.name] = ExerciseInfo(
                name: row.name,
                equipment: Equipment(rawValue: row.equipment) ?? .other,
                primaryMuscle: primary,
                secondaryMuscles: muscles.filter { $0.share < 1 }.compactMap { Muscle(rawValue: $0.muscle) },
                isCustom: !row.isBuiltin
            )
        }
        let settingsByKey = Dictionary(grouping: rows.settings) { String($0.ownerId.dropFirst("library:".count)) }
        let setups = settingsByKey.mapValues { BrandSetup(settings: $0.sorted { $0.position < $1.position }.map(ExerciseSetting.init(row:))) }
        self.init(exercises: Array(exercises.values), setups: rows.exercises.isEmpty && rows.settings.isEmpty ? ExerciseCatalog.sampleSetups : setups)
    }
}
