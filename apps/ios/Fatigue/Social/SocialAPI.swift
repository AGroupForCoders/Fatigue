import Foundation

/// How someone relates to you, as the API says it.
nonisolated enum Relation: String, Codable, Hashable, Sendable {
    case me = "self"
    case friends, incoming, outgoing, none
}

/// Who sees a shared workout. Your profile picks the default for new ones.
nonisolated enum PostVisibility: String, Codable, CaseIterable, Hashable, Sendable {
    case everyone = "public"
    case friends
    case onlyMe = "private"

    var title: String {
        switch self {
        case .everyone: "Everyone"
        case .friends: "Friends"
        case .onlyMe: "Only me"
        }
    }
}

/// Someone else, as they show in search or at the top of their profile.
nonisolated struct Person: Codable, Hashable, Identifiable, Sendable {
    let userId: String
    let handle: String
    let name: String
    var bio: String?
    var relation: Relation
    var photoUrl: URL? = nil
    var id: String { userId }
}

/// Your own profile, with the settings only you see.
nonisolated struct MyProfile: Codable, Hashable, Sendable {
    let userId: String
    var handle: String
    var name: String
    var bio: String?
    var defaultVisibility: PostVisibility
    var photoUrl: URL? = nil
}

/// A friend, or a request either way, as it shows in the friends list.
nonisolated struct FriendRow: Codable, Hashable, Identifiable, Sendable {
    let userId: String
    let handle: String
    let name: String
    var relation: Relation
    /// When the request was sent, or when it was accepted for a friend.
    let since: Date
    var photoUrl: URL? = nil
    var id: String { userId }
}

/// What the app changes on your profile. Nil fields are left alone; an empty bio clears it.
nonisolated struct ProfileChanges: Encodable, Equatable, Sendable {
    var handle: String?
    var bio: String?
    var defaultVisibility: PostVisibility?
}

/// The profile and friend calls. A protocol so tests can stand in for the server.
protocol SocialAPI: Sendable {
    /// Your profile, or nil before you've picked a handle.
    func myProfile(token: String) async throws -> MyProfile?
    func saveProfile(_ changes: ProfileChanges, token: String) async throws -> MyProfile
    func search(_ query: String, token: String) async throws -> [Person]
    func friends(token: String) async throws -> [FriendRow]
    /// Sends a request, or accepts theirs if they already sent one. Returns where things stand.
    func addFriend(_ userId: String, token: String) async throws -> Relation
    func acceptFriend(_ userId: String, token: String) async throws -> Relation
    /// Declines, takes back a request, or unfriends.
    func removeFriend(_ userId: String, token: String) async throws
    /// Someone's profile by handle, or nil when nobody has it.
    func person(handle: String, token: String) async throws -> Person?
    /// Shares a workout, or shares it again. Returns the post, whose ID may be an earlier share's.
    func share(_ request: ShareRequest, token: String) async throws -> Post
    func deletePost(_ id: String, token: String) async throws
    func feed(cursor: String?, token: String) async throws -> PostPage
    func posts(by userId: String, cursor: String?, token: String) async throws -> PostPage
    /// One post, or nil when it's gone or you can't see it.
    func post(_ id: String, token: String) async throws -> Post?

    // Photos and videos on your posts.
    /// Gets a file ready to upload. The answer has no link when the file is already in.
    func prepareMedia(_ details: MediaDetails, id: String, postId: String, token: String) async throws -> PreparedUpload
    /// Sends the file to the link from `prepareMedia`.
    func upload(_ file: URL, to link: UploadLink) async throws
    /// Says the file is in, so the post shows it.
    func completeMedia(_ id: String, postId: String, token: String) async throws
    func removeMedia(_ id: String, postId: String, token: String) async throws

    // Your profile photo.
    func preparePhoto(id: String, byteSize: Int, token: String) async throws -> UploadLink
    func setPhoto(id: String, byteSize: Int, token: String) async throws -> MyProfile
    func clearPhoto(token: String) async throws
}

/// Talks to the profiles and friends modules on the Fatigue API.
nonisolated struct LiveSocialAPI: SocialAPI {
    var baseURL: URL = APIConfig.baseURL
    var session: URLSession = .bearerOnly

    func myProfile(token: String) async throws -> MyProfile? {
        do {
            return try await send("profiles/me", token: token)
        } catch let error as HTTPFailure where error.status == 404 {
            return nil
        }
    }

    func saveProfile(_ changes: ProfileChanges, token: String) async throws -> MyProfile {
        try await send("profiles/me", method: "PUT", body: changes, token: token)
    }

    func search(_ query: String, token: String) async throws -> [Person] {
        try await send("profiles/search", query: [URLQueryItem(name: "q", value: query)], token: token)
    }

    func friends(token: String) async throws -> [FriendRow] {
        try await send("friends", token: token)
    }

    func addFriend(_ userId: String, token: String) async throws -> Relation {
        struct Body: Decodable { let relation: Relation }
        let body: Body = try await send("friends/\(userId)", method: "POST", token: token)
        return body.relation
    }

    func acceptFriend(_ userId: String, token: String) async throws -> Relation {
        struct Body: Decodable { let relation: Relation }
        let body: Body = try await send("friends/\(userId)/accept", method: "POST", token: token)
        return body.relation
    }

    func removeFriend(_ userId: String, token: String) async throws {
        _ = try await data("friends/\(userId)", method: "DELETE", token: token)
    }

    func person(handle: String, token: String) async throws -> Person? {
        do {
            return try await send("profiles/\(handle)", token: token)
        } catch let error as HTTPFailure where error.status == 404 {
            return nil
        }
    }

    func share(_ request: ShareRequest, token: String) async throws -> Post {
        /// The request without the picked media, which uploads separately.
        struct Body: Encodable {
            let workoutId: String
            let caption: String?
            let visibility: PostVisibility
            let startedAt: Date
            let snapshotVersion: Int
            let snapshot: PostSnapshot
        }
        let body = Body(workoutId: request.workoutId, caption: request.caption, visibility: request.visibility, startedAt: request.startedAt,
                        snapshotVersion: request.snapshotVersion, snapshot: request.snapshot)
        return try await send("posts/\(request.id)", method: "PUT", body: body, token: token)
    }

    func post(_ id: String, token: String) async throws -> Post? {
        do {
            return try await send("posts/\(id)", token: token)
        } catch let error as HTTPFailure where error.status == 404 {
            return nil
        }
    }

    func prepareMedia(_ details: MediaDetails, id: String, postId: String, token: String) async throws -> PreparedUpload {
        try await send("posts/\(postId)/media/\(id)", method: "PUT", body: details, token: token)
    }

    func upload(_ file: URL, to link: UploadLink) async throws {
        var request = URLRequest(url: link.url)
        request.httpMethod = link.method
        for (name, value) in link.headers { request.setValue(value, forHTTPHeaderField: name) }
        let response: URLResponse
        do {
            (_, response) = try await session.upload(for: request, fromFile: file)
        } catch {
            throw APIError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.offline }
        // 412 means the file is already there from an earlier try.
        guard (200..<300).contains(http.statusCode) || http.statusCode == 412 else {
            throw HTTPFailure(status: http.statusCode, message: "The upload was refused (\(http.statusCode)).")
        }
    }

    func completeMedia(_ id: String, postId: String, token: String) async throws {
        _ = try await data("posts/\(postId)/media/\(id)/complete", method: "POST", token: token)
    }

    func removeMedia(_ id: String, postId: String, token: String) async throws {
        _ = try await data("posts/\(postId)/media/\(id)", method: "DELETE", token: token)
    }

    private struct PhotoBody: Encodable {
        let id: String
        let byteSize: Int
    }

    func preparePhoto(id: String, byteSize: Int, token: String) async throws -> UploadLink {
        struct Answer: Decodable { let upload: UploadLink }
        let answer: Answer = try await send("profiles/me/photo/upload", method: "POST", body: PhotoBody(id: id, byteSize: byteSize), token: token)
        return answer.upload
    }

    func setPhoto(id: String, byteSize: Int, token: String) async throws -> MyProfile {
        try await send("profiles/me/photo", method: "PUT", body: PhotoBody(id: id, byteSize: byteSize), token: token)
    }

    func clearPhoto(token: String) async throws {
        _ = try await data("profiles/me/photo", method: "DELETE", token: token)
    }

    func deletePost(_ id: String, token: String) async throws {
        _ = try await data("posts/\(id)", method: "DELETE", token: token)
    }

    func feed(cursor: String?, token: String) async throws -> PostPage {
        try await send("posts/feed", query: cursor.map { [URLQueryItem(name: "cursor", value: $0)] }, token: token)
    }

    func posts(by userId: String, cursor: String?, token: String) async throws -> PostPage {
        try await send("posts/by/\(userId)", query: cursor.map { [URLQueryItem(name: "cursor", value: $0)] }, token: token)
    }

    /// A non-2xx answer. Keeps the status so callers can treat 404 as "nothing there", and shows the server's message.
    struct HTTPFailure: LocalizedError {
        let status: Int
        let message: String
        var errorDescription: String? { message }
    }

    private func send<Response: Decodable>(
        _ path: String, method: String = "GET", query: [URLQueryItem]? = nil, body: (any Encodable)? = nil, token: String
    ) async throws -> Response {
        try JSONDecoder.api.decode(Response.self, from: try await data(path, method: method, query: query, body: body, token: token))
    }

    private func data(_ path: String, method: String, query: [URLQueryItem]? = nil, body: (any Encodable)? = nil, token: String) async throws -> Data {
        var url = baseURL.appending(path: "api/\(path)")
        if let query { url.append(queryItems: query) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder.api.encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.offline }
        guard (200..<300).contains(http.statusCode) else {
            struct Failure: Decodable { let message: String? }
            let message = (try? JSONDecoder().decode(Failure.self, from: data))?.message
            throw HTTPFailure(status: http.statusCode, message: message ?? "Something went wrong (\(http.statusCode)). Try again.")
        }
        return data
    }
}

nonisolated extension JSONEncoder {
    /// Writes dates the way the API reads them, ISO 8601 with milliseconds, such as 2026-11-12T11:45:34.687Z.
    static let api: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
        }
        return encoder
    }()
}
