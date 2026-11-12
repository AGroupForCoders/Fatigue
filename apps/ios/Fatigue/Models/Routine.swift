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
    /// Everything about the exercise except its id, for telling whether a workout changed it.
    var shape: [String] {
        [name, brand ?? "", String(restSeconds)]
            + settings.map { "\($0.name)=\($0.value)" }
            + sets.map { "\($0.setup.kind.rawValue) \($0.setup.values.sorted { $0.key < $1.key }) \($0.weight)x\($0.amount)" }
    }

    let id = UUID()
    var name: String
    var brand: String?
    var restSeconds = 90
    var settings: [ExerciseSetting] = []
    var sets: [RoutineSet]

    /// A new exercise in the routine editor: three plain rep sets with nothing filled in,
    /// and the settings saved for it with no brand.
    static func new(named name: String, settings: [ExerciseSetting] = []) -> RoutineExercise {
        RoutineExercise(name: name, settings: settings, sets: Array(repeating: RoutineSet(setup: SetSetup(kind: .reps)), count: 3))
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
        let session = WorkoutSession(
            title: name,
            exercises: exercises.map { exercise in
                WorkoutExercise(
                    name: exercise.name,
                    brand: exercise.brand,
                    restSeconds: exercise.restSeconds,
                    settings: exercise.settings,
                    sets: exercise.sets.map { set in
                        WorkoutSet(setup: set.setup, weight: set.weight, amount: set.amount, previous: Self.target(set))
                    }
                )
            },
            now: now
        )
        session.routineID = id
        return session
    }

    /// This prebuilt workout rebuilt from a workout you did: same name, today's exercises,
    /// settings, sets and weights as the new targets.
    func updated(from session: WorkoutSession) -> Routine {
        var routine = self
        routine.exercises = session.exercises.map { exercise in
            RoutineExercise(
                name: exercise.name,
                brand: exercise.brand,
                restSeconds: exercise.restSeconds,
                settings: exercise.settings,
                sets: exercise.sets.map { RoutineSet(setup: $0.setup, weight: $0.weight, amount: $0.amount) }
            )
        }
        return routine
    }

    /// Whether a workout started from this one ended up different: exercises added, removed or
    /// reordered, a brand or settings changed, or sets added, removed or changed.
    func differs(from session: WorkoutSession) -> Bool {
        updated(from: session).exercises.map(\.shape) != exercises.map(\.shape)
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

    /// Ends the workout and puts it at the top of your history, if it has any sets to keep.
    ///
    /// - Parameters:
    ///   - title: The name it's saved under, which you can change on the summary.
    ///   - description: Anything you wrote about it.
    ///   - unticked: Whether sets you didn't tick are dropped or counted as done.
    ///   - updateRoutine: Whether the prebuilt workout it came from takes today's exercises and sets.
    /// History only lives in memory until the local database exists.
    func finish(title: String? = nil, description: String = "", unticked: UntickedSets = .drop, updateRoutine: Bool = false) {
        guard let session = active else { return }
        if unticked == .count { session.tickAll() }
        if updateRoutine, let id = session.routineID, let index = routines.firstIndex(where: { $0.id == id }) {
            routines[index] = routines[index].updated(from: session)
        }
        var finished = session.finished(at: now())
        if let title, !title.trimmingCharacters(in: .whitespaces).isEmpty { finished.title = title.trimmingCharacters(in: .whitespaces) }
        finished.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if finished.setCount > 0 { history.insert(finished, at: 0) }
        isShowingActive = false
        active = nil
    }

    /// The prebuilt workout the running workout started from, if any and if it still exists.
    var activeRoutine: Routine? {
        guard let id = active?.routineID else { return nil }
        return routines.first { $0.id == id }
    }

    /// Changes a finished workout's name and description.
    func rename(_ workoutID: UUID, title: String, description: String) {
        guard let index = history.firstIndex(where: { $0.id == workoutID }) else { return }
        let title = title.trimmingCharacters(in: .whitespaces)
        if !title.isEmpty { history[index].title = title }
        history[index].description = description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Replaces a prebuilt workout with an edited copy.
    func update(_ routine: Routine) {
        guard let index = routines.firstIndex(where: { $0.id == routine.id }) else { return }
        routines[index] = routine
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
    /// Adds exercises picked from the library, each with one empty rep set to start,
    /// and the settings saved for it with no brand.
    func addExercises(named names: [String], catalog: ExerciseCatalog? = nil) {
        for name in names {
            let saved = catalog?.setup(for: name, brand: nil) ?? BrandSetup()
            exercises.append(WorkoutExercise(
                name: name, brand: nil, restSeconds: 90, settings: saved.settings,
                sets: [WorkoutSet(setup: SetSetup(kind: .reps), weight: "", amount: "", previous: "")]
            ))
        }
    }

    /// Applies an edit from the exercise editor to an exercise in this workout.
    /// Renamed settings keep their group overrides, and removed or text settings drop theirs.
    func applyEdit(to exerciseIndex: Int, name: String, settings: [ExerciseSetting], renamedSettings: [String: String]) {
        exercises[exerciseIndex].name = name
        exercises[exerciseIndex].settings = settings
        let kept = Set(settings.filter { $0.kind != .text }.map(\.name))
        for setIndex in exercises[exerciseIndex].sets.indices {
            var values: [String: Double] = [:]
            for (key, value) in exercises[exerciseIndex].sets[setIndex].setup.values {
                let newKey = renamedSettings[key] ?? key
                if kept.contains(newKey) { values[newKey] = value }
            }
            exercises[exerciseIndex].sets[setIndex].setup.values = values
        }
    }

    /// Switches an exercise to another brand, bringing in the settings saved for that brand.
    func changeBrand(of exerciseIndex: Int, to brand: String?, catalog: ExerciseCatalog) {
        exercises[exerciseIndex].brand = brand
        exercises[exerciseIndex].settings = catalog.setup(for: exercises[exerciseIndex].name, brand: brand).settings
    }
}

extension Routine {
    /// The prebuilt workouts the spike starts with.
    static let samples: [Routine] = [
        Routine(name: "Leg day", exercises: [
            RoutineExercise(
                name: "Adductors", brand: "Technogym", restSeconds: 120,
                settings: ExerciseCatalog.sampleAdductorSettings,
                sets: [
                    RoutineSet(setup: SetSetup(kind: .hold, values: ["Notch": 8]), weight: "40", amount: "45"),
                    RoutineSet(setup: SetSetup(kind: .reps), weight: "55", amount: "8"),
                    RoutineSet(setup: SetSetup(kind: .reps), weight: "55", amount: "8"),
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
