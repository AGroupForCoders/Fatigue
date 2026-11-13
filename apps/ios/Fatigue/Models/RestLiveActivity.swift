import ActivityKit
import Foundation

/// The rest countdown on the Lock Screen and in the Dynamic Island, as a Live Activity.
/// There's only ever one: it starts with a rest timer, moves with ±15 s, and ends when rest is
/// skipped or runs out. The RestWidget extension draws it; this side only tells it what to show.
@MainActor
final class RestLiveActivity {
    static let shared = RestLiveActivity()

    /// The state the activity shows for a rest timer.
    nonisolated static func state(for rest: RestTimer) -> RestActivityAttributes.ContentState {
        RestActivityAttributes.ContentState(endsAt: rest.endsAt, total: rest.total, exerciseName: rest.exerciseName)
    }

    /// Shows this timer, or ends the activity when there's none. Called on every change to the timer.
    /// Starting is skipped when Live Activities are off in Settings; nothing else needs asking for.
    func update(for rest: RestTimer?, workoutTitle: String) {
        guard let rest, rest.endsAt > .now else { return end() }
        let content = ActivityContent(state: Self.state(for: rest), staleDate: rest.endsAt)
        if let activity = current {
            Task { await activity.update(content) }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            _ = try? Activity.request(attributes: RestActivityAttributes(workoutTitle: workoutTitle), content: content, pushType: nil)
        }
    }

    /// Takes the activity off the Lock Screen. Also ends any left over from a previous run of the app.
    func end() {
        for activity in Activity<RestActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// The activity on screen, if there is one. Looked up each time rather than remembered, since
    /// one can outlive the app's process and still be there when it launches again.
    private var current: Activity<RestActivityAttributes>? {
        Activity<RestActivityAttributes>.activities.first { $0.activityState == .active || $0.activityState == .stale }
    }
}
