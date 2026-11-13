import Foundation

/// The account calls the app makes. A protocol so tests can stand in for the server.
protocol AuthAPI: Sendable {
    /// Returns the account and the session token to send with every later request.
    func signIn(email: String, password: String) async throws -> (Account, token: String)
    func signUp(name: String, email: String, password: String) async throws -> (Account, token: String)
    /// The account the token belongs to, or nil if the session has ended.
    func account(token: String) async throws -> Account?
    func signOut(token: String) async throws
    func rename(to name: String, token: String) async throws
    func deleteAccount(password: String, token: String) async throws
}

/// Talks to Better Auth on the Fatigue API.
///
/// The app keeps no cookies. On sign-in the server sends the session token in a `set-auth-token`
/// header, and the app sends it back as `Authorization: Bearer <token>`.
nonisolated struct LiveAuthAPI: AuthAPI {
    var baseURL: URL = APIConfig.baseURL
    var session: URLSession = .bearerOnly

    func signIn(email: String, password: String) async throws -> (Account, token: String) {
        let (data, response) = try await send("sign-in/email", body: ["email": email, "password": password])
        return try accountAndToken(data, response)
    }

    func signUp(name: String, email: String, password: String) async throws -> (Account, token: String) {
        let (data, response) = try await send("sign-up/email", body: ["name": name, "email": email, "password": password])
        return try accountAndToken(data, response)
    }

    func account(token: String) async throws -> Account? {
        let (data, _) = try await send("get-session", method: "GET", token: token)
        struct Session: Decodable { let user: Account }
        return try JSONDecoder.api.decode(Session?.self, from: data)?.user
    }

    func signOut(token: String) async throws {
        _ = try await send("sign-out", body: [:], token: token)
    }

    func rename(to name: String, token: String) async throws {
        _ = try await send("update-user", body: ["name": name], token: token)
    }

    func deleteAccount(password: String, token: String) async throws {
        _ = try await send("delete-user", body: ["password": password], token: token)
    }

    private func accountAndToken(_ data: Data, _ response: HTTPURLResponse) throws -> (Account, token: String) {
        struct Body: Decodable { let user: Account }
        guard let token = response.value(forHTTPHeaderField: "set-auth-token") else {
            throw APIError(message: "Signed in, but the server sent no session. Try again.")
        }
        return (try JSONDecoder.api.decode(Body.self, from: data).user, token)
    }

    private func send(_ path: String, method: String = "POST", body: [String: String]? = nil, token: String? = nil) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: baseURL.appending(path: "api/auth/\(path)"))
        request.httpMethod = method
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

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
            throw APIError(message: message ?? "Something went wrong (\(http.statusCode)). Try again.")
        }
        return (data, http)
    }
}

/// Where the API lives.
///
/// Debug builds talk to the API running on this Mac; release builds (TestFlight, App Store) talk to
/// the deployed Worker. Change `productionBaseURL` when the API moves, for example to a custom domain.
nonisolated enum APIConfig {
    /// The API running on this Mac with `pnpm api:dev`. The simulator reaches it as localhost.
    static let localBaseURL = URL(string: "http://localhost:8787")!

    /// The Worker deployed by `.github/workflows/deploy-api.yml`. The `workers.dev` subdomain is the
    /// Cloudflare account's; it appears in the deploy log and in the dashboard under Workers & Pages.
    /// Must match `BETTER_AUTH_URL` on the Worker, or Better Auth rejects sign-in.
    static let productionBaseURL = URL(string: "https://fatigue-api.CHANGE-ME.workers.dev")!

    #if DEBUG
    static let baseURL = localBaseURL
    #else
    static let baseURL = productionBaseURL
    #endif
}

nonisolated extension URLSession {
    /// A session that never stores or sends cookies.
    ///
    /// Better Auth sets a session cookie on sign-in as well as the bearer token. If the app kept that
    /// cookie, later requests would carry it with no Origin header, and Better Auth rejects those with
    /// 403 to stop cross-site requests. The app only ever uses the bearer token, so it ignores cookies.
    static let bearerOnly: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        return URLSession(configuration: configuration)
    }()
}
