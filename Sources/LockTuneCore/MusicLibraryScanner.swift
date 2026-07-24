import CryptoKit
import Foundation
import LockTuneDomain

public protocol AudioMetadataReading: Sendable {
    func metadata(for url: URL, format: AudioFileFormat) async -> TrackMetadata
}

public struct MusicLibraryScanner: Sendable {
    private let metadataReader: any AudioMetadataReading

    public init(metadataReader: any AudioMetadataReading) {
        self.metadataReader = metadataReader
    }

    public func scan(
        folderURLs: [URL],
        previous: MusicLibrarySnapshot = MusicLibrarySnapshot()
    ) async -> MusicLibrarySnapshot {
        var snapshot = MusicLibrarySnapshot(
            tracks: previous.tracks,
            locations: previous.locations
        )
        var tracksByFingerprint = Dictionary(
            uniqueKeysWithValues: previous.tracks.map { ($0.contentFingerprint, $0) }
        )
        var locationIDs = Set(previous.locations.map(\.id))

        for folderURL in folderURLs {
            let discovery = discoverAudioFiles(in: folderURL)
            snapshot.issues.append(contentsOf: discovery.issues)
            for (fileURL, format) in discovery.files {
                guard let fingerprint = contentFingerprint(for: fileURL) else {
                    snapshot.issues.append(MusicScanIssue(url: fileURL, reason: .unreadable))
                    continue
                }

                if let track = tracksByFingerprint[fingerprint] {
                    let location = TrackLocation(trackID: track.id, url: fileURL, format: format)
                    if locationIDs.insert(location.id).inserted {
                        snapshot.locations.append(location)
                    }
                    continue
                }

                let metadata = await metadataReader.metadata(for: fileURL, format: format)
                let track = IndexedTrack(contentFingerprint: fingerprint, metadata: metadata)
                tracksByFingerprint[fingerprint] = track
                snapshot.tracks.append(track)
                let location = TrackLocation(trackID: track.id, url: fileURL, format: format)
                locationIDs.insert(location.id)
                snapshot.locations.append(location)
            }
        }

        return snapshot
    }

    private func contentFingerprint(for url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func discoverAudioFiles(
        in folderURL: URL
    ) -> (files: [(URL, AudioFileFormat)], issues: [MusicScanIssue]) {
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isReadableKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ([], [MusicScanIssue(url: folderURL, reason: .unreadable)])
        }

        var files: [(URL, AudioFileFormat)] = []
        var issues: [MusicScanIssue] = []
        for case let fileURL as URL in enumerator {
            guard let format = AudioFileFormat(url: fileURL) else { continue }
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isReadableKey])
            guard values?.isRegularFile == true, values?.isReadable != false else {
                issues.append(MusicScanIssue(url: fileURL, reason: .unreadable))
                continue
            }
            files.append((fileURL, format))
        }
        return (files, issues)
    }
}
