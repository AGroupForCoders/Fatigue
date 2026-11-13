import CryptoKit
import Foundation

/// What travels between the phone and the server: one top row and everything under it, as the Sync docs
/// page explains. The shapes here match `apps/api/src/modules/sync/sync.items.ts` field for field.
///
/// IDs are lowercase on the wire. The database keeps them in upper case, as `UUID.uuidString` gives them.
nonisolated struct SyncItem: Codable, Equatable, Sendable {
    /// In the order they have to arrive: a brand points at an exercise, and routines and workouts point at brands.
    enum Kind: String, Codable, CaseIterable, Sendable {
        case exercise, brand, routine, workout
        case userSetting = "user_setting"
    }

    var kind: Kind
    var id: String
    /// Milliseconds since 1970. The later one wins when two phones changed the same item.
    var updatedAt: Int64
    var deletedAt: Int64?
    /// Nil only for a deleted routine or workout, whose rows are gone.
    var body: Body?

    enum Body: Equatable, Sendable {
        case exercise(ExerciseBody)
        case brand(BrandBody)
        case routine(RoutineBody)
        case workout(WorkoutBody)
        case userSetting(UserSettingBody)
    }

    struct ExerciseBody: Codable, Equatable, Sendable {
        var name: String
        var equipment: String
        var muscles: [Muscle]
    }

    struct Muscle: Codable, Equatable, Sendable {
        var muscle: String
        var share: Double
    }

    struct BrandBody: Codable, Equatable, Sendable {
        var exerciseId: String
        var brand: String?
        var label: String?
        var settings: [Setting]
    }

    /// A setting with its next-time value. A removed one stays, marked deleted, for the workouts that used it.
    struct Setting: Codable, Equatable, Sendable {
        var id: String
        var name: String
        var kind: String
        var value: Double?
        var textValue: String?
        var direction: String?
        var rangeMin: Double?
        var rangeMax: Double?
        var splitByValue: Bool
        var factor: Double?
        var position: Double
        var deletedAt: Int64?
    }

    struct RoutineBody: Codable, Equatable, Sendable {
        var name: String
        var position: Double
        var exercises: [Exercise]
    }

    struct WorkoutBody: Codable, Equatable, Sendable {
        var title: String
        var note: String?
        var startedAt: Int64
        var finishedAt: Int64
        var routineId: String?
        var importKey: String?
        var gymName: String?
        var gymAddress: String?
        var gymLatitude: Double?
        var gymLongitude: Double?
        var exercises: [Exercise]
    }

    /// An exercise in a workout or a routine. The order of `exercises`, `notes` and `sets` is their position.
    struct Exercise: Codable, Equatable, Sendable {
        var id: String
        var brandId: String
        var restSeconds: Int
        /// Workouts only. Empty in a routine.
        var notes: [Note]
        var settings: [SettingValue]
        var sets: [WorkoutSet]
    }

    struct Note: Codable, Equatable, Sendable {
        var id: String
        var text: String
    }

    struct SettingValue: Codable, Equatable, Sendable {
        var settingId: String
        var value: Double?
        var textValue: String?
    }

    struct WorkoutSet: Codable, Equatable, Sendable {
        var id: String
        var kind: String
        var setType: String
        var weightKg: Double?
        var reps: Int?
        var durationSeconds: Int?
        /// Workouts only. Nil in a routine.
        var rpe: Double?
        var completedAt: Int64?
        var overrides: [Override]
    }

    struct Override: Codable, Equatable, Sendable {
        var settingId: String
        var value: Double
    }

    struct UserSettingBody: Codable, Equatable, Sendable {
        var weightUnit: String
    }

    // MARK: Coding

    private enum CodingKeys: String, CodingKey {
        case kind, id, updatedAt, deletedAt, body
    }

    init(kind: Kind, id: String, updatedAt: Int64, deletedAt: Int64? = nil, body: Body?) {
        self.kind = kind
        self.id = id
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.body = body
    }

    /// The body is read as whatever `kind` says it is.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        id = try container.decode(String.self, forKey: .id)
        updatedAt = try container.decode(Int64.self, forKey: .updatedAt)
        deletedAt = try container.decodeIfPresent(Int64.self, forKey: .deletedAt)
        guard container.contains(.body), try !container.decodeNil(forKey: .body) else {
            body = nil
            return
        }
        switch kind {
        case .exercise: body = .exercise(try container.decode(ExerciseBody.self, forKey: .body))
        case .brand: body = .brand(try container.decode(BrandBody.self, forKey: .body))
        case .routine: body = .routine(try container.decode(RoutineBody.self, forKey: .body))
        case .workout: body = .workout(try container.decode(WorkoutBody.self, forKey: .body))
        case .userSetting: body = .userSetting(try container.decode(UserSettingBody.self, forKey: .body))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(id, forKey: .id)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        switch body {
        case .exercise(let body): try container.encode(body, forKey: .body)
        case .brand(let body): try container.encode(body, forKey: .body)
        case .routine(let body): try container.encode(body, forKey: .body)
        case .workout(let body): try container.encode(body, forKey: .body)
        case .userSetting(let body): try container.encode(body, forKey: .body)
        case nil: try container.encodeNil(forKey: .body)
        }
    }

    // MARK: Comparing

    /// "workout:7a1c…", which tells one item from every other.
    var key: String { "\(kind.rawValue):\(id)" }

    /// A fingerprint of what the item holds: its body and whether it is deleted, and not when it changed.
    /// The phone compares it with the fingerprint from the last time it and the server agreed, and pushes
    /// the item when they differ. It is only ever compared with one made on the same phone.
    var contentHash: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var content = self
        content.updatedAt = 0
        content.deletedAt = deletedAt == nil ? nil : 1
        let data = (try? encoder.encode(content)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
