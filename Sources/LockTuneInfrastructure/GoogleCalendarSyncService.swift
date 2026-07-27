import Foundation
import LockTuneDomain

public protocol GoogleOAuthTokenStoring: Actor {
    func load() throws -> GoogleOAuthToken?
    func save(_ token: GoogleOAuthToken) throws
    func delete() throws
}

extension GoogleOAuthTokenStore: GoogleOAuthTokenStoring {}

public protocol GoogleOAuthRefreshing: Actor {
    func refresh(_ token: GoogleOAuthToken) async throws -> GoogleOAuthToken
}

extension GoogleOAuthClient: GoogleOAuthRefreshing {}

public protocol GoogleCalendarFetching: Actor {
    func calendars(accessToken: String) async throws -> [CalendarSource]
    func events(
        calendarID: String,
        calendarTitle: String?,
        accessToken: String,
        from start: Date,
        to end: Date
    ) async throws -> [CalendarEvent]
    func eventChanges(
        calendarID: String,
        calendarTitle: String?,
        accessToken: String,
        updatedSince: Date
    ) async throws -> [GoogleCalendarEventChange]
}

extension GoogleCalendarClient: GoogleCalendarFetching {}

public struct GoogleCalendarSyncResult: Equatable, Sendable {
    public let snapshot: CalendarSnapshot
    public let selectedCalendarIDs: Set<String>

    public init(snapshot: CalendarSnapshot, selectedCalendarIDs: Set<String>) {
        self.snapshot = snapshot
        self.selectedCalendarIDs = selectedCalendarIDs
    }
}

public enum GoogleCalendarSyncServiceError: Error, Sendable {
    case missingAuthorization
}

public actor GoogleCalendarSyncService {
    private let oauthClient: any GoogleOAuthRefreshing
    private let tokenStore: any GoogleOAuthTokenStoring
    private let calendarClient: any GoogleCalendarFetching
    private let cache: CalendarCache
    private let selectionStore: CalendarSelectionStore

    public init(
        oauthConfiguration: GoogleOAuthConfiguration,
        tokenStore: any GoogleOAuthTokenStoring = GoogleOAuthTokenStore(),
        calendarClient: any GoogleCalendarFetching = GoogleCalendarClient(),
        cache: CalendarCache = CalendarCache(),
        selectionStore: CalendarSelectionStore = CalendarSelectionStore()
    ) {
        oauthClient = GoogleOAuthClient(configuration: oauthConfiguration)
        self.tokenStore = tokenStore
        self.calendarClient = calendarClient
        self.cache = cache
        self.selectionStore = selectionStore
    }

    public init(
        oauthClient: any GoogleOAuthRefreshing,
        tokenStore: any GoogleOAuthTokenStoring,
        calendarClient: any GoogleCalendarFetching,
        cache: CalendarCache,
        selectionStore: CalendarSelectionStore
    ) {
        self.oauthClient = oauthClient
        self.tokenStore = tokenStore
        self.calendarClient = calendarClient
        self.cache = cache
        self.selectionStore = selectionStore
    }

    public func loadLocalState() async throws -> GoogleCalendarSyncResult {
        async let snapshot = cache.load()
        async let selectedCalendarIDs = selectionStore.load()
        return try await GoogleCalendarSyncResult(
            snapshot: snapshot,
            selectedCalendarIDs: selectedCalendarIDs
        )
    }

    public func hasStoredAuthorization() async throws -> Bool {
        try await tokenStore.load() != nil
    }

    public func storeAuthorization(_ token: GoogleOAuthToken) async throws {
        try await tokenStore.save(token)
    }

    public func deleteAuthorization() async throws {
        try await tokenStore.delete()
    }

    public func disconnect() async throws {
        try await cache.clear()
        await selectionStore.clear()
        try await tokenStore.delete()
    }

    public func saveSelection(_ selectedCalendarIDs: Set<String>) async {
        await selectionStore.save(selectedCalendarIDs)
    }

    public func sync(
        from snapshot: CalendarSnapshot,
        selectedCalendarIDs: Set<String>,
        forceFull: Bool = false
    ) async throws -> GoogleCalendarSyncResult {
        guard var token = try await tokenStore.load() else {
            throw GoogleCalendarSyncServiceError.missingAuthorization
        }
        if !token.isFresh() {
            token = try await refresh(token)
        }
        do {
            return try await fetch(
                token: token,
                snapshot: snapshot,
                selectedCalendarIDs: selectedCalendarIDs,
                forceFull: forceFull
            )
        } catch GoogleCalendarClientError.unauthorized {
            token = try await refresh(token)
            return try await fetch(
                token: token,
                snapshot: snapshot,
                selectedCalendarIDs: selectedCalendarIDs,
                forceFull: forceFull
            )
        }
    }

    private func refresh(_ token: GoogleOAuthToken) async throws -> GoogleOAuthToken {
        let refreshed = try await oauthClient.refresh(token)
        try await tokenStore.save(refreshed)
        return refreshed
    }

    private func fetch(
        token: GoogleOAuthToken,
        snapshot: CalendarSnapshot,
        selectedCalendarIDs: Set<String>,
        forceFull: Bool
    ) async throws -> GoogleCalendarSyncResult {
        let now = Date()
        let calendars = try await calendarClient.calendars(accessToken: token.accessToken)
        let availableIDs = Set(calendars.map(\.id))
        var selection = selectedCalendarIDs.intersection(availableIDs)
        if selection.isEmpty,
           let defaultCalendar = calendars.first(where: \.isPrimary) ?? calendars.first {
            selection = [defaultCalendar.id]
        }
        await selectionStore.save(selection)

        let start = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        let end = Calendar.current.date(byAdding: .day, value: 14, to: now) ?? now
        let syncStartedAt = Date()
        var events = snapshot.events.filter {
            guard let calendarID = $0.calendarID else { return false }
            return selection.contains(calendarID) && $0.end > start && $0.start < end
        }
        var cursors = snapshot.lastSyncByCalendarID.filter { selection.contains($0.key) }
        var fullSyncDates = snapshot.lastFullSyncByCalendarID.filter { selection.contains($0.key) }

        for calendar in calendars where selection.contains(calendar.id) {
            let lastFullSync = fullSyncDates[calendar.id]
            let fullSyncIsRecent = lastFullSync.map {
                syncStartedAt.timeIntervalSince($0) < 6 * 60 * 60
            } ?? false
            if !forceFull, fullSyncIsRecent, let cursor = cursors[calendar.id] {
                let changes = try await calendarClient.eventChanges(
                    calendarID: calendar.id,
                    calendarTitle: calendar.title,
                    accessToken: token.accessToken,
                    updatedSince: cursor
                )
                for change in changes {
                    switch change {
                    case let .remove(id):
                        events.removeAll { $0.id == id }
                    case let .upsert(event):
                        events.removeAll { $0.id == event.id }
                        if event.end > start && event.start < end { events.append(event) }
                    }
                }
            } else {
                events.removeAll { $0.calendarID == calendar.id }
                events.append(contentsOf: try await calendarClient.events(
                    calendarID: calendar.id,
                    calendarTitle: calendar.title,
                    accessToken: token.accessToken,
                    from: start,
                    to: end
                ))
                fullSyncDates[calendar.id] = syncStartedAt
            }
            cursors[calendar.id] = syncStartedAt
        }

        events.sort { $0.start < $1.start }
        let result = GoogleCalendarSyncResult(
            snapshot: CalendarSnapshot(
                events: events,
                calendars: calendars,
                lastSyncByCalendarID: cursors,
                lastFullSyncByCalendarID: fullSyncDates,
                lastSuccessfulSync: Date()
            ),
            selectedCalendarIDs: selection
        )
        try await cache.save(result.snapshot)
        return result
    }
}
