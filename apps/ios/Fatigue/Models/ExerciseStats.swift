import Foundation

/// What the exercise page graphs. See "Scores and stats" in the docs.
enum StatMetric: String, CaseIterable, Identifiable {
    case setVolume, sessionVolume, weight, oneRepMax

    var id: String { rawValue }

    var title: String {
        switch self {
        case .setVolume: "Set volume"
        case .sessionVolume: "Session volume"
        case .weight: "Weight"
        case .oneRepMax: "Est. 1RM"
        }
    }

    /// Only the volumes have a Weighted / Raw switch. Weight and 1RM are always plain kilograms.
    var canBeWeighted: Bool { self == .setVolume || self == .sessionVolume }
}

/// One point on the exercise page's graph: a workout's value, on one line.
struct StatPoint: Identifiable, Equatable {
    let date: Date
    let value: Double
    /// Which line it's on, such as "Notch 8". Empty when nothing is split.
    let series: String
    var id: String { "\(date.timeIntervalSince1970)|\(series)" }
}

/// A best, with when it happened and the set or day behind it.
struct StatRecord: Equatable {
    let value: Double
    let date: Date
    /// Such as "57.5 kg × 8".
    let detail: String
}

/// The four records under the graph, in plain kilograms, plus the weighted best for the two volumes.
struct ExerciseRecords: Equatable {
    var heaviestWeight: StatRecord?
    var bestOneRepMax: StatRecord?
    var bestSetVolume: StatRecord?
    var bestSessionVolume: StatRecord?
    var weightedSetVolume: StatRecord?
    var weightedSessionVolume: StatRecord?
}

/// One exercise on one brand, across every finished workout: the graph's points, the records, and the
/// past sets. Brands are never mixed, since two brands' machines aren't comparable.
struct ExerciseStats {
    /// One workout's ticked sets on this exercise and brand.
    struct Session: Identifiable {
        let date: Date
        let workoutTitle: String
        let exercise: WorkoutExercise
        var id: Date { date }
        var sets: [WorkoutSet] { exercise.sets.filter(\.isDone) }
    }

    let name: String
    let brand: String?
    /// Oldest first.
    let sessions: [Session]

    init(name: String, brand: String?, history: [FinishedWorkout]) {
        self.name = name
        self.brand = brand
        sessions = history
            .flatMap { workout in
                workout.exercises
                    .filter { $0.name == name && $0.brand == brand && $0.sets.contains(where: \.isDone) }
                    .map { Session(date: workout.startedAt, workoutTitle: workout.title, exercise: $0) }
            }
            .sorted { $0.date < $1.date }
    }

    /// The brands you've done an exercise on, most used first. Nil is no brand.
    static func brands(for name: String, in history: [FinishedWorkout]) -> [String?] {
        var counts: [String: (brand: String?, count: Int)] = [:]
        for workout in history {
            for exercise in workout.exercises where exercise.name == name && exercise.sets.contains(where: \.isDone) {
                counts[exercise.brand ?? "", default: (exercise.brand, 0)].count += 1
            }
        }
        return counts.values.sorted { $0.count != $1.count ? $0.count > $1.count : ($0.brand ?? "") < ($1.brand ?? "") }.map(\.brand)
    }

    // MARK: Values

    private static func weight(_ set: WorkoutSet) -> Double? { Double(set.weight) }

    private static func reps(_ set: WorkoutSet) -> Double? {
        guard set.kind == .reps, let reps = Double(set.amount), reps > 0 else { return nil }
        return reps
    }

    /// Weight × reps, for loaded rep sets. Holds and unloaded sets have no volume.
    static func volume(of set: WorkoutSet) -> Double? {
        guard let weight = weight(set), let reps = reps(set) else { return nil }
        return weight * reps
    }

    /// A rep set's volume made heavier by the settings that make it harder: its score.
    static func weightedVolume(of set: WorkoutSet, in exercise: WorkoutExercise) -> Double? {
        guard volume(of: set) != nil else { return nil }
        return SetScore.score(of: set, in: exercise)
    }

    /// Epley: weight × (1 + reps ÷ 30), for loaded rep sets.
    static func oneRepMax(of set: WorkoutSet) -> Double? {
        guard let weight = weight(set), let reps = reps(set) else { return nil }
        return weight * (1 + reps / 30)
    }

    /// A metric over some sets from one workout. Nil when none of them count towards it.
    static func value(_ metric: StatMetric, weighted: Bool, of sets: [WorkoutSet], in exercise: WorkoutExercise) -> Double? {
        let perSet: [Double]
        switch metric {
        case .setVolume, .sessionVolume:
            perSet = sets.compactMap { weighted ? weightedVolume(of: $0, in: exercise) : volume(of: $0) }
        case .weight:
            perSet = sets.compactMap(weight)
        case .oneRepMax:
            perSet = sets.compactMap(oneRepMax)
        }
        guard !perSet.isEmpty else { return nil }
        return metric == .sessionVolume ? perSet.reduce(0, +) : perSet.max()
    }

    // MARK: Splitting

    /// The settings you can split by: numbers and yes or no, from the latest workout first.
    var splittableSettings: [String] {
        var names: [String] = []
        for session in sessions.reversed() {
            for setting in session.exercise.settings where setting.kind != .text && !names.contains(setting.name) {
                names.append(setting.name)
            }
        }
        return names
    }

    /// The line a set is on when split by a setting, such as "Notch 8", "Dead stop" or "No dead stop".
    /// Nil when the set's workout didn't have that setting or gave it no value.
    static func series(of set: WorkoutSet, in exercise: WorkoutExercise, splitBy name: String) -> String? {
        guard let setting = exercise.settings.first(where: { $0.name == name && $0.kind != .text }),
              let value = exercise.value(of: setting, in: set.setup) else { return nil }
        return setting.label(for: value)
    }

    /// The graph's points, one per workout and line.
    func points(_ metric: StatMetric, weighted: Bool, splitBy name: String? = nil) -> [StatPoint] {
        sessions.flatMap { session -> [StatPoint] in
            guard let name else {
                return Self.value(metric, weighted: weighted, of: session.sets, in: session.exercise)
                    .map { [StatPoint(date: session.date, value: $0, series: "")] } ?? []
            }
            let grouped = Dictionary(grouping: session.sets) { Self.series(of: $0, in: session.exercise, splitBy: name) }
            return grouped.compactMap { series, sets in
                guard let series else { return nil }
                return Self.value(metric, weighted: weighted, of: sets, in: session.exercise)
                    .map { StatPoint(date: session.date, value: $0, series: series) }
            }
            .sorted { $0.series < $1.series }
        }
    }

    /// The lines when split, in the order they sort.
    func seriesNames(splitBy name: String?) -> [String] {
        guard let name else { return [] }
        let names = sessions.flatMap { session in session.sets.compactMap { Self.series(of: $0, in: session.exercise, splitBy: name) } }
        return Array(Set(names)).sorted()
    }

    // MARK: Records

    /// The records over every set, or only the sets on one line when split.
    func records(splitBy name: String? = nil, series: String? = nil) -> ExerciseRecords {
        var records = ExerciseRecords()
        for session in sessions {
            let sets = session.sets.filter { set in
                guard let name, let series else { return true }
                return Self.series(of: set, in: session.exercise, splitBy: name) == series
            }
            for set in sets {
                if let weight = Self.weight(set) {
                    Self.keepBest(&records.heaviestWeight, StatRecord(value: weight, date: session.date, detail: Self.describe(set)))
                }
                if let value = Self.oneRepMax(of: set) {
                    Self.keepBest(&records.bestOneRepMax, StatRecord(value: value, date: session.date, detail: Self.describe(set)))
                }
                if let value = Self.volume(of: set) {
                    Self.keepBest(&records.bestSetVolume, StatRecord(value: value, date: session.date, detail: Self.describe(set)))
                }
                if let value = Self.weightedVolume(of: set, in: session.exercise) {
                    let labels = session.exercise.settings
                        .filter(\.isTracked)
                        .compactMap { setting in session.exercise.value(of: setting, in: set.setup).map { setting.label(for: $0) } }
                    let detail = ([Self.describe(set)] + labels).joined(separator: " · ")
                    Self.keepBest(&records.weightedSetVolume, StatRecord(value: value, date: session.date, detail: detail))
                }
            }
            let count = sets.filter { Self.volume(of: $0) != nil }.count
            let detail = "\(count) set\(count == 1 ? "" : "s")"
            if let value = Self.value(.sessionVolume, weighted: false, of: sets, in: session.exercise) {
                Self.keepBest(&records.bestSessionVolume, StatRecord(value: value, date: session.date, detail: detail))
            }
            if let value = Self.value(.sessionVolume, weighted: true, of: sets, in: session.exercise) {
                Self.keepBest(&records.weightedSessionVolume, StatRecord(value: value, date: session.date, detail: detail))
            }
        }
        return records
    }

    /// Keeps the first time a best was reached, so a tie doesn't move the record's date.
    private static func keepBest(_ best: inout StatRecord?, _ candidate: StatRecord) {
        if best == nil || candidate.value > best!.value { best = candidate }
    }

    /// A set as "57.5 kg × 8", or "40 kg × 45s" for a hold.
    static func describe(_ set: WorkoutSet) -> String {
        "\(set.weight.isEmpty ? "-" : "\(set.weight) kg") × \(set.amount)\(set.kind == .hold ? "s" : "")"
    }
}
