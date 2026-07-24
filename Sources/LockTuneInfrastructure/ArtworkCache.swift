import Foundation
import LockTuneDomain

public actor ArtworkCache {
    private let rootURL: URL

    public init(rootURL: URL? = nil) {
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.rootURL = caches.appending(path: "LockTune/Artwork", directoryHint: .isDirectory)
        }
    }

    public func persistArtwork(in track: IndexedTrack) throws -> IndexedTrack {
        guard let data = track.metadata.artworkData, !data.isEmpty else { return track }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let key = "\(track.contentFingerprint).artwork"
        try data.write(to: rootURL.appending(path: key), options: .atomic)
        var updated = track
        updated.metadata.artworkCacheKey = key
        return updated
    }

    public func data(for key: String) throws -> Data {
        try Data(contentsOf: rootURL.appending(path: key), options: .mappedIfSafe)
    }
}
