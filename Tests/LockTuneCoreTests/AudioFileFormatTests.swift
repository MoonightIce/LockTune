import Foundation
import Testing
import LockTuneDomain

@Test("MVP audio formats are recognized case-insensitively")
func recognizesMVPFormats() {
    let examples: [(String, AudioFileFormat)] = [
        ("track.MP3", .mp3),
        ("track.aac", .aac),
        ("track.m4a", .m4a),
        ("track.FLAC", .flac),
        ("track.wav", .wav),
        ("track.APE", .ape),
    ]

    for (filename, expected) in examples {
        #expect(AudioFileFormat(url: URL(fileURLWithPath: filename)) == expected)
    }

    #expect(AudioFileFormat(url: URL(fileURLWithPath: "cover.jpg")) == nil)
}
