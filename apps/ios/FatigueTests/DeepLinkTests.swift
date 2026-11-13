import Foundation
import Testing
@testable import Fatigue

struct DeepLinkTests {
    @Test func readsTheTokenFromAResetLink() {
        #expect(DeepLink(url: URL(string: "fatigue://reset-password?token=abc%2Fdef")!) == .resetPassword(token: "abc/def"))
    }

    @Test func aResetLinkNeedsAToken() {
        #expect(DeepLink(url: URL(string: "fatigue://reset-password")!) == nil)
        #expect(DeepLink(url: URL(string: "fatigue://reset-password?token=")!) == nil)
    }

    @Test func recognisesTheVerifiedLinkInAnyCase() {
        #expect(DeepLink(url: URL(string: "fatigue://email-verified")!) == .emailVerified)
        #expect(DeepLink(url: URL(string: "FATIGUE://Email-Verified")!) == .emailVerified)
    }

    @Test func ignoresOtherSchemesAndPaths() {
        #expect(DeepLink(url: URL(string: "https://example.com/reset-password?token=abc")!) == nil)
        #expect(DeepLink(url: URL(string: "fatigue://something-else")!) == nil)
    }
}
