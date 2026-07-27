import Foundation
import Testing
import LockTuneDomain
import LockTuneInfrastructure

@Test("A Calendar API 401 refreshes the access token once and retries")
func retriesCalendarSyncAfterUnauthorizedAccessToken() async throws {
    let suiteName = "LockTuneCalendarSyncTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    let cacheDirectory = FileManager.default.temporaryDirectory
        .appending(path: "LockTuneCalendarSyncTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    let initialToken = GoogleOAuthToken(
        accessToken: "expired-access",
        refreshToken: "refresh-token",
        expiresAt: Date().addingTimeInterval(3600)
    )
    let refreshedToken = GoogleOAuthToken(
        accessToken: "fresh-access",
        refreshToken: "refresh-token",
        expiresAt: Date().addingTimeInterval(7200)
    )
    let tokenStore = InMemoryGoogleTokenStore(token: initialToken)
    let oauthClient = StubGoogleOAuthRefresher(token: refreshedToken)
    let calendarClient = UnauthorizedOnceCalendarClient()
    let service = GoogleCalendarSyncService(
        oauthClient: oauthClient,
        tokenStore: tokenStore,
        calendarClient: calendarClient,
        cache: CalendarCache(directoryURL: cacheDirectory),
        selectionStore: CalendarSelectionStore(suiteName: suiteName)
    )

    let result = try await service.sync(
        from: CalendarSnapshot(),
        selectedCalendarIDs: [],
        forceFull: true
    )

    #expect(result.snapshot.calendars.map(\.id) == ["primary"])
    #expect(result.selectedCalendarIDs == ["primary"])
    #expect(await calendarClient.calendarRequestCount() == 2)
    #expect(await oauthClient.refreshCount() == 1)
    #expect(try await tokenStore.load() == refreshedToken)

    try? FileManager.default.removeItem(at: cacheDirectory)
    defaults.removePersistentDomain(forName: suiteName)
}

private actor InMemoryGoogleTokenStore: GoogleOAuthTokenStoring {
    private var token: GoogleOAuthToken?

    init(token: GoogleOAuthToken?) {
        self.token = token
    }

    func load() throws -> GoogleOAuthToken? { token }
    func save(_ token: GoogleOAuthToken) throws { self.token = token }
    func delete() throws { token = nil }
}

private actor StubGoogleOAuthRefresher: GoogleOAuthRefreshing {
    private let token: GoogleOAuthToken
    private var count = 0

    init(token: GoogleOAuthToken) {
        self.token = token
    }

    func refresh(_ token: GoogleOAuthToken) async throws -> GoogleOAuthToken {
        count += 1
        return self.token
    }

    func refreshCount() -> Int { count }
}

private actor UnauthorizedOnceCalendarClient: GoogleCalendarFetching {
    private var calendarRequests = 0

    func calendars(accessToken: String) async throws -> [CalendarSource] {
        calendarRequests += 1
        if calendarRequests == 1 {
            throw GoogleCalendarClientError.unauthorized
        }
        return [CalendarSource(id: "primary", title: "Primary", isPrimary: true)]
    }

    func events(
        calendarID: String,
        calendarTitle: String?,
        accessToken: String,
        from start: Date,
        to end: Date
    ) async throws -> [CalendarEvent] {
        []
    }

    func eventChanges(
        calendarID: String,
        calendarTitle: String?,
        accessToken: String,
        updatedSince: Date
    ) async throws -> [GoogleCalendarEventChange] {
        []
    }

    func calendarRequestCount() -> Int { calendarRequests }
}
