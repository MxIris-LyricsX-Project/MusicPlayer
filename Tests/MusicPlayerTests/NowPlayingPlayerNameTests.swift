import Foundation
import Testing
@testable import MusicPlayer

/// `SystemMedia` reports the player its current track plays in, read from
/// the now-playing info's source app. A host uses it to tell, for instance,
/// that the system-wide now-playing track is playing in Music.
@Suite("The player a system now-playing track plays in")
struct NowPlayingPlayerNameTests {

    @Test("Music's bundle identifiers name the Apple Music player", arguments: [
        "com.apple.Music",
        "com.apple.iTunes",
    ])
    func musicApplication(bundleIdentifier: String) {
        #expect(MusicPlayerName(bundleIdentifier: bundleIdentifier) == .appleMusic)
    }

    @Test("another known player's app is named after that player")
    func otherKnownPlayer() {
        #expect(MusicPlayerName(bundleIdentifier: "com.spotify.client") == .spotify)
    }

    @Test("an app that is not a known player has no player name", arguments: [
        "com.apple.Safari",
        "com.netease.163music",
        "",
    ])
    func unknownApplication(bundleIdentifier: String) {
        #expect(MusicPlayerName(bundleIdentifier: bundleIdentifier) == nil)
    }

    @Test("a track the adapter reports from Music plays in Apple Music")
    func adapterTrackFromMusic() {
        let info = MRNowPlayingInfo(dict: [
            "kMRMediaRemoteNowPlayingInfoTitle": "芒种",
            "bundleIdentifier": "com.apple.Music",
        ])
        #expect(info.playerName == .appleMusic)
    }

    @Test("a hosted now-playing client is attributed to its parent app")
    func parentApplicationWins() {
        let hostedByMusic = MRNowPlayingInfo(dict: [
            "bundleIdentifier": "com.apple.Music.helper",
            "parentApplicationBundleIdentifier": "com.apple.Music",
        ])
        let hostedBySafari = MRNowPlayingInfo(dict: [
            "bundleIdentifier": "com.apple.Music",
            "parentApplicationBundleIdentifier": "com.apple.Safari",
        ])
        #expect(hostedByMusic.playerName == .appleMusic)
        #expect(hostedBySafari.playerName == nil)
    }

    @Test("a track whose source app is not reported has no player name")
    func missingSourceApplication() {
        let info = MRNowPlayingInfo(dict: ["kMRMediaRemoteNowPlayingInfoTitle": "芒种"])
        #expect(info.playerName == nil)
    }

    @Test("info read through MediaRemote directly carries the now-playing client's app")
    func directMediaRemoteInfo() {
        let info = MRNowPlayingInfo(
            dict: ["kMRMediaRemoteNowPlayingInfoTitle": "芒种"],
            bundleIdentifier: "com.apple.Music",
            parentApplicationBundleIdentifier: nil
        )
        #expect(info.playerName == .appleMusic)
        #expect(info._title == "芒种")
    }
}
