import Foundation

// Turns the app's model into what the database stores, and back. Runs on the main actor, where the model lives.

private func number(_ text: String) -> Double? { Double(text.trimmingCharacters(in: .whitespaces)) }
private func whole(_ text: String) -> Int? { number(text).map { Int($0.rounded()) } }
private func uuid(_ text: String) -> UUID { UUID(uuidString: text) ?? UUID() }

// MARK: Settings

extension ExerciseSetting {
    var stored: StoredSetting {
        let kindName: String
        var value: Double?
        var textValue: String?
        switch kind {
        case .number:
            kindName = "number"
            value = number(self.value)
        case .yesNo:
            kindName = "yes_no"
            value = self.value == "yes" ? 1 : 0
        case .text:
            kindName = "text"
            textValue = self.value.isEmpty ? nil : self.value
        }
        return StoredSetting(
            id: id.uuidString, name: name, kind: kindName, value: value, textValue: textValue,
            direction: direction.map { $0 == .higher ? "higher" : "lower" },
            rangeMin: rangeMin, rangeMax: rangeMax, splitByValue: splitByValue,
            factor: kind == .yesNo ? factor : nil
        )
    }

    init(stored: StoredSetting) {
        let kind: Kind = stored.kind == "yes_no" ? .yesNo : stored.kind == "text" ? .text : .number
        let value: String = switch kind {
        case .number: stored.value.map(PlainNumber.string) ?? ""
        case .yesNo: stored.value == 1 ? "yes" : "no"
        case .text: stored.textValue ?? ""
        }
        self.init(
            id: uuid(stored.id), name: stored.name, kind: kind, value: value,
            direction: stored.direction.map { $0 == "lower" ? .lower : .higher },
            rangeMin: stored.rangeMin, rangeMax: stored.rangeMax, splitByValue: stored.splitByValue,
            factor: stored.factor
        )
    }
}

// MARK: Sets and exercises

/// A group's overrides, from setting names (how the app keys them) to setting ids (how they're stored).
private func overrides(_ setup: SetSetup, settings: [ExerciseSetting]) -> [String: Double] {
    var byId: [String: Double] = [:]
    for (name, value) in setup.values {
        if let setting = settings.first(where: { $0.name == name && $0.kind != .text }) { byId[setting.id.uuidString] = value }
    }
    return byId
}

private func setup(kind: String, overrides: [String: Double], settings: [StoredSetting]) -> SetSetup {
    var values: [String: Double] = [:]
    for (id, value) in overrides {
        if let setting = settings.first(where: { $0.id == id }) { values[setting.name] = value }
    }
    return SetSetup(kind: SetKind(rawValue: kind) ?? .reps, values: values)
}

private func storedSet(id: String, kind: SetKind, weight: String, amount: String, rpe: Double?, completedAt: Int64?, overrides: [String: Double]) -> StoredSet {
    StoredSet(
        id: id, kind: kind.rawValue, weightKg: number(weight),
        reps: kind == .reps ? whole(amount) : nil, durationSeconds: kind == .hold ? whole(amount) : nil,
        rpe: rpe, completedAt: completedAt, overrides: overrides
    )
}

private func amount(of set: StoredSet) -> String {
    (set.reps ?? set.durationSeconds).map(String.init) ?? ""
}

extension WorkoutExercise {
    /// `completedAt` stamps ticked sets; the app doesn't track when each one was ticked yet.
    func stored(completedAt: Int64) -> StoredExercise {
        StoredExercise(
            id: id.uuidString, name: name, brand: brand?.name, label: brand?.label, restSeconds: restSeconds,
            settings: settings.map(\.stored),
            notes: notes.map { StoredNote(id: $0.id.uuidString, text: $0.text) },
            sets: sets.map { set in
                storedSet(id: set.id.uuidString, kind: set.kind, weight: set.weight, amount: set.amount, rpe: set.rpe,
                          completedAt: set.isDone ? completedAt : nil, overrides: overrides(set.setup, settings: settings))
            }
        )
    }

    init(stored: StoredExercise) {
        self.init(
            id: uuid(stored.id), name: stored.name, brand: Brand(name: stored.brand, label: stored.label), restSeconds: stored.restSeconds,
            notes: stored.notes.map { ExerciseNote(id: uuid($0.id), text: $0.text) },
            settings: stored.settings.map(ExerciseSetting.init(stored:)),
            sets: stored.sets.map { set in
                WorkoutSet(
                    id: uuid(set.id), setup: setup(kind: set.kind, overrides: set.overrides, settings: stored.settings),
                    weight: set.weightKg.map(PlainNumber.string) ?? "", amount: amount(of: set), rpe: set.rpe,
                    previous: "", isDone: set.completedAt != nil
                )
            }
        )
    }
}

// MARK: Workouts

private func millis(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1000).rounded()) }

extension FinishedWorkout {
    var stored: StoredWorkout {
        let end = startedAt.addingTimeInterval(duration)
        return StoredWorkout(
            id: id.uuidString, title: title, note: description.isEmpty ? nil : description,
            startedAt: startedAt, finishedAt: end, routineId: nil,
            exercises: exercises.map { $0.stored(completedAt: millis(end)) }
        )
    }

    init(stored: StoredWorkout) {
        let end = stored.finishedAt ?? stored.startedAt
        self.init(
            id: uuid(stored.id), title: stored.title, description: stored.note ?? "",
            startedAt: stored.startedAt, duration: end.timeIntervalSince(stored.startedAt),
            exercises: stored.exercises.map(WorkoutExercise.init(stored:))
        )
    }
}

extension WorkoutSession {
    /// The running workout, with no finish time.
    var stored: StoredWorkout {
        StoredWorkout(
            id: id.uuidString, title: title, note: nil, startedAt: startedAt, finishedAt: nil,
            routineId: routineID?.uuidString, exercises: exercises.map { $0.stored(completedAt: millis(.now)) }
        )
    }

    convenience init(stored: StoredWorkout) {
        self.init(title: stored.title, exercises: stored.exercises.map(WorkoutExercise.init(stored:)), startedAt: stored.startedAt)
        id = uuid(stored.id)
        routineID = stored.routineId.map(uuid)
    }
}

// MARK: Prebuilt workouts

extension Routine {
    var stored: StoredRoutine {
        StoredRoutine(id: id.uuidString, name: name, exercises: exercises.map { exercise in
            StoredExercise(
                id: exercise.id.uuidString, name: exercise.name, brand: exercise.brand?.name, label: exercise.brand?.label, restSeconds: exercise.restSeconds,
                settings: exercise.settings.map(\.stored), notes: [],
                sets: exercise.sets.map { set in
                    // Planned sets have no id in the app, so each save gives them a new one.
                    storedSet(id: UUID().uuidString, kind: set.setup.kind, weight: set.weight, amount: set.amount, rpe: nil,
                              completedAt: nil, overrides: overrides(set.setup, settings: exercise.settings))
                }
            )
        })
    }

    init(stored: StoredRoutine) {
        self.init(id: uuid(stored.id), name: stored.name, exercises: stored.exercises.map { exercise in
            RoutineExercise(
                id: uuid(exercise.id), name: exercise.name, brand: Brand(name: exercise.brand, label: exercise.label), restSeconds: exercise.restSeconds,
                settings: exercise.settings.map(ExerciseSetting.init(stored:)),
                sets: exercise.sets.map { set in
                    RoutineSet(
                        setup: setup(kind: set.kind, overrides: set.overrides, settings: exercise.settings),
                        weight: set.weightKg.map(PlainNumber.string) ?? "", amount: amount(of: set)
                    )
                }
            )
        })
    }
}

// MARK: Library

extension ExerciseCatalog {
    var stored: StoredLibrary {
        StoredLibrary(
            exercises: exercises.map { info in
                StoredExerciseInfo(
                    name: info.name, equipment: info.equipment.rawValue, isBuiltin: !info.isCustom,
                    muscles: [StoredMuscle(muscle: info.primaryMuscle.rawValue, share: 1)]
                        + info.secondaryMuscles.map { StoredMuscle(muscle: $0.rawValue, share: 0.5) }
                )
            },
            setups: savedSetups.map { key, setup in
                let (name, brand) = ExerciseCatalog.parse(key: key)
                return StoredSetup(name: name, brand: brand?.name, label: brand?.label, settings: setup.settings.map(\.stored))
            }
        )
    }

    /// The library from what's saved, on top of the built-in exercises. An empty database
    /// starts from the sample settings, so debug builds have something to show.
    convenience init(stored: StoredLibrary) {
        var exercises = Dictionary(ExerciseCatalog.builtIn.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        for row in stored.exercises where !row.muscles.isEmpty || !row.isBuiltin {
            let primary = row.muscles.first { $0.share == 1 }.flatMap { Muscle(rawValue: $0.muscle) } ?? exercises[row.name]?.primaryMuscle ?? .chest
            exercises[row.name] = ExerciseInfo(
                name: row.name,
                equipment: Equipment(rawValue: row.equipment) ?? exercises[row.name]?.equipment ?? .other,
                primaryMuscle: primary,
                secondaryMuscles: row.muscles.filter { $0.share < 1 }.compactMap { Muscle(rawValue: $0.muscle) },
                isCustom: !row.isBuiltin
            )
        }
        var setups: [String: BrandSetup] = [:]
        for setup in stored.setups {
            setups[ExerciseCatalog.key(setup.name, Brand(name: setup.brand, label: setup.label))] = BrandSetup(settings: setup.settings.map(ExerciseSetting.init(stored:)))
        }
        self.init(exercises: Array(exercises.values), setups: stored.exercises.isEmpty && stored.setups.isEmpty ? ExerciseCatalog.sampleSetups : setups)
    }
}
