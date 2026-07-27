import Foundation

public enum CalendarAttendanceStatus: String, Codable, Sendable {
    case needsAction
    case declined
    case tentative
    case accepted
    case unknown
}

public struct CalendarSource: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let title: String
    public let isPrimary: Bool
    public let colorHex: String?

    public init(id: String, title: String, isPrimary: Bool = false, colorHex: String? = nil) {
        self.id = id
        self.title = title
        self.isPrimary = isPrimary
        self.colorHex = colorHex
    }
}

public struct CalendarEvent: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let organizer: String?
    public let attendanceStatus: CalendarAttendanceStatus
    public let location: String?
    public let meetURL: URL?
    public let calendarURL: URL?
    public let calendarID: String?
    public let calendarTitle: String?

    public init(
        id: String,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool,
        organizer: String? = nil,
        attendanceStatus: CalendarAttendanceStatus = .unknown,
        location: String? = nil,
        meetURL: URL? = nil,
        calendarURL: URL? = nil,
        calendarID: String? = nil,
        calendarTitle: String? = nil
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.organizer = organizer
        self.attendanceStatus = attendanceStatus
        self.location = location
        self.meetURL = meetURL
        self.calendarURL = calendarURL
        self.calendarID = calendarID
        self.calendarTitle = calendarTitle
    }
}

public struct CalendarSnapshot: Equatable, Codable, Sendable {
    public var events: [CalendarEvent]
    public var calendars: [CalendarSource]
    public var lastSyncByCalendarID: [String: Date]
    public var lastFullSyncByCalendarID: [String: Date]
    public var lastSuccessfulSync: Date?

    public init(
        events: [CalendarEvent] = [],
        calendars: [CalendarSource] = [],
        lastSyncByCalendarID: [String: Date] = [:],
        lastFullSyncByCalendarID: [String: Date] = [:],
        lastSuccessfulSync: Date? = nil
    ) {
        self.events = events
        self.calendars = calendars
        self.lastSyncByCalendarID = lastSyncByCalendarID
        self.lastFullSyncByCalendarID = lastFullSyncByCalendarID
        self.lastSuccessfulSync = lastSuccessfulSync
    }

    private enum CodingKeys: String, CodingKey {
        case events, calendars, lastSyncByCalendarID, lastFullSyncByCalendarID, lastSuccessfulSync
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        events = try container.decodeIfPresent([CalendarEvent].self, forKey: .events) ?? []
        calendars = try container.decodeIfPresent([CalendarSource].self, forKey: .calendars) ?? []
        lastSyncByCalendarID = try container.decodeIfPresent(
            [String: Date].self,
            forKey: .lastSyncByCalendarID
        ) ?? [:]
        lastFullSyncByCalendarID = try container.decodeIfPresent(
            [String: Date].self,
            forKey: .lastFullSyncByCalendarID
        ) ?? [:]
        lastSuccessfulSync = try container.decodeIfPresent(Date.self, forKey: .lastSuccessfulSync)
    }
}
