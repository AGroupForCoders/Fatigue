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

    /// Only the volumes have a Weighted / Raw switch. Weight and 1RM are always plain weights.
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
    /// Such as "57.5 kg × 8", in the unit the records were asked for.
    let detail: String
}

/// The four records under the graph, in plain kilograms (their details in the unit asked for), plus the
/// weighted best for the two volumes.
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
        /// Every ticked set, warm-ups included, for the history list.
        var sets: [WorkoutSet] { exercise.sets.filter(\.isDone) }
        /// The ticked sets that count towards the graph and records: everything but warm-ups.
        var countedSets: [WorkoutSet] { sets.filter(\.counts) }
    }

    let name: String
    let brand: Brand?
    /// Oldest first.
    let sessions: [Session]

    init(name: String, brand: Brand?, history: [FinishedWorkout]) {
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
    static func brands(for name: String, in history: [FinishedWorkout]) -> [Brand?] {
        var counts: [String: (brand: Brand?, count: Int)] = [:]
        for workout in history {
            for exercise in workout.exercises where exercise.name == name && exercise.sets.contains(where: \.isDone) {
                counts[exercise.brand?.key ?? "", default: (exercise.brand, 0)].count += 1
            }
        }
        return counts.values.sorted { $0.count != $1.count ? $0.count > $1.count : ($0.brand?.display ?? "") < ($1.brand?.display ?? "") }.map(\.brand)
    }

    // MARK: Values

    /// Nothing about a warm-up counts: not its weight, volume or 1RM.
    private static func weight(_ set: WorkoutSet) -> Double? {
        guard set.counts else { return nil }
        return Double(set.weight)
    }

    private static func reps(_ set: WorkoutSet) -> Double? {
        guard set.counts, set.kind == .reps, let reps = Double(set.amount), reps > 0 else { return nil }
        return reps
    }

    /// Weight × reps, for loaded rep sets. Holds, unloaded sets and warm-ups have no volume.
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

    /// The graph's points, one per workout and line. Warm-ups are left out.
    func points(_ metric: StatMetric, weighted: Bool, splitBy name: String? = nil) -> [StatPoint] {
        sessions.flatMap { session -> [StatPoint] in
            guard let name else {
                return Self.value(metric, weighted: weighted, of: session.countedSets, in: session.exercise)
                    .map { [StatPoint(date: session.date, value: $0, series: "")] } ?? []
            }
            let grouped = Dictionary(grouping: session.countedSets) { Self.series(of: $0, in: session.exercise, splitBy: name) }
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
        let names = sessions.flatMap { session in session.countedSets.compactMap { Self.series(of: $0, in: session.exercise, splitBy: name) } }
        return Array(Set(names)).sorted()
    }

    // MARK: Records

    /// The records over every set, or only the sets on one line when split. Warm-ups never set a record.
    /// Values stay in kilograms; each record's detail reads in `unit`.
    func records(splitBy name: String? = nil, series: String? = nil, in unit: WeightUnit) -> ExerciseRecords {
        var records = ExerciseRecords()
        for session in sessions {
            let sets = session.countedSets.filter { set in
                guard let name, let series else { return true }
                return Self.series(of: set, in: session.exercise, splitBy: name) == series
            }
            for set in sets {
                if let weight = Self.weight(set) {
                    Self.keepBest(&records.heaviestWeight, StatRecord(value: weight, date: session.date, detail: Self.describe(set, in: unit)))
                }
                if let value = Self.oneRepMax(of: set) {
                    Self.keepBest(&records.bestOneRepMax, StatRecord(value: value, date: session.date, detail: Self.describe(set, in: unit)))
                }
                if let value = Self.volume(of: set) {
                    Self.keepBest(&records.bestSetVolume, StatRecord(value: value, date: session.date, detail: Self.describe(set, in: unit)))
                }
                if let value = Self.weightedVolume(of: set, in: session.exercise) {
                    let labels = session.exercise.settings
                        .filter(\.isTracked)
                        .compactMap { setting in session.exercise.value(of: setting, in: set.setup).map { setting.label(for: $0) } }
                    let detail = ([Self.describe(set, in: unit)] + labels).joined(separator: " · ")
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

    /// A record a workout beat, for the finish summary.
    struct Beaten: Identifiable, Equatable {
        let exercise: String
        let brand: Brand?
        /// Such as "Heaviest weight" or "Best set volume, weighted".
        let record: String
        /// Such as "60 kg", "132 lb" or "1,227 weighted".
        let value: String
        var id: String { "\(exercise)|\(brand?.key ?? "")|\(record)" }
    }

    /// The records each exercise in `workout` beat, against everything before it on the same exercise and brand.
    /// Doing an exercise or brand for the first time has nothing to beat, so it sets no records.
    /// Weights read in `unit`; weighted scores are unitless.
    static func beaten(by workout: FinishedWorkout, history: [FinishedWorkout], in unit: WeightUnit) -> [Beaten] {
        var seen: Set<String> = []
        return workout.exercises.flatMap { exercise -> [Beaten] in
            guard seen.insert("\(exercise.name)|\(exercise.brand?.key ?? "")").inserted else { return [] }
            let before = ExerciseStats(name: exercise.name, brand: exercise.brand, history: history).records(in: unit)
            let after = ExerciseStats(name: exercise.name, brand: exercise.brand, history: history + [workout]).records(in: unit)
            let weighted = exercise.settings.contains(where: \.isTracked)
            // Scores are unitless, so only the plain records convert.
            let checks: [(String, KeyPath<ExerciseRecords, StatRecord?>, Bool, Bool)] = [
                ("Heaviest weight", \.heaviestWeight, false, false),
                ("Best 1RM", \.bestOneRepMax, false, false),
                ("Best set volume", \.bestSetVolume, false, true),
                ("Best session volume", \.bestSessionVolume, false, true),
                ("Best set volume, weighted", \.weightedSetVolume, true, true),
                ("Best session volume, weighted", \.weightedSessionVolume, true, true),
            ]
            return checks.compactMap { title, path, isScore, whole in
                if isScore, !weighted { return nil }
                guard let old = before[keyPath: path], let new = after[keyPath: path], new.value > old.value else { return nil }
                let value = isScore ? new.value : unit.amount(fromKilograms: new.value)
                let number = value.formatted(.number.precision(.fractionLength(0...(whole ? 0 : 1))))
                return Beaten(exercise: exercise.name, brand: exercise.brand, record: title, value: "\(number) \(isScore ? "weighted" : unit.rawValue)")
            }
        }
    }

    /// Keeps the first time a best was reached, so a tie doesn't move the record's date.
    private static func keepBest(_ best: inout StatRecord?, _ candidate: StatRecord) {
        if best == nil || candidate.value > best!.value { best = candidate }
    }

    /// A set as "57.5 kg × 8" (or "127 lb × 8"), or "40 kg × 45s" for a hold.
    static func describe(_ set: WorkoutSet, in unit: WeightUnit) -> String {
        "\(Double(set.weight).map(unit.labelled) ?? "-") × \(set.amount)\(set.kind == .hold ? "s" : "")"
    }
}
