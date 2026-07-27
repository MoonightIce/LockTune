import AVFoundation
import Foundation
import LockTuneCore
import LockTuneDomain

public struct SystemAudioMetadataReader: AudioMetadataReading {
    public init() {}

    public func metadata(for url: URL, format: AudioFileFormat) async -> TrackMetadata {
        if format == .ape {
            return APEMetadataParser.parse(url: url)
        }
        return await readAVFoundationMetadata(url: url)
    }

    private func readAVFoundationMetadata(url: URL) async -> TrackMetadata {
        let asset = AVURLAsset(url: url)
        guard let items = try? await asset.load(.commonMetadata) else {
            return TrackMetadata(status: .unavailable)
        }
        let duration = try? await asset.load(.duration)
        let formats = (try? await asset.load(.availableMetadataFormats)) ?? []
        var allItems = items
        for format in formats {
            if let formatItems = try? await asset.loadMetadata(for: format) {
                allItems.append(contentsOf: formatItems)
            }
        }
        var title: String?
        var artist: String?
        var album: String?
        var artwork: Data?

        for item in allItems {
            switch item.commonKey?.rawValue {
            case "title" where title == nil: title = try? await item.load(.stringValue)
            case "artist" where artist == nil: artist = try? await item.load(.stringValue)
            case "albumName" where album == nil: album = try? await item.load(.stringValue)
            case "artwork" where artwork == nil: artwork = try? await item.load(.dataValue)
            default: break
            }
        }
        let trackNumber = await trackNumber(in: allItems)

        let seconds = duration.map(CMTimeGetSeconds).flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        return TrackMetadata(
            title: title,
            artist: artist,
            album: album,
            trackNumber: trackNumber,
            duration: seconds,
            artworkData: artwork,
            status: metadataStatus(
                title: title,
                artist: artist,
                album: album,
                trackNumber: trackNumber,
                duration: seconds,
                artwork: artwork
            )
        )
    }

    private func trackNumber(in items: [AVMetadataItem]) async -> Int? {
        for item in items {
            let identifier = item.identifier?.rawValue.lowercased() ?? ""
            guard identifier.contains("track") || identifier.contains("trck") || identifier.contains("trkn")
            else { continue }
            if let string = try? await item.load(.stringValue),
               let first = string.split(separator: "/").first,
               let number = Int(first.trimmingCharacters(in: .whitespaces)) {
                return number
            }
            if let data = try? await item.load(.dataValue), data.count >= 4 {
                let bytes = [UInt8](data)
                let number = Int(bytes[2]) << 8 | Int(bytes[3])
                if number > 0 { return number }
            }
        }
        return nil
    }
}

func metadataStatus(
    title: String?,
    artist: String?,
    album: String?,
    trackNumber: Int?,
    duration: TimeInterval?,
    artwork: Data?
) -> MetadataStatus {
    let values: [Any?] = [title, artist, album, trackNumber, duration, artwork]
    if values.allSatisfy({ $0 != nil }) { return .complete }
    if values.contains(where: { $0 != nil }) { return .partial }
    return .unavailable
}
