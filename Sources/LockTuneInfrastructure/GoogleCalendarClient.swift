import Foundation
import LockTuneDomain

public enum GoogleCalendarClientError: Error, Sendable {
    case invalidRequest
    case unauthorized
    case server(statusCode: Int)
    case invalidResponse
}

public enum GoogleCalendarRequest {
    public static func calendarListURL(pageToken: String? = nil) -> URL? {
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")
        components?.queryItems = [
            URLQueryItem(name: "minAccessRole", value: "reader"),
            URLQueryItem(name: "showDeleted", value: "false"),
            URLQueryItem(name: "showHidden", value: "false"),
            URLQueryItem(name: "maxResults", value: "250"),
        ]
        if let pageToken {
            components?.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        return components?.url
    }

    public static func eventsURL(
        calendarID: String,
        from start: Date,
        to end: Date,
        pageToken: String? = nil
    ) -> URL? {
        guard start < end else { return nil }
        var url = URL(string: "https://www.googleapis.com/calendar/v3/calendars")!
        url.append(path: calendarID)
        url.append(path: "events")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        components?.queryItems = [
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "showDeleted", value: "false"),
            URLQueryItem(name: "conferenceDataVersion", value: "1"),
            URLQueryItem(name: "maxResults", value: "250"),
            URLQueryItem(name: "timeMin", value: formatter.string(from: start)),
            URLQueryItem(name: "timeMax", value: formatter.string(from: end)),
        ]
        if let pageToken {
            components?.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        return components?.url
    }

    public static func eventChangesURL(
        calendarID: String,
        updatedSince: Date,
        pageToken: String? = nil
    ) -> URL? {
        var url = URL(string: "https://www.googleapis.com/calendar/v3/calendars")!
        url.append(path: calendarID)
        url.append(path: "events")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "showDeleted", value: "true"),
            URLQueryItem(name: "conferenceDataVersion", value: "1"),
            URLQueryItem(name: "maxResults", value: "250"),
            URLQueryItem(name: "updatedMin", value: formatter.string(from: updatedSince)),
        ]
        if let pageToken {
            components?.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        return components?.url
    }
}

public struct GoogleCalendarPage<Element: Sendable>: Sendable {
    public let items: [Element]
    public let nextPageToken: String?

    public init(items: [Element], nextPageToken: String?) {
        self.items = items
        self.nextPageToken = nextPageToken
    }
}

public enum GoogleCalendarEventChange: Equatable, Sendable {
    case upsert(CalendarEvent)
    case remove(id: String)
}

public actor GoogleCalendarClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func calendars(accessToken: String) async throws -> [CalendarSource] {
        var calendars: [CalendarSource] = []
        var pageToken: String?
        repeat {
            guard let url = GoogleCalendarRequest.calendarListURL(pageToken: pageToken) else {
                throw GoogleCalendarClientError.invalidRequest
            }
            let page = try GoogleCalendarListDecoder.decodePage(
                await get(url: url, accessToken: accessToken)
            )
            calendars.append(contentsOf: page.items)
            pageToken = page.nextPageToken
        } while pageToken != nil
        return GoogleCalendarListDecoder.sort(calendars)
    }

    public func events(
        calendarID: String = "primary",
        calendarTitle: String? = nil,
        accessToken: String,
        from start: Date,
        to end: Date
    ) async throws -> [CalendarEvent] {
        var events: [CalendarEvent] = []
        var pageToken: String?
        repeat {
            guard let url = GoogleCalendarRequest.eventsURL(
                calendarID: calendarID,
                from: start,
                to: end,
                pageToken: pageToken
            ) else { throw GoogleCalendarClientError.invalidRequest }
            let page = try GoogleCalendarEventDecoder.decodePage(
                await get(url: url, accessToken: accessToken),
                calendarID: calendarID,
                calendarTitle: calendarTitle
            )
            events.append(contentsOf: page.items)
            pageToken = page.nextPageToken
        } while pageToken != nil
        return events.sorted { $0.start < $1.start }
    }

    public func eventChanges(
        calendarID: String,
        calendarTitle: String? = nil,
        accessToken: String,
        updatedSince: Date
    ) async throws -> [GoogleCalendarEventChange] {
        var changes: [GoogleCalendarEventChange] = []
        var pageToken: String?
        repeat {
            guard let url = GoogleCalendarRequest.eventChangesURL(
                calendarID: calendarID,
                updatedSince: updatedSince,
                pageToken: pageToken
            ) else { throw GoogleCalendarClientError.invalidRequest }
            let page = try GoogleCalendarEventDecoder.decodeChangesPage(
                await get(url: url, accessToken: accessToken),
                calendarID: calendarID,
                calendarTitle: calendarTitle
            )
            changes.append(contentsOf: page.items)
            pageToken = page.nextPageToken
        } while pageToken != nil
        return changes
    }

    private func get(url: URL, accessToken: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw GoogleCalendarClientError.invalidResponse
        }
        if response.statusCode == 401 { throw GoogleCalendarClientError.unauthorized }
        guard (200..<300).contains(response.statusCode) else {
            throw GoogleCalendarClientError.server(statusCode: response.statusCode)
        }
        return data
    }
}

public enum GoogleCalendarListDecoder {
    public static func decode(_ data: Data) throws -> [CalendarSource] {
        try decodePage(data).items
    }

    public static func decodePage(_ data: Data) throws -> GoogleCalendarPage<CalendarSource> {
        let response = try JSONDecoder().decode(Response.self, from: data)
        let items = response.items
            .filter { $0.deleted != true && $0.hidden != true }
            .map {
                CalendarSource(
                    id: $0.id,
                    title: $0.summaryOverride ?? $0.summary,
                    isPrimary: $0.primary == true,
                    colorHex: $0.backgroundColor
                )
            }
        return GoogleCalendarPage(items: sort(items), nextPageToken: response.nextPageToken)
    }

    public static func sort(_ calendars: [CalendarSource]) -> [CalendarSource] {
        calendars.sorted { lhs, rhs in
                if lhs.isPrimary != rhs.isPrimary { return lhs.isPrimary }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
    }

    private struct Response: Decodable { let items: [Item]; let nextPageToken: String? }
    private struct Item: Decodable {
        let id: String
        let summary: String
        let summaryOverride: String?
        let primary: Bool?
        let deleted: Bool?
        let hidden: Bool?
        let backgroundColor: String?
    }
}

public enum GoogleCalendarEventDecoder {
    public static func decode(
        _ data: Data,
        calendarID: String? = nil,
        calendarTitle: String? = nil,
        calendar: Calendar = .current
    ) throws -> [CalendarEvent] {
        try decodePage(data, calendarID: calendarID, calendarTitle: calendarTitle, calendar: calendar).items
    }

    public static func decodePage(
        _ data: Data,
        calendarID: String? = nil,
        calendarTitle: String? = nil,
        calendar: Calendar = .current
    ) throws -> GoogleCalendarPage<CalendarEvent> {
        let response = try JSONDecoder().decode(Response.self, from: data)
        let events: [CalendarEvent] = response.items.compactMap { item -> CalendarEvent? in
            guard item.status != "cancelled" else { return nil }
            return event(from: item, calendarID: calendarID, calendarTitle: calendarTitle, calendar: calendar)
        }
        .sorted { $0.start < $1.start }
        return GoogleCalendarPage(items: events, nextPageToken: response.nextPageToken)
    }

    public static func decodeChangesPage(
        _ data: Data,
        calendarID: String,
        calendarTitle: String? = nil,
        calendar: Calendar = .current
    ) throws -> GoogleCalendarPage<GoogleCalendarEventChange> {
        let response = try JSONDecoder().decode(Response.self, from: data)
        let changes = response.items.compactMap { item -> GoogleCalendarEventChange? in
            let compoundID = "\(calendarID):\(item.id)"
            if item.status == "cancelled" { return .remove(id: compoundID) }
            guard let event = event(
                from: item,
                calendarID: calendarID,
                calendarTitle: calendarTitle,
                calendar: calendar
            ) else { return nil }
            return .upsert(event)
        }
        return GoogleCalendarPage(items: changes, nextPageToken: response.nextPageToken)
    }

    private static func event(
        from item: Item,
        calendarID: String?,
        calendarTitle: String?,
        calendar: Calendar
    ) -> CalendarEvent? {
        guard let startBoundary = item.start,
              let endBoundary = item.end,
              let start = parseBoundary(startBoundary, calendar: calendar),
              let end = parseBoundary(endBoundary, calendar: calendar)
        else { return nil }
            let selfStatus = item.attendees?.first(where: { $0.isSelf == true })?.responseStatus
            let attendance = CalendarAttendanceStatus(rawValue: selfStatus ?? "") ?? .unknown
            let conferenceURL = item.conferenceData?.entryPoints?
                .first(where: { $0.entryPointType == "video" })
                .flatMap { URL(string: $0.uri) }
            let meetURL = [conferenceURL, item.hangoutLink.flatMap(URL.init(string:))]
                .compactMap { $0 }
                .first(where: { $0.host?.lowercased() == "meet.google.com" })
        return CalendarEvent(
                id: calendarID.map { "\($0):\(item.id)" } ?? item.id,
                title: item.summary ?? "",
                start: start.date,
                end: end.date,
                isAllDay: start.isAllDay,
                organizer: item.organizer?.displayName ?? item.organizer?.email,
                attendanceStatus: attendance,
                location: item.location,
                meetURL: meetURL,
                calendarURL: item.htmlLink.flatMap(URL.init(string:)),
                calendarID: calendarID,
                calendarTitle: calendarTitle
        )
    }

    private static func parseBoundary(_ boundary: Boundary, calendar: Calendar) -> (date: Date, isAllDay: Bool)? {
        if let dateTime = boundary.dateTime {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let date = formatter.date(from: dateTime) ?? {
                formatter.formatOptions = [.withInternetDateTime]
                return formatter.date(from: dateTime)
            }()
            return date.map { ($0, false) }
        }
        guard let day = boundary.date else { return nil }
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        else { return nil }
        return (date, true)
    }

    private struct Response: Decodable { let items: [Item]; let nextPageToken: String? }
    private struct Item: Decodable {
        let id: String
        let summary: String?
        let status: String?
        let start: Boundary?
        let end: Boundary?
        let organizer: Person?
        let attendees: [Attendee]?
        let location: String?
        let htmlLink: String?
        let hangoutLink: String?
        let conferenceData: ConferenceData?
    }
    private struct Boundary: Decodable { let dateTime: String?; let date: String? }
    private struct Person: Decodable { let displayName: String?; let email: String? }
    private struct Attendee: Decodable {
        let isSelf: Bool?
        let responseStatus: String?
        enum CodingKeys: String, CodingKey { case isSelf = "self"; case responseStatus }
    }
    private struct ConferenceData: Decodable { let entryPoints: [EntryPoint]? }
    private struct EntryPoint: Decodable { let entryPointType: String; let uri: String }
}
