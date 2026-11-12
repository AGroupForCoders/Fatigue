import Foundation

/// The Stats tab's numbers: this week against last, weekly volume, and a trend for each exercise.
/// Volume is plain kilograms on rep sets, the same as history rows and the finish summary.
struct TrainingStats {
    /// Workouts, sets and volume over one stretch of time.
    struct Totals: Equatable {
        var workouts = 0
        var sets = 0
        var volume = 0.0
    }

    /// One week's volume, for the bar chart.
    struct Week: Identifiable, Equatable {
        let start: Date
        let volume: Double
        var id: Date { start }
    }

    /// An exercise you've done, on the brand you've used most, with its best set volume per workout.
    struct ExerciseTrend: Identifiable, Equatable {
        let name: String
        let brand: String?
        /// Best set volume per workout, oldest first, at most the last eight.
        let values: [Double]
        let lastDone: Date
        var id: String { name }

        /// Latest against the first of `values`, as a fraction: 0.1 is up 10%. Nil with fewer than two.
        var change: Double? {
            guard values.count > 1, let first = values.first, let last = values.last, first > 0 else { return nil }
            return (last - first) / first
        }
    }

    let thisWeek: Totals
    let lastWeek: Totals
    /// The last 12 weeks, oldest first, ending with this one.
    let weeks: [Week]
    /// Most recently done first.
    let exercises: [ExerciseTrend]

    init(history: [FinishedWorkout], now: Date = .now, calendar: Calendar = .current) {
        let thisStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        func weekStart(_ offset: Int) -> Date { calendar.date(byAdding: .weekOfYear, value: offset, to: thisStart) ?? thisStart }
        func totals(from start: Date, to end: Date) -> Totals {
            history.filter { $0.startedAt >= start && $0.startedAt < end }.reduce(into: Totals()) { totals, workout in
                totals.workouts += 1
                totals.sets += workout.setCount
                totals.volume += workout.volume
            }
        }

        thisWeek = totals(from: thisStart, to: weekStart(1))
        lastWeek = totals(from: weekStart(-1), to: thisStart)
        weeks = (-11...0).map { offset in
            Week(start: weekStart(offset), volume: totals(from: weekStart(offset), to: weekStart(offset + 1)).volume)
        }

        var lastDone: [String: Date] = [:]
        for workout in history {
            for exercise in workout.exercises where exercise.sets.contains(where: \.isDone) {
                lastDone[exercise.name] = max(lastDone[exercise.name] ?? .distantPast, workout.startedAt)
            }
        }
        exercises = lastDone
            .sorted { $0.value > $1.value }
            .map { name, date in
                let brand = ExerciseStats.brands(for: name, in: history).first ?? nil
                let values = ExerciseStats(name: name, brand: brand, history: history).points(.setVolume, weighted: false).map(\.value)
                return ExerciseTrend(name: name, brand: brand, values: Array(values.suffix(8)), lastDone: date)
            }
    }
}
