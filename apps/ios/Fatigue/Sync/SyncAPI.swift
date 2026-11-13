import Foundation

/// What the server did with one pushed item. See `PushResult` in `apps/api/src/modules/sync/sync.service.ts`.
nonisolated struct PushResult: Decodable, Equatable, Sendable {
    enum Status: String, Decodable, Sendable {
        /// The server took it.
        case saved
        /// The server already has this edit or a later one. Its copy comes with the next pull.
        case older
        /// A newer build wrote the item last, and this build could lose what it doesn't know about.
        case tooOld = "too_old"
        /// The item is malformed. `message` says where.
        case invalid
    }

    var kind: String?
    var id: String?
    var status: Status
    var message: String?
}

/// One page of a pull: the items changed since the cursor, the cursor to send next, and whether to ask again.
nonisolated struct PullPage: Decodable, Equatable, Sendable {
    var items: [SyncItem]
    var cursor: Int64
    var more: Bool
}

nonisolated enum SyncAPIError: Error, Equatable {
    /// No connection, or the server couldn't be reached.
    case offline
    /// The session has ended. The app has to sign in again before it can sync.
    case signedOut
    /// The server answered with an error, such as 500.
    case server(Int)
}

/// The two sync calls. A protocol so tests can stand in for the server.
nonisolated protocol SyncAPI: Sendable {
    /// Sends up to 100 items and gets one result per item, in the same order.
    func push(schema: Int, items: [SyncItem], token: String) async throws -> [PushResult]
    func pull(cursor: Int64, token: String) async throws -> PullPage
}

/// Talks to `/api/sync` on the Fatigue API.
nonisolated struct LiveSyncAPI: SyncAPI {
    var baseURL: URL = APIConfig.baseURL
    var session: URLSession = .bearerOnly

    func push(schema: Int, items: [SyncItem], token: String) async throws -> [PushResult] {
        struct Body: Encodable {
            let schema: Int
            let items: [SyncItem]
        }
        struct Reply: Decodable { let results: [PushResult] }
        var request = URLRequest(url: baseURL.appending(path: "api/sync/push"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Body(schema: schema, items: items))
        return try JSONDecoder().decode(Reply.self, from: try await send(request, token: token)).results
    }

    func pull(cursor: Int64, token: String) async throws -> PullPage {
        let url = baseURL.appending(path: "api/sync/pull").appending(queryItems: [URLQueryItem(name: "cursor", value: String(cursor))])
        return try JSONDecoder().decode(PullPage.self, from: try await send(URLRequest(url: url), token: token))
    }

    private func send(_ request: URLRequest, token: String) async throws -> Data {
        var request = request
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SyncAPIError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw SyncAPIError.offline }
        if http.statusCode == 401 { throw SyncAPIError.signedOut }
        guard (200..<300).contains(http.statusCode) else { throw SyncAPIError.server(http.statusCode) }
        return data
    }
}
