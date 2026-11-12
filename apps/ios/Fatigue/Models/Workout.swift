import Foundation
import Observation

/// Whether a set counts reps or holds for a time.
enum SetKind: String {
    case reps
    case hold

    var name: String { self == .reps ? "Reps" : "Hold" }
}

/// One set in a running workout. Values are kept as typed text for this spike,
/// so the fields can be edited directly. The real model stores numbers.
struct WorkoutSet: Identifiable {
    let id = UUID()
    var kind: SetKind
    var weight: String
    /// Reps for a rep set, seconds for a hold.
    var amount: String
    var rpe: Double?
    /// What you did last time, such as "55 × 8 @8.5".
    var previous: String
    /// The set's own field values in display form, such as ["Notch 7", "Dead stop"].
    var setup: [String]
    var isDone = false
}

struct WorkoutExercise: Identifiable {
    let id = UUID()
    var name: String
    var brand: String?
    var restSeconds: Int
    var note: String
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

/// Which number field has the keyboard.
enum FocusedCell: Hashable {
    case weight(UUID)
    case amount(UUID)
}

/// Adds or removes a step from a number typed as text, such as "55" to "57.5".
/// Empty text counts as zero, and the result never goes below zero.
enum NumberText {
    nonisolated static func adjust(_ text: String, by step: Double) -> String {
        let value = max(0, (Double(text) ?? 0) + step)
        return value.rounded() == value ? String(Int(value)) : String(value)
    }
}

/// A run of sets that share a kind and setup, shown under one small heading.
struct SetGroup: Identifiable, Equatable {
    /// The heading, such as "Hold · Notch 8". Empty when the exercise has nothing to separate.
    let heading: String
    let setIndices: [Int]
    var id: Int { setIndices.first ?? 0 }
}

extension WorkoutExercise {
    /// Splits the sets into groups wherever the kind or setup changes.
    /// An exercise where every set is a plain rep set gets one group with no heading.
    var groups: [SetGroup] {
        let plain = sets.allSatisfy { $0.kind == .reps && $0.setup.isEmpty }
        var groups: [SetGroup] = []
        var current: [Int] = []
        var currentKey: String?
        for (index, set) in sets.enumerated() {
            let key = ([set.kind.name] + set.setup).joined(separator: " · ")
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

    /// Adds a set that copies the last one's kind, weight, amount and setup, not yet done.
    func addSet(to exerciseIndex: Int) {
        guard let last = exercises[exerciseIndex].sets.last else { return }
        exercises[exerciseIndex].sets.append(
            WorkoutSet(kind: last.kind, weight: last.weight, amount: last.amount, previous: "", setup: last.setup)
        )
    }

    /// Every number field in order, the way "Next" on the keyboard moves through them:
    /// weight, then reps or time, then the next set.
    var cellOrder: [FocusedCell] {
        exercises.flatMap(\.sets).flatMap { [FocusedCell.weight($0.id), .amount($0.id)] }
    }

    func cell(after cell: FocusedCell) -> FocusedCell? {
        let order = cellOrder
        guard let index = order.firstIndex(of: cell), index + 1 < order.count else { return nil }
        return order[index + 1]
    }

    /// Steps the focused field: 2.5 kg for weight, 1 rep, or 5 seconds for a hold.
    func step(_ cell: FocusedCell, up: Bool) {
        for e in exercises.indices {
            for s in exercises[e].sets.indices {
                let set = exercises[e].sets[s]
                switch cell {
                case .weight(set.id):
                    exercises[e].sets[s].weight = NumberText.adjust(set.weight, by: up ? 2.5 : -2.5)
                case .amount(set.id):
                    let step: Double = set.kind == .hold ? 5 : 1
                    exercises[e].sets[s].amount = NumberText.adjust(set.amount, by: up ? step : -step)
                default:
                    continue
                }
                return
            }
        }
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
                    name: "Adductors", brand: "Technogym", restSeconds: 120, note: "Pads on the widest setting.",
                    sets: [
                        WorkoutSet(kind: .hold, weight: "40", amount: "50", rpe: 8, previous: "40 × 45s @8", setup: ["Notch 8"], isDone: true),
                        WorkoutSet(kind: .reps, weight: "55", amount: "8", rpe: 8.5, previous: "55 × 8 @8.5", setup: ["Notch 7", "Dead stop"], isDone: true),
                        WorkoutSet(kind: .reps, weight: "55", amount: "8", previous: "55 × 7 @9", setup: ["Notch 7", "Dead stop"]),
                    ],
                    knownBrands: [
                        KnownBrand(name: "Technogym", lastSet: "55 × 8", when: "3 days ago"),
                        KnownBrand(name: "Hammer Strength", lastSet: "50 × 10", when: "2 weeks ago"),
                        KnownBrand(name: nil, lastSet: "45 × 12", when: "2 months ago"),
                    ]
                ),
                WorkoutExercise(
                    name: "Leg Press", brand: nil, restSeconds: 150, note: "",
                    sets: [
                        WorkoutSet(kind: .reps, weight: "160", amount: "10", previous: "160 × 10 @8", setup: []),
                        WorkoutSet(kind: .reps, weight: "160", amount: "10", previous: "160 × 10 @8.5", setup: []),
                        WorkoutSet(kind: .reps, weight: "160", amount: "10", previous: "160 × 9 @9", setup: []),
                    ]
                ),
                WorkoutExercise(
                    name: "Seated Calf Raise", brand: "Hammer Strength", restSeconds: 90, note: "",
                    sets: [
                        WorkoutSet(kind: .reps, weight: "60", amount: "12", previous: "60 × 12 @8", setup: []),
                        WorkoutSet(kind: .reps, weight: "60", amount: "12", previous: "60 × 11 @9", setup: []),
                        WorkoutSet(kind: .reps, weight: "60", amount: "12", previous: "60 × 10 @9.5", setup: []),
                    ]
                ),
            ],
            now: now
        )
    }
}
