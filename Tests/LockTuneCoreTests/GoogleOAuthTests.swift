import Foundation
import Testing
import LockTuneInfrastructure

@Test("Google OAuth authorization request uses PKCE and the narrow read-only event scope")
func buildsGoogleOAuthAuthorizationURL() throws {
    let configuration = GoogleOAuthConfiguration(
        clientID: "desktop-client.apps.googleusercontent.com",
        clientSecret: "desktop-client-secret"
    )
    let url = try #require(configuration.authorizationURL(
        redirectURI: "http://127.0.0.1:49152/callback",
        state: "state-value",
        codeChallenge: "challenge-value"
    ))
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let query: [String: String] = Dictionary(
        uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
    )

    #expect(query["client_id"] == "desktop-client.apps.googleusercontent.com")
    #expect(query["redirect_uri"] == "http://127.0.0.1:49152/callback")
    #expect(query["response_type"] == "code")
    let scopes = Set((query["scope"] ?? "").split(separator: " ").map(String.init))
    #expect(scopes == [
        "https://www.googleapis.com/auth/calendar.events.readonly",
        "https://www.googleapis.com/auth/calendar.calendarlist.readonly",
    ])
    #expect(query["access_type"] == "offline")
    #expect(Set((query["prompt"] ?? "").split(separator: " ").map(String.init)) == ["consent", "select_account"])
    #expect(query["client_secret"] == nil)
    #expect(query["code_challenge_method"] == "S256")
    #expect(query["code_challenge"] == "challenge-value")
    #expect(query["state"] == "state-value")
}

@Test("Google OAuth requires both desktop client credentials")
func validatesGoogleOAuthConfiguration() {
    #expect(GoogleOAuthConfiguration(clientID: "client", clientSecret: "secret").isConfigured)
    #expect(!GoogleOAuthConfiguration(clientID: "client", clientSecret: "").isConfigured)
    #expect(!GoogleOAuthConfiguration(clientID: "", clientSecret: "secret").isConfigured)
}

@Test("Only revoked or rejected Google authorization requires reconnecting")
func classifiesGoogleAuthorizationFailures() {
    #expect(GoogleAuthorizationFailure.requiresReconnect(GoogleCalendarClientError.unauthorized))
    #expect(GoogleAuthorizationFailure.requiresReconnect(
        GoogleOAuthError.tokenRequestFailed(statusCode: 400)
    ))
    #expect(!GoogleAuthorizationFailure.requiresReconnect(
        GoogleOAuthError.tokenRequestFailed(statusCode: 500)
    ))
    #expect(!GoogleAuthorizationFailure.requiresReconnect(URLError(.notConnectedToInternet)))
}

@Test("PKCE challenge uses unpadded base64url SHA-256")
func createsPKCEChallenge() {
    #expect(
        GoogleOAuthPKCE.codeChallenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
            == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
    )
}

@Test("OAuth callback requires the original state and an authorization code")
func validatesOAuthCallback() throws {
    let valid = URL(string: "http://127.0.0.1:49152/callback?code=opaque-code&state=expected")!
    #expect(try GoogleOAuthCallback.authorizationCode(from: valid, expectedState: "expected") == "opaque-code")

    let mismatched = URL(string: "http://127.0.0.1:49152/callback?code=opaque-code&state=wrong")!
    #expect(throws: GoogleOAuthError.invalidState) {
        try GoogleOAuthCallback.authorizationCode(from: mismatched, expectedState: "expected")
    }
}

@Test("Loopback OAuth server accepts a callback on 127.0.0.1")
func acceptsLoopbackOAuthCallback() async throws {
    let server = LoopbackOAuthServer()
    let redirect = try await server.start()
    var components = URLComponents(url: redirect, resolvingAgainstBaseURL: false)!
    components.queryItems = [
        URLQueryItem(name: "code", value: "local-code"),
        URLQueryItem(name: "state", value: "local-state"),
    ]

    let callbackTask = Task { try await server.waitForCallback() }
    let (_, response) = try await URLSession.shared.data(from: components.url!)

    #expect((response as? HTTPURLResponse)?.statusCode == 200)
    let callback = try await callbackTask.value
    #expect(
        try GoogleOAuthCallback.authorizationCode(
            from: callback,
            expectedState: "local-state"
        ) == "local-code"
    )
}

@Test("Cancelling the loopback OAuth server releases a pending callback")
func cancelsPendingLoopbackOAuthCallback() async throws {
    let server = LoopbackOAuthServer()
    _ = try await server.start()
    let callbackTask = Task { try await server.waitForCallback() }

    await server.cancel()

    await #expect(throws: CancellationError.self) {
        try await callbackTask.value
    }
}
