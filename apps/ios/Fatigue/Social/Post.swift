import Foundation

/// A finished workout as it was when shared. Friends read this, never your synced tables, so editing the
/// workout later doesn't change the post unless you share it again.
///
/// Weights are kilograms and each viewer sees their own unit. Records are written in the sharer's unit,
/// since they're worked out on the sharer's phone.
nonisolated struct PostSnapshot: Codable, Hashable, Sendable {
    /// Bumped when the shape changes, so a newer app can still read posts shared by an older one.
    static let version = 1

    struct Place: Codable, Hashable, Sendable {
        var name: String
        var address: String?
        var latitude: Double?
        var longitude: Double?
    }

    struct Exercise: Codable, Hashable, Sendable {
        var name: String
        var brand: String?
        /// Such as "Notch 7" or "Dead stop yes".
        var settings: [String]
        var notes: [String]
        var groups: [Group]
    }

    /// Sets under one heading, such as "Hold · Notch 8". The heading is empty when there's nothing to separate.
    struct Group: Codable, Hashable, Sendable {
        var heading: String
        var sets: [LoggedSet]
    }

    struct LoggedSet: Codable, Hashable, Sendable {
        /// The set's number, or W, D or F for a warm-up, drop set or set to failure.
        var mark: String
        var type: String
        var kind: String
        var weightKg: Double?
        /// Reps for a rep set, seconds for a hold.
        var amount: String
        var rpe: Double?
    }

    struct Record: Codable, Hashable, Sendable {
        var exercise: String
        var brand: String?
        /// Such as "Heaviest weight".
        var record: String
        /// Such as "60 kg".
        var value: String
    }

    var title: String
    var description: String
    var startedAt: Date
    var durationSeconds: Int
    var gym: Place?
    var setCount: Int
    var volumeKg: Double
    var exercises: [Exercise]
    var records: [Record]
}

extension PostSnapshot {
    /// The snapshot of `workout`, with the records it beat.
    init(_ workout: FinishedWorkout, records: [ExerciseStats.Beaten]) {
        self.init(
            title: workout.title,
            description: workout.description,
            startedAt: workout.startedAt,
            durationSeconds: Int(workout.duration.rounded()),
            gym: workout.gym.map { Place(name: $0.name, address: $0.address, latitude: $0.latitude, longitude: $0.longitude) },
            setCount: workout.setCount,
            volumeKg: workout.volume,
            exercises: workout.exercises.map { exercise in
                Exercise(
                    name: exercise.name,
                    brand: exercise.brand?.display,
                    settings: exercise.settings.map { "\($0.name) \(SettingEditor.displayValue($0))" },
                    notes: exercise.notes.map(\.text).filter { !$0.isEmpty },
                    groups: exercise.groups.map { group in
                        Group(heading: group.heading, sets: group.setIndices.map { index in
                            let set = exercise.sets[index]
                            return LoggedSet(mark: exercise.sets.mark(at: index), type: set.type.rawValue, kind: set.kind.rawValue,
                                       weightKg: Double(set.weight), amount: set.amount, rpe: set.rpe)
                        })
                    }
                )
            },
            records: records.map { Record(exercise: $0.exercise, brand: $0.brand?.display, record: $0.record, value: $0.value) }
        )
    }
}

extension PostSnapshot.LoggedSet {
    /// Such as "60 kg × 8" or "45 s", in the viewer's unit.
    func text(in unit: WeightUnit) -> String {
        PreviousSet(kind: SetKind(rawValue: kind) ?? .reps, weightKg: weightKg, amount: amount).text(in: unit)
    }

    var isNormal: Bool { type == SetType.normal.rawValue }
}

/// What the phone sends to share a workout. Kept on the phone until the API has it, so a share made
/// offline goes out later under the same ID and never makes two posts.
nonisolated struct ShareRequest: Codable, Hashable, Sendable {
    var id: String
    var workoutId: String
    var caption: String?
    var visibility: PostVisibility
    var startedAt: Date
    var snapshotVersion = PostSnapshot.version
    var snapshot: PostSnapshot
}

/// A shared workout, as the API returns it.
nonisolated struct Post: Decodable, Hashable, Identifiable, Sendable {
    struct Author: Codable, Hashable, Sendable {
        let userId: String
        let handle: String
        let name: String
    }

    let id: String
    let author: Author
    /// The workout's ID on the sharer's phone. Only there on your own posts.
    let workoutId: String?
    let caption: String?
    let visibility: PostVisibility
    let startedAt: Date
    let createdAt: Date
    /// Nil when it was shared by a newer app in a shape this one can't read.
    let snapshot: PostSnapshot?

    private enum CodingKeys: String, CodingKey { case id, author, workoutId, caption, visibility, startedAt, createdAt, snapshotVersion, snapshot }

    init(id: String, author: Author, workoutId: String?, caption: String?, visibility: PostVisibility, startedAt: Date, createdAt: Date, snapshot: PostSnapshot?) {
        self.id = id
        self.author = author
        self.workoutId = workoutId
        self.caption = caption
        self.visibility = visibility
        self.startedAt = startedAt
        self.createdAt = createdAt
        self.snapshot = snapshot
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        author = try container.decode(Author.self, forKey: .author)
        workoutId = try container.decodeIfPresent(String.self, forKey: .workoutId)
        caption = try container.decodeIfPresent(String.self, forKey: .caption)
        visibility = try container.decode(PostVisibility.self, forKey: .visibility)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        let version = try container.decode(Int.self, forKey: .snapshotVersion)
        snapshot = version <= PostSnapshot.version ? try? container.decode(PostSnapshot.self, forKey: .snapshot) : nil
    }
}

/// One page of posts. `nextCursor` is nil on the last page.
nonisolated struct PostPage: Decodable, Sendable {
    let posts: [Post]
    let nextCursor: String?
}
