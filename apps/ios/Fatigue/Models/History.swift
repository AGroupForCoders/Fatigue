import Foundation

/// A workout you finished: what you did and when. Only ticked sets are kept.
struct FinishedWorkout: Identifiable {
    let id = UUID()
    var title: String
    var startedAt: Date
    var duration: TimeInterval
    /// Exercise names with the sets you ticked, in the order you did them.
    var exercises: [Exercise]

    struct Exercise {
        var name: String
        var brand: String?
        var sets: [WorkoutSet]
    }

    var setCount: Int { exercises.reduce(0) { $0 + $1.sets.count } }

    /// Total kilograms moved across rep sets, as weight × reps. Holds are left out, since a second isn't a rep.
    var volume: Double {
        exercises.flatMap(\.sets).reduce(0) { total, set in
            guard set.kind == .reps, let weight = Double(set.weight), let reps = Double(set.amount) else { return total }
            return total + weight * reps
        }
    }
}

extension WorkoutSession {
    /// What gets saved when you finish: ticked sets only, and exercises with none ticked are dropped.
    func finished(at end: Date) -> FinishedWorkout {
        FinishedWorkout(
            title: title,
            startedAt: startedAt,
            duration: end.timeIntervalSince(startedAt),
            exercises: exercises.compactMap { exercise in
                let done = exercise.sets.filter(\.isDone)
                return done.isEmpty ? nil : FinishedWorkout.Exercise(name: exercise.name, brand: exercise.brand, sets: done)
            }
        )
    }
}

extension FinishedWorkout {
    /// Past workouts for the spike, so the profile has history to show before the database exists.
    static func samples(now: Date = .now) -> [FinishedWorkout] {
        func day(_ daysAgo: Double) -> Date { now.addingTimeInterval(-daysAgo * 86_400) }
        func reps(_ weight: String, _ reps: String, count: Int) -> [WorkoutSet] {
            Array(repeating: WorkoutSet(setup: SetSetup(kind: .reps), weight: weight, amount: reps, previous: "", isDone: true), count: count)
        }
        return [
            FinishedWorkout(title: "Pull", startedAt: day(2), duration: 52 * 60, exercises: [
                Exercise(name: "Lat Pulldown", sets: reps("65", "10", count: 3)),
                Exercise(name: "Seated Row", brand: "Life Fitness", sets: reps("60", "10", count: 3)),
                Exercise(name: "Bicep Curl", sets: reps("14", "12", count: 3)),
            ]),
            FinishedWorkout(title: "Push", startedAt: day(4), duration: 47 * 60, exercises: [
                Exercise(name: "Chest Press", brand: "Technogym", sets: reps("70", "8", count: 3)),
                Exercise(name: "Shoulder Press", brand: "Hammer Strength", sets: reps("40", "10", count: 3)),
                Exercise(name: "Triceps Pushdown", sets: reps("30", "12", count: 2)),
            ]),
            FinishedWorkout(title: "Leg day", startedAt: day(6), duration: 61 * 60, exercises: [
                Exercise(name: "Adductors", brand: "Technogym", sets: reps("55", "8", count: 2)),
                Exercise(name: "Leg Press", sets: reps("160", "10", count: 3)),
                Exercise(name: "Seated Calf Raise", brand: "Hammer Strength", sets: reps("60", "12", count: 3)),
            ]),
        ]
    }
}
