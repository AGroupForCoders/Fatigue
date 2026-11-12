import Foundation
import Observation

/// Whether a set counts reps or holds for a time.
enum SetKind: String {
    case reps
    case hold

    var name: String { self == .reps ? "Reps" : "Hold" }
}

/// A custom field an exercise tracks on each set, such as "Notch" or "Dead stop".
struct SetField: Identifiable, Hashable {
    enum Kind: Hashable {
        /// A value such as notch 7.
        case number
        /// On or off, such as dead stop.
        case yesNo
    }

    let name: String
    let kind: Kind
    var id: String { name }
}

/// How a set is done: reps or a hold, and its field values keyed by field name.
/// A yes/no field is on when its value is 1. A field with no value is left out of the heading.
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
    /// The custom fields this exercise tracks, in the order they appear in headings.
    var fields: [SetField] = []
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
}


/// A run of sets that share a kind and setup, shown under one small heading.
struct SetGroup: Identifiable, Equatable {
    /// The heading, such as "Hold · Notch 8". Empty when the exercise has nothing to separate.
    let heading: String
    let setIndices: [Int]
    var id: Int { setIndices.first ?? 0 }
}

extension WorkoutExercise {
    /// The field values of a setup in display form, such as ["Notch 7", "Dead stop"].
    func labels(for setup: SetSetup) -> [String] {
        fields.compactMap { field in
            guard let value = setup.values[field.name] else { return nil }
            switch field.kind {
            case .number: return "\(field.name) \(PlainNumber.string(value))"
            case .yesNo: return value == 1 ? field.name : nil
            }
        }
    }

    /// The heading for a setup, such as "Reps · Notch 7 · Dead stop".
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
    /// The set whose RPE scale is open, if any. Only one is open at a time.
    var openRPE: UUID?
    private let now: () -> Date

    init(title: String, exercises: [WorkoutExercise], now: @escaping () -> Date = Date.init) {
        self.title = title
        self.exercises = exercises
        self.now = now
        self.startedAt = now()
    }

    var doneCount: Int { exercises.reduce(0) { $0 + $1.sets.filter(\.isDone).count } }
    var setCount: Int { exercises.reduce(0) { $0 + $1.sets.count } }

    /// Ticks or unticks a set. Ticking starts the rest timer for that exercise.
    func toggle(set setIndex: Int, in exerciseIndex: Int) {
        exercises[exerciseIndex].sets[setIndex].isDone.toggle()
        if exercises[exerciseIndex].sets[setIndex].isDone {
            let seconds = TimeInterval(exercises[exerciseIndex].restSeconds)
            rest = RestTimer(endsAt: now().addingTimeInterval(seconds), total: seconds)
        }
    }

    /// Adds a set that copies the last one's setup, weight and amount, not yet done.
    /// With no sets left, it adds a plain rep set.
    func addSet(to exerciseIndex: Int) {
        addSet(to: exerciseIndex, setup: exercises[exerciseIndex].sets.last?.setup ?? SetSetup(kind: .reps))
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
                    fields: [SetField(name: "Notch", kind: .number), SetField(name: "Dead stop", kind: .yesNo)],
                    sets: [
                        WorkoutSet(setup: SetSetup(kind: .hold, values: ["Notch": 8]), weight: "40", amount: "50", rpe: 8, previous: "40 × 45s @8", isDone: true),
                        WorkoutSet(setup: SetSetup(kind: .reps, values: ["Notch": 7, "Dead stop": 1]), weight: "55", amount: "8", rpe: 8.5, previous: "55 × 8 @8.5", isDone: true),
                        WorkoutSet(setup: SetSetup(kind: .reps, values: ["Notch": 7, "Dead stop": 1]), weight: "55", amount: "8", previous: "55 × 7 @9"),
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
