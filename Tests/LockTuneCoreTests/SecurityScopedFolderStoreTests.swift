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

@MainActor
@Test("All authorized music folders can be cleared")
func clearsAllFolderBookmarks() throws {
    let suite = "app.locktune.tests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let first = URL(fileURLWithPath: "/Music/First")
    let second = URL(fileURLWithPath: "/Music/Second")
    let store = SecurityScopedFolderStore(defaults: defaults, bookmarker: TestBookmarker())
    try store.add(first)
    try store.add(second)

    store.removeAll()

    #expect(store.resolveAll().urls.isEmpty)
    #expect((defaults.array(forKey: "musicFolderBookmarks") ?? []).isEmpty)
}

@MainActor
@Test("A stale bookmark is regenerated while its folder is being accessed")
func refreshesStaleBookmarkWithinSecurityScope() throws {
    let suite = "app.locktune.tests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let renamed = URL(fileURLWithPath: "/Music/Renamed")
    defaults.set([Data("stale:\(renamed.path)".utf8)], forKey: "musicFolderBookmarks")
    let bookmarker = ScopeCheckingBookmarker()
    let store = SecurityScopedFolderStore(defaults: defaults, bookmarker: bookmarker)

    let first = store.resolveAll()
    let second = store.resolveAll()

    #expect(first.urls == [renamed])
    #expect(first.failedBookmarkCount == 0)
    #expect(bookmarker.events == [
        "start \(renamed.path)", "create \(renamed.path)", "stop \(renamed.path)",
    ])
    #expect(defaults.array(forKey: "musicFolderBookmarks") as? [Data] == [Data(renamed.path.utf8)])
    #expect(second.urls == [renamed])
    #expect(second.failedBookmarkCount == 0)
}

@MainActor
@Test("A stale bookmark that cannot be regenerated is kept, not forgotten")
func keepsStaleBookmarkWhenRefreshFails() throws {
    let suite = "app.locktune.tests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let renamed = URL(fileURLWithPath: "/Music/Renamed")
    let stale = Data("stale:\(renamed.path)".utf8)
    defaults.set([stale], forKey: "musicFolderBookmarks")
    let bookmarker = ScopeCheckingBookmarker(grantsAccess: false)
    let store = SecurityScopedFolderStore(defaults: defaults, bookmarker: bookmarker)

    let first = store.resolveAll()
    let second = store.resolveAll()

    #expect(first.urls == [renamed])
    #expect(first.failedBookmarkCount == 0)
    #expect(defaults.array(forKey: "musicFolderBookmarks") as? [Data] == [stale])
    #expect(second.urls == [renamed])
}

@MainActor
@Test("Removing a folder refreshes the remaining stale bookmarks within their scope")
func removeRefreshesRemainingStaleBookmarks() throws {
    let suite = "app.locktune.tests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let removed = URL(fileURLWithPath: "/Music/Removed")
    let renamed = URL(fileURLWithPath: "/Music/Renamed")
    defaults.set(
        [Data(removed.path.utf8), Data("stale:\(renamed.path)".utf8)],
        forKey: "musicFolderBookmarks"
    )
    let bookmarker = ScopeCheckingBookmarker()
    let store = SecurityScopedFolderStore(defaults: defaults, bookmarker: bookmarker)

    store.remove(removed)

    #expect(bookmarker.events == [
        "start \(renamed.path)", "create \(renamed.path)", "stop \(renamed.path)",
    ])
    #expect(defaults.array(forKey: "musicFolderBookmarks") as? [Data] == [Data(renamed.path.utf8)])
}

/// Mirrors the sandbox: regenerating a bookmark for a URL resolved from a
/// stale bookmark only succeeds while that URL's security scope is held.
private final class ScopeCheckingBookmarker: SecurityScopedBookmarking {
    private let grantsAccess: Bool
    private var accessing: Set<URL> = []
    private(set) var events: [String] = []

    init(grantsAccess: Bool = true) {
        self.grantsAccess = grantsAccess
    }

    func create(for url: URL) throws -> Data {
        events.append("create \(url.path)")
        guard accessing.contains(url) else { throw TestBookmarkError.noAccess }
        return Data(url.path.utf8)
    }

    func resolve(_ data: Data) throws -> (url: URL, isStale: Bool) {
        let text = String(decoding: data, as: UTF8.self)
        if text.hasPrefix("stale:") {
            return (URL(fileURLWithPath: String(text.dropFirst("stale:".count))), true)
        }
        return (URL(fileURLWithPath: text), false)
    }

    func startAccessing(_ url: URL) -> Bool {
        guard grantsAccess else { return false }
        events.append("start \(url.path)")
        accessing.insert(url)
        return true
    }

    func stopAccessing(_ url: URL) {
        events.append("stop \(url.path)")
        accessing.remove(url)
    }
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
    case noAccess
}
