import Foundation

/// A link that opens the app, such as `fatigue://reset-password?token=abc`.
///
/// The links in emails point at the API, which checks them and lands on a page that hands off to one
/// of these. The scheme is registered in Info.plist and matches `APP_DEEP_LINK_SCHEME` on the API.
nonisolated enum DeepLink: Equatable, Sendable {
    static let scheme = "fatigue"

    /// Open "Set a new password" with the one-time token from the reset email.
    case resetPassword(token: String)
    /// The verification link was opened, so the account should be refreshed.
    case emailVerified

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        switch components.host?.lowercased() {
        case "reset-password":
            guard let token = components.queryItems?.first(where: { $0.name == "token" })?.value, !token.isEmpty else { return nil }
            self = .resetPassword(token: token)
        case "email-verified":
            self = .emailVerified
        default:
            return nil
        }
    }
}
