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

    var shares: [ShareRequest] = []
    var shareFailure: Error?
    var deletedPosts: [String] = []
    var feedPages: [String?: PostPage] = [:]

    func person(handle: String, token: String) async throws -> Person? { people.first { $0.handle == handle } }

    func share(_ request: ShareRequest, token: String) async throws -> Post {
        if let shareFailure { throw shareFailure }
        shares.append(request)
        return post(for: request.id, request)
    }

    private func post(for id: String, _ request: ShareRequest? = nil) -> Post {
        let request = request ?? shares.last { $0.id == id }!
        return Post(id: id, author: .init(userId: "anton", handle: "anton", name: "Anton"), workoutId: request.workoutId,
                    caption: request.caption, visibility: request.visibility, startedAt: request.startedAt, createdAt: .now, snapshot: request.snapshot,
                    media: ready[id] ?? [])
    }

    /// What happens to media, in order, such as "prepare m1", "upload m1", "complete m1".
    var mediaCalls: [String] = []
    /// Finished media per post, as the API would return it.
    var ready: [String: [PostMedia]] = [:]
    /// Makes uploads fail as if the connection dropped.
    var uploadsOffline = false
    var photoID: String?

    func post(_ id: String, token: String) async throws -> Post? { shares.contains { $0.id == id } ? post(for: id) : nil }

    func prepareMedia(_ details: MediaDetails, id: String, postId: String, token: String) async throws -> PreparedUpload {
        mediaCalls.append("prepare \(id)")
        return PreparedUpload(id: id, status: "pending", upload: UploadLink(url: URL(string: "https://storage.test/\(id)")!, method: "PUT", headers: [:]))
    }

    func upload(_ file: URL, to link: UploadLink) async throws {
        if uploadsOffline { throw APIError.offline }
        mediaCalls.append("upload \(link.url.lastPathComponent)")
    }

    func completeMedia(_ id: String, postId: String, token: String) async throws {
        mediaCalls.append("complete \(id)")
        ready[postId, default: []].append(PostMedia(id: id, kind: .photo, width: 10, height: 10, durationSeconds: nil, position: ready[postId]?.count ?? 0,
                                                    url: URL(string: "https://storage.test/\(id)")!, expiresAt: .now.addingTimeInterval(3600)))
    }

    func removeMedia(_ id: String, postId: String, token: String) async throws {
        mediaCalls.append("remove \(id)")
        ready[postId]?.removeAll { $0.id == id }
    }

    func preparePhoto(id: String, byteSize: Int, token: String) async throws -> UploadLink {
        UploadLink(url: URL(string: "https://storage.test/profile/\(id)")!, method: "PUT", headers: [:])
    }

    func setPhoto(id: String, byteSize: Int, token: String) async throws -> MyProfile {
        photoID = id
        var saved = profile!
        saved.photoUrl = URL(string: "https://storage.test/profile/\(id)")
        profile = saved
        return saved
    }

    func clearPhoto(token: String) async throws { photoID = nil }

    func deletePost(_ id: String, token: String) async throws {
        if let failure { throw failure }
        deletedPosts.append(id)
    }

    func feed(cursor: String?, token: String) async throws -> PostPage { feedPages[cursor] ?? PostPage(posts: [], nextCursor: nil) }
    func posts(by userId: String, cursor: String?, token: String) async throws -> PostPage { PostPage(posts: [], nextCursor: nil) }
}

@MainActor
struct SocialStoreTests {
    let jos = FriendRow(userId: "jos", handle: "jos", name: "Jos", relation: .incoming, since: .now)
    let bea = FriendRow(userId: "bea", handle: "bea", name: "Bea", relation: .friends, since: .now)
    let mine = MyProfile(userId: "anton", handle: "anton", name: "Anton", bio: nil, defaultVisibility: .everyone)

    private func store(_ api: FakeSocialAPI, token: String? = "token", defaults: UserDefaults = UserDefaults(suiteName: "fatigue-tests-\(UUID())")!) -> SocialStore {
        SocialStore(api: api, token: { token }, defaults: defaults, mediaFolder: FileManager.default.temporaryDirectory, export: Self.fakeExport,
                    localPhoto: { nil })
    }

    /// Stands in for shrinking: a tiny file in the scratch folder.
    private static let fakeExport: @Sendable (URL, WorkoutMedia.Kind, String, Int) async throws -> ExportedMedia = { _, kind, id, position in
        let url = FileManager.default.temporaryDirectory.appending(path: "export-\(id)")
        try Data([1, 2, 3]).write(to: url)
        return ExportedMedia(url: url, details: MediaDetails(kind: kind, contentType: "image/jpeg", byteSize: 3, position: position))
    }

    private func photo(_ id: String) -> WorkoutMedia {
        WorkoutMedia(id: UUID(uuidString: id)!, workoutID: legDay.id, kind: .photo, fileName: "\(id).jpg", createdAt: .now)
    }

    private let one = "00000000-0000-0000-0000-000000000001"
    private let two = "00000000-0000-0000-0000-000000000002"

    private func sharing(_ api: FakeSocialAPI = FakeSocialAPI(), defaults: UserDefaults = UserDefaults(suiteName: "fatigue-tests-\(UUID())")!) async -> (SocialStore, FakeSocialAPI) {
        api.profile = mine
        let social = store(api, defaults: defaults)
        await social.load()
        return (social, api)
    }

    private var legDay: FinishedWorkout {
        FinishedWorkout(title: "Leg day", description: "Knee felt fine", startedAt: Date(timeIntervalSince1970: 1_700_000_000), duration: 3120,
                        gym: Gym(name: "City Gym", latitude: 51.5, longitude: -0.12), exercises: [
            WorkoutExercise(name: "Adductors", brand: Brand(name: "Technogym"), restSeconds: 90, notes: [ExerciseNote(text: "Seat 4")], sets: [
                WorkoutSet(setup: SetSetup(kind: .reps), type: .warmup, weight: "20", amount: "12", isDone: true),
                WorkoutSet(setup: SetSetup(kind: .reps), weight: "60", amount: "8", rpe: 8, isDone: true),
            ]),
        ])
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

    // MARK: Sharing

    @Test func aSnapshotKeepsTheSetsNotesAndGym() {
        let snapshot = PostSnapshot(legDay, records: [ExerciseStats.Beaten(exercise: "Adductors", brand: Brand(name: "Technogym"), record: "Heaviest weight", value: "60 kg")])
        #expect(snapshot.title == "Leg day")
        #expect(snapshot.durationSeconds == 3120)
        #expect(snapshot.gym?.name == "City Gym")
        #expect(snapshot.volumeKg == 480)
        let exercise = snapshot.exercises[0]
        #expect(exercise.brand == "Technogym")
        #expect(exercise.notes == ["Seat 4"])
        let sets = exercise.groups.flatMap(\.sets)
        #expect(sets.map(\.mark) == ["W", "1"])
        #expect(sets[1].text(in: .kg) == "60 × 8")
        #expect(snapshot.records.first?.value == "60 kg")
    }

    @Test func sharingSendsTheWorkoutAndRemembersItsPost() async {
        let (social, api) = await sharing()
        let workout = legDay
        let sent = await social.share(workout, records: [], visibility: .friends, caption: "  New notch ")
        #expect(sent)
        #expect(api.shares.first?.caption == "New notch")
        #expect(api.shares.first?.visibility == .friends)
        #expect(social.isShared(workout.id))
        #expect(social.pending.isEmpty)
    }

    @Test func sharingAgainReusesThePostID() async {
        let (social, api) = await sharing()
        let workout = legDay
        await social.share(workout, records: [], visibility: .everyone)
        await social.share(workout, records: [], visibility: .everyone)
        #expect(api.shares.count == 2)
        #expect(api.shares[0].id == api.shares[1].id)
    }

    @Test func offlineSharesWaitAndGoOutLaterUnderTheSameID() async {
        let defaults = UserDefaults(suiteName: "fatigue-tests-\(UUID())")!
        let (social, api) = await sharing(defaults: defaults)
        api.shareFailure = APIError.offline
        let sent = await social.share(legDay, records: [], visibility: .everyone)
        #expect(!sent)
        #expect(social.pending.count == 1)
        let queuedID = social.pending[0].id

        // A relaunch picks the waiting share back up from the phone.
        api.shareFailure = nil
        let relaunched = store(api, defaults: defaults)
        await relaunched.load()
        #expect(relaunched.pending.isEmpty)
        #expect(api.shares.map(\.id) == [queuedID])
    }

    @Test func aShareTheAPIRefusesIsDropped() async {
        let (social, api) = await sharing()
        api.shareFailure = LiveSocialAPI.HTTPFailure(status: 410, message: "That post was deleted.")
        let workout = legDay
        await social.share(workout, records: [], visibility: .everyone)
        #expect(social.pending.isEmpty)
        #expect(!social.isShared(workout.id))
    }

    @Test func anotherAccountDoesntSendTheFirstOnesShares() async {
        let defaults = UserDefaults(suiteName: "fatigue-tests-\(UUID())")!
        let (social, api) = await sharing(defaults: defaults)
        api.shareFailure = APIError.offline
        await social.share(legDay, records: [], visibility: .everyone)

        let other = FakeSocialAPI()
        other.profile = MyProfile(userId: "jos", handle: "jos", name: "Jos", bio: nil, defaultVisibility: .everyone)
        let second = store(other, defaults: defaults)
        await second.load()
        #expect(second.pending.isEmpty)
        #expect(other.shares.isEmpty)
    }

    @Test func unsharingDeletesThePost() async throws {
        let (social, api) = await sharing()
        let workout = legDay
        await social.share(workout, records: [], visibility: .everyone)
        let postID = api.shares[0].id
        try await social.unshare(workout.id)
        #expect(api.deletedPosts == [postID])
        #expect(!social.isShared(workout.id))
    }

    @Test func theFeedPagesWithoutRepeatingPosts() async throws {
        let (social, api) = await sharing()
        func post(_ id: String, _ seconds: Double) -> Post {
            Post(id: id, author: .init(userId: "jos", handle: "jos", name: "Jos"), workoutId: nil, caption: nil, visibility: .everyone,
                 startedAt: Date(timeIntervalSince1970: seconds), createdAt: .now, snapshot: nil)
        }
        api.feedPages[nil] = PostPage(posts: [post("b", 2), post("a", 1)], nextCursor: "next")
        api.feedPages["next"] = PostPage(posts: [post("a", 1), post("z", 0)], nextCursor: nil)
        try await social.refreshFeed()
        try await social.loadMoreFeed()
        #expect(social.feed.map(\.id) == ["b", "a", "z"])
        #expect(social.feedCursor == nil)
    }

    @Test func aPostFromANewerAppStillLoadsWithoutItsWorkout() throws {
        let json = Data("""
        {"id":"p1","author":{"userId":"jos","handle":"jos","name":"Jos"},"workoutId":null,"caption":"Hi","visibility":"friends",
         "startedAt":"2026-11-10T18:00:00.000Z","createdAt":"2026-11-10T19:00:00.000Z","snapshotVersion":99,"snapshot":{"something":"new"}}
        """.utf8)
        let post = try JSONDecoder.api.decode(Post.self, from: json)
        #expect(post.snapshot == nil)
        #expect(post.caption == "Hi")
    }

    @Test func aShareRoundTripsThroughTheAPIsJSON() throws {
        let request = ShareRequest(id: "p1", workoutId: "w1", caption: nil, visibility: .everyone, startedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                   snapshot: PostSnapshot(legDay, records: []))
        let json = String(decoding: try JSONEncoder.api.encode(request), as: UTF8.self)
        #expect(json.contains(#""startedAt":"2023-11-14T22:13:20.000Z""#))
        #expect(json.contains(#""visibility":"public""#))
        let back = try JSONDecoder.api.decode(ShareRequest.self, from: Data(json.utf8))
        #expect(back == request)
    }

    // MARK: Photos and videos

    @Test func sharingWithMediaUploadsEachFileAfterThePost() async {
        let (social, api) = await sharing()
        let workout = legDay
        await social.share(workout, records: [], visibility: .friends, media: [photo(one), photo(two)])
        #expect(api.mediaCalls == ["prepare \(one)", "upload \(one)", "complete \(one)", "prepare \(two)", "upload \(two)", "complete \(two)"])
        #expect(social.uploads.isEmpty)
    }

    @Test func anUploadCutOffByTheConnectionFinishesLater() async {
        let defaults = UserDefaults(suiteName: "fatigue-tests-\(UUID())")!
        let (social, api) = await sharing(defaults: defaults)
        api.uploadsOffline = true
        await social.share(legDay, records: [], visibility: .friends, media: [photo(one)])
        #expect(social.uploads.map(\.media.id) == [one])

        // Kept on the phone, so a fresh launch picks it up.
        let relaunched = store(api, defaults: defaults)
        await relaunched.load()
        api.uploadsOffline = false
        await relaunched.sendPending()
        #expect(api.mediaCalls.suffix(3) == ["prepare \(one)", "upload \(one)", "complete \(one)"])
        #expect(relaunched.uploads.isEmpty)
    }

    @Test func sharingAgainWithoutAPhotoTakesItOffThePost() async {
        let (social, api) = await sharing()
        await social.share(legDay, records: [], visibility: .friends, media: [photo(one), photo(two)])
        await social.share(legDay, records: [], visibility: .friends, media: [photo(two)])
        #expect(api.mediaCalls.last == "remove \(one)")
        #expect(api.ready.values.flatMap { $0 }.map(\.id) == [two])
    }

    @Test func sharingAgainDoesntUploadWhatsAlreadyThere() async {
        let (social, api) = await sharing()
        await social.share(legDay, records: [], visibility: .friends, media: [photo(one)])
        let before = api.mediaCalls.count
        await social.share(legDay, records: [], visibility: .friends, media: [photo(one)])
        #expect(api.mediaCalls.count == before)
    }

    @Test func aNewProfilePhotoBecomesYours() async throws {
        let (social, api) = await sharing()
        try await social.setProfilePhoto(Data([0xFF, 0xD8, 0xFF]))
        #expect(api.photoID != nil)
        #expect(social.myProfile?.photoUrl != nil)
    }

    @Test func aPostsMediaDecodesFromTheAPI() throws {
        let json = """
        {"id":"p1","author":{"userId":"a","handle":"a","name":"A","photoUrl":"https://x.test/p.jpg"},"workoutId":null,"caption":null,
         "visibility":"friends","startedAt":"2026-11-10T18:00:00.000Z","createdAt":"2026-11-10T18:00:00.000Z","snapshotVersion":99,"snapshot":{},
         "media":[{"id":"m1","kind":"video","width":1920,"height":1080,"durationSeconds":12.5,"position":0,"url":"https://x.test/m1.mp4",
                   "expiresAt":"2026-11-10T19:00:00.000Z"}]}
        """
        let post = try JSONDecoder.api.decode(Post.self, from: Data(json.utf8))
        #expect(post.media.first?.kind == .video)
        #expect(post.media.first?.aspectRatio == 1920.0 / 1080.0)
        #expect(post.author.photoUrl?.absoluteString == "https://x.test/p.jpg")
    }
}