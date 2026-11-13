import AppIntents
import Foundation

/// What the Live Activity's buttons can do to the rest timer.
nonisolated enum RestAction: Equatable, Sendable {
    case skip
    case extend(TimeInterval)
}

/// Where the intents below hand their action to the app.
///
/// A `LiveActivityIntent` runs in the app's process, not the widget's, launching the app in the
/// background if it was closed. The app points `perform` at its workout store when it launches
/// (see `FatigueApp`). The widget extension compiles the intents too, to put them on its buttons,
/// but never runs them, so there `perform` stays nil.
@MainActor
enum RestIntentHandler {
    static var perform: ((RestAction) -> Void)?
}

/// Skip on the Live Activity: ends the rest timer now.
nonisolated struct SkipRestIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Skip rest" }
    static var description: IntentDescription { IntentDescription("Ends the rest timer now.") }
    static var isDiscoverable: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult {
        RestIntentHandler.perform?(.skip)
        return .result()
    }
}

/// +15 s on the Live Activity: gives the rest timer fifteen more seconds, like the button in the app.
nonisolated struct ExtendRestIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Add 15 seconds of rest" }
    static var description: IntentDescription { IntentDescription("Adds fifteen seconds to the rest timer.") }
    static var isDiscoverable: Bool { false }

    /// How much Skip's neighbour adds, matching +15 in the app's rest bar.
    static let seconds: TimeInterval = 15

    @MainActor
    func perform() async throws -> some IntentResult {
        RestIntentHandler.perform?(.extend(Self.seconds))
        return .result()
    }
}
