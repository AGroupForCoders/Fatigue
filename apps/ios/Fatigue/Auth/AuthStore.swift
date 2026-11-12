import Foundation
import Observation

/// Whether someone is signed in, and the calls that change it.
///
/// The app is meant to work offline, so a saved session stays signed in when the server can't be
/// reached. Only the server saying the session has ended signs you out.
@Observable
final class AuthStore {
    enum State: Equatable {
        /// Checking a saved session on launch.
        case loading
        case signedOut
        case signedIn(Account)
    }

    private(set) var state: State = .loading
    private let api: any AuthAPI
    private let tokens: TokenStore
    private let defaults: UserDefaults
    private static let cachedAccountKey = "account"

    init(api: any AuthAPI = LiveAuthAPI(), tokens: TokenStore = TokenStore(), defaults: UserDefaults = .standard) {
        self.api = api
        self.tokens = tokens
        self.defaults = defaults
    }

    var account: Account? {
        if case .signedIn(let account) = state { account } else { nil }
    }

    /// Picks up the session saved on this phone, if there is one.
    func restore() async {
        guard let token = tokens.read() else { state = .signedOut; return }
        let cached = cachedAccount
        do {
            if let account = try await api.account(token: token) {
                signedIn(account, token: token)
            } else {
                clear()
            }
        } catch {
            // Offline or the server is down: carry on with the account from last time.
            if let cached { state = .signedIn(cached) } else { clear() }
        }
    }

    func signIn(email: String, password: String) async throws {
        let (account, token) = try await api.signIn(email: email.trimmed, password: password)
        signedIn(account, token: token)
    }

    func signUp(name: String, email: String, password: String) async throws {
        let (account, token) = try await api.signUp(name: name.trimmed, email: email.trimmed, password: password)
        signedIn(account, token: token)
    }

    /// Signs out on this phone straight away. Telling the server is best effort.
    func signOut() async {
        let token = tokens.read()
        clear()
        if let token { try? await api.signOut(token: token) }
    }

    func rename(to name: String) async throws {
        guard var account, let token = tokens.read() else { return }
        let name = name.trimmed
        guard !name.isEmpty, name != account.name else { return }
        try await api.rename(to: name, token: token)
        account.name = name
        signedIn(account, token: token)
    }

    func deleteAccount(password: String) async throws {
        guard let token = tokens.read() else { return }
        try await api.deleteAccount(password: password, token: token)
        clear()
    }

    private func signedIn(_ account: Account, token: String) {
        tokens.save(token)
        cachedAccount = account
        state = .signedIn(account)
    }

    private func clear() {
        tokens.delete()
        cachedAccount = nil
        state = .signedOut
    }

    private var cachedAccount: Account? {
        get { defaults.data(forKey: Self.cachedAccountKey).flatMap { try? JSONDecoder().decode(Account.self, from: $0) } }
        set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.cachedAccountKey) }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
