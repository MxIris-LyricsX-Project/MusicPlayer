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

        public let usesAdapter: Bool = {
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

        // Track raw NowPlayingInfo artwork data so we can detect artwork-only
        // updates within the same track id. Some sources (notably iOS-on-Mac
        // apps and any app that lazy-loads artwork) deliver the new song's
        // title/artist first and the new artwork in a later NowPlayingInfo
        // notification with the same id. Without this, the second update is
        // dropped and consumers keep showing the previous song's cover.
        private var lastArtworkData: Data?
        private let positionLock = NSRecursiveLock()
        private var pendingSeek: (id: UUID, trackID: String?, time: TimeInterval, started: Date)?
        private var lastPositionTimestamp: Date?

        public init?(allowsApplicationBundleIdentifiers: [String] = []) {
            self.allowsApplicationBundleIdentifiers = allowsApplicationBundleIdentifiers
            if usesAdapter {
                setupAdapterController()
                // Pick up the host-side debug toggle without forcing host code
                // to wire it through. Toggle it from the host with:
                //   defaults write <host-bundle-id> MediaRemoteAdapterDebugDump -bool YES
                // Then restart the host process. When on, every NowPlayingInfo
                // change is logged to the host's console with the full source
                // dictionary, including fields this adapter normally drops.
                adapterController.debugDumpEnabled = false
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
                    self.positionLock.lock()
                    self.systemPlaybackState = isPlaying.boolValue ? .playing : .paused
                    self.positionLock.unlock()
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
            positionLock.lock()
            defer { positionLock.unlock() }
            guard let trackInfo else {
                resetPlayback()
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
            guard let infoDict else {
                resetPlayback()
                return
            }
            _handleNowPlayingInfoDidChange(for: MRNowPlayingInfo(dict: infoDict))
        }

        private func resetPlayback() {
            positionLock.lock()
            defer { positionLock.unlock() }
            pendingSeek = nil
            lastPositionTimestamp = nil
            lastArtworkData = nil
            playbackState = .stopped
            currentTrack = nil
        }

        private func _handleNowPlayingInfoDidChange(for info: MRNowPlayingInfo) {
            positionLock.lock()
            defer { positionLock.unlock() }
            // Pause/resume continuity applies only within the same track.
            let newTrack = info.track
            let trackWillChange = newTrack?.id != currentTrack?.id
            var acceptPosition = true
            var resetContinuity = trackWillChange
            if trackWillChange { lastPositionTimestamp = nil }
            if let seek = pendingSeek {
                if trackWillChange || newTrack?.id != seek.trackID {
                    pendingSeek = nil
                } else {
                    let age = max(0, -seek.started.timeIntervalSinceNow)
                    let elapsed = info._elapsedTime
                    let expected = seek.time + (systemPlaybackState == .playing ? age : 0)
                    let fresh = info._timestamp.map { timestamp in
                        lastPositionTimestamp.map { timestamp >= $0 } ?? true
                    } ?? true
                    let confirmed = fresh && (elapsed.map {
                        $0.isFinite && min(abs($0 - seek.time), abs($0 - expected)) <= 2
                    } ?? false)
                    if confirmed || age >= 2 {
                        pendingSeek = nil
                        resetContinuity = true
                    } else {
                        // A command reply/listener update may still describe the
                        // pre-seek position. Keep the optimistic clock until a
                        // matching sample arrives, or reconcile after the deadline.
                        acceptPosition = false
                    }
                }
            }
            if let timestamp = info._timestamp, let previous = lastPositionTimestamp,
               timestamp < previous, !resetContinuity {
                acceptPosition = false
            }
            let newState: PlaybackState
            switch systemPlaybackState {
            case .playing:
                if !resetContinuity, case .paused(let pausedTime) = playbackState {
                    // Resuming from pause. The dict's start time is `timestamp −
                    // elapsed`, and right after resume the timestamp is usually
                    // still the pre-resume sample, so `.playing.time` (= elapsed +
                    // (now − timestamp)) counts the whole paused span as if it had
                    // played — the position drifts forward until the next info
                    // refresh corrects it. The paused time is the accurate resume
                    // position, so seed the playing clock from it instead.
                    newState = .playing(time: pausedTime)
                } else {
                    newState = info.startTime.map(PlaybackState.playing) ?? (trackWillChange ? .stopped : playbackState)
                }
            case .paused:
                if !resetContinuity && playbackState.isPlaying {
                    // Transitioning from playing → paused. The Now-Playing dict's
                    // elapsed time is the position sampled at its `_timestamp`,
                    // which is usually still from BEFORE the pause (the dict is
                    // refreshed asynchronously), so taking it verbatim makes the
                    // position jump several seconds backwards the instant playback
                    // pauses. The just-ended playing state already interpolates the
                    // accurate stop position (`elapsed + (now − timestamp)`), so
                    // freeze there instead.
                    newState = .paused(time: playbackState.time)
                } else if let elapsed = info._elapsedTime {
                    // Already paused: accept a fresh elapsed time unless it is an
                    // apparent backward jump (a stale re-report of the pre-pause
                    // sample), so the held position never regresses.
                    newState = resetContinuity || elapsed + 0.5 >= playbackState.time ? .paused(time: elapsed) : playbackState
                } else {
                    newState = trackWillChange ? .stopped : playbackState
                }
            default:
                newState = .stopped
            }
            let stateApproxEqual = playbackState.approximateEqual(to: newState)
//            let oldStateDescription = String(describing: playbackState)
            if acceptPosition {
                if resetContinuity || !stateApproxEqual { playbackState = newState }
                if info._elapsedTime != nil, let timestamp = info._timestamp {
                    lastPositionTimestamp = timestamp
                }
            } else {
                // Playback state notifications remain authoritative even while
                // an older position sample is being ignored.
                if systemPlaybackState == .paused && playbackState.isPlaying {
                    playbackState = .paused(time: playbackState.time)
                } else if systemPlaybackState == .playing, case .paused(let time) = playbackState {
                    playbackState = .playing(time: time)
                }
            }

            let newArtworkData = info._artworkData
//            let oldId = currentTrack?.id ?? "<nil>"
//            let newId = newTrack?.id ?? "<nil>"
            let artworkWillChange = newArtworkData != lastArtworkData
//
//            // Only probe MachO when the decision is interesting — every track-
//            // replace event is exactly the flicker we're chasing, and the iOS-
//            // on-Mac fingerprint helps confirm the source.
//            #if os(macOS)
//            let iosFingerprint = trackWillChange ? (info.isiOSAppOnMac ? "true" : "false") : "<skip>"
//            #else
//            let iosFingerprint = "<n/a>"
//            #endif
//
//            NSLog("[SystemMedia][Flicker] InfoChange trackWillChange=%@ stateChanged=%@ oldId=%@ newId=%@ uid=%@ bundle=%@ iOSAppOnMac=%@ rawTitle=%@ rawArtist=%@ recoveredTitle=%@ recoveredArtist=%@ oldState=%@ newState=%@",
//                  String(trackWillChange),
//                  String(!stateApproxEqual),
//                  oldId,
//                  newId,
//                  info._uniqueIdentifier.map(String.init) ?? "<nil>",
//                  info._bundleIdentifier ?? "<nil>",
//                  iosFingerprint,
//                  info._title ?? "<nil>",
//                  info._artist ?? "<nil>",
//                  newTrack?.title ?? "<nil>",
//                  newTrack?.artist ?? "<nil>",
//                  oldStateDescription,
//                  String(describing: newState))

            if trackWillChange || artworkWillChange {
                currentTrack = newTrack
                lastArtworkData = newArtworkData
            }
        }

        private func handleNowPlayingApplicationPlaybackStateDidChange(for notification: Notification) {
            guard let info = notification.userInfo else {
                resetPlayback()
                return
            }

            _handleNowPlayingApplicationPlaybackStateDidChange(for: info["kMRMediaRemotePlaybackStateUserInfoKey"] as? Int)
        }

        private func _handleNowPlayingApplicationPlaybackStateDidChange(for rawValue: Int?) {
            positionLock.lock()
            defer { positionLock.unlock() }
//            let oldSystemState = systemPlaybackState
            systemPlaybackState = rawValue.flatMap(SystemPlaybackState.init)
//            NSLog("[SystemMedia][Flicker] AppPlaybackStateChange raw=%@ old=%@ new=%@",
//                  rawValue.map(String.init) ?? "<nil>",
//                  oldSystemState.map { String(describing: $0) } ?? "<nil>",
//                  systemPlaybackState.map { String(describing: $0) } ?? "<nil>")
            if systemPlaybackState == .playing || systemPlaybackState == .paused {
                updatePlayerState()
            } else {
                resetPlayback()
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
            positionLock.lock()
            defer { positionLock.unlock() }
            return playbackState.time
        }
        set {
            positionLock.lock()
            defer { positionLock.unlock() }
            guard newValue.isFinite else { return }
            let seekID = UUID()
            pendingSeek = (seekID, currentTrack?.id, newValue, Date())
            playbackState = playbackState.withTime(newValue)
            if usesAdapter {
                adapterController.setTime(seconds: newValue)
            } else {
                MRMediaRemoteSetElapsedTime_?(newValue)
            }
            // A paused player may not send another event if seeking fails.
            // Request a final sample instead of relying only on notifications.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self else { return }
                self.positionLock.lock()
                let stillPending = self.pendingSeek?.id == seekID
                self.positionLock.unlock()
                guard stillPending else { return }
                self.updatePlayerState()
            }
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
