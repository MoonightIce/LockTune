import Foundation
import Testing
import LockTuneDomain
import LockTuneInfrastructure

@Test("Google Calendar response preserves meeting fields and all-day events")
func decodesGoogleCalendarEvents() throws {
    let data = Data(#"""
    {
      "items": [
        {
          "id": "meeting-1",
          "summary": "Product review",
          "status": "confirmed",
          "start": { "dateTime": "2026-07-27T10:30:00+08:00" },
          "end": { "dateTime": "2026-07-27T11:00:00+08:00" },
          "organizer": { "displayName": "Nancheng", "email": "owner@example.com" },
          "attendees": [{ "self": true, "responseStatus": "accepted" }],
          "location": "Online",
          "htmlLink": "https://calendar.google.com/event?eid=opaque",
          "conferenceData": {
            "entryPoints": [
              { "entryPointType": "phone", "uri": "tel:+10000000000" },
              { "entryPointType": "video", "uri": "https://meet.google.com/abc-defg-hij" }
            ]
          }
        },
        {
          "id": "all-day-1",
          "summary": "Release day",
          "status": "confirmed",
          "start": { "date": "2026-07-28" },
          "end": { "date": "2026-07-29" }
        }
      ]
    }
    """#.utf8)

    let events = try GoogleCalendarEventDecoder.decode(data)
    let meeting = try #require(events.first)
    #expect(meeting.title == "Product review")
    #expect(meeting.organizer == "Nancheng")
    #expect(meeting.attendanceStatus == .accepted)
    #expect(meeting.location == "Online")
    #expect(meeting.meetURL?.host == "meet.google.com")
    #expect(meeting.calendarURL?.host == "calendar.google.com")
    #expect(!meeting.isAllDay)

    let allDay = try #require(events.last)
    #expect(allDay.isAllDay)
    #expect(allDay.title == "Release day")
}

@Test("Calendar request is read-only, bounded, and expands recurrences")
func buildsBoundedCalendarRequest() throws {
    let start = try #require(ISO8601DateFormatter().date(from: "2026-07-27T00:00:00Z"))
    let end = try #require(ISO8601DateFormatter().date(from: "2026-08-10T00:00:00Z"))
    let url = try #require(GoogleCalendarRequest.eventsURL(calendarID: "primary", from: start, to: end))
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

    #expect(url.path == "/calendar/v3/calendars/primary/events")
    #expect(query["singleEvents"] == "true")
    #expect(query["orderBy"] == "startTime")
    #expect(query["showDeleted"] == "false")
    #expect(query["timeMin"] == "2026-07-27T00:00:00Z")
    #expect(query["timeMax"] == "2026-08-10T00:00:00Z")
}

@Test("Calendar list response keeps readable visible calendars and primary first")
func decodesCalendarList() throws {
    let data = Data(#"""
    {
      "items": [
        { "id": "team", "summary": "Team", "backgroundColor": "#123456" },
        { "id": "hidden", "summary": "Hidden", "hidden": true },
        { "id": "primary@example.com", "summary": "Owner", "summaryOverride": "Personal", "primary": true }
      ]
    }
    """#.utf8)

    let calendars = try GoogleCalendarListDecoder.decode(data)

    #expect(calendars.map(\.id) == ["primary@example.com", "team"])
    #expect(calendars.first?.title == "Personal")
    #expect(calendars.last?.colorHex == "#123456")
}

@Test("Calendar list request is read-only and excludes hidden calendars")
func buildsCalendarListRequest() throws {
    let url = try #require(GoogleCalendarRequest.calendarListURL(pageToken: "next-page"))
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

    #expect(url.path == "/calendar/v3/users/me/calendarList")
    #expect(query["minAccessRole"] == "reader")
    #expect(query["showHidden"] == "false")
    #expect(query["showDeleted"] == "false")
    #expect(query["pageToken"] == "next-page")
}

@Test("Calendar decoders preserve next page tokens")
func decodesCalendarPageTokens() throws {
    let calendars = try GoogleCalendarListDecoder.decodePage(Data(#"""
    { "items": [], "nextPageToken": "calendar-page-2" }
    """#.utf8))
    let events = try GoogleCalendarEventDecoder.decodePage(Data(#"""
    { "items": [], "nextPageToken": "event-page-2" }
    """#.utf8))

    #expect(calendars.nextPageToken == "calendar-page-2")
    #expect(events.nextPageToken == "event-page-2")
}

@Test("Incremental event changes preserve cancellations and updated events")
func decodesIncrementalCalendarChanges() throws {
    let data = Data(#"""
    {
      "items": [
        { "id": "removed", "status": "cancelled" },
        {
          "id": "updated",
          "status": "confirmed",
          "summary": "Updated meeting",
          "start": { "dateTime": "2026-07-27T10:30:00+08:00" },
          "end": { "dateTime": "2026-07-27T11:00:00+08:00" }
        }
      ]
    }
    """#.utf8)

    let page = try GoogleCalendarEventDecoder.decodeChangesPage(data, calendarID: "team")

    #expect(page.items.contains(.remove(id: "team:removed")))
    #expect(page.items.contains { change in
        if case let .upsert(event) = change { return event.id == "team:updated" }
        return false
    })
}

@Test("Incremental event request uses updatedMin and includes deletions")
func buildsIncrementalEventRequest() throws {
    let updatedSince = try #require(ISO8601DateFormatter().date(from: "2026-07-27T00:00:00Z"))
    let url = try #require(GoogleCalendarRequest.eventChangesURL(
        calendarID: "team",
        updatedSince: updatedSince,
        pageToken: "page-2"
    ))
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

    #expect(query["updatedMin"] == "2026-07-27T00:00:00Z")
    #expect(query["showDeleted"] == "true")
    #expect(query["singleEvents"] == "true")
    #expect(query["pageToken"] == "page-2")
    #expect(query["timeMin"] == nil)
}
