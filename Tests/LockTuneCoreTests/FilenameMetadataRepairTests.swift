import Foundation
import Testing
import LockTuneDomain
@testable import LockTuneInfrastructure

@Test("Filename metadata repair recognizes the MP3 naming convention")
func recognizesFilenameMetadata() {
    let url = URL(fileURLWithPath: "/Music/2018粤语 LOVE高品质/敬烟-陈奕迅_eason_and_the_duo_band.mp3")
    let metadata = TrackMetadata(title: "未知标题", artist: "�", album: "未知专辑", status: .partial)
    let suggestion = FilenameMetadataRepair.suggestion(for: url, metadata: metadata)
    #expect(FilenameMetadataRepair.needsRepair(metadata))
    #expect(suggestion.title == "敬烟")
    #expect(suggestion.artist == "陈奕迅")
    #expect(suggestion.album == "2018粤语 LOVE高品质")
}

@Test("Album and disc filenames are not mistaken for song titles")
func ignoresAlbumDiscFilename() {
    let url = URL(fileURLWithPath: "/Music/陈奕迅.-.[1997-2007.跨世纪国语精选].专辑.(APE)/陈奕迅.-.[1997-2007.跨世纪国语精选.CD1].专辑.(APE).ape")
    let metadata = TrackMetadata(artist: "陈奕迅", status: .partial)
    let suggestion = FilenameMetadataRepair.suggestion(for: url, metadata: metadata)
    #expect(suggestion.title == nil)
    #expect(suggestion.artist == nil)
}

@Test("MP3 title writer preserves the payload and existing artist")
func writesMP3TitleWithoutDroppingPayload() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).mp3")
    defer { try? FileManager.default.removeItem(at: url) }

    var body = Data()
    body.append(frame("TPE1", "陈奕迅"))
    var tag = Data("ID3".utf8)
    tag.append(contentsOf: [4, 0, 0])
    tag.append(contentsOf: synchsafe(body.count))
    tag.append(body)
    let payload = Data("AUDIO_PAYLOAD".utf8)
    try (tag + payload).write(to: url)

    try MP3TitleWriter().writeTitle("敬烟", to: url)
    let result = try Data(contentsOf: url)
    #expect(result.range(of: Data("TIT2".utf8)) != nil)
    #expect(result.range(of: Data("敬烟".utf8)) != nil)
    #expect(result.range(of: Data("TPE1".utf8)) != nil)
    #expect(result.suffix(payload.count) == payload)
}

private func frame(_ id: String, _ value: String) -> Data {
    let text = Data([3]) + Data(value.utf8)
    var frame = Data(id.utf8)
    frame.append(contentsOf: synchsafe(text.count))
    frame.append(contentsOf: [0, 0])
    frame.append(text)
    return frame
}

private func synchsafe(_ value: Int) -> [UInt8] {
    [UInt8((value >> 21) & 127), UInt8((value >> 14) & 127), UInt8((value >> 7) & 127), UInt8(value & 127)]
}
