import Foundation

public actor FavoritesStore {
    private let defaults: UserDefaults
    private let key: String

    public init(suiteName: String? = nil, key: String = "music.favoriteTrackIDs") {
        defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        self.key = key
    }

    public func load() -> Set<UUID> {
        Set((defaults.stringArray(forKey: key) ?? []).compactMap(UUID.init(uuidString:)))
    }

    public func save(_ trackIDs: Set<UUID>) {
        defaults.set(trackIDs.map(\.uuidString).sorted(), forKey: key)
    }
}
