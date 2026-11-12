import Foundation
import Testing
@testable import Fatigue

/// Stands in for the server. Each call does whatever the test set up.
private final class FakeAuthAPI: AuthAPI, @unchecked Sendable {
    var accountForToken: Result<Account?, APIError> = .success(nil)
    var signInResult: Result<(Account, String), APIError> = .failure(APIError(message: "Invalid email or password"))

    func signIn(email: String, password: String) async throws -> (Account, token: String) { try signInResult.get() }
    func signUp(name: String, email: String, password: String) async throws -> (Account, token: String) { try signInResult.get() }
    func account(token: String) async throws -> Account? { try accountForToken.get() }
    func signOut(token: String) async throws {}
    func rename(to name: String, token: String) async throws {}
    func deleteAccount(password: String, token: String) async throws {}
}

@MainActor
struct AuthStoreTests {
    let lifter = Account(id: "1", name: "Anton", email: "lifter@example.com", createdAt: Date(timeIntervalSince1970: 0))

    private func makeStore(_ api: FakeAuthAPI) -> (AuthStore, TokenStore) {
        let tokens = TokenStore(service: "fatigue-tests-\(UUID())")
        let defaults = UserDefaults(suiteName: "fatigue-tests-\(UUID())")!
        return (AuthStore(api: api, tokens: tokens, defaults: defaults), tokens)
    }

    @Test func noSavedSessionMeansSignedOut() async {
        let (store, _) = makeStore(FakeAuthAPI())
        await store.restore()
        #expect(store.state == .signedOut)
    }

    @Test func signingInKeepsTheToken() async throws {
        let api = FakeAuthAPI()
        api.signInResult = .success((lifter, "token"))
        let (store, tokens) = makeStore(api)
        try await store.signIn(email: " lifter@example.com ", password: "password123")
        #expect(store.state == .signedIn(lifter))
        #expect(tokens.read() == "token")
        tokens.delete()
    }

    @Test func aWrongPasswordShowsTheServersMessage() async {
        let (store, _) = makeStore(FakeAuthAPI())
        await #expect(throws: APIError(message: "Invalid email or password")) {
            try await store.signIn(email: "lifter@example.com", password: "nope")
        }
        #expect(store.state == .loading)
    }

    @Test func stayingSignedInWhileOffline() async throws {
        let api = FakeAuthAPI()
        api.signInResult = .success((lifter, "token"))
        let (store, tokens) = makeStore(api)
        try await store.signIn(email: "lifter@example.com", password: "password123")
        api.accountForToken = .failure(.offline)
        await store.restore()
        #expect(store.state == .signedIn(lifter))
        tokens.delete()
    }

    @Test func anEndedSessionSignsOut() async throws {
        let api = FakeAuthAPI()
        api.signInResult = .success((lifter, "token"))
        let (store, tokens) = makeStore(api)
        try await store.signIn(email: "lifter@example.com", password: "password123")
        api.accountForToken = .success(nil)
        await store.restore()
        #expect(store.state == .signedOut)
        #expect(tokens.read() == nil)
    }

    @Test func readsTheAPIsDates() throws {
        let json = #"{"id":"1","name":"A","email":"a@example.com","createdAt":"2026-11-12T11:45:34.687Z"}"#
        let account = try JSONDecoder.api.decode(Account.self, from: Data(json.utf8))
        #expect(account.createdAt.timeIntervalSince1970.rounded() == 1_794_483_935)
    }
}
