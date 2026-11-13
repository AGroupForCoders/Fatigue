import CoreLocation
import Foundation

/// Where a workout was done: a gym picked from the map, with its address and coordinates,
/// or just a name you typed, such as "Home" or "Hotel gym".
nonisolated struct Gym: Hashable, Sendable {
    var name: String
    /// Such as "12 High St, Brighton". Nil for a typed name.
    var address: String?
    var latitude: Double?
    var longitude: Double?

    /// Nil when the name is blank, so an empty field never saves a gym.
    init?(name: String, address: String? = nil, latitude: Double? = nil, longitude: Double? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        self.name = trimmed
        self.address = address.flatMap { $0.isEmpty ? nil : $0 }
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Where it is on the map. Nil for a typed name.
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// The gyms you've trained at, most recent first, each once. Two with the same name and no map location
    /// are the same gym; ones picked from the map are told apart by where they are.
    static func recent(in history: [FinishedWorkout]) -> [Gym] {
        var seen: Set<Gym> = []
        return history.sorted { $0.startedAt > $1.startedAt }.compactMap(\.gym).filter { seen.insert($0).inserted }
    }
}
