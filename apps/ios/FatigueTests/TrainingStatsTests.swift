import Foundation
import Testing
@testable import Fatigue

@MainActor
struct TrainingStatsTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }

    /// Wednesday 11 November 2026, noon UTC.
    private let now = Date(timeIntervalSince1970: 1_794_398_400)

    private func workout(daysAgo: Double, _ name: String = "Leg Press", weight: String = "100") -> FinishedWorkout {
        FinishedWorkout(title: "Legs", startedAt: now.addingTimeInterval(-daysAgo * 86_400), duration: 3600, exercises: [
            WorkoutExercise(name: name, restSeconds: 90, sets: [
                WorkoutSet(setup: SetSetup(kind: .reps), weight: weight, amount: "10", isDone: true),
                WorkoutSet(setup: SetSetup(kind: .reps), weight: weight, amount: "10", isDone: true),
            ]),
        ])
    }

    @Test func thisWeekIsComparedWithLastWeek() {
        let stats = TrainingStats(history: [workout(daysAgo: 1), workout(daysAgo: 8), workout(daysAgo: 9)], now: now, calendar: calendar)
        #expect(stats.thisWeek == .init(workouts: 1, sets: 2, volume: 2000))
        #expect(stats.lastWeek == .init(workouts: 2, sets: 4, volume: 4000))
    }

    @Test func weeklyVolumeCoversTwelveWeeksEndingThisWeek() {
        let stats = TrainingStats(history: [workout(daysAgo: 1), workout(daysAgo: 75)], now: now, calendar: calendar)
        #expect(stats.weeks.count == 12)
        #expect(stats.weeks.last?.volume == 2000)
        #expect(stats.weeks.first?.volume == 2000)
    }

    @Test func exercisesComeMostRecentFirstWithTheirChange() {
        let stats = TrainingStats(history: [
            workout(daysAgo: 1, weight: "110"), workout(daysAgo: 5, weight: "100"), workout(daysAgo: 3, "Squat"),
        ], now: now, calendar: calendar)
        #expect(stats.exercises.map(\.name) == ["Leg Press", "Squat"])
        #expect(stats.exercises[0].values == [1000, 1100])
        #expect(abs(stats.exercises[0].change! - 0.1) < 0.0001)
        #expect(stats.exercises[1].change == nil)
        #expect(StatsScreen.percent(0.1) == "+10%")
    }
}
