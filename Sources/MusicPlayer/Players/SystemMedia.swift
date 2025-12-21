#if os(macOS) || os(iOS)

import Foundation
import Combine
import MediaRemotePrivate
import MediaRemoteAdapter

extension MusicPlayers {
    public final class SystemMedia: ObservableObject {
        public static var available: Bool {
            return MRIsMediaRemoteLoaded
        }

        @Published public private(set) var currentTrack: MusicTrack?
        @Published public private(set) var playbackState: PlaybackState = .stopped

        public private(set) var usesAdapter: Bool = {
            if #available(macOS 15.4, *) {
                return true
            } else {
                return false
            }
        }()

        private lazy var adapterController: MediaController = .init(bundleIdentifiers: allowsApplicationBundleIdentifiers) {
            didSet {
                oldValue.stopListening()
                setupAdapterController()
                adapterController.startListening()
            }
        }

        public var allowsApplicationBundleIdentifiers: [String] {
            didSet {
                adapterController = .init(bundleIdentifiers: allowsApplicationBundleIdentifiers)
            }
        }

        private var systemPlaybackState: SystemPlaybackState?

        public init?(allowsApplicationBundleIdentifiers: [String] = []) {
            self.allowsApplicationBundleIdentifiers = allowsApplicationBundleIdentifiers
            if usesAdapter {
                setupAdapterController()
                adapterController.startListening()
                adapterController.updatePlayerState(userInfo: ["setSystemPlaybackState": true])
            } else {
                guard Self.available else { return nil }

                MRMediaRemoteRegisterForNowPlayingNotifications_?(DispatchQueue.playerUpdate)

                let nc = NotificationCenter.default
                nc.addObserver(forName: .mediaRemoteNowPlayingApplicationPlaybackStateDidChange, object: nil, queue: nil) { [weak self] in
                    guard let self else { return }
                    handleNowPlayingApplicationPlaybackStateDidChange(for: $0)
                }
                nc.addObserver(forName: .mediaRemoteNowPlayingInfoDidChange, object: nil, queue: nil) { [weak self] in
                    guard let self else { return }
                    handleNowPlayingInfoDidChange(for: $0)
                }

                MRMediaRemoteGetNowPlayingApplicationIsPlaying_?(DispatchQueue.playerUpdate) { [weak self] isPlaying in
                    guard let self else { return }
                    self.systemPlaybackState = isPlaying.boolValue ? .playing : .paused
                    updatePlayerState()
                }
            }
        }

        deinit {
            if usesAdapter {
                adapterController.stopListening()
            } else {
                MRMediaRemoteUnregisterForNowPlayingNotifications_?()
            }
        }

        private func setupAdapterController() {
            adapterController.onTrackInfoReceived = { [weak self] trackInfo, userInfo in
                guard let self else { return }
                handleNowPlayingInfoDidChange(for: trackInfo, userInfo: userInfo)
            }
            adapterController.onPlaybackStateReceived = { [weak self] in
                guard let self else { return }
                _handleNowPlayingApplicationPlaybackStateDidChange(for: $0)
            }
        }

        private func handleNowPlayingInfoDidChange(for trackInfo: TrackInfo?, userInfo: [String: Any]?) {
            guard let trackInfo else {
                playbackState = .stopped
                currentTrack = nil
                return
            }
            if userInfo?["setSystemPlaybackState"] != nil {
                systemPlaybackState = trackInfo.isPlaying == true ? .playing : .paused
            }
            _handleNowPlayingInfoDidChange(for: MRNowPlayingInfo(dict: trackInfo.asDictionary))
        }

        private func handleNowPlayingInfoDidChange(for notification: Notification) {
            updatePlayerState()
        }
        
        private func handleNowPlayingInfoDidChange(for infoDict: CFDictionary?) {
            guard let infoDict = infoDict as? NSDictionary else {
                playbackState = .stopped
                currentTrack = nil
                return
            }
            _handleNowPlayingInfoDidChange(for: MRNowPlayingInfo(dict: infoDict))
        }

        private func _handleNowPlayingInfoDidChange(for info: MRNowPlayingInfo) {
            let newState: PlaybackState
            switch systemPlaybackState {
            case .playing:
                newState = info.startTime.map(PlaybackState.playing) ?? .stopped
            case .paused:
                newState = info._elapsedTime.map(PlaybackState.paused) ?? .stopped
            default:
                newState = .stopped
            }
            if !playbackState.approximateEqual(to: newState) {
                playbackState = newState
            }

            let newTrack = info.track
            if newTrack?.id != currentTrack?.id {
                currentTrack = newTrack
            }
        }

        private func handleNowPlayingApplicationPlaybackStateDidChange(for notification: Notification) {
            guard let info = notification.userInfo else {
                playbackState = .stopped
                currentTrack = nil
                return
            }

            _handleNowPlayingApplicationPlaybackStateDidChange(for: info["kMRMediaRemotePlaybackStateUserInfoKey"] as? Int)
        }

        private func _handleNowPlayingApplicationPlaybackStateDidChange(for rawValue: Int?) {
            systemPlaybackState = rawValue.flatMap(SystemPlaybackState.init)
            if systemPlaybackState == .playing || systemPlaybackState == .paused {
                updatePlayerState()
            } else {
                playbackState = .stopped
                currentTrack = nil
            }
        }
    }
}

extension MusicPlayers.SystemMedia: MusicPlayerProtocol {
    public var currentTrackWillChange: AnyPublisher<MusicTrack?, Never> {
        return $currentTrack.eraseToAnyPublisher()
    }

    public var playbackStateWillChange: AnyPublisher<PlaybackState, Never> {
        return $playbackState.eraseToAnyPublisher()
    }

    public var name: MusicPlayerName? {
        return nil
    }

    public var playbackTime: TimeInterval {
        get {
            return playbackState.time
        }
        set {
            if usesAdapter {
                adapterController.setTime(seconds: newValue)
            } else {
                MRMediaRemoteSetElapsedTime_?(newValue)
            }
            playbackState = playbackState.withTime(newValue)
        }
    }

    public func resume() {
        if usesAdapter {
            adapterController.play()
        } else {
            _ = MRMediaRemoteSendCommand_?(.play, nil)
        }
    }

    public func pause() {
        if usesAdapter {
            adapterController.pause()
        } else {
            _ = MRMediaRemoteSendCommand_?(.pause, nil)
        }
    }

    public func playPause() {
        if usesAdapter {
            adapterController.togglePlayPause()
        } else {
            _ = MRMediaRemoteSendCommand_?(.togglePlayPause, nil)
        }
    }

    public func skipToNextItem() {
        if usesAdapter {
            adapterController.nextTrack()
        } else {
            _ = MRMediaRemoteSendCommand_?(.nextTrack, nil)
        }
    }

    public func skipToPreviousItem() {
        if usesAdapter {
            adapterController.previousTrack()
        } else {
            _ = MRMediaRemoteSendCommand_?(.previousTrack, nil)
        }
    }

    public func updatePlayerState() {
        if usesAdapter {
            adapterController.updatePlayerState()
        } else {
            MRMediaRemoteGetNowPlayingClient_?(DispatchQueue.playerUpdate) { [weak self] client in
                guard let self, let client else { return }
                if var bundleIdentifier = client.bundleIdentifier, !allowsApplicationBundleIdentifiers.isEmpty {
                    if let parentApplicationBundleIdentifier = client.parentApplicationBundleIdentifier {
                        bundleIdentifier = parentApplicationBundleIdentifier
                    }
                    guard allowsApplicationBundleIdentifiers.contains(bundleIdentifier) else { return }
                }
                MRMediaRemoteGetNowPlayingInfo_?(DispatchQueue.playerUpdate) { [weak self] info in
                    guard let self else { return }
                    handleNowPlayingInfoDidChange(for: info)
                }
            }
        }
    }
}

extension MusicPlayers.SystemMedia {
    fileprivate enum SystemPlaybackState: Int {
        case terminated = 0
        case playing = 1
        case paused = 2
        case stopped = 3
    }
}

extension Notification.Name {
    fileprivate static let mediaRemoteNowPlayingInfoDidChange = Notification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification")
    fileprivate static let mediaRemoteNowPlayingApplicationPlaybackStateDidChange = Notification.Name("kMRMediaRemoteNowPlayingApplicationPlaybackStateDidChangeNotification")
}

#endif
