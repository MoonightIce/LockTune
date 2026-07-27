import CryptoKit
import Foundation
import Security

public enum GoogleOAuthError: Error, Equatable, Sendable {
    case missingConfiguration
    case invalidCallback
    case invalidState
    case authorizationDenied
    case invalidResponse
    case tokenRequestFailed(statusCode: Int)
    case keychain(status: OSStatus)
}

public struct GoogleOAuthConfiguration: Equatable, Sendable {
    public static let calendarEventsReadOnlyScope =
        "https://www.googleapis.com/auth/calendar.events.readonly"
    public static let calendarListReadOnlyScope =
        "https://www.googleapis.com/auth/calendar.calendarlist.readonly"

    public let clientID: String

    public init(clientID: String) {
        self.clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isConfigured: Bool {
        !clientID.isEmpty && !clientID.contains("$(")
    }

    public func authorizationURL(
        redirectURI: String,
        state: String,
        codeChallenge: String
    ) -> URL? {
        guard isConfigured else { return nil }
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(
                name: "scope",
                value: [Self.calendarEventsReadOnlyScope, Self.calendarListReadOnlyScope].joined(separator: " ")
            ),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        return components?.url
    }
}

public enum GoogleOAuthPKCE {
    public static func makeVerifier() -> String { randomBase64URL(byteCount: 32) }
    public static func makeState() -> String { randomBase64URL(byteCount: 24) }

    public static func codeChallenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func randomBase64URL(byteCount: Int) -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<byteCount).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

public enum GoogleOAuthCallback {
    public static func authorizationCode(from url: URL, expectedState: String) throws -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw GoogleOAuthError.invalidCallback
        }
        let query = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        )
        guard query["state"] == expectedState else { throw GoogleOAuthError.invalidState }
        if query["error"] != nil { throw GoogleOAuthError.authorizationDenied }
        guard let code = query["code"], !code.isEmpty else { throw GoogleOAuthError.invalidCallback }
        return code
    }
}

public struct GoogleOAuthToken: Equatable, Codable, Sendable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date

    public init(accessToken: String, refreshToken: String?, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    public func isFresh(at date: Date = Date()) -> Bool {
        expiresAt.timeIntervalSince(date) > 60
    }
}

public actor GoogleOAuthClient {
    private let configuration: GoogleOAuthConfiguration
    private let session: URLSession

    public init(configuration: GoogleOAuthConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    public func exchangeCode(_ code: String, verifier: String, redirectURI: String) async throws -> GoogleOAuthToken {
        try await requestToken(parameters: [
            "client_id": configuration.clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI,
        ], existingRefreshToken: nil)
    }

    public func refresh(_ token: GoogleOAuthToken) async throws -> GoogleOAuthToken {
        guard let refreshToken = token.refreshToken else { throw GoogleOAuthError.invalidResponse }
        return try await requestToken(parameters: [
            "client_id": configuration.clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ], existingRefreshToken: refreshToken)
    }

    private func requestToken(
        parameters: [String: String],
        existingRefreshToken: String?
    ) async throws -> GoogleOAuthToken {
        guard configuration.isConfigured,
              let url = URL(string: "https://oauth2.googleapis.com/token")
        else { throw GoogleOAuthError.missingConfiguration }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = parameters.sorted(by: { $0.key < $1.key })
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw GoogleOAuthError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            throw GoogleOAuthError.tokenRequestFailed(statusCode: response.statusCode)
        }
        let payload = try JSONDecoder().decode(TokenPayload.self, from: data)
        return GoogleOAuthToken(
            accessToken: payload.accessToken,
            refreshToken: payload.refreshToken ?? existingRefreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(payload.expiresIn))
        )
    }

    private struct TokenPayload: Decodable {
        let accessToken: String
        let expiresIn: Int
        let refreshToken: String?
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
            case refreshToken = "refresh_token"
        }
    }
}

public actor GoogleOAuthTokenStore {
    private let service: String
    private let account: String

    public init(service: String = "app.locktune.macos.google-oauth", account: String = "calendar") {
        self.service = service
        self.account = account
    }

    public func load() throws -> GoogleOAuthToken? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw GoogleOAuthError.keychain(status: status)
        }
        return try JSONDecoder().decode(GoogleOAuthToken.self, from: data)
    }

    public func save(_ token: GoogleOAuthToken) throws {
        let data = try JSONEncoder().encode(token)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var insertion = query
            attributes.forEach { insertion[$0.key] = $0.value }
            let addStatus = SecItemAdd(insertion as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw GoogleOAuthError.keychain(status: addStatus) }
        } else if updateStatus != errSecSuccess {
            throw GoogleOAuthError.keychain(status: updateStatus)
        }
    }

    public func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GoogleOAuthError.keychain(status: status)
        }
    }
}
