import Foundation
import LockTuneDomain

public actor CalendarCache {
    private let directoryURL: URL
    private let fileManager: FileManager

    public init(directoryURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.directoryURL = applicationSupport
                .appending(path: "LockTune", directoryHint: .isDirectory)
                .appending(path: "Calendar", directoryHint: .isDirectory)
        }
    }

    public func load() throws -> CalendarSnapshot {
        let fileURL = directoryURL.appending(path: "events.json")
        guard fileManager.fileExists(atPath: fileURL.path) else { return CalendarSnapshot() }
        return try JSONDecoder().decode(CalendarSnapshot.self, from: Data(contentsOf: fileURL))
    }

    public func save(_ snapshot: CalendarSnapshot) throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: directoryURL.appending(path: "events.json"), options: .atomic)
    }

    public func clear() throws {
        let fileURL = directoryURL.appending(path: "events.json")
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
    }
}
