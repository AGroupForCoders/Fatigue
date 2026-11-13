import Foundation
import Testing
@testable import Fatigue

/// Warm-ups, drop sets and sets to failure: how they're numbered, and what warm-ups are left out of.
@MainActor
struct SetTypeTests {
    private func set(_ weight: String, _ reps: String, type: SetType = .normal, done: Bool = true) -> WorkoutSet {
        WorkoutSet(setup: SetSetup(kind: .reps), type: type, weight: weight, amount: reps, previous: "", isDone: done)
    }

    private func legPress(_ sets: [WorkoutSet]) -> WorkoutExercise {
        WorkoutExercise(name: "Leg Press", brand: "Technogym", restSeconds: 90, sets: sets)
    }

    private func workout(day: Double, _ sets: [WorkoutSet]) -> FinishedWorkout {
        FinishedWorkout(title: "Legs", startedAt: Date(timeIntervalSince1970: day * 86_400), duration: 3600, exercises: [legPress(sets)])
    }

    // MARK: Numbering

    @Test func warmUpsShowWAndTakeNoNumber() {
        let sets = [set("60", "10", type: .warmup), set("100", "8"), set("100", "8"), set("70", "12", type: .drop), set("100", "6", type: .failure), set("100", "8")]
        #expect((0..<sets.count).map { sets.mark(at: $0) } == ["W", "1", "2", "D", "F", "5"])
        #expect((0..<sets.count).map { sets.number(at: $0) } == [nil, 1, 2, 3, 4, 5])
    }

    @Test func setsAreReadOutWithTheirType() {
        let sets = [set("60", "10", type: .warmup), set("100", "8"), set("70", "12", type: .drop)]
        #expect(sets.spokenName(at: 0) == "Warm-up set")
        #expect(sets.spokenName(at: 1) == "Set 1")
        #expect(sets.spokenName(at: 2) == "Set 2, drop set")
    }

    @Test func aSetsTypeCanBeChanged() {
        let session = WorkoutSession(title: "Legs", exercises: [legPress([set("60", "10"), set("100", "8")])])
        session.changeType(of: session.exercises[0].sets[0].id, to: .warmup)
        #expect(session.exercises[0].sets.map(\.type) == [.warmup, .normal])
        #expect(session.exercises[0].sets.mark(at: 1) == "1")
    }

    // MARK: Volume

    @Test func warmUpsAreLeftOutOfVolume() {
        let finished = workout(day: 1, [set("60", "10", type: .warmup), set("100", "8"), set("70", "12", type: .drop), set("100", "6", type: .failure)])
        #expect(finished.volume == 800 + 840 + 600)
        #expect(finished.setCount == 4)
    }

    @Test func warmUpsAreLeftOutOfTheExercisePage() {
        let stats = ExerciseStats(name: "Leg Press", brand: "Technogym", history: [
            workout(day: 1, [set("120", "10", type: .warmup), set("100", "8")]),
        ])
        #expect(stats.points(.setVolume, weighted: false).map(\.value) == [800])
        #expect(stats.points(.weight, weighted: false).map(\.value) == [100])
        #expect(stats.records().heaviestWeight?.value == 100)
        #expect(stats.records().bestSessionVolume?.detail == "1 set")
        #expect(stats.sessions[0].sets.count == 2)
    }

    @Test func aWorkoutOfOnlyWarmUpsHasNoPoints() {
        let stats = ExerciseStats(name: "Leg Press", brand: "Technogym", history: [workout(day: 1, [set("60", "10", type: .warmup)])])
        #expect(stats.points(.setVolume, weighted: false).isEmpty)
        #expect(stats.records().heaviestWeight == nil)
    }

    // MARK: Records and scores

    @Test func aWarmUpHasNoScore() {
        let exercise = legPress([set("100", "8", type: .warmup), set("100", "8", type: .failure)])
        #expect(SetScore.score(of: exercise.sets[0], in: exercise) == nil)
        #expect(SetScore.score(of: exercise.sets[1], in: exercise) == 800)
    }

    @Test func aWarmUpIsNeverARecordAndSetsNoBest() {
        let history = [workout(day: 1, [set("100", "8")])]
        let today = legPress([set("120", "8", type: .warmup), set("110", "8")])
        let marks = RecordBook.marks(for: [today], after: history)
        #expect(marks[today.sets[0].id] == nil)
        #expect(marks[today.sets[1].id] == [.weight, .score])
    }

    @Test func aHeavyWarmUpInHistoryDoesNotHideALaterRecord() {
        let history = [workout(day: 1, [set("150", "5", type: .warmup), set("100", "8")])]
        let today = legPress([set("110", "8")])
        #expect(RecordBook(history: history).records(for: today.sets[0], in: today) == [.weight, .score])
    }

    @Test func dropAndFailureSetsCountLikeNormalSets() {
        let history = [workout(day: 1, [set("100", "8")])]
        let today = legPress([set("110", "8", type: .drop), set("120", "8", type: .failure)])
        let marks = RecordBook.marks(for: [today], after: history)
        #expect(marks[today.sets[0].id] == [.weight, .score])
        #expect(marks[today.sets[1].id] == [.weight, .score])
    }

    @Test func theFinishSummaryIgnoresWarmUpsWhenListingBeatenRecords() {
        let today = workout(day: 2, [set("200", "10", type: .warmup), set("100", "10")])
        #expect(ExerciseStats.beaten(by: today, history: [workout(day: 1, [set("100", "10")])]).isEmpty)
    }

    // MARK: Persistence

    @Test func setTypesSurviveSavingAndLoading() throws {
        let database = try AppDatabase.inMemory()
        let original = workout(day: 1, [set("60", "10", type: .warmup), set("100", "8"), set("70", "12", type: .drop), set("100", "6", type: .failure)])
        try database.save(original.stored)
        let loaded = FinishedWorkout(stored: try #require(try database.workouts().first))
        #expect(loaded.exercises[0].sets.map(\.type) == [.warmup, .normal, .drop, .failure])
        #expect(loaded.volume == original.volume)
    }

    @Test func aRoutineKeepsItsWarmUps() throws {
        let database = try AppDatabase.inMemory()
        let finished = workout(day: 1, [set("60", "10", type: .warmup), set("100", "8")])
        try database.save([finished.asRoutine().stored])
        let routine = Routine(stored: try #require(try database.routines().first))
        #expect(routine.exercises[0].sets.map(\.type) == [.warmup, .normal])
        #expect(routine.start().exercises[0].sets.map(\.type) == [.warmup, .normal])
    }
}
