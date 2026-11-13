import CryptoKit
import Foundation

/// IDs built from what makes a row unique, so two phones offline produce the same row and sync merges
/// them instead of keeping both. A UUIDv5 of the parts, as the data model page describes.
///
/// Used for exercises (their name), exercise-and-brand rows (exercise and brand), setting values and
/// overrides (their parent and setting), muscles (exercise and muscle) and planned sets (exercise and position).
nonisolated enum SyncID {
    /// Fatigue's own namespace. Changing it would give every derived row a new id, so it never changes.
    private static let namespace = UUID(uuidString: "3b9c6f0e-2a4d-4c8a-9e51-7f0d2b6a1c45")!

    static func uuid(_ parts: String...) -> String {
        var hasher = Insecure.SHA1()
        withUnsafeBytes(of: namespace.uuid) { hasher.update(bufferPointer: $0) }
        hasher.update(data: Data(parts.joined(separator: "|").utf8))
        var bytes = Array(hasher.finalize().prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let uuid = UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                               bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
        return uuid.uuidString
    }

    static func exercise(named name: String) -> String { uuid("exercise", name) }
    static func exerciseBrand(exerciseId: String, brand: String?) -> String { uuid("exercise_brand", exerciseId, brand ?? "") }
    static func muscle(exerciseId: String, muscle: String) -> String { uuid("exercise_muscle", exerciseId, muscle) }
    static func settingValue(ownerId: String, settingId: String) -> String { uuid("setting_value", ownerId, settingId) }
    static func override(setId: String, settingId: String) -> String { uuid("override", setId, settingId) }
    static func plannedSet(exerciseId: String, position: Int) -> String { uuid("planned_set", exerciseId, String(position)) }
}
