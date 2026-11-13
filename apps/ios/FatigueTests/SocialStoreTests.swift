import Foundation
import Testing
@testable import Fatigue

/// Stands in for the server, keeping friendships in memory the way the API does.
private final class FakeSocialAPI: SocialAPI, @unchecked Sendable {
    var profile: MyProfile?
    var rows: [FriendRow] = []
    var people: [Person] = []
    var failure: APIError?
    var removed: [String] = []

    func myProfile(token: String) async throws -> MyProfile? {
        if let failure { throw failure }
        return profile
    }

    func saveProfile(_ changes: ProfileChanges, token: String) async throws -> MyProfile {
        if let failure { throw failure }
        var saved = profile ?? MyProfile(userId: "anton", handle: "", name: "Anton", bio: nil, defaultVisibility: .everyone)
        if let handle = changes.handle { saved.handle = handle }
        if let bio = changes.bio { saved.bio = bio.isEmpty ? nil : bio }
        if let visibility = changes.defaultVisibility { saved.defaultVisibility = visibility }
        profile = saved
        return saved
    }

    func search(_ query: String, token: String) async throws -> [Person] { people.filter { $0.handle.hasPrefix(query) } }
    func friends(token: String) async throws -> [FriendRow] { rows }

    func addFriend(_ userId: String, token: String) async throws -> Relation {
        if let failure { throw failure }
        return rows.first { $0.userId == userId }?.relation == .incoming ? .friends : .outgoing
    }

    func acceptFriend(_ userId: String, token: String) async throws -> Relation {
        if let failure { throw failure }
        return .friends
    }

    func removeFriend(_ userId: String, token: String) async throws {
        if let failure { throw failure }
        removed.append(userId)
    }
}

@MainActor
struct SocialStoreTests {
    let jos = FriendRow(userId: "jos", handle: "jos", name: "Jos", relation: .incoming, since: .now)
    let bea = FriendRow(userId: "bea", handle: "bea", name: "Bea", relation: .friends, since: .now)
    let mine = MyProfile(userId: "anton", handle: "anton", name: "Anton", bio: nil, defaultVisibility: .everyone)

    private func store(_ api: FakeSocialAPI, token: String? = "token") -> SocialStore {
        SocialStore(api: api, token: { token })
    }

    @Test func noProfileYetAsksForAHandle() async {
        let social = store(FakeSocialAPI())
        await social.load()
        #expect(social.profile == .needsHandle)
    }

    @Test func loadsTheProfileAndSplitsFriendsFromRequests() async {
        let api = FakeSocialAPI()
        api.profile = mine
        api.rows = [bea, jos]
        let social = store(api)
        await social.load()
        #expect(social.profile == .ready(mine))
        #expect(social.accepted.map(\.handle) == ["bea"])
        #expect(social.incoming.map(\.handle) == ["jos"])
    }

    @Test func offlineLeavesTheSocialPartsOut() async {
        let api = FakeSocialAPI()
        api.failure = .offline
        let social = store(api)
        await social.load()
        #expect(social.profile == .unavailable)
    }

    @Test func signedOutLoadsNothing() async {
        let api = FakeSocialAPI()
        api.profile = mine
        let social = store(api, token: nil)
        await social.load()
        #expect(social.profile == .unknown)
    }

    @Test func savingAHandleMakesTheProfileReady() async throws {
        let social = store(FakeSocialAPI())
        await social.load()
        try await social.save(ProfileChanges(handle: "anton"))
        #expect(social.myProfile?.handle == "anton")
    }

    @Test func aTakenHandleThrowsTheServersMessageAndKeepsAskingForOne() async {
        let api = FakeSocialAPI()
        let social = store(api)
        await social.load()
        api.failure = APIError(message: "@anton is taken.")
        await #expect(throws: APIError(message: "@anton is taken.")) { try await social.save(ProfileChanges(handle: "anton")) }
        #expect(social.profile == .needsHandle)
    }

    @Test func acceptingMovesTheRequestToFriendsStraightAway() async throws {
        let api = FakeSocialAPI()
        api.profile = mine
        api.rows = [jos]
        let social = store(api)
        await social.load()
        try await social.accept(jos)
        #expect(social.incoming.isEmpty)
        #expect(social.accepted.map(\.handle) == ["jos"])
    }

    @Test func aFailedRemoveBringsTheRowBack() async {
        let api = FakeSocialAPI()
        api.profile = mine
        api.rows = [bea]
        let social = store(api)
        await social.load()
        api.failure = .offline
        await #expect(throws: APIError.offline) { try await social.remove(bea) }
        #expect(social.accepted.map(\.handle) == ["bea"])
    }

    @Test func addingSomeoneWhoAskedYouMakesYouFriends() async throws {
        let api = FakeSocialAPI()
        api.profile = mine
        api.rows = [jos]
        let social = store(api)
        await social.load()
        let relation = try await social.add(Person(userId: "jos", handle: "jos", name: "Jos", relation: .incoming))
        #expect(relation == .friends)
        #expect(social.friends.map(\.relation) == [.friends])
    }

    @Test func addingSomeoneNewShowsAsSent() async throws {
        let api = FakeSocialAPI()
        api.profile = mine
        let social = store(api)
        await social.load()
        try await social.add(Person(userId: "cal", handle: "cal", name: "Cal", relation: .none))
        #expect(social.outgoing.map(\.handle) == ["cal"])
    }

    @Test func readsTheAPIsJSON() throws {
        let json = Data("""
        [{"userId":"jos","handle":"jos","name":"Jos","relation":"incoming","since":"2026-11-13T05:16:01.123Z"}]
        """.utf8)
        let rows = try JSONDecoder.api.decode([FriendRow].self, from: json)
        #expect(rows.first?.relation == .incoming)

        let profile = try JSONDecoder.api.decode(MyProfile.self, from: Data("""
        {"userId":"anton","handle":"anton","name":"Anton","bio":null,"defaultVisibility":"public","relation":"self"}
        """.utf8))
        #expect(profile.defaultVisibility == .everyone)
    }

    @Test func sendsOnlyTheChangedFields() throws {
        let json = try JSONEncoder().encode(ProfileChanges(defaultVisibility: .onlyMe))
        #expect(String(decoding: json, as: UTF8.self) == #"{"defaultVisibility":"private"}"#)
    }
}
