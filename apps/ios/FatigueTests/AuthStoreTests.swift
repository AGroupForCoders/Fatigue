import Foundation
import Testing
@testable import Fatigue

/// Stands in for the server. Each call does whatever the test set up.
private final class FakeAuthAPI: AuthAPI, @unchecked Sendable {
    var accountForToken: Result<Account?, APIError> = .success(nil)
    var signInResult: Result<(Account, String), APIError> = .failure(APIError(message: "Invalid email or password"))
    var resetResult: Result<Void, APIError> = .success(())
    var resetRequests: [String] = []
    var resets: [(token: String, newPassword: String)] = []
    var verificationEmails: [(email: String, token: String)] = []

    func signIn(email: String, password: String) async throws -> (Account, token: String) { try signInResult.get() }
    func signUp(name: String, email: String, password: String) async throws -> (Account, token: String) { try signInResult.get() }
    func account(token: String) async throws -> Account? { try accountForToken.get() }
    func signOut(token: String) async throws {}
    func rename(to name: String, token: String) async throws {}
    func deleteAccount(password: String, token: String) async throws {}
    func requestPasswordReset(email: String) async throws { resetRequests.append(email) }
    func resetPassword(token: String, newPassword: String) async throws {
        try resetResult.get()
        resets.append((token, newPassword))
    }
    func sendVerificationEmail(email: String, token: String) async throws { verificationEmails.append((email, token)) }
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

    @Test func forgotPasswordSendsTheTrimmedEmail() async throws {
        let api = FakeAuthAPI()
        let (store, _) = makeStore(api)
        try await store.requestPasswordReset(email: " lifter@example.com\n")
        #expect(api.resetRequests == ["lifter@example.com"])
    }

    @Test func aResetLinkOpensTheResetScreenAndSavesWithItsToken() async throws {
        let api = FakeAuthAPI()
        let (store, _) = makeStore(api)
        store.open(URL(string: "fatigue://reset-password?token=abc123")!)
        #expect(store.passwordReset == PasswordReset(token: "abc123"))
        try await store.resetPassword(newPassword: "newpassword456")
        #expect(api.resets.count == 1)
        #expect(api.resets[0].token == "abc123")
        #expect(api.resets[0].newPassword == "newpassword456")
    }

    @Test func resettingWhileSignedInSignsOutThisPhoneToo() async throws {
        let api = FakeAuthAPI()
        api.signInResult = .success((lifter, "token"))
        let (store, tokens) = makeStore(api)
        try await store.signIn(email: "lifter@example.com", password: "password123")
        store.open(URL(string: "fatigue://reset-password?token=abc123")!)
        try await store.resetPassword(newPassword: "newpassword456")
        #expect(store.state == .signedOut)
        #expect(tokens.read() == nil)
    }

    @Test func aBadResetTokenKeepsTheScreenAndShowsTheError() async {
        let api = FakeAuthAPI()
        api.resetResult = .failure(APIError(message: "Invalid token"))
        let (store, _) = makeStore(api)
        store.open(URL(string: "fatigue://reset-password?token=old")!)
        await #expect(throws: APIError(message: "Invalid token")) {
            try await store.resetPassword(newPassword: "newpassword456")
        }
        #expect(store.passwordReset != nil)
    }

    @Test func resendingVerificationUsesTheAccountsEmailAndSession() async throws {
        let api = FakeAuthAPI()
        api.signInResult = .success((lifter, "token"))
        let (store, tokens) = makeStore(api)
        try await store.signIn(email: "lifter@example.com", password: "password123")
        try await store.sendVerificationEmail()
        #expect(api.verificationEmails.count == 1)
        #expect(api.verificationEmails[0].email == "lifter@example.com")
        #expect(api.verificationEmails[0].token == "token")
        tokens.delete()
    }

    @Test func theVerifiedLinkRefreshesTheAccount() async throws {
        let api = FakeAuthAPI()
        api.signInResult = .success((lifter, "token"))
        let (store, tokens) = makeStore(api)
        try await store.signIn(email: "lifter@example.com", password: "password123")
        var verified = lifter
        verified.emailVerified = true
        api.accountForToken = .success(verified)
        store.open(URL(string: "fatigue://email-verified")!)
        await store.restore()
        #expect(store.account?.emailVerified == true)
        tokens.delete()
    }

    @Test func anAccountCachedBeforeVerificationExistedStillDecodes() throws {
        let json = #"{"id":"1","name":"A","email":"a@example.com","createdAt":"2026-11-12T11:45:34.687Z"}"#
        let account = try JSONDecoder.api.decode(Account.self, from: Data(json.utf8))
        #expect(account.emailVerified == false)
        let verified = #"{"id":"1","name":"A","email":"a@example.com","emailVerified":true,"createdAt":"2026-11-12T11:45:34.687Z"}"#
        #expect(try JSONDecoder.api.decode(Account.self, from: Data(verified.utf8)).emailVerified == true)
    }

    @Test func readsTheAPIsDates() throws {
        let json = #"{"id":"1","name":"A","email":"a@example.com","createdAt":"2026-11-12T11:45:34.687Z"}"#
        let account = try JSONDecoder.api.decode(Account.self, from: Data(json.utf8))
        #expect(account.createdAt.timeIntervalSince1970.rounded() == 1_794_483_935)
    }
}
