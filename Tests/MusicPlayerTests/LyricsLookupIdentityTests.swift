import Foundation
import Testing
import Combine
@testable import MusicPlayer

struct LyricsLookupIdentityTests {
    private func track(album: String? = "sup", duration: Double? = 264.594, source: String = "com.netease.163music") -> MusicTrack {
        MusicTrack(id: "same-id", title: "杀死忍者", album: album, artist: "AKA小予", duration: duration,
                   originalTrack: NSDictionary(dictionary: ["bundleIdentifier": source]))
    }
    @Test func completedMetadataMustRestartLookup() {
        var events = 0
        let token = [track(album: nil, duration: nil), track()].publisher
            .removeDuplicates(by: { $0.hasSameLyricsLookupIdentity(as: $1) }).sink { _ in events += 1 }
        #expect(events == 2)
        withExtendedLifetime(token) {}
    }
    @Test func sourceAndAlbumUpdatesMustRestartLookup() {
        #expect(!track().hasSameLyricsLookupIdentity(as: track(source: "com.spotify.client")))
        #expect(!track().hasSameLyricsLookupIdentity(as: track(album: "Live")))
        #expect(!track().hasSameLyricsLookupIdentity(as: track(duration: nil)))
    }
    @Test func identicalMetadataKeepsExistingLookup() {
        #expect(track().hasSameLyricsLookupIdentity(as: track()))
        var unrelated = track()
        unrelated.originalTrack = NSDictionary(dictionary: ["bundleIdentifier": "com.netease.163music", "artwork": "changed"])
        #expect(track().hasSameLyricsLookupIdentity(as: unrelated))
    }

}
