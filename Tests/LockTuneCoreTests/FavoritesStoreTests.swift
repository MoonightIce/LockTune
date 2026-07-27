import Foundation
import Testing
import LockTuneInfrastructure

@Test("Favorite track identifiers persist locally")
func favoritesRoundTrip() async throws {
    let suiteName = "LockTuneFavoritesTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    let store = FavoritesStore(suiteName: suiteName)
    let favorites: Set<UUID> = [UUID(), UUID()]

    await store.save(favorites)

    #expect(await store.load() == favorites)
    defaults.removePersistentDomain(forName: suiteName)
}
