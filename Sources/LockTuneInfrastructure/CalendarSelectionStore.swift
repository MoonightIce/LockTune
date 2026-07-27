import Foundation

public actor CalendarSelectionStore {
    private let defaults: UserDefaults
    private let key: String

    public init(suiteName: String? = nil, key: String = "google.selectedCalendarIDs") {
        self.defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        self.key = key
    }

    public func load() -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    public func save(_ calendarIDs: Set<String>) {
        defaults.set(calendarIDs.sorted(), forKey: key)
    }

    public func clear() {
        defaults.removeObject(forKey: key)
    }
}
