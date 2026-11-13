import Foundation
import Testing
@testable import Fatigue

@MainActor
struct MediaTests {
    private func row(_ workout: String, id: String = UUID().uuidString, kind: String = "photo", at seconds: TimeInterval = 0) -> StoredMedia {
        StoredMedia(id: id, workoutId: workout, kind: kind, fileName: "\(id).heic", width: 3024, height: 4032,
                    durationSeconds: kind == "video" ? 12.4 : nil, createdAt: Date(timeIntervalSince1970: 1_700_000_000 + seconds))
    }

    @Test func insertedMediaComesBackOldestFirst() throws {
        let database = try AppDatabase.inMemory()
        let workout = UUID().uuidString
        let later = row(workout, at: 10)
        let earlier = row(workout, kind: "video", at: 0)
        try database.insert(later)
        try database.insert(earlier)
        try database.insert(row(UUID().uuidString))

        let all = try database.media()
        #expect(all.count == 3)
        #expect(all.filter { $0.workoutId == workout } == [earlier, later])
        let video = try #require(all.first { $0.kind == "video" })
        #expect(video.durationSeconds == 12.4)
        #expect(video.width == 3024)
    }

    @Test func deletingMarksTheRowInsteadOfRemovingIt() throws {
        let database = try AppDatabase.inMemory()
        let workout = UUID().uuidString
        let kept = row(workout)
        let gone = row(workout)
        try database.insert(kept)
        try database.insert(gone)

        try database.deleteMedia(id: gone.id)
        #expect(try database.media().map(\.id) == [kept.id])
        let marked = try #require(try database.media(includingDeleted: true).first { $0.id == gone.id })
        #expect(marked.deletedAt != nil)

        try database.deleteMedia(workoutId: workout)
        #expect(try database.media().isEmpty)
        #expect(try database.media(includingDeleted: true).count == 2)
        #expect(try database.media(includingDeleted: true).allSatisfy { $0.deletedAt != nil })
    }

    @Test func movingFollowsTheWorkoutToItsNewId() throws {
        let database = try AppDatabase.inMemory()
        let running = UUID().uuidString
        let finished = UUID().uuidString
        try database.insert(row(running))
        try database.insert(row(running))
        try database.moveMedia(from: running, to: finished)
        #expect(try database.media().map(\.workoutId) == [finished, finished])
    }

    @Test func finishingMovesMediaOntoTheSavedWorkout() throws {
        let database = try AppDatabase.inMemory()
        let first = WorkoutStore(database: database)
        first.start(first.routines[0])
        first.saveActive()
        let runningID = try #require(first.active?.id)
        try database.insert(row(runningID.uuidString))

        let reopened = WorkoutStore(database: database)
        #expect(reopened.media.media(for: runningID).count == 1)
        reopened.finish(unticked: .count)
        let saved = try #require(reopened.history.first)
        #expect(saved.id != runningID)
        #expect(reopened.media.media(for: saved.id).count == 1)
        #expect(reopened.media.media(for: runningID).isEmpty)
        #expect(try database.media().map(\.workoutId) == [saved.id.uuidString])
    }

    @Test func discardingAndDeletingTakeTheMediaWithThem() throws {
        let database = try AppDatabase.inMemory()
        let setup = WorkoutStore(database: database)
        let workout = try #require(setup.history.first)
        setup.startEmpty()
        setup.saveActive()
        let runningID = try #require(setup.active?.id)
        try database.insert(row(workout.id.uuidString))
        try database.insert(row(runningID.uuidString))

        let store = WorkoutStore(database: database)
        store.discard()
        store.deleteFromHistory(workout.id)
        #expect(store.media.media(for: workout.id).isEmpty)
        #expect(store.media.media(for: runningID).isEmpty)
        #expect(try database.media().isEmpty)
    }

    @Test func storedRowsMapBothWays() throws {
        let stored = row(UUID().uuidString, kind: "video")
        let media = try #require(WorkoutMedia(stored: stored))
        #expect(media.kind == .video)
        #expect(media.durationLabel == "0:12")
        #expect(media.stored == stored)
        #expect(WorkoutMedia(stored: row("not-a-uuid")) == nil)
    }
}
