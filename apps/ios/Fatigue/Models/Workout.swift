import Foundation
import Observation

/// Whether a set counts reps or holds for a time.
enum SetKind: String {
    case reps
    case hold

    var name: String { self == .reps ? "Reps" : "Hold" }
}

/// What kind of effort a set was. Stored as `set_type`, with the data model's values as raw values.
/// Warm-ups never count towards volume, records or scores. Drop sets and sets to failure count like
/// normal sets; the type is kept so a fatigue meter can weigh them differently later.
enum SetType: String, CaseIterable {
    case normal
    case warmup
    case drop
    case failure

    /// How it reads in the type menu.
    var name: String {
        switch self {
        case .normal: "Normal"
        case .warmup: "Warm-up"
        case .drop: "Drop set"
        case .failure: "Failure"
        }
    }

    /// The letter shown in place of the set's number. A normal set shows its number.
    var letter: String? {
        switch self {
        case .normal: nil
        case .warmup: "W"
        case .drop: "D"
        case .failure: "F"
        }
    }

    /// Whether sets of this type count towards volume, records and scores.
    var counts: Bool { self != .warmup }
}

/// A setting on an exercise, shown as a row under its name: seat height, notch, dead stop.
/// Every set uses the exercise's value unless its group overrides it from the group heading,
/// so a hold at notch 8 sits under "Hold · Notch 8" while the rest of the sets use notch 7.
/// Saved per exercise and brand, since every machine is set up differently.
struct ExerciseSetting: Identifiable, Hashable {
    enum Kind: Hashable {
        /// A number, such as notch 7 or seat 4.
        case number
        /// On or off, such as dead stop.
        case yesNo
        /// Anything else, such as "wide grip". Text never counts towards the score.
        case text
    }

    /// Which way is progress, for a number setting that counts towards the score.
    enum Direction: Hashable {
        case higher, lower
    }

    var id = UUID()
    var name: String
    var kind: Kind = .number
    /// The value for the whole exercise as typed. A yes/no setting holds "yes" or "no".
    var value = ""
    /// Set only on a number setting that counts towards the score. Without it the setting never weighs on it.
    var direction: Direction? = nil
    /// The worst and best values a counted setting can take, such as notch 1 to 10.
    var rangeMin: Double? = nil
    var rangeMax: Double? = nil
    /// Gives each value its own progress, so notch 8 is compared with notch 8 and never with notch 7.
    var splitByValue = false
    /// How much harder a yes/no setting makes a set when it's on, ×1 to ×2, such as ×1.5 for a dead stop.
    /// Nil until you say it makes the set harder. See ADR 0002.
    var factor: Double? = nil

    /// Whether this setting counts towards the set's score: a number with a direction and a range,
    /// or a yes/no setting with a factor above ×1.
    var isTracked: Bool {
        switch kind {
        case .number:
            guard direction != nil, let rangeMin, let rangeMax else { return false }
            return rangeMax > rangeMin
        case .yesNo:
            return (factor ?? 1) > 1
        case .text:
            return false
        }
    }

    /// The exercise-wide value as a number, for comparing with a group's override. Yes is 1 and no is 0.
    var numberValue: Double? {
        switch kind {
        case .number: Double(value)
        case .yesNo: value == "yes" ? 1 : 0
        case .text: nil
        }
    }

    /// How an override reads in a heading, such as "Notch 8", "Dead stop" or "No dead stop".
    func label(for override: Double) -> String {
        switch kind {
        case .number, .text: "\(name) \(PlainNumber.string(override))"
        case .yesNo: override == 1 ? name : "No \(name.lowercased())"
        }
    }
}

/// How a set is done: reps or a hold, plus any settings this set's group changes from the exercise's
/// values, keyed by setting name. A yes/no override is 1 for yes and 0 for no.
struct SetSetup: Hashable {
    var kind: SetKind
    var values: [String: Double] = [:]
}

/// One set in a running workout. Weight and amount are kept as text for this spike,
/// so the cells can be edited directly. The real model stores numbers.
struct WorkoutSet: Identifiable {
    var id = UUID()
    var setup: SetSetup
    var type: SetType = .normal
    /// Always kilograms, whatever unit is picked in Settings; `WeightUnit` converts for the cells. Empty is unloaded.
    var weight: String
    /// Reps for a rep set, seconds for a hold.
    var amount: String
    var rpe: Double?
    /// What you did last time, or the target from a prebuilt workout. Nil when there's neither.
    var previous: PreviousSet?
    var isDone = false

    var kind: SetKind { setup.kind }
    /// Whether this set counts towards volume, records and scores. Warm-ups don't.
    var counts: Bool { type.counts }
}

/// What a set's Previous column shows. Kept as values, not text, so it reads in whichever unit is picked.
struct PreviousSet: Equatable {
    var kind: SetKind
    /// Nil when unloaded.
    var weightKg: Double?
    /// Reps for a rep set, seconds for a hold.
    var amount: String
    var rpe: Double?

    /// A past set, with its RPE.
    init(_ set: WorkoutSet) {
        self.init(kind: set.kind, weightKg: Double(set.weight), amount: set.amount, rpe: set.rpe)
    }

    init(kind: SetKind, weightKg: Double?, amount: String, rpe: Double? = nil) {
        self.kind = kind
        self.weightKg = weightKg
        self.amount = amount
        self.rpe = rpe
    }

    /// Such as "55 × 8 @8.5", or "40 × 45s @8" for a hold, with the weight in `unit` and "-" when unloaded.
    func text(in unit: WeightUnit) -> String {
        var text = "\(weightKg.map(unit.text(fromKilograms:)) ?? "-") × \(amount)\(kind == .hold ? "s" : "")"
        if let rpe { text += " @\(PlainNumber.string(rpe))" }
        return text
    }
}

/// A free-form note under an exercise's name. An exercise can have several.
struct ExerciseNote: Identifiable, Equatable {
    var id = UUID()
    var text: String
}

/// Who made the equipment an exercise is done on, with an optional label such as the model or the gym
/// that tells two of the same brand apart. Brand and label together decide which history, settings and
/// records you get: a Technogym adductor at the city gym and the one at work are two brands.
/// No brand is `nil` wherever a `Brand?` is used.
struct Brand: Hashable, Sendable {
    var name: String
    var label: String?

    /// Nil when there's no brand name, so a label alone never makes a brand. Blank text counts as empty.
    init?(name: String?, label: String? = nil) {
        guard let trimmed = name?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty else { return nil }
        self.name = trimmed
        let label = label?.trimmingCharacters(in: .whitespaces) ?? ""
        self.label = label.isEmpty ? nil : label
    }

    /// What the brand button and headings show: "Technogym · City gym", or just "Technogym" without a label.
    var display: String {
        label.map { "\(name) · \($0)" } ?? name
    }

    /// The brand as one string for dictionary keys: the name, then "|" and the label if there is one.
    var key: String {
        label.map { "\(name)|\($0)" } ?? name
    }

    /// Reads a brand back from `key`. Empty is no brand.
    init?(key: String) {
        let parts = key.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        self.init(name: parts.first.map(String.init), label: parts.count > 1 ? String(parts[1]) : nil)
    }
}

extension Brand: ExpressibleByStringLiteral {
    /// A brand with no label, so `"Technogym"` reads as one where a `Brand` is expected.
    init(stringLiteral value: String) {
        self.init(name: value)!
    }
}

struct WorkoutExercise: Identifiable {
    var id = UUID()
    var name: String
    var brand: Brand?
    var restSeconds: Int
    var notes: [ExerciseNote] = []
    /// Settings like seat height or notch, in the order they show under the name and in headings.
    var settings: [ExerciseSetting] = []
    var sets: [WorkoutSet]
}

/// A brand you have used for an exercise, for the brand picker.
struct KnownBrand: Identifiable, Equatable {
    /// `nil` means no brand.
    let brand: Brand?
    let lastSet: String
    let when: String
    var id: String { brand?.key ?? "" }

    /// The brands you've used for an exercise, newest first, each with your last set on it in `unit`.
    /// Brands with saved settings but no sets yet come after, with no last set.
    static func list(for exercise: String, history: [FinishedWorkout], saved: [Brand], unit: WeightUnit, now: Date = .now) -> [KnownBrand] {
        var brands: [KnownBrand] = []
        for workout in history.sorted(by: { $0.startedAt > $1.startedAt }) {
            for done in workout.exercises where done.name == exercise && !brands.contains(where: { $0.brand == done.brand }) {
                guard let last = done.sets.last(where: \.isDone) else { continue }
                let lastSet = PreviousSet(kind: last.kind, weightKg: Double(last.weight), amount: last.amount).text(in: unit)
                let when = workout.startedAt.formatted(.relative(presentation: .named, unitsStyle: .wide))
                brands.append(KnownBrand(brand: done.brand, lastSet: lastSet, when: when))
            }
        }
        for brand in saved.sorted(by: { $0.display < $1.display }) where !brands.contains(where: { $0.brand == brand }) {
            brands.append(KnownBrand(brand: brand, lastSet: "", when: ""))
        }
        return brands
    }
}

/// Which text field has the keyboard.
enum FocusedCell: Hashable {
    case weight(UUID)
    case amount(UUID)
    case note(UUID)
    case settingName(UUID)
    case settingValue(UUID)
}


/// A run of sets that share a kind and setup, shown under one small heading.
struct SetGroup: Identifiable, Equatable {
    /// The heading, such as "Hold · Notch 8". Empty when the exercise has nothing to separate.
    let heading: String
    let setIndices: [Int]
    var id: Int { setIndices.first ?? 0 }
}

extension WorkoutExercise {
    /// The settings a setup changes from the exercise's values, in display form, such as ["Notch 8"].
    /// An override that matches the exercise's value, or names a setting that no longer exists, is left out.
    func labels(for setup: SetSetup) -> [String] {
        settings.compactMap { setting in
            guard setting.kind != .text, let value = setup.values[setting.name], value != setting.numberValue else { return nil }
            return setting.label(for: value)
        }
    }

    /// The settings as one line for under the exercise name, such as "Seat 4 · Notch 7 · Dead stop".
    /// A yes/no setting that's off reads "No dead stop". A setting with no value yet shows just its name.
    var settingsSummary: String {
        settings.filter { !$0.name.isEmpty }.map { setting in
            switch setting.kind {
            case .yesNo: setting.value == "yes" ? setting.name : "No \(setting.name.lowercased())"
            case .number, .text: setting.value.isEmpty ? setting.name : "\(setting.name) \(setting.value)"
            }
        }
        .joined(separator: " · ")
    }

    /// The value a setting has for a set: the group's override, or the exercise's value.
    func value(of setting: ExerciseSetting, in setup: SetSetup) -> Double? {
        setup.values[setting.name] ?? setting.numberValue
    }

    /// The heading for a setup, such as "Hold · Notch 8".
    func heading(for setup: SetSetup) -> String {
        ([setup.kind.name] + labels(for: setup)).joined(separator: " · ")
    }

    /// Every setup used in this exercise, in the order they first appear.
    var setups: [SetSetup] {
        var seen: [SetSetup] = []
        for set in sets where !seen.contains(set.setup) { seen.append(set.setup) }
        return seen
    }

    /// Splits the sets into groups wherever the kind or setup changes.
    /// An exercise where every set is a plain rep set gets one group with no heading.
    var groups: [SetGroup] {
        let plain = sets.allSatisfy { $0.kind == .reps && labels(for: $0.setup).isEmpty }
        var groups: [SetGroup] = []
        var current: [Int] = []
        var currentKey: String?
        for (index, set) in sets.enumerated() {
            let key = heading(for: set.setup)
            if key != currentKey, !current.isEmpty {
                groups.append(SetGroup(heading: plain ? "" : currentKey ?? "", setIndices: current))
                current = []
            }
            currentKey = key
            current.append(index)
        }
        if !current.isEmpty {
            groups.append(SetGroup(heading: plain ? "" : currentKey ?? "", setIndices: current))
        }
        return groups
    }
}

/// Set numbering. Warm-ups show "W" and don't take a number, so the first working set is 1. Drop sets and
/// sets to failure keep their place in the count but show "D" or "F", so the set after a drop set is still
/// the next number: W, 1, 2, D, 4.
extension Array where Element == WorkoutSet {
    /// What the set at `index` shows in place of a number: its number, or its type's letter.
    func mark(at index: Int) -> String {
        self[index].type.letter ?? String(number(at: index) ?? 0)
    }

    /// The set's number among the sets that aren't warm-ups, starting at 1. Nil for a warm-up.
    func number(at index: Int) -> Int? {
        guard self[index].type != .warmup else { return nil }
        return self[...index].filter { $0.type != .warmup }.count
    }

    /// How the set is read out, such as "Set 3", "Set 3, drop set" or "Warm-up set".
    func spokenName(at index: Int) -> String {
        guard let number = number(at: index) else { return "Warm-up set" }
        return self[index].type == .normal ? "Set \(number)" : "Set \(number), \(self[index].type.name.lowercased())"
    }
}

/// A rest countdown that started when a set was ticked.
struct RestTimer: Equatable {
    var endsAt: Date
    var total: TimeInterval
    /// The exercise you're resting from, for the notification when rest ends.
    var exerciseName = ""
}

/// The workout that is running. Holds everything the workout screen shows and changes.
@Observable
final class WorkoutSession {
    var id = UUID()
    var title: String
    let startedAt: Date
    var exercises: [WorkoutExercise]
    private(set) var rest: RestTimer?
    /// Off when editing a finished workout, where ticking a set shouldn't start a rest timer.
    var startsRestWhenTicked = true
    /// Looks up your sets on an exercise and brand from last time, for the Previous column.
    /// Set by the store; nil in tests and previews.
    @ObservationIgnored var previousLookup: ((String, Brand?) -> [WorkoutSet])?
    /// The prebuilt workout this was started from, so finishing can offer to update it.
    var routineID: UUID?
    /// The set whose RPE scale is open, if any. Only one is open at a time.
    var openRPE: UUID?
    private let now: () -> Date

    init(title: String, exercises: [WorkoutExercise], startedAt: Date? = nil, now: @escaping () -> Date = Date.init) {
        self.title = title
        self.exercises = exercises
        self.now = now
        self.startedAt = startedAt ?? now()
    }

    var doneCount: Int { exercises.reduce(0) { $0 + $1.sets.filter(\.isDone).count } }
    var setCount: Int { exercises.reduce(0) { $0 + $1.sets.count } }

    /// Ticks or unticks a set. Ticking starts the rest timer for that exercise.
    func toggle(set setIndex: Int, in exerciseIndex: Int) {
        exercises[exerciseIndex].sets[setIndex].isDone.toggle()
        if startsRestWhenTicked, exercises[exerciseIndex].sets[setIndex].isDone {
            let seconds = TimeInterval(exercises[exerciseIndex].restSeconds)
            rest = RestTimer(endsAt: now().addingTimeInterval(seconds), total: seconds, exerciseName: exercises[exerciseIndex].name)
        }
    }

    /// Adds a set that copies the last one's setup, weight and amount, not yet done.
    /// With no sets left, it adds a plain rep set.
    func addSet(to exerciseIndex: Int) {
        addSet(to: exerciseIndex, setup: exercises[exerciseIndex].sets.last?.setup ?? SetSetup(kind: .reps))
    }

    /// Removes an exercise and everything logged on it.
    func removeExercise(at exerciseIndex: Int) {
        if let open = openRPE, exercises[exerciseIndex].sets.contains(where: { $0.id == open }) { openRPE = nil }
        exercises.remove(at: exerciseIndex)
    }

    /// Moves exercises into a new order, as `List.onMove` reports it.
    func moveExercises(from source: IndexSet, to destination: Int) {
        exercises.move(fromOffsets: source, toOffset: destination)
    }

    /// Deletes a set. If its RPE panel was open, the panel closes too.
    func deleteSet(_ setID: UUID) {
        guard let place = place(of: setID) else { return }
        exercises[place.exercise].sets.remove(at: place.set)
        if openRPE == setID { openRPE = nil }
    }

    /// Deletes a note from whichever exercise has it.
    func deleteNote(_ noteID: UUID) {
        for index in exercises.indices { exercises[index].notes.removeAll { $0.id == noteID } }
    }

    /// Adds a set with the given setup, straight after the last set that already uses it,
    /// so it joins that group. A setup nothing uses yet goes at the end, under a new heading.
    /// Weight and amount copy the set it follows.
    func addSet(to exerciseIndex: Int, setup: SetSetup) {
        let sets = exercises[exerciseIndex].sets
        let after = sets.lastIndex { $0.setup == setup }
        let template = after.map { sets[$0] } ?? sets.last
        let set = WorkoutSet(setup: setup, weight: template?.weight ?? "", amount: template?.amount ?? "", previous: nil)
        exercises[exerciseIndex].sets.insert(set, at: after.map { $0 + 1 } ?? sets.count)
    }

    /// Changes the setup of every set in a group, such as moving them all to notch 8.
    func changeSetup(of setIndices: [Int], in exerciseIndex: Int, to setup: SetSetup) {
        for index in setIndices { exercises[exerciseIndex].sets[index].setup = setup }
    }

    /// Marks a set as normal, a warm-up, a drop set or a set to failure.
    func changeType(of setID: UUID, to type: SetType) {
        guard let place = place(of: setID) else { return }
        exercises[place.exercise].sets[place.set].type = type
    }

    /// Adds an empty note to an exercise and returns its id, so the screen can put the cursor in it.
    @discardableResult
    func addNote(to exerciseIndex: Int) -> UUID {
        let note = ExerciseNote(text: "")
        exercises[exerciseIndex].notes.append(note)
        return note.id
    }

    /// Adds an empty setting row to an exercise and returns its id, so the screen can put the cursor in it.
    @discardableResult
    func addSetting(to exerciseIndex: Int) -> UUID {
        let setting = ExerciseSetting(name: "")
        exercises[exerciseIndex].settings.append(setting)
        return setting.id
    }

    func deleteSetting(_ settingID: UUID) {
        for index in exercises.indices { exercises[index].settings.removeAll { $0.id == settingID } }
    }

    /// Drops setting rows left with no name and no value.
    func removeEmptySettings() {
        for index in exercises.indices {
            exercises[index].settings.removeAll {
                $0.name.trimmingCharacters(in: .whitespaces).isEmpty && $0.value.trimmingCharacters(in: .whitespaces).isEmpty
            }
        }
    }

    /// Drops notes that were left empty, such as one added by mistake.
    func removeEmptyNotes() {
        for index in exercises.indices {
            exercises[index].notes.removeAll { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
    }

    /// Where a set is: the index of its exercise, and its index within that exercise.
    func place(of setID: UUID) -> (exercise: Int, set: Int)? {
        for e in exercises.indices {
            if let s = exercises[e].sets.firstIndex(where: { $0.id == setID }) { return (e, s) }
        }
        return nil
    }

    func adjustRest(by seconds: TimeInterval) {
        guard var timer = rest else { return }
        timer.endsAt = max(now(), timer.endsAt.addingTimeInterval(seconds))
        timer.total = max(1, timer.total + seconds)
        rest = timer
    }

    func skipRest() {
        rest = nil
    }

    /// Clears the rest timer once its time is up. Returns whether it did.
    @discardableResult
    func finishRestIfDue() -> Bool {
        guard let timer = rest, timer.endsAt <= now() else { return false }
        rest = nil
        return true
    }
}

extension WorkoutSession {
    /// The workout from the design mock-ups, for the spike and previews.
    static func sample(now: @escaping () -> Date = Date.init) -> WorkoutSession {
        WorkoutSession(
            title: "Leg day",
            exercises: [
                WorkoutExercise(
                    name: "Adductors", brand: "Technogym", restSeconds: 120,
                    notes: [ExerciseNote(text: "Pads on the widest setting.")],
                    settings: ExerciseCatalog.sampleAdductorSettings,
                    sets: [
                        WorkoutSet(setup: SetSetup(kind: .hold, values: ["Notch": 8]), weight: "40", amount: "50", rpe: 8, previous: PreviousSet(kind: .hold, weightKg: 40, amount: "45", rpe: 8), isDone: true),
                        WorkoutSet(setup: SetSetup(kind: .reps), weight: "55", amount: "8", rpe: 8.5, previous: PreviousSet(kind: .reps, weightKg: 55, amount: "8", rpe: 8.5), isDone: true),
                        WorkoutSet(setup: SetSetup(kind: .reps), weight: "55", amount: "8", previous: PreviousSet(kind: .reps, weightKg: 55, amount: "7", rpe: 9)),
                    ]
                ),
                WorkoutExercise(
                    name: "Leg Press", brand: nil, restSeconds: 150,
                    sets: [
                        WorkoutSet(setup: SetSetup(kind: .reps), weight: "160", amount: "10", previous: PreviousSet(kind: .reps, weightKg: 160, amount: "10", rpe: 8)),
                        WorkoutSet(setup: SetSetup(kind: .reps), weight: "160", amount: "10", previous: PreviousSet(kind: .reps, weightKg: 160, amount: "10", rpe: 8.5)),
                        WorkoutSet(setup: SetSetup(kind: .reps), weight: "160", amount: "10", previous: PreviousSet(kind: .reps, weightKg: 160, amount: "9", rpe: 9)),
                    ]
                ),
                WorkoutExercise(
                    name: "Seated Calf Raise", brand: "Hammer Strength", restSeconds: 90,
                    sets: [
                        WorkoutSet(setup: SetSetup(kind: .reps), weight: "60", amount: "12", previous: PreviousSet(kind: .reps, weightKg: 60, amount: "12", rpe: 8)),
                        WorkoutSet(setup: SetSetup(kind: .reps), weight: "60", amount: "12", previous: PreviousSet(kind: .reps, weightKg: 60, amount: "11", rpe: 9)),
                        WorkoutSet(setup: SetSetup(kind: .reps), weight: "60", amount: "12", previous: PreviousSet(kind: .reps, weightKg: 60, amount: "10", rpe: 9.5)),
                    ]
                ),
            ],
            now: now
        )
    }
}

/// Formats a number without a trailing ".0", so 8 shows as "8" and 8.5 as "8.5".
nonisolated enum PlainNumber {
    static func string(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }
}

/// Lets a running session drive `.fullScreenCover(item:)`.
extension WorkoutSession: Identifiable {}
