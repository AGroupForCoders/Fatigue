import Foundation
import Observation

/// A prebuilt workout: a name and the exercises and sets to start from.
/// Starting one copies it into a new `WorkoutSession`, so changes during the workout never reach it.
struct Routine: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var exercises: [RoutineExercise]

    var setCount: Int { exercises.reduce(0) { $0 + $1.sets.count } }
}

/// One exercise in a prebuilt workout.
struct RoutineExercise: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var brand: String?
    var restSeconds = 90
    var fields: [SetField] = []
    var sets: [RoutineSet]

    /// A new exercise in the routine editor: three plain rep sets with nothing filled in.
    static func new(named name: String) -> RoutineExercise {
        RoutineExercise(name: name, sets: Array(repeating: RoutineSet(setup: SetSetup(kind: .reps)), count: 3))
    }
}

/// One planned set: its setup and the target weight and reps or seconds.
struct RoutineSet: Equatable {
    var setup: SetSetup
    var weight = ""
    var amount = ""
}

extension Routine {
    /// A fresh running workout from this routine, with new ids so it shares nothing with the routine.
    /// Each set's target shows in Previous until real history exists.
    func start(now: @escaping () -> Date = Date.init) -> WorkoutSession {
        WorkoutSession(
            title: name,
            exercises: exercises.map { exercise in
                WorkoutExercise(
                    name: exercise.name,
                    brand: exercise.brand,
                    restSeconds: exercise.restSeconds,
                    fields: exercise.fields,
                    sets: exercise.sets.map { set in
                        WorkoutSet(setup: set.setup, weight: set.weight, amount: set.amount, previous: Self.target(set))
                    }
                )
            },
            now: now
        )
    }

    private static func target(_ set: RoutineSet) -> String {
        guard !set.weight.isEmpty, !set.amount.isEmpty else { return "" }
        return "\(set.weight) × \(set.amount)\(set.setup.kind == .hold ? "s" : "")"
    }
}

/// The workouts you have and the one you are doing, shared by the Workout tab, the bar above
/// the bottom nav and the workout screen.
@Observable
final class WorkoutStore {
    var routines: [Routine]
    /// Finished workouts, newest first.
    private(set) var history: [FinishedWorkout]
    /// The workout running now, if any. Only one runs at a time.
    private(set) var active: WorkoutSession?
    /// Whether the running workout fills the screen, or sits in the bar above the bottom nav.
    var isShowingActive = false
    private let now: () -> Date

    init(routines: [Routine] = Routine.samples, history: [FinishedWorkout] = FinishedWorkout.samples(), now: @escaping () -> Date = Date.init) {
        self.routines = routines
        self.history = history
        self.now = now
    }

    func start(_ routine: Routine) {
        active = routine.start(now: now)
        isShowingActive = true
    }

    func startEmpty() {
        active = WorkoutSession(title: "Workout", exercises: [], now: now)
        isShowingActive = true
    }

    /// Ends the workout and puts it at the top of your history, if you ticked anything.
    /// History only lives in memory until the local database exists.
    func finish() {
        if let finished = active?.finished(at: now()), finished.setCount > 0 {
            history.insert(finished, at: 0)
        }
        isShowingActive = false
        active = nil
    }

    /// Throws the running workout away without saving it.
    func discard() {
        isShowingActive = false
        active = nil
    }

    /// Puts an edited past workout back in its place in history.
    func replace(_ workout: FinishedWorkout) {
        guard let index = history.firstIndex(where: { $0.id == workout.id }) else { return }
        if workout.setCount == 0 { history.remove(at: index) } else { history[index] = workout }
    }

    func deleteFromHistory(_ workoutID: UUID) {
        history.removeAll { $0.id == workoutID }
    }

    func add(_ routine: Routine) {
        routines.append(routine)
    }

    func delete(_ routineID: UUID) {
        routines.removeAll { $0.id == routineID }
    }
}

extension WorkoutSession {
    /// Adds exercises picked from the library, each with one empty rep set to start.
    func addExercises(named names: [String]) {
        for name in names {
            exercises.append(WorkoutExercise(name: name, brand: nil, restSeconds: 90, sets: [WorkoutSet(setup: SetSetup(kind: .reps), weight: "", amount: "", previous: "")]))
        }
    }
}

/// The built-in exercises, until the real library ships with the local database.
nonisolated enum ExerciseLibrary {
    static let all = [
        "Adductors", "Abductors", "Bench Press", "Bicep Curl", "Cable Fly", "Calf Raise", "Chest Press",
        "Deadlift", "Hack Squat", "Hip Thrust", "Incline Dumbbell Press", "Lat Pulldown", "Lateral Raise",
        "Leg Curl", "Leg Extension", "Leg Press", "Pec Deck", "Preacher Curl", "Pull Up", "Rear Delt Fly",
        "Romanian Deadlift", "Seated Calf Raise", "Seated Row", "Shoulder Press", "Squat", "Triceps Pushdown",
    ]
}

extension Routine {
    /// The prebuilt workouts the spike starts with.
    static let samples: [Routine] = [
        Routine(name: "Leg day", exercises: [
            RoutineExercise(
                name: "Adductors", brand: "Technogym", restSeconds: 120,
                fields: [SetField(name: "Notch", kind: .number), SetField(name: "Dead stop", kind: .yesNo)],
                sets: [
                    RoutineSet(setup: SetSetup(kind: .hold, values: ["Notch": 8]), weight: "40", amount: "45"),
                    RoutineSet(setup: SetSetup(kind: .reps, values: ["Notch": 7, "Dead stop": 1]), weight: "55", amount: "8"),
                    RoutineSet(setup: SetSetup(kind: .reps, values: ["Notch": 7, "Dead stop": 1]), weight: "55", amount: "8"),
                ]
            ),
            RoutineExercise(name: "Leg Press", restSeconds: 150, sets: Array(repeating: RoutineSet(setup: SetSetup(kind: .reps), weight: "160", amount: "10"), count: 3)),
            RoutineExercise(name: "Seated Calf Raise", brand: "Hammer Strength", sets: Array(repeating: RoutineSet(setup: SetSetup(kind: .reps), weight: "60", amount: "12"), count: 3)),
        ]),
        Routine(name: "Push", exercises: [
            RoutineExercise(name: "Chest Press", brand: "Technogym", restSeconds: 120, sets: Array(repeating: RoutineSet(setup: SetSetup(kind: .reps), weight: "70", amount: "8"), count: 3)),
            RoutineExercise(name: "Shoulder Press", brand: "Hammer Strength", sets: Array(repeating: RoutineSet(setup: SetSetup(kind: .reps), weight: "40", amount: "10"), count: 3)),
            RoutineExercise(name: "Triceps Pushdown", restSeconds: 60, sets: Array(repeating: RoutineSet(setup: SetSetup(kind: .reps), weight: "30", amount: "12"), count: 3)),
        ]),
        Routine(name: "Pull", exercises: [
            RoutineExercise(name: "Lat Pulldown", restSeconds: 120, sets: Array(repeating: RoutineSet(setup: SetSetup(kind: .reps), weight: "65", amount: "10"), count: 3)),
            RoutineExercise(name: "Seated Row", brand: "Life Fitness", sets: Array(repeating: RoutineSet(setup: SetSetup(kind: .reps), weight: "60", amount: "10"), count: 3)),
            RoutineExercise(name: "Bicep Curl", restSeconds: 60, sets: Array(repeating: RoutineSet(setup: SetSetup(kind: .reps), weight: "14", amount: "12"), count: 3)),
        ]),
    ]
}
