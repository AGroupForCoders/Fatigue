import Foundation
import Testing
@testable import Fatigue

@MainActor
struct HistoryTests {
    @Test func finishingKeepsOnlyTickedSets() {
        let start = Date(timeIntervalSince1970: 0)
        let session = WorkoutSession.sample(now: { start })
        let finished = session.finished(at: start.addingTimeInterval(3_000))
        // The sample has sets 1 and 2 of Adductors ticked and nothing else.
        #expect(finished.exercises.map(\.name) == ["Adductors"])
        #expect(finished.setCount == 2)
        #expect(finished.duration == 3_000)
    }

    @Test func volumeCountsRepSetsOnly() {
        let finished = WorkoutSession.sample().finished(at: .now)
        // The 40 kg hold is left out, the 55 × 8 rep set counts.
        #expect(finished.volume == 440)
    }

    @Test func finishingPutsTheWorkoutAtTheTopOfHistory() {
        let store = WorkoutStore(history: [])
        store.start(store.routines[0])
        store.active?.toggle(set: 0, in: 1)
        store.finish()
        #expect(store.history.map(\.title) == ["Leg day"])
        #expect(store.active == nil)
    }

    @Test func aWorkoutWithNothingTickedIsNotSaved() {
        let store = WorkoutStore(history: [])
        store.startEmpty()
        store.finish()
        #expect(store.history.isEmpty)
    }

    @Test func historyRowsSayWhenAndHowMuch() {
        let now = Date(timeIntervalSince1970: 1_794_500_000)
        #expect(HistoryRow.when(now, now: now) == "Today")
        #expect(HistoryRow.when(now.addingTimeInterval(-86_400), now: now) == "Yesterday")
        let workout = FinishedWorkout.samples(now: now)[0]
        #expect(HistoryRow.summary(workout) == "52 min · 9 sets · \(Int(workout.volume).formatted()) kg")
    }
}
