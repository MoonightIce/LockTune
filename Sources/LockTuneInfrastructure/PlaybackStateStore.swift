import Foundation
import LockTuneDomain

public actor PlaybackStateStore {
    private let directoryURL: URL
    private let fileManager: FileManager

    public init(directoryURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            self.directoryURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appending(path: "LockTune", directoryHint: .isDirectory)
                .appending(path: "Playback", directoryHint: .isDirectory)
        }
    }

    public func load() throws -> PersistedPlaybackState? {
        let fileURL = directoryURL.appending(path: "state.json")
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        return try JSONDecoder().decode(PersistedPlaybackState.self, from: Data(contentsOf: fileURL))
    }

    public func save(_ snapshot: PlaybackSnapshot) throws {
        try save(PersistedPlaybackState(snapshot: snapshot))
    }

    public func save(_ persisted: PersistedPlaybackState) throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try JSONEncoder().encode(persisted)
            .write(to: directoryURL.appending(path: "state.json"), options: .atomic)
    }
}
