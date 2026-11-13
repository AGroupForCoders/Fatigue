import Foundation

/// What the server did with one pushed item, in the same order as the push.
nonisolated struct PushResult: Decodable, Equatable, Sendable {
    enum Status: String, Decodable, Sendable {
        /// Saved.
        case saved
        /// The server already had this edit or a later one. Counts as pushed.
        case older
        /// Last written by a newer build. Waits until the app is updated.
        case tooOld = "too_old"
        /// Refused. Not offered again until it changes.
        case invalid
    }

    let kind: String?
    let id: String?
    let status: Status
    var message: String?
}

/// One page of items changed since a cursor, oldest change first.
nonisolated struct PullPage: Decodable, Sendable {
    let items: [SyncItem]
    /// What to send as the cursor next time.
    let cursor: Int64
    /// Whether to ask again straight away.
    let more: Bool
}

/// Why a sync stopped.
nonisolated enum SyncFailure: Error, Equatable, Sendable {
    /// No connection. The connection coming back starts a sync.
    case offline
    /// The session expired or was revoked. Nothing more happens until you sign in again.
    case unauthorized
    /// A server error or timeout. Tried again on a schedule.
    case server(String)
}

/// The two sync calls. A protocol so tests can stand in for the server, or point at a real one.
protocol SyncAPI: Sendable {
    /// Pushes up to `SyncEngine.pageSize` items. Answers one result per item, in order.
    func push(_ items: [SyncItem], schema: Int, token: String) async throws(SyncFailure) -> [PushResult]
    func pull(after cursor: Int64, token: String) async throws(SyncFailure) -> PullPage
}

/// Talks to `/api/sync` on the Fatigue API.
nonisolated struct LiveSyncAPI: SyncAPI {
    var baseURL: URL = APIConfig.baseURL
    var session: URLSession = .bearerOnly

    func push(_ items: [SyncItem], schema: Int, token: String) async throws(SyncFailure) -> [PushResult] {
        struct Body: Encodable {
            let schema: Int
            let items: [SyncItem]
        }
        struct Answer: Decodable { let results: [PushResult] }
        let body: Data
        do { body = try JSONEncoder().encode(Body(schema: schema, items: items)) } catch { throw .server("Couldn't write the push.") }
        let answer: Answer = try await send("api/sync/push", method: "POST", body: body, token: token)
        return answer.results
    }

    func pull(after cursor: Int64, token: String) async throws(SyncFailure) -> PullPage {
        var url = baseURL.appending(path: "api/sync/pull")
        url.append(queryItems: [URLQueryItem(name: "cursor", value: String(cursor))])
        return try await send(url, method: "GET", body: nil, token: token)
    }

    private func send<Answer: Decodable>(_ path: String, method: String, body: Data?, token: String) async throws(SyncFailure) -> Answer {
        try await send(baseURL.appending(path: path), method: method, body: body, token: token)
    }

    private func send<Answer: Decodable>(_ url: URL, method: String, body: Data?, token: String) async throws(SyncFailure) -> Answer {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where Self.offlineCodes.contains(error.code) {
            throw .offline
        } catch {
            throw .server(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw .server("No answer.") }
        if http.statusCode == 401 { throw .unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw .server("The server answered \(http.statusCode).") }
        do {
            return try JSONDecoder().decode(Answer.self, from: data)
        } catch {
            throw .server("Couldn't read the server's answer.")
        }
    }

    /// Errors that mean there's no connection at all, rather than a server that didn't answer.
    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff, .callIsActive,
    ]
}
