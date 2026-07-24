import Foundation
import Testing
import LockTuneCore
import LockTuneDomain
import LockTuneInfrastructure

@Test("Scanner finds supported files and preserves partial metadata state")
func scansSupportedFiles() async throws {
    let folder = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    try Data("audio".utf8).write(to: folder.appending(path: "First.MP3"))
    try Data("image".utf8).write(to: folder.appending(path: "cover.jpg"))

    let scanner = MusicLibraryScanner(metadataReader: FixedMetadataReader())
    let snapshot = await scanner.scan(folderURLs: [folder])

    #expect(snapshot.tracks.count == 1)
    #expect(snapshot.locations.count == 1)
    #expect(snapshot.tracks.first?.metadata.title == "First")
    #expect(snapshot.tracks.first?.metadata.status == .partial)
    #expect(snapshot.issues.isEmpty)
}

@Test("Exact duplicate files share one track and retain both locations")
func deduplicatesExactFileContent() async throws {
    let folder = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let bytes = Data("same audio bytes".utf8)
    try bytes.write(to: folder.appending(path: "First.mp3"))
    try bytes.write(to: folder.appending(path: "Copy.mp3"))

    let scanner = MusicLibraryScanner(metadataReader: FixedMetadataReader())
    let snapshot = await scanner.scan(folderURLs: [folder])

    #expect(snapshot.tracks.count == 1)
    #expect(snapshot.locations.count == 2)
    #expect(Set(snapshot.locations.map(\.trackID)).count == 1)
}

@Test("Incremental scan reuses existing tracks and locations")
func reusesPreviousSnapshot() async throws {
    let folder = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try Data("stable audio".utf8).write(to: folder.appending(path: "Stable.flac"))

    let scanner = MusicLibraryScanner(metadataReader: FixedMetadataReader())
    let first = await scanner.scan(folderURLs: [folder])
    let second = await scanner.scan(folderURLs: [folder], previous: first)

    #expect(second.tracks.count == 1)
    #expect(second.locations.count == 1)
    #expect(second.tracks.first?.id == first.tracks.first?.id)
    #expect(second.locations.first?.id == first.locations.first?.id)
}

@Test("Changed content at the same location replaces the old track")
func replacesChangedLocation() async throws {
    let folder = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appending(path: "Changed.flac")
    try Data("first".utf8).write(to: file)

    let scanner = MusicLibraryScanner(metadataReader: FixedMetadataReader())
    let first = await scanner.scan(folderURLs: [folder])
    try Data("second version".utf8).write(to: file)
    let second = await scanner.scan(folderURLs: [folder], previous: first)

    #expect(second.tracks.count == 1)
    #expect(second.locations.count == 1)
    #expect(second.tracks.first?.id != first.tracks.first?.id)
    #expect(second.locations.first?.trackID == second.tracks.first?.id)
}

@Test("Unreadable metadata is retained as an explicit scan issue")
func reportsUnavailableMetadata() async throws {
    let folder = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try Data("not valid audio".utf8).write(to: folder.appending(path: "Broken.ape"))

    let scanner = MusicLibraryScanner(metadataReader: UnavailableMetadataReader())
    let snapshot = await scanner.scan(folderURLs: [folder])

    #expect(snapshot.tracks.count == 1)
    #expect(snapshot.locations.count == 1)
    #expect(snapshot.issues.map(\.reason) == [.metadataUnavailable])
}

@Test("Incremental scan retains unavailable metadata issues for unchanged files")
func retainsUnavailableMetadataIssueDuringIncrementalScan() async throws {
    let folder = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try Data("not valid audio".utf8).write(to: folder.appending(path: "Broken.ape"))

    let scanner = MusicLibraryScanner(metadataReader: UnavailableMetadataReader())
    let first = await scanner.scan(folderURLs: [folder])
    let second = await scanner.scan(folderURLs: [folder], previous: first)

    #expect(second.tracks.first?.id == first.tracks.first?.id)
    #expect(second.issues.map(\.reason) == [.metadataUnavailable])
}

@Test("Known non-MVP audio files are reported as unsupported")
func reportsUnsupportedAudioFormat() async throws {
    let folder = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try Data("audio".utf8).write(to: folder.appending(path: "Unsupported.ogg"))
    try Data("image".utf8).write(to: folder.appending(path: "cover.jpg"))

    let snapshot = await MusicLibraryScanner(metadataReader: FixedMetadataReader())
        .scan(folderURLs: [folder])

    #expect(snapshot.tracks.isEmpty)
    #expect(snapshot.issues.map(\.reason) == [.unsupportedFormat])
}

@Test("Authorized real library completes full and incremental scans")
func scansAuthorizedRealLibrary() async throws {
    guard let path = ProcessInfo.processInfo.environment["LOCKTUNE_REAL_MUSIC_PATH"] else { return }
    let folder = URL(fileURLWithPath: path)
    let expectedLocationCount = countSupportedFiles(in: folder)
    let scanner = MusicLibraryScanner(metadataReader: SystemAudioMetadataReader())

    let first = await scanner.scan(folderURLs: [folder])
    let second = await scanner.scan(folderURLs: [folder], previous: first)

    #expect(first.locations.count == expectedLocationCount)
    #expect(first.tracks.count > 0)
    #expect(first.tracks.count <= first.locations.count)
    #expect(Set(first.locations.map(\.format)).isSuperset(of: [.mp3, .m4a, .flac, .ape]))
    #expect(second.tracks.map(\.id).sorted(by: uuidOrder) == first.tracks.map(\.id).sorted(by: uuidOrder))
    #expect(second.locations.map(\.id).sorted() == first.locations.map(\.id).sorted())
}

private func countSupportedFiles(in folder: URL) -> Int {
    guard let enumerator = FileManager.default.enumerator(
        at: folder,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else { return 0 }
    return enumerator.compactMap { $0 as? URL }.filter { AudioFileFormat(url: $0) != nil }.count
}

private func uuidOrder(_ lhs: UUID, _ rhs: UUID) -> Bool {
    lhs.uuidString < rhs.uuidString
}

private struct FixedMetadataReader: AudioMetadataReading {
    func metadata(for url: URL, format: AudioFileFormat) async -> TrackMetadata {
        TrackMetadata(title: "First", status: .partial)
    }
}

private struct UnavailableMetadataReader: AudioMetadataReading {
    func metadata(for url: URL, format: AudioFileFormat) async -> TrackMetadata {
        TrackMetadata(status: .unavailable)
    }
}
