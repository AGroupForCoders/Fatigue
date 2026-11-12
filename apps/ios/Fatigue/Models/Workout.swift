import Foundation
import Observation

/// Whether a set counts reps or holds for a time.
enum SetKind: String {
    case reps
    case hold

    var name: String { self == .reps ? "Reps" : "Hold" }
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

    /// Whether this setting counts towards the set's score: a number with a direction and a range.
    var isTracked: Bool {
        guard kind == .number, direction != nil, let rangeMin, let rangeMax else { return false }
        return rangeMax > rangeMin
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

/// One set in a running workout. Weight and amount are kept as typed text for this spike,
/// so the cells can be edited directly. The real model stores numbers.
struct WorkoutSet: Identifiable {
    let id = UUID()
    var setup: SetSetup
    var weight: String
    /// Reps for a rep set, seconds for a hold.
    var amount: String
    var rpe: Double?
    /// What you did last time, such as "55 × 8 @8.5".
    var previous: String
    var isDone = false

    var kind: SetKind { setup.kind }
}

/// A free-form note under an exercise's name. An exercise can have several.
struct ExerciseNote: Identifiable, Equatable {
    let id = UUID()
    var text: String
}

struct WorkoutExercise: Identifiable {
    let id = UUID()
    var name: String
    var brand: String?
    var restSeconds: Int
    var notes: [ExerciseNote] = []
    /// Settings like seat height or notch, in the order they show under the name and in headings.
    var settings: [ExerciseSetting] = []
    var sets: [WorkoutSet]
    /// Brands you have used for this exercise before, with your last set on each.
    /// Sample data for the spike. The real app reads this from history.
    var knownBrands: [KnownBrand] = []
}

/// A brand you have used for an exercise, for the brand picker.
struct KnownBrand: Identifiable, Equatable {
    /// `nil` means no brand.
    let name: String?
    let lastSet: String
    let when: String
    var id: String { name ?? "" }
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

/// A rest countdown that started when a set was ticked.
struct RestTimer: Equatable {
    var endsAt: Date
    var total: TimeInterval
}

/// The workout that is running. Holds everything the workout screen shows and changes.
@Observable
final class WorkoutSession {
    var title: String
    let startedAt: Date
    var exercises: [WorkoutExercise]
    private(set) var rest: RestTimer?
    /// Off when editing a finished workout, where ticking a set shouldn't start a rest timer.
    var startsRestWhenTicked = true
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
            rest = RestTimer(endsAt: now().addingTimeInterval(seconds), total: seconds)
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
        let set = WorkoutSet(setup: setup, weight: template?.weight ?? "", amount: template?.amount ?? "", previous: "")
        exercises[exerciseIndex].sets.insert(set, at: after.map { $0 + 1 } ?? sets.count)
    }

    /// Changes the setup of every set in a group, such as moving them all to notch 8.
    func changeSetup(of setIndices: [Int], in exerciseIndex: Int, to setup: SetSetup) {
        for index in setIndices { exercises[exerciseIndex].sets[index].setup = setup }
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
                        WorkoutSet(setup: SetSetup(kind: .hold, values: ["Notch": 8]), weight: "40", amount: "50", rpe: 8, previous: "40 × 45s @8", isDone: true),
                        WorkoutSet(setup: SetSetup(kind: .reps), weight: "55", amount: "8", rpe: 8.5, previous: "55 × 8 @8.5", isDone: true),
                        WorkoutSet(setup: SetSetup(kind: .reps), weight: "55", amount: "8", previous: "55 × 7 @9"),
                    ],
                    knownBrands: [
                        KnownBrand(name: "Technogym", lastSet: "55 × 8", when: "3 days ago"),
                        KnownBrand(name: "Hammer Strength", lastSet: "50 × 10", when: "2 weeks ago"),
                        KnownBrand(name: nil, lastSet: "45 × 12", when: "2 months ago"),
                    ]
                ),
                WorkoutExercise(
                    name: "Leg Press", brand: nil, restSeconds: 150,
                    sets: [
                        WorkoutSet(setup: SetSetup(kind: .reps), weight: "160", amount: "10", previous: "160 × 10 @8"),
                        WorkoutSet(setup: SetSetup(kind: .reps), weight: "160", amount: "10", previous: "160 × 10 @8.5"),
                        WorkoutSet(setup: SetSetup(kind: .reps), weight: "160", amount: "10", previous: "160 × 9 @9"),
                    ]
                ),
                WorkoutExercise(
                    name: "Seated Calf Raise", brand: "Hammer Strength", restSeconds: 90,
                    sets: [
                        WorkoutSet(setup: SetSetup(kind: .reps), weight: "60", amount: "12", previous: "60 × 12 @8"),
                        WorkoutSet(setup: SetSetup(kind: .reps), weight: "60", amount: "12", previous: "60 × 11 @9"),
                        WorkoutSet(setup: SetSetup(kind: .reps), weight: "60", amount: "12", previous: "60 × 10 @9.5"),
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

/// Lets a running session drive `.fullScreenCover(item:)`. Classes get an identity-based id for free.
extension WorkoutSession: Identifiable {}
