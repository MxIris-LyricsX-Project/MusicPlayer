#if os(macOS) || os(iOS)

import Foundation

#if os(macOS)
import AppKit
#endif

#if canImport(MediaRemoteAdapter)
import MediaRemoteAdapter

extension TrackInfo {
    var asDictionary: NSDictionary {
        let result: NSMutableDictionary = [:]
        result["kMRMediaRemoteNowPlayingInfoTitle"] = title
        result["kMRMediaRemoteNowPlayingInfoAlbum"] = album
        result["kMRMediaRemoteNowPlayingInfoArtist"] = artist
        result["kMRMediaRemoteNowPlayingInfoTimestamp"] = timestampEpochMicros.map { Date(timeIntervalSince1970: $0 / 1000 / 1000) }
        result["kMRMediaRemoteNowPlayingInfoElapsedTime"] = elapsedTimeMicros.map { $0 / 1000 / 1000 }
        result["kMRMediaRemoteNowPlayingInfoArtworkData"] = artworkDataBase64.flatMap { Data(base64Encoded: $0) }
        result["kMRMediaRemoteNowPlayingInfoUniqueIdentifier"] = uniqueIdentifier
        result["kMRMediaRemoteNowPlayingInfoDuration"] = durationMicros.map { $0 / 1000 / 1000 }
        // Source-app identity (added by the adapter, not part of MediaRemote's
        // canonical NowPlayingInfo schema). Carried through so MRNowPlayingInfo
        // can resolve `NSRunningApplication` and detect iOS-on-Mac apps.
        result["bundleIdentifier"] = bundleIdentifier
        result["parentApplicationBundleIdentifier"] = parentApplicationBundleIdentifier
        result["processIdentifier"] = processIdentifier
        result["applicationName"] = applicationName
        return result
    }
}
#endif

struct MRNowPlayingInfo {
    var dict: NSDictionary

    init(dict: NSDictionary) {
        self.dict = dict
    }

    private subscript<T>(key: String) -> T? {
        return dict.value(forKey: key) as? T
    }

    var _timestamp: Date? {
        return self["kMRMediaRemoteNowPlayingInfoTimestamp"]
    }

    var _elapsedTime: TimeInterval? {
        return self["kMRMediaRemoteNowPlayingInfoElapsedTime"]
    }

    var _startTime: Date? {
        return self["kMRMediaRemoteNowPlayingInfoStartTime"]
    }

    var _uniqueIdentifier: Int? {
        return self["kMRMediaRemoteNowPlayingInfoUniqueIdentifier"]
    }

    var _title: String? {
        return self["kMRMediaRemoteNowPlayingInfoTitle"]
    }

    var _album: String? {
        return self["kMRMediaRemoteNowPlayingInfoAlbum"]
    }

    var _artist: String? {
        return self["kMRMediaRemoteNowPlayingInfoArtist"]
    }

    var _duration: TimeInterval? {
        let value: TimeInterval? = self["kMRMediaRemoteNowPlayingInfoDuration"]
        guard let value, value.isFinite else { return nil }
        return value
    }

    var _artworkData: Data? {
        return self["kMRMediaRemoteNowPlayingInfoArtworkData"]
    }

    /// Source-app identity carried in the dictionary by the adapter (not part
    /// of the canonical MediaRemote NowPlayingInfo schema). Available iff the
    /// payload originated from `mediaremote-adapter`.
    var _bundleIdentifier: String? {
        return self["bundleIdentifier"]
    }

    var _parentApplicationBundleIdentifier: String? {
        return self["parentApplicationBundleIdentifier"]
    }

    var _processIdentifier: Int? {
        return self["processIdentifier"]
    }

    var _applicationName: String? {
        return self["applicationName"]
    }

    #if os(macOS)
    /// `NSRunningApplication` for the source app's process, if it can be
    /// resolved from the reported PID. Provides bundleURL, executable arch,
    /// active state, etc.
    var clientRunningApplication: NSRunningApplication? {
        guard let pid = _processIdentifier else { return nil }
        return NSRunningApplication(processIdentifier: pid_t(pid))
    }

    /// Bundle URL of the source app, e.g. `/Applications/Music.app` or
    /// `~/Applications/<iOS app>.app` for iOS apps running on Mac.
    var clientBundleURL: URL? {
        return clientRunningApplication?.bundleURL
    }

    /// Whether the source app is an iOS-on-Mac app. Backed by reading the
    /// Mach-O `LC_BUILD_VERSION.platform` field of the source process's
    /// executable (see `MediaController.isiOSAppOnMac`).
    var isiOSAppOnMac: Bool {
        return MediaController.isiOSAppOnMac(runningApp: clientRunningApplication)
    }
    #endif

    /// Real (title, artist) after applying the iOS-on-Mac em-dash recovery.
    /// Native macOS sources pass through unchanged. Used by both `id` and
    /// `track`, so an iOS-on-Mac app that abuses one field as a per-lyric-
    /// line ticker still produces a stable id keyed on the recovered values.
    private var resolvedTitleArtist: (title: String?, artist: String?) {
        #if os(macOS)
        if isiOSAppOnMac {
            let recovered = Self.recoverTitleArtist(rawTitle: _title, rawArtist: _artist)
            return (recovered.title, recovered.artist)
        }
        #endif
        return (_title, _artist)
    }

    var id: String? {
        if let uniqueIdentifier = _uniqueIdentifier {
            return uniqueIdentifier.description
        }
        #if os(macOS)
        if isiOSAppOnMac {
            // iOS-on-Mac apps that lack `kMRMediaRemoteNowPlayingInfoUniqueIdentifier`
            // (e.g. QQMusic) rotate a lyric ticker through the title field.
            // Keying on recovered title + artist pulls the stable song name
            // from the em-dash field instead, with album as final discriminator.
            let resolved = resolvedTitleArtist
            guard let title = resolved.title else { return nil }
            var components: [String] = ["NowPlaying", title]
            if let artist = resolved.artist { components.append(artist) }
            if let album = _album { components.append(album) }
            return components.joined(separator: "-")
        }
        #endif
        guard let title = _title else {
            return nil
        }
        return "NowPlaying-\(title)\(_album.map { "-\($0)" } ?? "")"
    }

    var startTime: Date? {
        if let _elapsedTime = _elapsedTime {
            if let _timestamp = _timestamp {
                return _timestamp.addingTimeInterval(-_elapsedTime)
            } else {
                return Date(timeIntervalSinceNow: -_elapsedTime)
            }
        } else {
            return nil
        }
    }

    var artwork: Image? {
        guard let artworkData = _artworkData else {
            return nil
        }
        return Image(data: artworkData)
    }

    /// Some iOS apps running on Mac (e.g. iOS-on-Mac builds of music apps that
    /// were never designed for the macOS NowPlaying widget's two-line layout)
    /// abuse the NowPlayingInfo dictionary in two related ways:
    ///
    /// 1. The "real" title and artist are packed into a single field, separated
    ///    by " — " (U+2014 with surrounding spaces), e.g.
    ///    `kMRMediaRemoteNowPlayingInfoTitle = "Animals — Maroon 5"`.
    ///    This is to make the iOS lock-screen single-line render look right.
    ///
    /// 2. The other field (whichever one isn't carrying "song — artist") is
    ///    then reused as a per-lyric-line ticker, updated every time the
    ///    current lyric advances. Which field carries which is observed to
    ///    flip between apps, so we can't hard-code one assignment.
    ///
    /// This helper recovers the real title/artist while leaving compliant apps
    /// (no " — " present) untouched.
    private static let emDashSeparator = " \u{2014} "  // " — "

    private static func splitOnEmDash(_ value: String?) -> (title: String, artist: String)? {
        guard let value = value, let range = value.range(of: emDashSeparator) else { return nil }
        let title = String(value[..<range.lowerBound])
        let artist = String(value[range.upperBound...])
        guard !title.isEmpty, !artist.isEmpty else { return nil }
        return (title, artist)
    }

    private static func recoverTitleArtist(rawTitle: String?, rawArtist: String?) -> (title: String?, artist: String?) {
        // Whichever field carries the " — " separator wins; the other field
        // is presumed to be a lyric ticker and is dropped. Both modes covered.
        if let split = splitOnEmDash(rawTitle) {
            return (split.title, split.artist)
        }
        if let split = splitOnEmDash(rawArtist) {
            return (split.title, split.artist)
        }
        return (rawTitle, rawArtist)
    }

    var track: MusicTrack? {
        guard let id = id else {
            return nil
        }
        let resolved = resolvedTitleArtist
        return MusicTrack(id: id, title: resolved.title, album: _album, artist: resolved.artist, duration: _duration, fileURL: nil, artwork: artwork, originalTrack: nil)
    }
}

#endif
