import Foundation
import Observation

/// Your profile and friends, read from the API. Nothing here is kept on the phone: social stays out of sync,
/// so it's loaded when the Profile tab opens and simply isn't shown while offline.
@Observable
final class SocialStore {
    enum ProfileState: Equatable {
        /// Not loaded yet.
        case unknown
        /// Signed in, but no handle picked yet, so nobody can find you.
        case needsHandle
        case ready(MyProfile)
        /// The API couldn't be reached. The Profile tab leaves the social parts out.
        case unavailable
    }

    private(set) var profile: ProfileState = .unknown
    private(set) var friends: [FriendRow] = []
    /// Your feed so far, newest workout first. More loads as you scroll.
    private(set) var feed: [Post] = []
    private(set) var feedCursor: String?
    private(set) var feedLoaded = false
    /// Shares still waiting for a connection, oldest first.
    private(set) var pending: [ShareRequest] = []
    /// The post for each workout you've shared, by workout ID, so sharing again updates it.
    private(set) var shared: [String: String] = [:]
    private let api: any SocialAPI
    private let token: @Sendable () -> String?
    private let defaults: UserDefaults

    init(api: any SocialAPI = LiveSocialAPI(), token: @escaping @Sendable () -> String? = { TokenStore().read() }, defaults: UserDefaults = .standard) {
        self.api = api
        self.token = token
        self.defaults = defaults
    }

    var myProfile: MyProfile? {
        if case .ready(let profile) = profile { profile } else { nil }
    }

    var accepted: [FriendRow] { friends.filter { $0.relation == .friends } }
    var incoming: [FriendRow] { friends.filter { $0.relation == .incoming } }
    var outgoing: [FriendRow] { friends.filter { $0.relation == .outgoing } }

    /// Loads your profile, then your friends once there's a profile to have friends with.
    func load() async {
        guard let token = token() else { reset(); return }
        do {
            guard let mine = try await api.myProfile(token: token) else {
                profile = .needsHandle
                friends = []
                return
            }
            if myProfile?.userId != mine.userId { restoreSaved(for: mine.userId) }
            profile = .ready(mine)
            friends = try await api.friends(token: token)
            await sendPending()
        } catch {
            if profile == .unknown { profile = .unavailable }
        }
    }

    /// Creates or changes your profile. Throws the server's message, such as a taken handle, to show on the form.
    func save(_ changes: ProfileChanges) async throws {
        let saved = try await api.saveProfile(changes, token: try requireToken())
        if savedUserID != saved.userId { restoreSaved(for: saved.userId) }
        profile = .ready(saved)
    }

    func search(_ query: String) async throws -> [Person] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return [] }
        return try await api.search(text, token: try requireToken())
    }

    /// Sends a request, or accepts theirs. Returns where things stand, for the search row's button.
    @discardableResult
    func add(_ person: Person) async throws -> Relation {
        let relation = try await api.addFriend(person.userId, token: try requireToken())
        upsert(FriendRow(userId: person.userId, handle: person.handle, name: person.name, relation: relation, since: .now))
        return relation
    }

    /// Accepts their request. The row moves to friends straight away and moves back if the server says no.
    func accept(_ row: FriendRow) async throws {
        upsert(FriendRow(userId: row.userId, handle: row.handle, name: row.name, relation: .friends, since: .now))
        do {
            _ = try await api.acceptFriend(row.userId, token: try requireToken())
        } catch {
            upsert(row)
            throw error
        }
    }

    /// Declines, takes back a request, or unfriends. The row goes straight away and comes back if the server says no.
    func remove(_ row: FriendRow) async throws {
        friends.removeAll { $0.userId == row.userId }
        do {
            try await api.removeFriend(row.userId, token: try requireToken())
        } catch {
            upsert(row)
            throw error
        }
    }

    /// Forgets everything, such as on sign-out, so the next account on this phone starts clean.
    func reset() {
        profile = .unknown
        friends = []
        feed = []
        feedCursor = nil
        feedLoaded = false
        pending = []
        shared = [:]
        savedUserID = nil
    }

    // MARK: Sharing

    func isShared(_ workoutID: UUID) -> Bool {
        shared[workoutID.uuidString] != nil || pending.contains { $0.workoutId == workoutID.uuidString }
    }

    /// Shares `workout`, or shares it again with a fresh snapshot. Waits for a connection if there isn't one,
    /// and goes out on the next launch or refresh. Returns false when it's waiting.
    @discardableResult
    func share(_ workout: FinishedWorkout, records: [ExerciseStats.Beaten], visibility: PostVisibility, caption: String? = nil) async -> Bool {
        guard myProfile != nil else { return false }
        let workoutID = workout.id.uuidString
        let caption = caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = ShareRequest(
            id: shared[workoutID] ?? pending.first { $0.workoutId == workoutID }?.id ?? UUID().uuidString,
            workoutId: workoutID,
            caption: caption?.isEmpty == false ? caption : nil,
            visibility: visibility,
            startedAt: workout.startedAt,
            snapshot: PostSnapshot(workout, records: records)
        )
        pending.removeAll { $0.workoutId == workoutID }
        pending.append(request)
        save()
        return await send(request)
    }

    /// Sends every share still waiting. Stops at the first that can't reach the API, since the rest won't either.
    func sendPending() async {
        for request in pending {
            guard await send(request) else { return }
        }
    }

    /// Takes a workout off the feed. A share still waiting is simply dropped.
    func unshare(_ workoutID: UUID) async throws {
        let id = workoutID.uuidString
        pending.removeAll { $0.workoutId == id }
        save()
        guard let postID = shared[id] else { return }
        try await api.deletePost(postID, token: try requireToken())
        shared[id] = nil
        feed.removeAll { $0.id == postID }
        save()
    }

    /// Sends one share. A refusal from the API (not a lost connection) drops it, since sending again won't help.
    private func send(_ request: ShareRequest) async -> Bool {
        guard let token = token() else { return false }
        do {
            let post = try await api.share(request, token: token)
            pending.removeAll { $0.id == request.id }
            shared[request.workoutId] = post.id
            save()
            if let index = feed.firstIndex(where: { $0.id == post.id }) {
                feed[index] = post
            } else if feedLoaded {
                feed.append(post)
                feed.sort { ($0.startedAt, $0.id) > ($1.startedAt, $1.id) }
            }
            return true
        } catch let error as APIError where error == .offline {
            return false
        } catch {
            pending.removeAll { $0.id == request.id }
            save()
            return true
        }
    }

    // MARK: Feed

    /// Loads the first page of your feed, replacing what was there.
    func refreshFeed() async throws {
        await sendPending()
        let page = try await api.feed(cursor: nil, token: try requireToken())
        feed = page.posts
        feedCursor = page.nextCursor
        feedLoaded = true
    }

    /// Loads the next page, if there is one.
    func loadMoreFeed() async throws {
        guard let cursor = feedCursor else { return }
        let page = try await api.feed(cursor: cursor, token: try requireToken())
        guard feedCursor == cursor else { return }
        let known = Swift.Set(feed.map(\.id))
        feed += page.posts.filter { !known.contains($0.id) }
        feedCursor = page.nextCursor
    }

    func person(handle: String) async throws -> Person? {
        try await api.person(handle: handle, token: try requireToken())
    }

    func posts(by userId: String, cursor: String? = nil) async throws -> PostPage {
        try await api.posts(by: userId, cursor: cursor, token: try requireToken())
    }

    /// Deletes one of your posts, such as from its page.
    func delete(_ post: Post) async throws {
        try await api.deletePost(post.id, token: try requireToken())
        feed.removeAll { $0.id == post.id }
        if let workoutID = post.workoutId { shared[workoutID] = nil }
        save()
    }

    // MARK: Saved on the phone

    /// Pending shares and the post for each workout are kept per account, so a second account on this
    /// phone never sends the first one's shares.
    private var savedUserID: String?

    private func restoreSaved(for userID: String) {
        savedUserID = userID
        if let data = defaults.data(forKey: "social.pending.\(userID)") {
            pending = (try? JSONDecoder.api.decode([ShareRequest].self, from: data)) ?? []
        } else {
            pending = []
        }
        shared = defaults.dictionary(forKey: "social.shared.\(userID)") as? [String: String] ?? [:]
    }

    private func save() {
        guard let savedUserID else { return }
        defaults.set(try? JSONEncoder.api.encode(pending), forKey: "social.pending.\(savedUserID)")
        defaults.set(shared, forKey: "social.shared.\(savedUserID)")
    }

    private func upsert(_ row: FriendRow) {
        if let index = friends.firstIndex(where: { $0.userId == row.userId }) {
            friends[index] = row
        } else {
            friends.append(row)
        }
        friends.sort { ($0.relation.order, $0.handle) < ($1.relation.order, $1.handle) }
    }

    private func requireToken() throws -> String {
        guard let token = token() else { throw APIError(message: "Sign in again to do that.") }
        return token
    }
}

private extension Relation {
    /// Friends first, then requests to you, then requests you sent, the same as the API.
    var order: Int {
        switch self {
        case .friends: 0
        case .incoming: 1
        case .outgoing: 2
        case .me, .none: 3
        }
    }
}
