import Foundation

/// The signed-in person, as the API returns them.
nonisolated struct Account: Codable, Equatable, Sendable {
    let id: String
    var name: String
    let email: String
    /// Whether they've opened the link in the verification email. The app works either way.
    var emailVerified = false
    let createdAt: Date

    private enum CodingKeys: String, CodingKey { case id, name, email, emailVerified, createdAt }
}

nonisolated extension Account {
    /// Accounts cached before verification existed have no `emailVerified`, so it defaults to false.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        email = try container.decode(String.self, forKey: .email)
        emailVerified = try container.decodeIfPresent(Bool.self, forKey: .emailVerified) ?? false
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
}

/// Something the API said no to, with a message fit to show under the form.
nonisolated struct APIError: LocalizedError, Equatable, Sendable {
    let message: String
    var errorDescription: String? { message }

    static let offline = APIError(message: "Can't reach Fatigue. Check your connection and try again.")
}

nonisolated extension JSONDecoder {
    /// Reads the API's dates, which are ISO 8601 with milliseconds, such as 2026-11-12T11:45:34.687Z.
    static let api: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return date }
            if let date = try? Date(text, strategy: .iso8601) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not an ISO 8601 date: \(text)"))
        }
        return decoder
    }()
}
