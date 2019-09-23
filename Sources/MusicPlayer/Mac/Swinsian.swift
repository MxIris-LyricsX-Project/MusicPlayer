//
//  Swinsian.swift
//
//  This file is part of LyricsX - https://github.com/ddddxxx/LyricsX
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

#if os(macOS)

import AppKit
import ScriptingBridge
import MusicPlayerBridge

public final class Swinsian: MusicPlayerController {
    
    override public class var name: MusicPlayerName {
        return .swinsian
    }
    
    private var _app: SwinsianApplication {
        return originalPlayer as! SwinsianApplication
    }
    
    public override var currentTrack: MusicTrack? {
        get { super.currentTrack }
        set { super.currentTrack = newValue }
    }
    public override var playbackState: PlaybackState {
        get { super.playbackState }
        set { super.playbackState = newValue }
    }
    
    required init?() {
        super.init()
        if isRunning {
            playbackState = _app._playbackState
            currentTrack = _app._currentTrack
        }
        
        distributedNC.cx.publisher(for: .swinsianPlaying)
            .sink { [unowned self] _ in
                self.setPlaybackState(self._app._playbackState, tolerate: 1.0)
                self.currentTrack = self._app._currentTrack
            }.store(in: &cancelBag)
        distributedNC.cx.publisher(for: .swinsianPaused)
            .sink { [unowned self] _ in
                self.setPlaybackState(self._app._playbackState, tolerate: 1.0)
            }.store(in: &cancelBag)
        distributedNC.cx.publisher(for: .swinsianStopped)
            .sink { _ in
                self.playbackState = .stopped
                self.currentTrack = nil
            }.store(in: &cancelBag)
    }
    
    override public var playbackTime: TimeInterval {
        get {
            return playbackState.time
        }
        set {
            guard isRunning else { return }
            _app.playerPosition = Int(newValue)
            playbackState.time = newValue
        }
    }
    
    override public func resume() {
        _app.play()
    }
    
    override public func pause() {
        _app.pause()
    }
    
    override public func playPause() {
        _app.playpause()
    }
    
    override public func skipToNextItem() {
        _app.nextTrack()
    }
    
    override public func skipToPreviousItem() {
        _app.previousTrack()
    }
}

extension SwinsianApplication {
    
    var _currentTrack: MusicTrack? {
        guard let track = currentTrack else { return nil }
        let originalTrack = track.get() as? SBObject
        let url = track.path.flatMap(URL.init(string:))
        return MusicTrack(id: track.id() ?? "",
                          title: track.name,
                          album: track.album,
                          artist: track.artist,
                          duration: track.duration,
                          url: url,
                          artwork: track.albumArt,
                          originalTrack: originalTrack)
    }
    
    var _playbackState: PlaybackState {
        switch playerState {
        case .stopped: return .stopped
        case .playing: return .playing(time: TimeInterval(playerPosition))
        case .paused:  return .paused(time: TimeInterval(playerPosition))
        @unknown default: return .stopped
        }
    }
}

#endif
