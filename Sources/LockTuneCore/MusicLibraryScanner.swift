import CryptoKit
import Foundation
import LockTuneDomain

public protocol AudioMetadataReading: Sendable {
    func metadata(for url: URL, format: AudioFileFormat) async -> TrackMetadata
}

public extension MusicLibrarySnapshot {
    func retainingAuthorizedRoots(_ roots: [URL]) -> MusicLibrarySnapshot {
        let normalizedRoots = roots.map(\.standardizedFileURL)
        let retainedLocations = locations.filter {
            Self.isInside($0.url, roots: normalizedRoots)
        }
        let retainedTrackIDs = Set(retainedLocations.map(\.trackID))
        let retainedIssues = issues.filter {
            Self.isInside($0.url, roots: normalizedRoots)
        }
        var state = scanState
        if normalizedRoots.isEmpty {
            state.lastCompletedAt = nil
        }
        return MusicLibrarySnapshot(
            tracks: tracks.filter { retainedTrackIDs.contains($0.id) },
            locations: retainedLocations,
            issues: retainedIssues,
            scanState: state
        )
    }

    private static func isInside(_ url: URL, roots: [URL]) -> Bool {
        let path = url.standardizedFileURL.path
        return roots.contains { path == $0.path || path.hasPrefix($0.path + "/") }
    }
}

public actor MusicLibraryScanner {
    private let metadataReader: any AudioMetadataReading

    public init(metadataReader: any AudioMetadataReading) {
        self.metadataReader = metadataReader
    }

    public func scan(
        folderURLs: [URL],
        previous: MusicLibrarySnapshot = MusicLibrarySnapshot(),
        progressMinimumInterval: Duration = .milliseconds(120),
        progress: (@Sendable (MusicScanProgress) async -> Void)? = nil
    ) async -> MusicLibrarySnapshot {
        var progressPublisher = MusicScanProgressPublisher(
            minimumInterval: progressMinimumInterval,
            callback: progress
        )
        let roots = folderURLs.map(\.standardizedFileURL)
        let previousTracksByID = Dictionary(uniqueKeysWithValues: previous.tracks.map { ($0.id, $0) })
        let previousLocationsByID = Dictionary(uniqueKeysWithValues: previous.locations.map { ($0.id, $0) })
        let retainedLocations = previous.locations.filter { !isInside($0.url, roots: roots) }
        let retainedTrackIDs = Set(retainedLocations.map(\.trackID))
        var snapshot = MusicLibrarySnapshot(
            tracks: previous.tracks.filter { retainedTrackIDs.contains($0.id) },
            locations: retainedLocations,
            issues: previous.issues.filter { !isInside($0.url, roots: roots) },
            scanState: previous.scanState
        )
        var tracksByFingerprint = Dictionary(
            uniqueKeysWithValues: previous.tracks.map { ($0.contentFingerprint, $0) }
        )
        var includedTrackIDs = Set(snapshot.tracks.map(\.id))
        var processedLocationIDs = Set(snapshot.locations.map(\.id))
        var discoveredFiles: [DiscoveredAudioFile] = []

        await progressPublisher.publish(MusicScanProgress(
            phase: .discovering,
            completed: 0,
            total: folderURLs.count
        ), force: true)
        for (folderIndex, folderURL) in folderURLs.enumerated() {
            guard !Task.isCancelled else { return snapshot }
            let discovery = discoverAudioFiles(in: folderURL)
            snapshot.issues.append(contentsOf: discovery.issues)
            discoveredFiles.append(contentsOf: discovery.files)
            await progressPublisher.publish(MusicScanProgress(
                phase: .discovering,
                completed: folderIndex + 1,
                total: folderURLs.count
            ), force: folderIndex + 1 == folderURLs.count)
        }

        let uniqueFiles = discoveredFiles.filter { processedLocationIDs.insert($0.id).inserted }
        await progressPublisher.publish(
            MusicScanProgress(phase: .indexing, completed: 0, total: uniqueFiles.count),
            force: true
        )
        for (fileIndex, file) in uniqueFiles.enumerated() {
            guard !Task.isCancelled else { return snapshot }
            if let existingLocation = previousLocationsByID[file.id],
               existingLocation.fileSize == file.fileSize,
               existingLocation.contentModificationDate == file.contentModificationDate,
               let existingTrack = previousTracksByID[existingLocation.trackID] {
                append(
                    existingTrack,
                    at: existingLocation,
                    issueURL: file.url,
                    to: &snapshot,
                    includedTrackIDs: &includedTrackIDs
                )
            } else {
                let fileURL = file.url
                let format = file.format
                if let fingerprint = contentFingerprint(for: fileURL) {
                    if let track = tracksByFingerprint[fingerprint] {
                        append(
                            track,
                            at: file.location(trackID: track.id),
                            issueURL: fileURL,
                            to: &snapshot,
                            includedTrackIDs: &includedTrackIDs
                        )
                    } else {
                        let metadata = await metadataReader.metadata(for: fileURL, format: format)
                        if metadata.status == .unavailable {
                            snapshot.issues.append(MusicScanIssue(
                                url: fileURL,
                                reason: .metadataUnavailable
                            ))
                        }
                        let track = Track(contentFingerprint: fingerprint, metadata: metadata)
                        tracksByFingerprint[fingerprint] = track
                        includedTrackIDs.insert(track.id)
                        snapshot.tracks.append(track)
                        snapshot.locations.append(file.location(trackID: track.id))
                    }
                } else {
                    snapshot.issues.append(MusicScanIssue(url: fileURL, reason: .unreadable))
                }
            }
            await progressPublisher.publish(MusicScanProgress(
                phase: .indexing,
                completed: fileIndex + 1,
                total: uniqueFiles.count
            ), force: fileIndex + 1 == uniqueFiles.count)
        }

        return snapshot
    }

    private func append(
        _ track: Track,
        at location: TrackLocation,
        issueURL: URL,
        to snapshot: inout MusicLibrarySnapshot,
        includedTrackIDs: inout Set<UUID>
    ) {
        if includedTrackIDs.insert(track.id).inserted {
            snapshot.tracks.append(track)
        }
        snapshot.locations.append(location)
        if track.metadata.status == .unavailable {
            snapshot.issues.append(MusicScanIssue(url: issueURL, reason: .metadataUnavailable))
        }
    }

    private func contentFingerprint(for url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var digest = SHA256()
        do {
            while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
                guard !Task.isCancelled else { return nil }
                digest.update(data: chunk)
            }
        } catch {
            return nil
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func discoverAudioFiles(
        in folderURL: URL
    ) -> (files: [DiscoveredAudioFile], issues: [MusicScanIssue]) {
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isReadableKey,
                .fileSizeKey,
                .contentModificationDateKey,
            ],
            options: [.skipsHiddenFiles]
        ) else {
            return ([], [MusicScanIssue(url: folderURL, reason: .unreadable)])
        }

        var files: [DiscoveredAudioFile] = []
        var issues: [MusicScanIssue] = []
        for case let fileURL as URL in enumerator {
            guard !Task.isCancelled else { break }
            guard let format = AudioFileFormat(url: fileURL) else {
                if knownUnsupportedAudioExtensions.contains(fileURL.pathExtension.lowercased()) {
                    issues.append(MusicScanIssue(url: fileURL, reason: .unsupportedFormat))
                }
                continue
            }
            let values = try? fileURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .isReadableKey,
                .fileSizeKey,
                .contentModificationDateKey,
            ])
            guard values?.isRegularFile == true, values?.isReadable != false else {
                issues.append(MusicScanIssue(url: fileURL, reason: .unreadable))
                continue
            }
            files.append(DiscoveredAudioFile(
                url: fileURL,
                format: format,
                fileSize: values?.fileSize.map(Int64.init),
                contentModificationDate: values?.contentModificationDate
            ))
        }
        return (files, issues)
    }

    private func isInside(_ url: URL, roots: [URL]) -> Bool {
        let path = url.standardizedFileURL.path
        return roots.contains { path == $0.path || path.hasPrefix($0.path + "/") }
    }

    private var knownUnsupportedAudioExtensions: Set<String> {
        ["aif", "aiff", "alac", "m4b", "mka", "mpc", "ogg", "oga", "opus", "tta", "wavpack", "wma", "wv"]
    }
}

private struct MusicScanProgressPublisher {
    let minimumInterval: Duration
    let callback: (@Sendable (MusicScanProgress) async -> Void)?
    private var lastPublishedAt: ContinuousClock.Instant?

    init(
        minimumInterval: Duration,
        callback: (@Sendable (MusicScanProgress) async -> Void)?
    ) {
        self.minimumInterval = minimumInterval
        self.callback = callback
    }

    mutating func publish(_ progress: MusicScanProgress, force: Bool) async {
        guard let callback else { return }
        let now = ContinuousClock.now
        if !force,
           let lastPublishedAt,
           lastPublishedAt.duration(to: now) < minimumInterval {
            return
        }
        self.lastPublishedAt = now
        await callback(progress)
    }
}

private struct DiscoveredAudioFile {
    let url: URL
    let format: AudioFileFormat
    let fileSize: Int64?
    let contentModificationDate: Date?

    var id: String { url.standardizedFileURL.path }

    func location(trackID: UUID) -> TrackLocation {
        TrackLocation(
            trackID: trackID,
            url: url,
            format: format,
            fileSize: fileSize,
            contentModificationDate: contentModificationDate
        )
    }
}
