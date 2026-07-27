import Foundation
import Testing
import LockTuneDomain
import LockTuneInfrastructure

@Test("Calendar cache restores the last successful offline snapshot")
func calendarCacheRoundTrip() async throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "LockTuneCalendarCacheTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let cache = CalendarCache(directoryURL: root)
    let event = CalendarEvent(
        id: "event-1",
        title: "Review",
        start: Date(timeIntervalSince1970: 100),
        end: Date(timeIntervalSince1970: 200),
        isAllDay: false,
        meetURL: URL(string: "https://meet.google.com/abc-defg-hij")
    )
    let snapshot = CalendarSnapshot(events: [event], lastSuccessfulSync: Date(timeIntervalSince1970: 300))

    try await cache.save(snapshot)

    #expect(try await cache.load() == snapshot)
}
