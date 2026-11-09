import Foundation

public protocol SecurityScopedBookmarking {
    func create(for url: URL) throws -> Data
    func resolve(_ data: Data) throws -> (url: URL, isStale: Bool)
    func startAccessing(_ url: URL) -> Bool
    func stopAccessing(_ url: URL)
}

public extension SecurityScopedBookmarking {
    func startAccessing(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}

public struct SystemSecurityScopedBookmarking: SecurityScopedBookmarking {
    public init() {}

    public func create(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    public func resolve(_ data: Data) throws -> (url: URL, isStale: Bool) {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return (url, isStale)
    }
}

public struct SecurityScopedFolderResolution: Equatable, Sendable {
    public let urls: [URL]
    public let failedBookmarkCount: Int

    public init(urls: [URL], failedBookmarkCount: Int) {
        self.urls = urls
        self.failedBookmarkCount = failedBookmarkCount
    }
}

@MainActor
public final class SecurityScopedFolderStore {
    private let defaults: UserDefaults
    private let key: String
    private let bookmarker: any SecurityScopedBookmarking

    public init(
        defaults: UserDefaults = .standard,
        key: String = "musicFolderBookmarks",
        bookmarker: any SecurityScopedBookmarking = SystemSecurityScopedBookmarking()
    ) {
        self.defaults = defaults
        self.key = key
        self.bookmarker = bookmarker
    }

    public func add(_ url: URL) throws {
        let normalized = url.standardizedFileURL
        if resolveAll().urls.contains(where: { $0.standardizedFileURL == normalized }) { return }
        let bookmark = try bookmarker.create(for: normalized)
        var bookmarks = storedBookmarks
        bookmarks.append(bookmark)
        defaults.set(bookmarks, forKey: key)
    }

    public func resolveAll() -> SecurityScopedFolderResolution {
        var refreshed: [Data] = []
        var urls: [URL] = []
        var failedBookmarkCount = 0
        for bookmark in storedBookmarks {
            do {
                let resolution = try bookmarker.resolve(bookmark)
                urls.append(resolution.url)
                refreshed.append(current(bookmark, resolution))
            } catch {
                failedBookmarkCount += 1
            }
        }
        if refreshed != storedBookmarks {
            defaults.set(refreshed, forKey: key)
        }
        return SecurityScopedFolderResolution(
            urls: urls,
            failedBookmarkCount: failedBookmarkCount
        )
    }

    public func remove(_ url: URL) {
        let normalized = url.standardizedFileURL
        let retained = storedBookmarks.compactMap { bookmark -> Data? in
            guard let resolution = try? bookmarker.resolve(bookmark),
                  resolution.url.standardizedFileURL != normalized
            else { return nil }
            return current(bookmark, resolution)
        }
        defaults.set(retained, forKey: key)
    }

    public func removeAll() {
        defaults.removeObject(forKey: key)
    }

    /// Returns the bookmark to keep for a resolved folder. A stale bookmark
    /// (folder renamed or moved) is regenerated, which the sandbox only allows
    /// while the resolved URL's security scope is held. If regeneration still
    /// fails, the stale bookmark is kept: it keeps resolving, so dropping it
    /// would silently forget the folder on the next launch.
    private func current(
        _ bookmark: Data,
        _ resolution: (url: URL, isStale: Bool)
    ) -> Data {
        guard resolution.isStale else { return bookmark }
        let accessing = bookmarker.startAccessing(resolution.url)
        defer { if accessing { bookmarker.stopAccessing(resolution.url) } }
        return (try? bookmarker.create(for: resolution.url)) ?? bookmark
    }

    private var storedBookmarks: [Data] {
        defaults.array(forKey: key) as? [Data] ?? []
    }
}
