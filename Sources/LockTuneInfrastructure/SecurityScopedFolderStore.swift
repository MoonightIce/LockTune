import Foundation

public protocol SecurityScopedBookmarking {
    func create(for url: URL) throws -> Data
    func resolve(_ data: Data) throws -> (url: URL, isStale: Bool)
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
        if try resolveAll().contains(where: { $0.standardizedFileURL == normalized }) { return }
        let bookmark = try bookmarker.create(for: normalized)
        var bookmarks = storedBookmarks
        bookmarks.append(bookmark)
        defaults.set(bookmarks, forKey: key)
    }

    public func resolveAll() throws -> [URL] {
        var refreshed: [Data] = []
        var urls: [URL] = []
        for bookmark in storedBookmarks {
            let resolution = try bookmarker.resolve(bookmark)
            let url = resolution.url
            urls.append(url)
            if resolution.isStale {
                refreshed.append(try bookmarker.create(for: url))
            } else {
                refreshed.append(bookmark)
            }
        }
        if refreshed != storedBookmarks {
            defaults.set(refreshed, forKey: key)
        }
        return urls
    }

    public func remove(_ url: URL) throws {
        let normalized = url.standardizedFileURL
        let retained = try zip(storedBookmarks, resolveAll()).compactMap { bookmark, resolved in
            resolved.standardizedFileURL == normalized ? nil : bookmark
        }
        defaults.set(retained, forKey: key)
    }

    private var storedBookmarks: [Data] {
        defaults.array(forKey: key) as? [Data] ?? []
    }
}
