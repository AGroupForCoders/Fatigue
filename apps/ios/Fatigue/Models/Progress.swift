import Foundation

/// A set's score, as in ADR 0001: its load (weight × reps, or weight × seconds for a hold, with an unloaded
/// set counting its weight as 1) multiplied by `1 + position in range` for each tracked setting.
/// Worked out whenever it's shown and never stored, so fixing a setting's range rescores every past set.
enum SetScore {
    static func score(of set: WorkoutSet, in exercise: WorkoutExercise) -> Double? {
        guard let amount = Double(set.amount), amount > 0 else { return nil }
        let load = (Double(set.weight) ?? 1) * amount
        return exercise.settings.reduce(load) { score, setting in
            guard let position = position(of: setting, for: set, in: exercise) else { return score }
            return score * (1 + position)
        }
    }

    /// Where a tracked setting's value for this set falls in its range: 0 at the worst end, 1 at the best.
    /// A value outside the range is held at the nearest end. `nil` for untracked settings and for no value.
    static func position(of setting: ExerciseSetting, for set: WorkoutSet, in exercise: WorkoutExercise) -> Double? {
        guard setting.isTracked, let direction = setting.direction, let low = setting.rangeMin, let high = setting.rangeMax,
              let value = exercise.value(of: setting, in: set.setup) else { return nil }
        let fromLow = (min(max(value, low), high) - low) / (high - low)
        return direction == .higher ? fromLow : 1 - fromLow
    }
}

/// What a set has to have in common with another before the two are compared: the same exercise and brand,
/// rep set or hold, loaded or unloaded, and the same tracked settings with a value. A setting with its own
/// progress per value adds the value too, so notch 8 is only ever compared with notch 8.
struct SetShape: Hashable {
    let exercise: String
    let brand: String?
    let kind: SetKind
    let isLoaded: Bool
    let tracked: Set<String>
    let splitValues: [String: Double]

    init(of set: WorkoutSet, in exercise: WorkoutExercise) {
        self.exercise = exercise.name
        brand = exercise.brand
        kind = set.kind
        isLoaded = Double(set.weight) != nil
        tracked = Set(exercise.settings.filter { $0.isTracked && exercise.value(of: $0, in: set.setup) != nil }.map(\.name))
        var splitValues: [String: Double] = [:]
        for setting in exercise.settings where setting.kind == .number && setting.splitByValue {
            if let value = exercise.value(of: setting, in: set.setup) { splitValues[setting.name] = value }
        }
        self.splitValues = splitValues
    }
}

/// A kind of record a set can set.
enum RecordKind: Hashable {
    case weight
    case reps
    /// The longest hold.
    case time
    /// The best value of a tracked setting, by its direction.
    case setting(String)
    case score
}

/// The best of everything so far, per shape, for spotting records.
/// A set is a record when it beats the best before it. The first set of a shape has nothing to beat, so it isn't one.
struct RecordBook {
    private struct Bests {
        var weight: Double?
        var reps: Double?
        var time: Double?
        var settings: [String: Double] = [:]
        var score: Double?
    }

    private var bests: [SetShape: Bests] = [:]

    /// Every set in these workouts, in any order.
    init(history: [FinishedWorkout] = []) {
        for workout in history {
            for exercise in workout.exercises {
                for set in exercise.sets where set.isDone { add(set, in: exercise) }
            }
        }
    }

    /// The records this set sets against everything added so far.
    func records(for set: WorkoutSet, in exercise: WorkoutExercise) -> Set<RecordKind> {
        guard let best = bests[SetShape(of: set, in: exercise)] else { return [] }
        let values = Self.values(of: set, in: exercise)
        var records: Set<RecordKind> = []
        if Self.beats(values.weight, best.weight) { records.insert(.weight) }
        if Self.beats(values.reps, best.reps) { records.insert(.reps) }
        if Self.beats(values.time, best.time) { records.insert(.time) }
        for (name, value) in values.settings where Self.beats(value, best.settings[name]) { records.insert(.setting(name)) }
        if Self.beats(values.score, best.score) { records.insert(.score) }
        return records
    }

    mutating func add(_ set: WorkoutSet, in exercise: WorkoutExercise) {
        let values = Self.values(of: set, in: exercise)
        var best = bests[SetShape(of: set, in: exercise), default: Bests()]
        best.weight = Self.better(values.weight, best.weight)
        best.reps = Self.better(values.reps, best.reps)
        best.time = Self.better(values.time, best.time)
        for (name, value) in values.settings { best.settings[name] = Self.better(value, best.settings[name]) }
        best.score = Self.better(values.score, best.score)
        bests[SetShape(of: set, in: exercise)] = best
    }

    /// The records each ticked set in these exercises sets, compared with the history and with the ticked sets
    /// before it. Sets that set none are left out. Used for the marks on the set rows and the finish summary.
    static func marks(for exercises: [WorkoutExercise], after history: [FinishedWorkout]) -> [UUID: Set<RecordKind>] {
        var book = RecordBook(history: history)
        var marks: [UUID: Set<RecordKind>] = [:]
        for exercise in exercises {
            for set in exercise.sets where set.isDone {
                let records = book.records(for: set, in: exercise)
                if !records.isEmpty { marks[set.id] = records }
                book.add(set, in: exercise)
            }
        }
        return marks
    }

    /// A set's values, each turned so that bigger is better. A lower-is-better setting is stored negated.
    private static func values(of set: WorkoutSet, in exercise: WorkoutExercise) -> Bests {
        var values = Bests()
        let amount = Double(set.amount).flatMap { $0 > 0 ? $0 : nil }
        values.weight = Double(set.weight)
        values.reps = set.kind == .reps ? amount : nil
        values.time = set.kind == .hold ? amount : nil
        for setting in exercise.settings where setting.isTracked {
            guard let value = exercise.value(of: setting, in: set.setup) else { continue }
            values.settings[setting.name] = setting.direction == .lower ? -value : value
        }
        values.score = SetScore.score(of: set, in: exercise)
        return values
    }

    private static func beats(_ value: Double?, _ best: Double?) -> Bool {
        guard let value, let best else { return false }
        return value > best
    }

    private static func better(_ value: Double?, _ best: Double?) -> Double? {
        guard let value else { return best }
        guard let best else { return value }
        return max(value, best)
    }
}
