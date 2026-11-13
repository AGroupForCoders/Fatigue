import CryptoKit
import Foundation

/// IDs built from what makes a row unique, so two phones that each create the row offline give it the
/// same ID and sync treats them as one. The data model page lists which rows get one.
///
/// These are UUIDv5: a SHA-1 of a namespace and a name, shaped into a UUID.
nonisolated enum SyncID {
    /// Every built ID hangs off this. The server builds the same IDs from it, so it must never change.
    static let namespace = UUID(uuidString: "708A9EE1-ED5C-4125-BAD5-AA140C42036D")!

    /// An exercise's ID, from its name. Case and the spaces around it don't count, so "Chest Press" and
    /// " chest press" are one exercise.
    static func exercise(named name: String) -> String {
        let name = name.trimmingCharacters(in: .whitespaces).precomposedStringWithCanonicalMapping.lowercased()
        return uuid5("exercise:" + name).uuidString
    }

    /// The ID of an exercise's no-brand row, from the exercise's ID. An exercise has at most one.
    static func noBrand(exerciseId: String) -> String {
        uuid5("exercise_brand:" + exerciseId.lowercased()).uuidString
    }

    static func uuid5(_ name: String, in namespace: UUID = namespace) -> UUID {
        var hasher = Insecure.SHA1()
        withUnsafeBytes(of: namespace.uuid) { hasher.update(bufferPointer: $0) }
        hasher.update(data: Data(name.utf8))
        var bytes = Array(hasher.finalize().prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // version 5
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
