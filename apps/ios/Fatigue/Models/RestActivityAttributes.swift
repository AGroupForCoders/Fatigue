import ActivityKit
import Foundation

/// What the rest Live Activity shows on the Lock Screen and in the Dynamic Island.
/// Compiled into the app, which starts and updates the activity, and into the RestWidget
/// extension, which draws it. Keep it free of anything else in the app.
nonisolated struct RestActivityAttributes: ActivityAttributes {
    /// The part that changes: each rest, and each ±15 s, is a new state.
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        var endsAt: Date
        var total: TimeInterval
        /// The exercise you're resting from.
        var exerciseName: String

        /// When the countdown started, so the progress line doesn't jump when the timer moves.
        var startedAt: Date { endsAt.addingTimeInterval(-total) }
    }

    /// The workout's name, fixed for the life of the activity.
    var workoutTitle: String
}
