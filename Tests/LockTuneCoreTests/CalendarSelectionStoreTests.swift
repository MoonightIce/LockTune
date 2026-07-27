import Foundation
import Testing
import LockTuneInfrastructure

@Test("Selected calendars persist independently from the event cache")
func calendarSelectionRoundTrip() async throws {
    let suiteName = "LockTuneCalendarSelectionTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    let store = CalendarSelectionStore(suiteName: suiteName)

    await store.save(["primary", "team"])
    #expect(await store.load() == ["primary", "team"])

    await store.clear()
    #expect(await store.load().isEmpty)
    defaults.removePersistentDomain(forName: suiteName)
}
