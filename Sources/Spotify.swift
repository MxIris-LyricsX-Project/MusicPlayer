//
//  Spotify.swift
//
//  This file is part of LyricsX
//  Copyright (C) 2017  Xander Deng
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import AppKit
import ScriptingBridge

final public class Spotify {
    
    public weak var delegate: MusicPlayerDelegate?
    
    public var autoLaunch = false
    
    private var _spotify: SpotifyApplication
    private var _currentTrack: MusicTrack?
    private var _playbackState: MusicPlaybackState = .stopped
    private var _startTime: Date?
    private var _pausePosition: Double?
    
    private var observer: NSObjectProtocol?
    
    public init?() {
        guard let spotify = SBApplication(bundleIdentifier: Spotify.name.bundleID) else {
            return nil
        }
        _spotify = spotify
        if isRunning {
            _playbackState = _spotify.playerState?.state ?? .stopped
            _currentTrack = _spotify.currentTrack.map(MusicTrack.init)
            _startTime = _spotify.startTime
        }
        
        observer = DistributedNotificationCenter.default.addObserver(forName: .SpotifyPlayerInfo, object: nil, queue: nil, using: playerInfoNotification)
    }
    
    deinit {
        if let observer = observer {
            DistributedNotificationCenter.default.removeObserver(observer)
        }
    }
    
    func playerInfoNotification(_ n: Notification) {
        guard autoLaunch || isRunning else { return }
        let track = _spotify.currentTrack.map(MusicTrack.init)
        let state = _spotify.playerState?.state ?? .stopped
        guard track?.id == _currentTrack?.id else {
            _currentTrack = track
            _playbackState = state
            _startTime = _spotify.startTime
            delegate?.currentTrackChanged(track: track, from: self)
            return
        }
        guard state == _playbackState else {
            _playbackState = state
            _startTime = _spotify.startTime
            _pausePosition = playerPosition
            delegate?.playbackStateChanged(state: state, from: self)
            return
        }
        updatePlayerPosition()
    }
    
    func updatePlayerPosition() {
        guard autoLaunch || isRunning else { return }
        if _playbackState.isPlaying {
            if let _startTime = _startTime,
                let startTime = _spotify.startTime,
                abs(startTime.timeIntervalSince(_startTime)) > positionMutateThreshold {
                self._startTime = startTime
                delegate?.playerPositionMutated(position: playerPosition, from: self)
            }
        } else {
            if let _pausePosition = _pausePosition,
                let pausePosition = _spotify.playerPosition,
                abs(_pausePosition - pausePosition) > positionMutateThreshold {
                self._pausePosition = pausePosition
                self.playerPosition = pausePosition
                delegate?.playerPositionMutated(position: playerPosition, from: self)
            }
        }
    }
}

extension Spotify: MusicPlayer {
    
    public static var name: MusicPlayerName = .spotify
    
    public static var needsUpdate = false
    
    public var playbackState: MusicPlaybackState {
        return _playbackState
    }
    
    public var currentTrack: MusicTrack? {
        return _currentTrack
    }
    
    public var playerPosition: TimeInterval {
        get {
            guard autoLaunch || isRunning else { return 0 }
            guard let _startTime = _startTime else { return 0 }
            return -_startTime.timeIntervalSinceNow
        }
        set {
            guard autoLaunch || isRunning else { return }
            originalPlayer.setValue(newValue, forKey: "playerPosition")
//            _spotify.playerPosition = newValue
            _startTime = Date().addingTimeInterval(-newValue)
        }
    }
    
    public func updatePlayerState() {
        updatePlayerPosition()
    }
    
    public var originalPlayer: SBApplication {
        return _spotify as! SBApplication
    }
}

extension SpotifyEPlS {
    
    var state: MusicPlaybackState {
        switch self {
        case .stopped:  return .stopped
        case .playing:  return .playing
        case .paused:   return .paused
        }
    }
}

extension MusicTrack {
    
    init(_ spotifyTrack: SpotifyTrack) {
        id = spotifyTrack.id?() ?? ""
        title = spotifyTrack.name ?? nil
        artist = spotifyTrack.artist ?? nil
        album = spotifyTrack.album ?? nil
        duration = spotifyTrack.duration.map(TimeInterval.init)
        url = nil
    }
}

extension SpotifyApplication {
    
    var startTime: Date? {
        guard let playerPosition = playerPosition else {
            return nil
        }
        return Date().addingTimeInterval(-playerPosition)
    }
}
