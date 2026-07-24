import Foundation
import Testing
import LockTuneCore
import LockTuneDomain

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

private struct FixedMetadataReader: AudioMetadataReading {
    func metadata(for url: URL, format: AudioFileFormat) async -> TrackMetadata {
        TrackMetadata(title: "First", status: .partial)
    }
}
