import Foundation
import Testing
@testable import MusicPlayer

struct NetEasePlaybackProvenanceTests {
    @Test func retainsSourceWithoutRetainingPrivateArtworkPayload() throws {
        let info = MRNowPlayingInfo(dict: ["kMRMediaRemoteNowPlayingInfoTitle": "Song", "bundleIdentifier": "com.netease.163music", "kMRMediaRemoteNowPlayingInfoArtworkData": Data([1, 2])] as NSDictionary)
        let track = try #require(info.track)
        let origin = try #require(track.originalTrack as? NSDictionary)
        #expect(origin["bundleIdentifier"] as? String == "com.netease.163music")
        #expect(origin.count == 1)
    }
    @Test func unknownSourceDoesNotBecomeNetEase() throws {
        let info = MRNowPlayingInfo(dict: ["kMRMediaRemoteNowPlayingInfoTitle": "Song"] as NSDictionary)
        let track = try #require(info.track)
        #expect(track.originalTrack == nil)
    }
}
