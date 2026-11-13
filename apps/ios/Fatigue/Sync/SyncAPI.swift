import Foundation

/// The version of the synced tables this build speaks. Sent with every sync call; the server turns away
/// builds older than what it knows, so an old app can't write rows the new shape doesn't understand.
nonisolated enum SyncSchema {
    static let version = 1
}

nonisolated struct SyncPushResponse: Sendable, Equatable, Codable {
    var accepted: [SyncAck]
    var rejected: [SyncRejection]
}

nonisolated struct SyncPullResponse: Sendable, Equatable, Codable {
    nonisolated struct Entry: Sendable, Equatable, Codable {
        var table: String
        var seq: Int64
        var row: [String: SyncValue]
    }
    var rows: [Entry]
    var next: Int64
    var hasMore: Bool
}

nonisolated enum SyncError: Error, Equatable, Sendable {
    /// The phone can't reach the server right now.
    case offline
    /// The server knows a newer schema than this build. Nothing syncs until the app is updated.
    case outdated
    /// The session ended; signing in again fixes it.
    case unauthorized
    case server(String)
}

/// The two sync calls. A protocol so tests can stand in for the server.
protocol SyncAPI: Sendable {
    func push(_ changes: [SyncRow], token: String) async throws -> SyncPushResponse
    func pull(since: Int64, limit: Int, token: String) async throws -> SyncPullResponse
}

/// Talks to `/api/sync` on the Fatigue API with the session's bearer token.
nonisolated struct LiveSyncAPI: SyncAPI {
    var baseURL: URL = APIConfig.baseURL
    var session: URLSession = .bearerOnly

    func push(_ changes: [SyncRow], token: String) async throws -> SyncPushResponse {
        struct Body: Encodable { let schemaVersion: Int; let changes: [SyncRow] }
        var request = URLRequest(url: baseURL.appending(path: "api/sync/push"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Body(schemaVersion: SyncSchema.version, changes: changes))
        return try await send(request, token: token)
    }

    func pull(since: Int64, limit: Int, token: String) async throws -> SyncPullResponse {
        var components = URLComponents(url: baseURL.appending(path: "api/sync/pull"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "since", value: String(since)),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "schemaVersion", value: String(SyncSchema.version)),
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        return try await send(request, token: token)
    }

    private func send<Response: Decodable>(_ request: URLRequest, token: String) async throws -> Response {
        var request = request
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SyncError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw SyncError.offline }
        switch http.statusCode {
        case 200..<300:
            do {
                return try JSONDecoder().decode(Response.self, from: data)
            } catch {
                throw SyncError.server("The server's answer couldn't be read.")
            }
        case 401:
            throw SyncError.unauthorized
        case 426:
            throw SyncError.outdated
        default:
            struct Failure: Decodable { let message: String? }
            let message = (try? JSONDecoder().decode(Failure.self, from: data))?.message
            throw SyncError.server(message ?? "Something went wrong (\(http.statusCode)).")
        }
    }
}
