import Foundation
import Testing
import LockTuneInfrastructure

@MainActor
@Test("Security-scoped folder bookmark survives store recreation")
func restoresFolderBookmark() throws {
    let suite = "app.locktune.tests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let folder = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let bookmarker = TestBookmarker()
    try SecurityScopedFolderStore(defaults: defaults, bookmarker: bookmarker).add(folder)
    let restored = try SecurityScopedFolderStore(
        defaults: defaults,
        bookmarker: bookmarker
    ).resolveAll()

    #expect(restored.map(\.standardizedFileURL) == [folder.standardizedFileURL])
}

private struct TestBookmarker: SecurityScopedBookmarking {
    func create(for url: URL) throws -> Data {
        Data(url.path.utf8)
    }

    func resolve(_ data: Data) throws -> (url: URL, isStale: Bool) {
        (URL(fileURLWithPath: String(decoding: data, as: UTF8.self)), false)
    }
}
