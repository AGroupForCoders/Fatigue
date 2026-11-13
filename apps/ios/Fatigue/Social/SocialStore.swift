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
    /// Photos and videos still to upload to shared workouts, oldest first.
    private(set) var uploads: [MediaUpload] = []
    private let api: any SocialAPI
    private let token: @Sendable () -> String?
    private let defaults: UserDefaults
    /// Where the workouts' photos and videos are, the same folder `MediaStore` keeps them in.
    private let mediaFolder: URL
    /// Makes the smaller copy that's sent. Tests swap it for one that just copies.
    private let export: @Sendable (URL, WorkoutMedia.Kind, String, Int) async throws -> ExportedMedia
    /// The profile photo saved on this phone, if any.
    private let localPhoto: @Sendable () -> Data?
    @ObservationIgnored private var uploading = false

    init(
        api: any SocialAPI = LiveSocialAPI(),
        token: @escaping @Sendable () -> String? = { TokenStore().read() },
        defaults: UserDefaults = .standard,
        mediaFolder: URL = URL.applicationSupportDirectory.appending(path: "media"),
        export: @escaping @Sendable (URL, WorkoutMedia.Kind, String, Int) async throws -> ExportedMedia = MediaExport.export,
        localPhoto: @escaping @Sendable () -> Data? = ProfilePhoto.data
    ) {
        self.api = api
        self.token = token
        self.defaults = defaults
        self.mediaFolder = mediaFolder
        self.export = export
        self.localPhoto = localPhoto
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
            await uploadLocalPhotoIfNeeded(mine)
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
        uploads = []
        savedUserID = nil
    }

    // MARK: Sharing

    func isShared(_ workoutID: UUID) -> Bool {
        shared[workoutID.uuidString] != nil || pending.contains { $0.workoutId == workoutID.uuidString }
    }

    /// Shares `workout`, or shares it again with a fresh snapshot. Waits for a connection if there isn't one,
    /// and goes out on the next launch or refresh. Returns false when it's waiting.
    @discardableResult
    func share(_ workout: FinishedWorkout, records: [ExerciseStats.Beaten], visibility: PostVisibility, caption: String? = nil,
               media: [WorkoutMedia] = []) async -> Bool {
        guard myProfile != nil else { return false }
        let workoutID = workout.id.uuidString
        let caption = caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = ShareRequest(
            id: shared[workoutID] ?? pending.first { $0.workoutId == workoutID }?.id ?? UUID().uuidString,
            workoutId: workoutID,
            caption: caption?.isEmpty == false ? caption : nil,
            visibility: visibility,
            startedAt: workout.startedAt,
            snapshot: PostSnapshot(workout, records: records),
            media: media.prefix(MediaStore.limit).enumerated().map { ShareMedia($1, position: $0) }
        )
        pending.removeAll { $0.workoutId == workoutID }
        pending.append(request)
        save()
        let sent = await send(request)
        if sent { await sendUploads() }
        return sent
    }

    /// Sends every share still waiting, then any photos and videos still to upload. Stops at the first share
    /// that can't reach the API, since the rest won't either.
    func sendPending() async {
        for request in pending {
            guard await send(request) else { return }
        }
        await sendUploads()
    }

    /// Takes a workout off the feed. A share still waiting is simply dropped.
    func unshare(_ workoutID: UUID) async throws {
        let id = workoutID.uuidString
        pending.removeAll { $0.workoutId == id }
        uploads.removeAll { $0.workoutId == id }
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
            await reconcileMedia(on: post, wanted: request.media, workoutID: request.workoutId, token: token)
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

    // MARK: Photos and videos on posts

    /// Makes the post's media match what was picked: takes off what's no longer wanted and queues what's missing.
    /// Media still uploading from an earlier try isn't in `post.media`, so it's queued again, which is harmless.
    private func reconcileMedia(on post: Post, wanted: [ShareMedia], workoutID: String, token: String) async {
        let wantedIDs = Swift.Set(wanted.map(\.id))
        for media in post.media where !wantedIDs.contains(media.id) {
            try? await api.removeMedia(media.id, postId: post.id, token: token)
        }
        let onPost = Swift.Set(post.media.map(\.id))
        uploads.removeAll { $0.workoutId == workoutID && !wantedIDs.contains($0.media.id) }
        for media in wanted where !onPost.contains(media.id) && !uploads.contains(where: { $0.media.id == media.id }) {
            uploads.append(MediaUpload(workoutId: workoutID, media: media))
        }
    }

    /// Uploads every photo and video still waiting, one at a time. Stops when the connection drops and picks
    /// up again on the next launch or refresh. One the API refuses, or whose file is gone, is dropped.
    func sendUploads() async {
        guard !uploading, let token = token() else { return }
        uploading = true
        defer { uploading = false }
        var changed: Swift.Set<String> = []
        for upload in uploads {
            guard let postID = shared[upload.workoutId] else { continue }
            do {
                try await send(upload, to: postID, token: token)
                drop(upload)
                changed.insert(postID)
            } catch let error as APIError where error == .offline {
                break
            } catch {
                drop(upload)
            }
        }
        for postID in changed {
            guard let fresh = try? await api.post(postID, token: token), let index = feed.firstIndex(where: { $0.id == postID }) else { continue }
            feed[index] = fresh
        }
    }

    private func send(_ upload: MediaUpload, to postID: String, token: String) async throws {
        let source = mediaFolder.appending(path: upload.media.fileName)
        let exported = try await export(source, upload.media.kind, upload.media.id, upload.media.position)
        defer { try? FileManager.default.removeItem(at: exported.url) }
        let prepared = try await api.prepareMedia(exported.details, id: upload.media.id, postId: postID, token: token)
        if let link = prepared.upload {
            try await api.upload(exported.url, to: link)
        }
        try await api.completeMedia(upload.media.id, postId: postID, token: token)
    }

    private func drop(_ upload: MediaUpload) {
        uploads.removeAll { $0.media.id == upload.media.id }
        save()
    }

    // MARK: Profile photo

    /// Uploads a new profile photo, a JPEG, and makes it yours. Throws when it can't, such as offline.
    func setProfilePhoto(_ jpeg: Data) async throws {
        let token = try requireToken()
        let id = UUID().uuidString
        let file = FileManager.default.temporaryDirectory.appending(path: "\(id).jpg")
        try jpeg.write(to: file, options: .atomic)
        defer { try? FileManager.default.removeItem(at: file) }
        let link = try await api.preparePhoto(id: id, byteSize: jpeg.count, token: token)
        try await api.upload(file, to: link)
        profile = .ready(try await api.setPhoto(id: id, byteSize: jpeg.count, token: token))
    }

    func clearProfilePhoto() async throws {
        try await api.clearPhoto(token: try requireToken())
        if case .ready(var mine) = profile {
            mine.photoUrl = nil
            profile = .ready(mine)
        }
    }

    /// Photos picked before they were uploaded only lived on this phone. Sends one up the first time the
    /// profile loads without a photo, so friends see it.
    private func uploadLocalPhotoIfNeeded(_ mine: MyProfile) async {
        guard mine.photoUrl == nil, let data = localPhoto() else { return }
        try? await setProfilePhoto(data)
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
        if let data = defaults.data(forKey: "social.uploads.\(userID)") {
            uploads = (try? JSONDecoder.api.decode([MediaUpload].self, from: data)) ?? []
        } else {
            uploads = []
        }
    }

    private func save() {
        guard let savedUserID else { return }
        defaults.set(try? JSONEncoder.api.encode(pending), forKey: "social.pending.\(savedUserID)")
        defaults.set(shared, forKey: "social.shared.\(savedUserID)")
        defaults.set(try? JSONEncoder.api.encode(uploads), forKey: "social.uploads.\(savedUserID)")
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
