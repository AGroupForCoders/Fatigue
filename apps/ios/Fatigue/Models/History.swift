import Foundation

/// A workout you finished: what you did and when. Only ticked sets are kept.
struct FinishedWorkout: Identifiable {
    let id: UUID
    var title: String
    /// What you want to remember about it, such as "Deload week, knee felt fine".
    var description: String
    var startedAt: Date
    var duration: TimeInterval
    /// The exercises with the sets you ticked, in the order you did them.
    var exercises: [WorkoutExercise]

    init(id: UUID = UUID(), title: String, description: String = "", startedAt: Date, duration: TimeInterval, exercises: [WorkoutExercise]) {
        self.id = id
        self.title = title
        self.description = description
        self.startedAt = startedAt
        self.duration = duration
        self.exercises = exercises
    }

    var setCount: Int { exercises.reduce(0) { $0 + $1.sets.count } }

    /// Total kilograms moved across rep sets, as weight × reps. Holds are left out, since a second isn't a rep,
    /// and so are warm-ups.
    var volume: Double {
        exercises.flatMap(\.sets).reduce(0) { total, set in
            guard set.counts, set.kind == .reps, let weight = Double(set.weight), let reps = Double(set.amount) else { return total }
            return total + weight * reps
        }
    }

    /// Opens this workout on the workout screen for editing: no rest timer, and it keeps its date.
    func editingSession() -> WorkoutSession {
        let session = WorkoutSession(title: title, exercises: exercises, startedAt: startedAt)
        session.startsRestWhenTicked = false
        return session
    }

    /// This workout with the edits from the workout screen. Sets you unticked while editing are dropped.
    func updated(from session: WorkoutSession) -> FinishedWorkout {
        var copy = session.finished(at: startedAt.addingTimeInterval(duration))
        copy = FinishedWorkout(id: id, title: copy.title, description: description, startedAt: startedAt, duration: duration, exercises: copy.exercises)
        return copy
    }

    /// A prebuilt workout with the same exercises, sets and setups, to start again another day.
    func asRoutine() -> Routine {
        Routine(name: title, exercises: exercises.map { exercise in
            RoutineExercise(
                name: exercise.name,
                brand: exercise.brand,
                restSeconds: exercise.restSeconds,
                settings: exercise.settings,
                sets: exercise.sets.map { RoutineSet(setup: $0.setup, type: $0.type, weight: $0.weight, amount: $0.amount) }
            )
        })
    }
}

extension [FinishedWorkout] {
    /// How many of these workouts logged sets on an exercise, on any brand. Said when you delete the exercise.
    func count(using exerciseName: String) -> Int {
        filter { $0.exercises.contains { $0.name == exerciseName } }.count
    }
}

/// What to do with sets you didn't tick when you finish.
enum UntickedSets {
    /// Leave them out of the saved workout.
    case drop
    /// Save them as done, as if you'd ticked them.
    case count
}

extension WorkoutSession {
    /// Sets that aren't ticked yet, which finishing will ask about.
    var untickedCount: Int { setCount - doneCount }

    /// Ticks every set, for when you finish and choose to count unticked sets as done.
    func tickAll() {
        for e in exercises.indices {
            for s in exercises[e].sets.indices { exercises[e].sets[s].isDone = true }
        }
    }

    /// What finishing would save, without changing the workout: the summary shows this before you confirm.
    func preview(unticked: UntickedSets, at end: Date) -> FinishedWorkout {
        guard unticked == .count else { return finished(at: end) }
        let copy = WorkoutSession(title: title, exercises: exercises, startedAt: startedAt)
        copy.tickAll()
        return copy.finished(at: end)
    }

    /// What gets saved when you finish: ticked sets only, and exercises with none ticked are dropped.
    func finished(at end: Date) -> FinishedWorkout {
        FinishedWorkout(
            title: title,
            startedAt: startedAt,
            duration: end.timeIntervalSince(startedAt),
            exercises: exercises.compactMap { exercise in
                var exercise = exercise
                exercise.sets = exercise.sets.filter(\.isDone)
                return exercise.sets.isEmpty ? nil : exercise
            }
        )
    }
}

extension FinishedWorkout {
    /// Past workouts for the spike, so the profile has history to show before the database exists.
    static func samples(now: Date = .now) -> [FinishedWorkout] {
        func day(_ daysAgo: Double) -> Date { now.addingTimeInterval(-daysAgo * 86_400) }
        func reps(_ weight: String, _ reps: String, rpe: [Double]) -> [WorkoutSet] {
            rpe.map { WorkoutSet(setup: SetSetup(kind: .reps), weight: weight, amount: reps, rpe: $0, previous: "", isDone: true) }
        }
        func exercise(_ name: String, brand: String? = nil, _ sets: [WorkoutSet], settings: [ExerciseSetting] = []) -> WorkoutExercise {
            WorkoutExercise(name: name, brand: brand, restSeconds: 90, settings: settings, sets: sets)
        }
        return [
            FinishedWorkout(title: "Pull", startedAt: day(2), duration: 52 * 60, exercises: [
                exercise("Lat Pulldown", reps("65", "10", rpe: [8, 8.5, 9])),
                exercise("Seated Row", brand: "Life Fitness", reps("60", "10", rpe: [8, 8.5, 9])),
                exercise("Bicep Curl", reps("14", "12", rpe: [8, 9, 9.5])),
            ]),
            FinishedWorkout(title: "Push", description: "Shoulder felt tight, kept the press light.", startedAt: day(4), duration: 47 * 60, exercises: [
                exercise("Chest Press", brand: "Technogym", reps("70", "8", rpe: [8, 8.5, 9])),
                exercise("Shoulder Press", brand: "Hammer Strength", reps("40", "10", rpe: [8, 9, 9])),
                exercise("Triceps Pushdown", reps("30", "12", rpe: [8.5, 9])),
            ]),
            FinishedWorkout(title: "Leg day", startedAt: day(6), duration: 74 * 60, exercises: [
                exercise("Adductors", brand: "Technogym", [
                    WorkoutSet(setup: SetSetup(kind: .hold, values: ["Notch": 8]), weight: "40", amount: "45", rpe: 8, previous: "", isDone: true),
                    WorkoutSet(setup: SetSetup(kind: .reps), weight: "55", amount: "8", rpe: 8.5, previous: "", isDone: true),
                    WorkoutSet(setup: SetSetup(kind: .reps), weight: "55", amount: "7", rpe: 9, previous: "", isDone: true),
                ], settings: ExerciseCatalog.sampleAdductorSettings),
                exercise("Leg Press", reps("160", "10", rpe: [8, 8.5, 9])),
                exercise("Leg Extension", reps("50", "12", rpe: [8, 9])),
                exercise("Leg Curl", reps("45", "12", rpe: [8, 9])),
                exercise("Hip Thrust", reps("100", "10", rpe: [8, 8.5])),
                exercise("Hack Squat", reps("80", "8", rpe: [9])),
                exercise("Seated Calf Raise", brand: "Hammer Strength", reps("60", "12", rpe: [8, 9, 9.5])),
            ]),
        ]
    }
}
