//
//  SpotifyiOS.swift
//
//  This file is part of LyricsX - https://github.com/ddddxxx/LyricsX
//  Copyright (C) 2017  Xander Deng. Licensed under GPLv3.
//

#if false

import UIKit

public final class SpotifyiOS: NSObject, SPTAppRemoteDelegate, SPTAppRemotePlayerStateDelegate {
    
    public static let accessTokenDefaultsKey = "ddddxxx.SpotifyiOS.AccessTokenDefaultsKey"
    
    public weak var delegate: MusicPlayerDelegate?
    
    let appRemote: SPTAppRemote
    var playerState: SPTAppRemotePlayerState?
    
    private var _startTime: Date?
    private var _pausePosition: Double?
    
    public init(clientID: String, redirectURL: URL) {
        let configuration = SPTConfiguration(clientID: clientID, redirectURL: redirectURL)
        appRemote = SPTAppRemote(configuration: configuration, logLevel: .info)
        super.init()
        appRemote.delegate = self
        
        let accessToken = UserDefaults.standard.string(forKey: SpotifyiOS.accessTokenDefaultsKey)
        appRemote.connectionParameters.accessToken = accessToken
        attemptConnect()
    }
    
    func addObserver() {
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidBecomeActiveNotification), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidBecomeActiveNotification), name: UIApplication.willResignActiveNotification, object: nil)
    }
    
    func attemptConnect() {
        SPTAppRemote.checkIfSpotifyAppIsActive { active in
            if active {
                self.appRemote.connect()
            }
        }
    }
    
    public func getAccessTokenAndConnect(from url: URL) -> Bool {
        if let token = appRemote.authorizationParameters(from: url)?[SPTAppRemoteAccessTokenKey] {
            appRemote.connectionParameters.accessToken = token
            appRemote.connect()
            UserDefaults.standard.set(token, forKey: SpotifyiOS.accessTokenDefaultsKey)
            return true
        }
        return false
    }
    
    // MARK: -
    
    @objc func applicationDidBecomeActiveNotification(_ n: Notification) {
        attemptConnect()
    }
    
    @objc func applicationWillResignActiveNotification(_ n: Notification) {
        appRemote.disconnect()
    }
    
    // MARK: - SPTAppRemoteDelegate
    
    public func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        appRemote.playerAPI?.delegate = self
        appRemote.playerAPI?.subscribe(toPlayerState: nil)
        delegate?.playbackStateChanged(state: .playing, from: self)
    }
    
    public func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        
    }
    
    public func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        
    }
    
    // MARK: SPTAppRemotePlayerStateDelegate
    
    public func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
        let oldState = self.playerState
        self.playerState = playerState
        if playerState.track.uri != oldState?.track.uri {
            delegate?.currentTrackChanged(track: playerState.track.track, from: self)
            _startTime = nil
            _pausePosition = nil
        } else if playerState.isPaused != oldState?.isPaused {
            if playbackState.isPlaying {
                let startTimeNew = playerState.startTime
                if let _startTime = _startTime,
                    abs(startTimeNew.timeIntervalSince(_startTime)) > positionMutateThreshold {
                    self._startTime = startTimeNew
                    delegate?.playerPositionMutated(position: playerPosition, from: self)
                } else {
                    self._startTime = startTimeNew
                }
            } else {
                let pausePositionNew = playerState.position
                if let _pausePosition = _pausePosition,
                    abs(_pausePosition - pausePositionNew) > positionMutateThreshold {
                    self._pausePosition = pausePositionNew
                    delegate?.playerPositionMutated(position: playerPosition, from: self)
                } else {
                    self._pausePosition = pausePositionNew
                }
            }
        } else if playerState.startTime != oldState?.startTime {
            delegate?.playerPositionMutated(position: playerState.position, from: self)
        }
    }
}

extension SpotifyiOS: MusicPlayerProtocol {
    
    public static let name: MusicPlayerName = .spotify
    public static var needsUpdateIfNotSelected = false
    
    public var isAuthorized: Bool {
        return appRemote.isConnected
    }
    
    public func requestAuthorizationIfNeeded() {
        appRemote.authorizeAndPlayURI("")
    }
    
    public var currentTrack: MusicTrack? {
        return playerState?.track.track
    }
    
    public var playbackState: MusicPlaybackState {
        return playerState?.playbackState ?? .stopped
    }
    
    public var playerPosition: TimeInterval {
        get {
            if playbackState.isPlaying, let pos = _pausePosition {
                return pos
            }
            if let _startTime = _startTime {
                return -_startTime.timeIntervalSinceNow
            }
            if let time = playerState?.startTime {
                _startTime = time
                return -time.timeIntervalSinceNow
            }
            return 0
        }
        set {
            guard isAuthorized else { return }
            _startTime = Date().addingTimeInterval(-newValue)
            let positionInMilliseconds = Int(newValue * 1000)
            appRemote.playerAPI?.seek(toPosition: positionInMilliseconds, callback: nil)
        }
    }
    
    public func updatePlayerState() {
        appRemote.playerAPI?.getPlayerState { state, error in
            if let state = state as? SPTAppRemotePlayerState {
                self.playerStateDidChange(state)
            }
        }
    }
    
    public func resume() {
        appRemote.playerAPI?.resume(nil)
    }
    
    public func pause() {
        appRemote.playerAPI?.pause(nil)
    }
    
    public func playPause() {
        if playbackState.isPlaying {
            pause()
        } else {
            resume()
        }
    }
    
    public func skipToNextItem() {
        appRemote.playerAPI?.skip(toNext: nil)
    }
    
    public func skipToPreviousItem() {
        appRemote.playerAPI?.skip(toPrevious: nil)
    }
}

extension SpotifyiOS: PlaybackModeSettable {
    
    public var repeatMode: MusicRepeatMode {
        get {
            // TODO: get repeat mode
            return .off
        }
        set {
            appRemote.playerAPI?.setRepeatMode(SPTAppRemotePlaybackOptionsRepeatMode(newValue), callback: nil)
        }
    }
    
    public var shuffleMode: MusicShuffleMode {
        get {
            // TODO: get repeat mode
            return .off
        }
        set {
            let shuffle = newValue != .off
            appRemote.playerAPI?.setShuffle(shuffle, callback: nil)
        }
    }
}

// MARK: - Extension

extension SPTAppRemoteTrack {
    
    var track: MusicTrack {
        let duration_ = TimeInterval(duration) / 1000
        // TODO: Artwork
        return MusicTrack(id: uri, title: name, album: album.name, artist: artist.name, duration: duration_, url: nil, artwork: nil)
    }
}

extension SPTAppRemotePlayerState {
    
    var playbackState: MusicPlaybackState {
        return isPaused ? .paused : .playing
    }
    
    var position: TimeInterval {
        return TimeInterval(playbackPosition) / 1000
    }
    
    var startTime: Date {
        return Date(timeIntervalSinceNow: -position)
    }
}

extension SPTAppRemotePlaybackOptionsRepeatMode {
    
    var mode: MusicRepeatMode {
        switch self {
        case .off: return .off
        case .track: return .one
        case .context: return .all
        @unknown default: return .off
        }
    }
    
    init(_ mode: MusicRepeatMode) {
        switch mode {
        case .off: self = .off
        case .one: self = .track
        case .all: self = .context
        }
    }
}

 #endif
