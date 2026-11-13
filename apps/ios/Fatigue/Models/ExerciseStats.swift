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

/// How one set's score was worked out, for the sum shown when a point on the graph is tapped:
/// "460 × 1.78 × 1.5 = 1,227". See ADR 0002.
struct ScoreBreakdown: Equatable {
    /// One setting's part in the score.
    struct Term: Equatable {
        let setting: String
        let kind: ExerciseSetting.Kind
        /// Such as "Notch 8" or "Dead stop".
        let label: String
        let factor: Double
    }

    /// The set, as "57.5 kg × 8".
    let set: String
    /// Weight × reps, or weight × seconds for a hold.
    let load: Double
    /// Every tracked setting with a value on the set, in the exercise's order. A yes/no setting that's off is ×1 and left out.
    let terms: [Term]
    /// Whether the factors together ran past ×3 and were held there.
    let isCapped: Bool
    let total: Double

    init?(of set: WorkoutSet, in exercise: WorkoutExercise) {
        guard let amount = Double(set.amount), amount > 0, let total = SetScore.score(of: set, in: exercise) else { return nil }
        // In kilograms whatever the unit, since the score is worked out from kilograms and the sum has to add up.
        self.set = ExerciseStats.describe(set, in: .kg)
        load = (Double(set.weight) ?? 1) * amount
        terms = exercise.settings.compactMap { setting -> Term? in
            guard setting.isTracked, let value = exercise.value(of: setting, in: set.setup) else { return nil }
            let factor: Double
            switch setting.kind {
            case .number: factor = 1 + (SetScore.position(of: setting, for: set, in: exercise) ?? 0)
            case .yesNo:
                guard value == 1, let picked = setting.factor else { return nil }
                factor = min(picked, 2)
            case .text: return nil
            }
            return Term(setting: setting.name, kind: setting.kind, label: setting.label(for: value), factor: factor)
        }
        isCapped = terms.reduce(1.0) { $0 * $1.factor } > SetScore.maxFactor
        self.total = total
    }

    /// A factor as it reads in the sum, such as "1.78" or "1.5".
    static func format(factor: Double) -> String {
        factor.formatted(.number.precision(.fractionLength(0...2)))
    }

    /// The whole sum on one line, such as "460 × 1.78 × 1.5 = 1,227", or "460 × 2 × 2, capped at ×3 = 1,380".
    var text: String {
        let parts = [load.formatted(.number.precision(.fractionLength(0...1)))] + terms.map { Self.format(factor: $0.factor) }
        var sum = parts.joined(separator: " × ")
        if isCapped { sum += ", capped at ×\(PlainNumber.string(SetScore.maxFactor))" }
        return "\(sum) = \(total.formatted(.number.precision(.fractionLength(0))))"
    }
}

/// The sets behind one point on the graph, with their sums, and the exercise as it was that day,
/// whose settings are what the factors can be changed on.
struct PointDetail: Equatable {
    let date: Date
    let series: String
    let value: Double
    let exercise: WorkoutExercise
    let breakdowns: [ScoreBreakdown]
    /// The yes/no settings that were on for a set behind the point, whose factor can be changed from here.
    /// One that doesn't count yet is included, so it can be made to.
    let adjustable: [ExerciseSetting]

    static func == (lhs: PointDetail, rhs: PointDetail) -> Bool {
        lhs.date == rhs.date && lhs.series == rhs.series && lhs.value == rhs.value && lhs.breakdowns == rhs.breakdowns && lhs.adjustable == rhs.adjustable
    }
}

/// The split the exercise page is on for each exercise, remembered between visits. The finish summary
/// reads it too, so a record names the line it was on.
enum ExerciseSplit {
    static func key(_ name: String) -> String { "exerciseSplit.\(name)" }

    static func remembered(for name: String, defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: key(name))
    }

    static func remember(_ split: String?, for name: String, defaults: UserDefaults = .standard) {
        defaults.set(split, forKey: key(name))
    }
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

    /// The settings you can pin while split by another: every splittable setting but the split.
    func filterableSettings(splitBy split: String?) -> [String] {
        splittableSettings.filter { $0 != split }
    }

    /// The line a set is on when split by a setting, such as "Notch 8", "Dead stop" or "No dead stop".
    /// Nil when the set's workout didn't have that setting or gave it no value.
    static func series(of set: WorkoutSet, in exercise: WorkoutExercise, splitBy name: String) -> String? {
        guard let setting = exercise.settings.first(where: { $0.name == name && $0.kind != .text }),
              let value = exercise.value(of: setting, in: set.setup) else { return nil }
        return setting.label(for: value)
    }

    /// Whether a set is on every pinned line: with `["Dead stop": "Dead stop"]`, only sets with the dead stop on.
    /// A set whose workout didn't have a pinned setting is left out.
    static func matches(_ set: WorkoutSet, in exercise: WorkoutExercise, pinned: [String: String]) -> Bool {
        pinned.allSatisfy { name, line in series(of: set, in: exercise, splitBy: name) == line }
    }

    /// The graph's points, one per workout and line. Warm-ups are left out. `pinned` keeps only the sets on those lines, such as
    /// notch lines with the dead stop on.
    func points(_ metric: StatMetric, weighted: Bool, splitBy name: String? = nil, pinned: [String: String] = [:]) -> [StatPoint] {
        sessions.flatMap { session -> [StatPoint] in
            let sets = session.countedSets.filter { Self.matches($0, in: session.exercise, pinned: pinned) }
            guard let name else {
                return Self.value(metric, weighted: weighted, of: sets, in: session.exercise)
                    .map { [StatPoint(date: session.date, value: $0, series: "")] } ?? []
            }
            let grouped = Dictionary(grouping: sets) { Self.series(of: $0, in: session.exercise, splitBy: name) }
            return grouped.compactMap { series, sets in
                guard let series else { return nil }
                return Self.value(metric, weighted: weighted, of: sets, in: session.exercise)
                    .map { StatPoint(date: session.date, value: $0, series: series) }
            }
            .sorted { $0.series < $1.series }
        }
    }

    /// The lines when split, in the order they sort. With `pinned`, only the lines that still have a set.
    func seriesNames(splitBy name: String?, pinned: [String: String] = [:]) -> [String] {
        guard let name else { return [] }
        let names = sessions.flatMap { session in
            session.countedSets
                .filter { Self.matches($0, in: session.exercise, pinned: pinned) }
                .compactMap { Self.series(of: $0, in: session.exercise, splitBy: name) }
        }
        return Array(Set(names)).sorted()
    }

    /// The sets behind a point, with how each was scored: the best set for set volume, weight and 1RM, and
    /// every counted set for session volume. Nil when there's no workout on that day.
    func detail(
        of metric: StatMetric, weighted: Bool, at date: Date, series: String = "", splitBy name: String? = nil, pinned: [String: String] = [:]
    ) -> PointDetail? {
        guard let session = sessions.first(where: { $0.date == date }) else { return nil }
        let sets = session.countedSets.filter { set in
            guard Self.matches(set, in: session.exercise, pinned: pinned) else { return false }
            guard let name else { return true }
            return Self.series(of: set, in: session.exercise, splitBy: name) == series
        }
        guard let value = Self.value(metric, weighted: weighted, of: sets, in: session.exercise) else { return nil }
        let counted: [WorkoutSet]
        switch metric {
        case .sessionVolume:
            counted = sets.filter { Self.volume(of: $0) != nil }
        case .setVolume, .weight, .oneRepMax:
            let best = sets.compactMap { set in Self.value(metric, weighted: weighted, of: [set], in: session.exercise).map { (set, $0) } }
                .first { $0.1 == value }
            counted = best.map { [$0.0] } ?? []
        }
        return PointDetail(
            date: date, series: series, value: value, exercise: session.exercise,
            breakdowns: counted.compactMap { ScoreBreakdown(of: $0, in: session.exercise) },
            adjustable: session.exercise.settings.filter { setting in
                setting.kind == .yesNo && counted.contains { session.exercise.value(of: setting, in: $0.setup) == 1 }
            }
        )
    }

    // MARK: Records

    /// The records over every set, or only the sets on one line when split. Warm-ups never set a record.
    /// `pinned` counts only the sets on those lines, as the graph does. Values stay in kilograms;
    /// each record's detail reads in `unit`.
    func records(splitBy name: String? = nil, series: String? = nil, pinned: [String: String] = [:], in unit: WeightUnit) -> ExerciseRecords {
        var records = ExerciseRecords()
        for session in sessions {
            let sets = session.countedSets.filter { set in
                guard Self.matches(set, in: session.exercise, pinned: pinned) else { return false }
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
    /// Weights read in `unit`; weighted scores are unitless. `splitBy` is the setting the exercise page splits an exercise by, if any. When it's split, records are
    /// checked per line and named after it, such as "Heaviest weight at notch 8".
    static func beaten(by workout: FinishedWorkout, history: [FinishedWorkout], splitBy: (String) -> String? = { _ in nil }, in unit: WeightUnit) -> [Beaten] {
        var seen: Set<String> = []
        return workout.exercises.flatMap { exercise -> [Beaten] in
            guard seen.insert("\(exercise.name)|\(exercise.brand?.key ?? "")").inserted else { return [] }
            let before = ExerciseStats(name: exercise.name, brand: exercise.brand, history: history)
            let after = ExerciseStats(name: exercise.name, brand: exercise.brand, history: history + [workout])
            let weighted = exercise.settings.contains(where: \.isTracked)
            let split = splitBy(exercise.name).flatMap { name in after.splittableSettings.contains(name) ? name : nil }
            let setting = split.flatMap { name in exercise.settings.first { $0.name == name } }
            let lines: [String?] = split.map { after.seriesNames(splitBy: $0).map(Optional.some) } ?? [nil]
            return lines.flatMap { line -> [Beaten] in
                let suffix = line.flatMap { line in setting.map { " \(Self.describeLine(line, of: $0))" } } ?? ""
                return Self.beaten(
                    exercise: exercise, weighted: weighted, suffix: suffix, unit: unit,
                    before: before.records(splitBy: split, series: line, in: unit), after: after.records(splitBy: split, series: line, in: unit)
                )
            }
        }
    }

    private static func beaten(
        exercise: WorkoutExercise, weighted: Bool, suffix: String, unit: WeightUnit, before: ExerciseRecords, after: ExerciseRecords
    ) -> [Beaten] {
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
            let name = isScore ? title.replacingOccurrences(of: ", weighted", with: "\(suffix), weighted") : title + suffix
            return Beaten(exercise: exercise.name, brand: exercise.brand, record: name, value: "\(number) \(isScore ? "weighted" : unit.rawValue)")
        }
    }

    /// How a line reads after a record's name: "at notch 8", "with dead stop" or "with no dead stop".
    static func describeLine(_ line: String, of setting: ExerciseSetting) -> String {
        switch setting.kind {
        case .number, .text: "at \(line.prefix(1).lowercased() + line.dropFirst())"
        case .yesNo: "with \(line.prefix(1).lowercased() + line.dropFirst())"
        }
    }

    // MARK: Factors

    /// `history` with a yes/no setting's factor changed on one exercise and brand, so every past set there is
    /// re-scored with it. Nil makes the setting stop counting. Workouts that don't have the setting are untouched.
    static func rescored(_ history: [FinishedWorkout], exercise name: String, brand: Brand?, setting: String, factor: Double?) -> [FinishedWorkout] {
        history.map { workout in
            var workout = workout
            for e in workout.exercises.indices where workout.exercises[e].name == name && workout.exercises[e].brand == brand {
                for s in workout.exercises[e].settings.indices where workout.exercises[e].settings[s].name == setting && workout.exercises[e].settings[s].kind == .yesNo {
                    workout.exercises[e].settings[s].factor = factor
                }
            }
            return workout
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
