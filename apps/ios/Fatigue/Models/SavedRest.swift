import Foundation

/// The rest timer of the running workout, saved on the phone while it runs.
///
/// The Live Activity's Skip and +15 s buttons run in the app, and can launch it after it was closed.
/// The workout comes back from the database, and this puts its rest timer back too, so the buttons act on
/// the timer the Lock Screen is showing. It's kept in `UserDefaults` rather than the database: the timer is
/// this phone's state for a few minutes, not part of the workout the data model syncs.
nonisolated struct SavedRest: Codable, Equatable, Sendable {
    /// Which workout the timer belongs to, so a timer from a workout since finished is ignored.
    var workoutID: UUID
    var rest: RestTimer

    static let key = "rest-timer"

    static func load(from defaults: UserDefaults) -> SavedRest? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SavedRest.self, from: data)
    }

    /// Saves the timer, or clears what was saved when there's none.
    static func save(_ saved: SavedRest?, to defaults: UserDefaults) {
        if let saved, let data = try? JSONEncoder().encode(saved) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
