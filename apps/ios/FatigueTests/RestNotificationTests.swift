import Foundation
import Testing
import UserNotifications
@testable import Fatigue

@MainActor
struct RestNotificationTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func tickingASetNamesTheExerciseOnTheTimer() {
        let session = WorkoutSession.sample(now: { self.now })
        session.toggle(set: 2, in: 0)
        #expect(session.rest?.exerciseName == "Adductors")
    }

    @Test func theNotificationFiresWhenRestEnds() throws {
        let rest = RestTimer(endsAt: now.addingTimeInterval(90), total: 90, exerciseName: "Adductors")
        let request = try #require(RestNotifications.request(for: rest, now: now))
        #expect(request.identifier == RestNotifications.identifier)
        #expect(request.content.title == "Rest done")
        #expect(request.content.body == "Adductors")
        let trigger = try #require(request.trigger as? UNTimeIntervalNotificationTrigger)
        #expect(trigger.timeInterval == 90)
    }

    @Test func movingTheTimerMovesTheNotification() throws {
        let session = WorkoutSession.sample(now: { self.now })
        session.toggle(set: 2, in: 0)
        session.adjustRest(by: 15)
        let trigger = try #require(RestNotifications.request(for: session.rest, now: now)?.trigger as? UNTimeIntervalNotificationTrigger)
        #expect(trigger.timeInterval == 135)
    }

    @Test func noTimerOrAFinishedOneSchedulesNothing() {
        #expect(RestNotifications.request(for: nil, now: now) == nil)
        #expect(RestNotifications.request(for: RestTimer(endsAt: now, total: 90), now: now) == nil)
    }
}
