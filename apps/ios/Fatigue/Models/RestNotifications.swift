import Foundation
import UserNotifications

/// Tells you rest is over when the phone is locked or you're in another app, with a local notification
/// such as "Rest done" over "Adductors". Only one is ever pending: the one for the current rest timer.
/// While the app is open the workout screen's haptic does the job, so the notification isn't shown.
@MainActor
final class RestNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = RestNotifications()

    nonisolated static let identifier = "rest-timer"

    /// Bumped on every update, so a slow permission prompt can't schedule a timer that has since changed.
    private var generation = 0

    func becomeDelegate() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// The notification for a rest timer, or nil when there's none or it's already over.
    nonisolated static func request(for rest: RestTimer?, now: Date = .now) -> UNNotificationRequest? {
        guard let rest else { return nil }
        let seconds = rest.endsAt.timeIntervalSince(now)
        guard seconds >= 1 else { return nil }
        let content = UNMutableNotificationContent()
        content.title = "Rest done"
        content.body = rest.exerciseName.isEmpty ? "Time for your next set." : rest.exerciseName
        content.sound = .default
        return UNNotificationRequest(
            identifier: identifier, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        )
    }

    /// Replaces any pending notification with one for this timer. Asks for permission the first time,
    /// so the prompt comes when rest starts rather than at launch. Saying no just means no notifications.
    func update(for rest: RestTimer?) {
        generation += 1
        let current = generation
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        guard let request = Self.request(for: rest) else { return }
        Task {
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true, current == generation else { return }
            try? await center.add(request)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        []
    }
}
