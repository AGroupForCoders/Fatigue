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
    private let api: any SocialAPI
    private let token: @Sendable () -> String?

    init(api: any SocialAPI = LiveSocialAPI(), token: @escaping @Sendable () -> String? = { TokenStore().read() }) {
        self.api = api
        self.token = token
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
            profile = .ready(mine)
            friends = try await api.friends(token: token)
        } catch {
            if profile == .unknown { profile = .unavailable }
        }
    }

    /// Creates or changes your profile. Throws the server's message, such as a taken handle, to show on the form.
    func save(_ changes: ProfileChanges) async throws {
        let saved = try await api.saveProfile(changes, token: try requireToken())
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
