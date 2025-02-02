//
//  MediaRemoteHelper.swift
//  LyricsX - https://github.com/ddddxxx/LyricsX
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

#if os(macOS) || os(iOS)

import Foundation

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
        return self["kMRMediaRemoteNowPlayingInfoDuration"]
    }
    
    var _artworkData: Data? {
        return self["kMRMediaRemoteNowPlayingInfoArtworkData"]
    }
    
    var id: String? {
        if let id = _uniqueIdentifier {
            return id.description
        } else if let title = _title {
            return "NowPlaying-\(title)\(_album.map { "-\($0)" } ?? "")"
        } else {
            return nil
        }
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
    
    var track: MusicTrack? {
        guard let id = id else {
            return nil
        }
        return MusicTrack(id: id, title: _title, album: _album, artist: _artist, duration: _duration, fileURL: nil, artwork: artwork, originalTrack: nil)
    }
}

#endif
