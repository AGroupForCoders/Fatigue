import Foundation
import Observation

/// A prebuilt workout: a name and the exercises and sets to start from.
/// Starting one copies it into a new `WorkoutSession`, so changes during the workout never reach it.
struct Routine: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var exercises: [RoutineExercise]

    var setCount: Int { exercises.reduce(0) { $0 + $1.sets.count } }
}

/// One exercise in a prebuilt workout.
struct RoutineExercise: Identifiable, Equatable {
    /// Everything about the exercise except its id, for telling whether a workout changed it.
    var shape: [String] {
        [name, brand?.key ?? "", String(restSeconds)]
            + settings.map { "\($0.name)=\($0.value)" }
            + sets.map { "\($0.setup.kind.rawValue) \($0.type.rawValue) \($0.setup.values.sorted { $0.key < $1.key }) \($0.weight)x\($0.amount)" }
    }

    var id = UUID()
    var name: String
    var brand: Brand?
    var restSeconds = 90
    var settings: [ExerciseSetting] = []
    var sets: [RoutineSet]

    /// A new exercise in the routine editor: three plain rep sets with nothing filled in,
    /// and the settings saved for it with no brand.
    static func new(named name: String, brand: Brand? = nil, settings: [ExerciseSetting] = []) -> RoutineExercise {
        RoutineExercise(name: name, brand: brand, settings: settings, sets: Array(repeating: RoutineSet(setup: SetSetup(kind: .reps)), count: 3))
    }
}

/// One planned set: its setup and the target weight and reps or seconds.
struct RoutineSet: Equatable {
    var setup: SetSetup
    var type: SetType = .normal
    /// Always kilograms, as on `WorkoutSet`.
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
                        WorkoutSet(setup: set.setup, type: set.type, weight: set.weight, amount: set.amount, previous: Self.target(set))
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
                sets: exercise.sets.map { RoutineSet(setup: $0.setup, type: $0.type, weight: $0.weight, amount: $0.amount) }
            )
        }
        return routine
    }

    /// Whether a workout started from this one ended up different: exercises added, removed or
    /// reordered, a brand or settings changed, or sets added, removed or changed.
    func differs(from session: WorkoutSession) -> Bool {
        updated(from: session).exercises.map(\.shape) != exercises.map(\.shape)
    }

    private static func target(_ set: RoutineSet) -> PreviousSet? {
        guard !set.weight.isEmpty, !set.amount.isEmpty else { return nil }
        return PreviousSet(kind: set.setup.kind, weightKg: Double(set.weight), amount: set.amount)
    }
}

/// The workouts you have and the one you are doing, shared by the Workout tab, the bar above
/// the bottom nav and the workout screen.
@Observable
final class WorkoutStore {
    var routines: [Routine] {
        didSet {
            let stored = routines.map(\.stored)
            persist { try $0.save(stored) }
        }
    }
    /// Finished workouts, newest first.
    private(set) var history: [FinishedWorkout]
    /// The workout running now, if any. Only one runs at a time.
    private(set) var active: WorkoutSession?
    /// Whether the running workout fills the screen, or sits in the bar above the bottom nav.
    /// A workout restored from the database opens full screen on launch. Debug builds also
    /// start one open with `-openWorkout`, for screenshots.
    var isShowingActive = ProcessInfo.processInfo.arguments.contains("-openWorkout")
    private let now: () -> Date
    /// Where everything is saved. Nil keeps it in memory, as tests and previews do.
    private let database: AppDatabase?
    /// The photos and videos on each workout. They follow a workout when it's finished, and go when it's deleted.
    let media: MediaStore

    init(routines: [Routine] = Routine.samples, history: [FinishedWorkout] = FinishedWorkout.samples(), media: MediaStore = MediaStore(), now: @escaping () -> Date = Date.init) {
        self.routines = routines
        self.history = history
        self.media = media
        self.now = now
        self.database = nil
    }

    /// Loads everything saved on the phone, including a workout that was running when the app closed.
    /// Debug builds fill an empty database with the sample workouts, so there's something to look at.
    init(database: AppDatabase, media: MediaStore? = nil, now: @escaping () -> Date = Date.init) {
        self.database = database
        self.media = media ?? MediaStore(database: database)
        self.now = now
        let workouts = (try? database.workouts()) ?? []
        routines = ((try? database.routines()) ?? []).map(Routine.init(stored:))
        history = workouts.filter { $0.finishedAt != nil }.map(FinishedWorkout.init(stored:))
        active = workouts.first { $0.finishedAt == nil }.map(WorkoutSession.init(stored:))
        #if DEBUG
        if routines.isEmpty, history.isEmpty, active == nil {
            routines = Routine.samples
            history = FinishedWorkout.samples()
            try? database.save(routines.map(\.stored))
            for workout in history { try? database.save(workout.stored) }
        }
        #endif
        if let active {
            // Previous isn't stored, since it comes from history; fill it in again.
            active.previousLookup = previousSets
            for index in active.exercises.indices { active.fillPrevious(for: index) }
            // The app opens straight into a running workout. The store is only built on a cold
            // launch, so coming back from the background leaves a minimised workout minimised.
            isShowingActive = true
        }
    }

    func start(_ routine: Routine) {
        let session = routine.start(now: now)
        begin(session)
        for index in session.exercises.indices { session.fillPrevious(for: index) }
        saveActive()
    }

    func startEmpty() {
        begin(WorkoutSession(title: "Workout", exercises: [], now: now))
        saveActive()
    }

    private func begin(_ session: WorkoutSession) {
        session.previousLookup = previousSets
        active = session
        isShowingActive = true
    }

    /// Your sets on an exercise and brand the last time you did it, newest workout first.
    func previousSets(name: String, brand: Brand?) -> [WorkoutSet] {
        for workout in history {
            if let exercise = workout.exercises.first(where: { $0.name == name && $0.brand == brand }) { return exercise.sets }
        }
        return []
    }

    /// Every finished workout as export rows, one per set, newest workout first.
    func exportRows() -> [ExportRow] {
        history.flatMap { $0.exportRows() }
    }

    /// Saves the running workout as it is now. Called after every change, and when the app goes to the background.
    func saveActive() {
        guard let session = active else { return }
        let stored = session.stored
        persist { try $0.save(stored) }
    }

    /// Saves the running workout a moment after each change, for as long as it runs.
    /// Waiting a moment means typing a weight saves once, not once per digit.
    func autosaveActive() async {
        while !Task.isCancelled, let session = active {
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                withObservationTracking {
                    _ = session.title
                    _ = session.exercises
                } onChange: {
                    done.resume()
                }
            }
            try? await Task.sleep(for: .milliseconds(400))
            guard active === session else { return }
            saveActive()
        }
    }

    /// Runs a database write, if there's a database. A failed write is logged rather than shown,
    /// since the app can carry on with what's in memory.
    private func persist(_ write: (AppDatabase) throws -> Void) {
        guard let database else { return }
        do { try write(database) } catch {
            #if DEBUG
            print("Saving failed: \(error)")
            #endif
        }
    }

    /// Ends the workout and puts it at the top of your history, if it has any sets to keep.
    ///
    /// - Parameters:
    ///   - title: The name it's saved under, which you can change on the summary.
    ///   - description: Anything you wrote about it.
    ///   - unticked: Whether sets you didn't tick are dropped or counted as done.
    ///   - updateRoutine: Whether the prebuilt workout it came from takes today's exercises and sets.
    /// Photos and videos added on the finish summary move to the saved workout, or go with it when there's nothing to save.
    func finish(title: String? = nil, description: String = "", unticked: UntickedSets = .drop, updateRoutine: Bool = false) {
        guard let session = active else { return }
        if unticked == .count { session.tickAll() }
        if updateRoutine, let id = session.routineID, let index = routines.firstIndex(where: { $0.id == id }) {
            routines[index] = routines[index].updated(from: session)
        }
        var finished = session.finished(at: now())
        if let title, !title.trimmingCharacters(in: .whitespaces).isEmpty { finished.title = title.trimmingCharacters(in: .whitespaces) }
        finished.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        persist { try $0.deleteWorkout(id: session.id.uuidString) }
        if finished.setCount > 0 {
            history.insert(finished, at: 0)
            let stored = finished.stored
            persist { try $0.save(stored) }
            media.move(from: session.id, to: finished.id)
        } else {
            media.deleteAll(for: session.id)
        }
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
        let workout = history[index]
        let stored = workout.stored
        persist { try $0.save(stored) }
    }

    /// Replaces a prebuilt workout with an edited copy.
    func update(_ routine: Routine) {
        guard let index = routines.firstIndex(where: { $0.id == routine.id }) else { return }
        routines[index] = routine
    }

    /// Throws the running workout away without saving it.
    func discard() {
        if let session = active {
            persist { try $0.deleteWorkout(id: session.id.uuidString) }
            media.deleteAll(for: session.id)
        }
        isShowingActive = false
        active = nil
    }

    /// Puts an edited past workout back in its place in history.
    func replace(_ workout: FinishedWorkout) {
        guard let index = history.firstIndex(where: { $0.id == workout.id }) else { return }
        if workout.setCount == 0 {
            history.remove(at: index)
            persist { try $0.deleteWorkout(id: workout.id.uuidString) }
            media.deleteAll(for: workout.id)
        } else {
            history[index] = workout
            let stored = workout.stored
            persist { try $0.save(stored) }
        }
    }

    func deleteFromHistory(_ workoutID: UUID) {
        history.removeAll { $0.id == workoutID }
        persist { try $0.deleteWorkout(id: workoutID.uuidString) }
        media.deleteAll(for: workoutID)
    }

    func add(_ routine: Routine) {
        routines.append(routine)
    }

    func delete(_ routineID: UUID) {
        routines.removeAll { $0.id == routineID }
    }

    /// Brings every workout in a Hevy export into history. Exercise names are matched to the library,
    /// and ones that match nothing are added to it as custom exercises. A workout that's already in
    /// history, because the same file was imported before, is skipped, so importing twice adds nothing.
    @discardableResult
    func importHevy(csv: String, catalog: ExerciseCatalog) throws -> HevyImportResult {
        let workouts = try HevyImport.parse(csv)
        var names = catalog.names
        var resolved: [String: String] = [:]
        var result = HevyImportResult()
        func name(for hevyName: String) -> String {
            if let name = resolved[hevyName] { return name }
            let name: String
            if let match = HevyExerciseMatcher.match(hevyName, among: names) {
                name = match
            } else {
                name = hevyName
                catalog.save(HevyExerciseMatcher.customExercise(named: name), brand: nil, setup: BrandSetup())
                names.append(name)
                result.newExercises.append(name)
            }
            resolved[hevyName] = name
            return name
        }

        var added: [FinishedWorkout] = []
        for workout in workouts {
            if history.contains(where: { $0.id == workout.id }) || added.contains(where: { $0.id == workout.id }) {
                result.alreadyThere += 1
                continue
            }
            let stored = workout.stored(exerciseName: name(for:))
            persist { try $0.save(stored) }
            added.append(FinishedWorkout(stored: stored))
            result.imported += 1
        }
        if !added.isEmpty {
            history = (history + added).sorted { $0.startedAt > $1.startedAt }
        }
        return result
    }

    /// Takes an exercise out of every prebuilt workout, after it's deleted from the library.
    /// Finished workouts aren't touched, so nothing you logged on it is lost.
    func removeFromRoutines(exerciseNamed name: String) {
        guard routines.contains(where: { $0.exercises.contains { $0.name == name } }) else { return }
        routines = routines.map { routine in
            var routine = routine
            routine.exercises.removeAll { $0.name == name }
            return routine
        }
    }
}

extension WorkoutSession {
    /// Adds exercises picked from the library, each with one empty rep set to start,
    /// on the brand picked when it was created (no brand otherwise), with the settings saved for it.
    func addExercises(named names: [String], brands: [String: Brand] = [:], catalog: ExerciseCatalog? = nil) {
        for name in names {
            let brand = brands[name]
            let saved = catalog?.setup(for: name, brand: brand) ?? BrandSetup()
            let last = previousLookup?(name, brand) ?? []
            // Start from last time's sets when there were any, so the cells are already filled in.
            let sets = last.isEmpty
                ? [WorkoutSet(setup: SetSetup(kind: .reps), weight: "", amount: "")]
                : last.map { WorkoutSet(setup: $0.setup, type: $0.type, weight: $0.weight, amount: $0.amount) }
            exercises.append(WorkoutExercise(name: name, brand: brand, restSeconds: 90, settings: saved.settings, sets: sets))
            fillPrevious(for: exercises.count - 1)
        }
    }

    /// Fills each set's Previous with what you did on that set last time, on this exercise and brand.
    /// Leaves it as it was when there's no history, such as the target from a prebuilt workout.
    func fillPrevious(for exerciseIndex: Int) {
        let exercise = exercises[exerciseIndex]
        let last = previousLookup?(exercise.name, exercise.brand) ?? []
        guard !last.isEmpty else { return }
        for index in exercise.sets.indices {
            exercises[exerciseIndex].sets[index].previous = PreviousSet(last[min(index, last.count - 1)])
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
    func changeBrand(of exerciseIndex: Int, to brand: Brand?, catalog: ExerciseCatalog) {
        exercises[exerciseIndex].brand = brand
        exercises[exerciseIndex].settings = catalog.setup(for: exercises[exerciseIndex].name, brand: brand).settings
        fillPrevious(for: exerciseIndex)
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
