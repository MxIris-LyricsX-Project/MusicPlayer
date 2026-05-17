import AppKit
import Foundation

public struct TrackInfo: Codable {
    public let title: String?
    public let artist: String?
    public let album: String?
    public let isPlaying: Bool?
    public let durationMicros: Double?
    public let elapsedTimeMicros: Double?
    /// `_MRNowPlayingClientProtobuf.displayName` — usually the localized name
    /// of the source app (e.g. "Music"). Useful for diagnostics; identity
    /// checks should prefer `bundleIdentifier`.
    public let applicationName: String?
    /// The source app's bundle identifier (e.g. `com.apple.Music`).
    public let bundleIdentifier: String?
    /// When the source is hosted by another app (extension, helper, embedded
    /// player), this is the parent app's bundle id; otherwise nil.
    public let parentApplicationBundleIdentifier: String?
    /// Source app's PID. Hosts can resolve it via `NSRunningApplication` to
    /// get the bundle URL, executable architecture, Info.plist, etc.
    public let processIdentifier: Int?
    public let artworkDataBase64: String?
    public let artworkMimeType: String?
    public let timestampEpochMicros: Double?
    public let uniqueIdentifier: Int?

    public var id: String {
        return "\(title ?? "")-\(artist ?? "")-\(album ?? "")"
    }
    
    public var artwork: NSImage? {
        guard let base64String = artworkDataBase64,
              let data = Data(base64Encoded: base64String)
        else {
            return nil
        }
        return NSImage(data: data)
    }

    enum CodingKeys: String, CodingKey {
        case title
        case artist
        case album
        case isPlaying
        case durationMicros
        case elapsedTimeMicros
        case applicationName
        case bundleIdentifier
        case parentApplicationBundleIdentifier
        case processIdentifier
        case artworkDataBase64
        case artworkMimeType
        case timestampEpochMicros
        case uniqueIdentifier
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.artist = try container.decodeIfPresent(String.self, forKey: .artist)
        self.album = try container.decodeIfPresent(String.self, forKey: .album)
        self.durationMicros = try container.decodeIfPresent(Double.self, forKey: .durationMicros)
        self.elapsedTimeMicros = try container.decodeIfPresent(Double.self, forKey: .elapsedTimeMicros)
        self.applicationName = try container.decodeIfPresent(String.self, forKey: .applicationName)
        self.bundleIdentifier = try container.decodeIfPresent(String.self, forKey: .bundleIdentifier)
        self.parentApplicationBundleIdentifier = try container.decodeIfPresent(String.self, forKey: .parentApplicationBundleIdentifier)
        self.processIdentifier = try container.decodeIfPresent(Int.self, forKey: .processIdentifier)
        self.artworkDataBase64 = try container.decodeIfPresent(String.self, forKey: .artworkDataBase64)
        self.artworkMimeType = try container.decodeIfPresent(String.self, forKey: .artworkMimeType)
        self.timestampEpochMicros = try container.decodeIfPresent(Double.self, forKey: .timestampEpochMicros)
        self.uniqueIdentifier = try container.decodeIfPresent(Int.self, forKey: .uniqueIdentifier)

        if let boolValue = try? container.decode(Bool.self, forKey: .isPlaying) {
            self.isPlaying = boolValue
        } else if let intValue = try? container.decode(Int.self, forKey: .isPlaying) {
            self.isPlaying = (intValue == 1)
        } else {
            self.isPlaying = nil
        }
    }
}
