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
    let restored = SecurityScopedFolderStore(
        defaults: defaults,
        bookmarker: bookmarker
    ).resolveAll()

    #expect(restored.urls.map(\.standardizedFileURL) == [folder.standardizedFileURL])
    #expect(restored.failedBookmarkCount == 0)
}

@MainActor
@Test("A damaged bookmark does not block other saved folders")
func skipsDamagedBookmark() throws {
    let suite = "app.locktune.tests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let folder = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defaults.set([Data("damaged".utf8), Data(folder.path.utf8)], forKey: "musicFolderBookmarks")

    let store = SecurityScopedFolderStore(defaults: defaults, bookmarker: TestBookmarker())
    let first = store.resolveAll()
    let second = store.resolveAll()

    #expect(first.urls.map(\.standardizedFileURL.path) == [folder.standardizedFileURL.path])
    #expect(first.failedBookmarkCount == 1)
    #expect(second.urls.map(\.standardizedFileURL.path) == [folder.standardizedFileURL.path])
    #expect(second.failedBookmarkCount == 0)
}

private struct TestBookmarker: SecurityScopedBookmarking {
    func create(for url: URL) throws -> Data {
        Data(url.path.utf8)
    }

    func resolve(_ data: Data) throws -> (url: URL, isStale: Bool) {
        if data == Data("damaged".utf8) { throw TestBookmarkError.damaged }
        return (URL(fileURLWithPath: String(decoding: data, as: UTF8.self)), false)
    }
}

private enum TestBookmarkError: Error {
    case damaged
}
