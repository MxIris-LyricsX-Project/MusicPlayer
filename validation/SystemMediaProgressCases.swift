import Foundation

@main enum Main {
 static func main() {
  var failures = 0, count = 0
  func check(_ pass: Bool, _ name: String) {
    count += 1
    if !pass { failures += 1 }
    print("\(pass ? "PASS" : "FAIL"): \(name)")
  }
  func info(_ id: Int, _ elapsed: Double? = nil) -> MRNowPlayingInfo {
    var dict: [String: Any] = ["kMRMediaRemoteNowPlayingInfoTitle": "Track", "kMRMediaRemoteNowPlayingInfoUniqueIdentifier": id]
    if let elapsed { dict["kMRMediaRemoteNowPlayingInfoElapsedTime"] = elapsed }
    return MRNowPlayingInfo(dict: dict as NSDictionary)
  }
  let paused = Probe()
  paused.feed(info(2, 0))
  check(paused.playbackState.time == 0, "paused new track resets position")
  let nearStart = Probe()
  nearStart.playbackState = .paused(time: 0.8)
  nearStart.feed(info(2, 0))
  check(nearStart.playbackState.time == 0, "track changes bypass same-track position tolerance")
  let resumeNew = Probe()
  resumeNew.systemPlaybackState = .playing
  resumeNew.feed(info(2, 2))
  check(abs(resumeNew.playbackState.time - 2) < 0.5, "new playing track does not borrow old paused position")
  let pauseNew = Probe()
  pauseNew.playbackState = .playing(time: 45)
  pauseNew.feed(info(2, 0))
  check(pauseNew.playbackState.time == 0, "new paused track does not borrow old playing position")
  let partial = Probe()
  partial.systemPlaybackState = .playing
  partial.playbackState = .playing(time: 45)
  partial.feed(info(1))
  check(partial.playbackState.isPlaying && abs(partial.playbackState.time - 45) < 0.5, "missing elapsed on same playing track preserves clock")
  let pausedPartial = Probe()
  pausedPartial.feed(info(1))
  check(pausedPartial.playbackState.time == 45, "missing elapsed on same paused track preserves position")
  let pausedStale = Probe()
  pausedStale.feed(info(1, 12))
  check(pausedStale.playbackState.time == 45, "same paused track still rejects stale earlier sample")
  let resumeSame = Probe()
  resumeSame.systemPlaybackState = .playing
  resumeSame.feed(info(1, 90))
  check(abs(resumeSame.playbackState.time - 45) < 0.5, "same-track resume still starts at held paused time")
  let pauseSame = Probe()
  pauseSame.playbackState = .playing(time: 45)
  pauseSame.feed(info(1, 12))
  check(abs(pauseSame.playbackState.time - 45) < 0.5, "same-track pause preserves interpolated position")
  let seekZero = Probe()
  seekZero.systemPlaybackState = .playing
  seekZero.playbackState = .playing(time: 45)
  seekZero.feed(info(1, 0))
  check(abs(seekZero.playbackState.time) < 0.5, "explicit zero elapsed is accepted while playing")
  let missingNew = Probe()
  missingNew.feed(info(2))
  check(missingNew.playbackState == .stopped, "new track without position never borrows old track position")
  let forwardSeek = Probe()
  forwardSeek.playbackState = .paused(time: 100)
  forwardSeek.pendingSeek = (UUID(), "1", 100, Date())
  forwardSeek.feed(info(1, 45))
  check(forwardSeek.playbackState.time == 100 && forwardSeek.pendingSeek != nil, "forward seek rejects pre-seek reply")
  let backwardSeek = Probe()
  backwardSeek.playbackState = .paused(time: 20)
  backwardSeek.pendingSeek = (UUID(), "1", 20, Date())
  backwardSeek.feed(info(1, 100))
  check(backwardSeek.playbackState.time == 20 && backwardSeek.pendingSeek != nil, "backward seek rejects pre-seek reply")
  let confirmedAt = Date()
  backwardSeek.feed(MRNowPlayingInfo(dict: ["kMRMediaRemoteNowPlayingInfoTitle": "Track", "kMRMediaRemoteNowPlayingInfoUniqueIdentifier": 1, "kMRMediaRemoteNowPlayingInfoElapsedTime": 20.0, "kMRMediaRemoteNowPlayingInfoTimestamp": confirmedAt]))
  check(backwardSeek.playbackState.time == 20 && backwardSeek.pendingSeek == nil, "actual position confirms backward seek")
  backwardSeek.feed(MRNowPlayingInfo(dict: ["kMRMediaRemoteNowPlayingInfoTitle": "Track", "kMRMediaRemoteNowPlayingInfoUniqueIdentifier": 1, "kMRMediaRemoteNowPlayingInfoElapsedTime": 100.0, "kMRMediaRemoteNowPlayingInfoTimestamp": confirmedAt.addingTimeInterval(-1)]))
  check(backwardSeek.playbackState.time == 20, "out-of-order pre-seek timestamp cannot undo confirmation")
  let pausePending = Probe()
  pausePending.playbackState = .playing(time: 100)
  pausePending.pendingSeek = (UUID(), "1", 100, Date())
  pausePending.feed(info(1, 45))
  check(!pausePending.playbackState.isPlaying && abs(pausePending.playbackState.time - 100) < 0.5,
        "pause during seek freezes target clock without accepting old position")
  pausePending.systemPlaybackState = .playing
  pausePending.feed(info(1, 45))
  check(pausePending.playbackState.isPlaying && abs(pausePending.playbackState.time - 100) < 0.5,
        "resume during seek restarts target clock without accepting old position")
  let failedSeek = Probe()
  failedSeek.playbackState = .paused(time: 100)
  failedSeek.pendingSeek = (UUID(), "1", 100, Date(timeIntervalSinceNow: -3))
  failedSeek.feed(info(1, 45))
  check(failedSeek.playbackState.time == 45 && failedSeek.pendingSeek == nil, "deadline reconciles rejected seek with actual player")
  let seekTrackChange = Probe()
  seekTrackChange.playbackState = .paused(time: 100)
  seekTrackChange.pendingSeek = (UUID(), "1", 100, Date())
  seekTrackChange.feed(info(2, 0))
  check(seekTrackChange.playbackState.time == 0 && seekTrackChange.pendingSeek == nil, "track change cancels pending seek")
  let seekZeroPending = Probe()
  seekZeroPending.playbackState = .paused(time: 0)
  seekZeroPending.pendingSeek = (UUID(), "1", 0, Date())
  seekZeroPending.feed(info(1, 45))
  check(seekZeroPending.playbackState.time == 0 && seekZeroPending.pendingSeek != nil, "seek to zero rejects previous position")
  seekZeroPending.feed(info(1, 0))
  check(seekZeroPending.playbackState.time == 0 && seekZeroPending.pendingSeek == nil, "seek to zero can be confirmed")
  let rapidSeek = Probe()
  rapidSeek.playbackState = .paused(time: 20)
  rapidSeek.pendingSeek = (UUID(), "1", 20, Date())
  rapidSeek.feed(info(1, 100))
  rapidSeek.feed(info(1))
  check(rapidSeek.playbackState.time == 20 && rapidSeek.pendingSeek != nil, "older seek result and missing elapsed cannot confirm latest request")

  let setter = Probe()
  setter.playbackTime = 120
  check(setter.playbackState.time == 120 && setter.adapterController.positions == [120], "setter publishes target and sends command")
  setter.playbackTime = .nan
  check(setter.playbackState.time == 120 && setter.adapterController.positions == [120], "nonfinite target does not change position or send command")
  setter.feed(info(1, 120))
  let immediate = Probe()
  immediate.adapterController.onSet = { [weak immediate] in immediate?.feed(info(1, 5)) }
  immediate.playbackTime = 90
  check(immediate.playbackState.time == 90, "synchronous old command reply cannot overwrite optimistic position")
  immediate.feed(info(1, 90))
  let timeout = Probe()
  timeout.onRefresh = { [weak timeout] in timeout?.feed(info(1, 45)) }
  timeout.playbackTime = 100
  let stopped = Probe()
  stopped.playbackTime = 100
  stopped.stop()
  check(stopped.pendingSeek == nil && stopped.playbackState == .stopped, "stopping clears pending seek")
  let cleared = Probe()
  cleared.playbackTime = 100
  cleared.clear()
  check(cleared.pendingSeek == nil && cleared.lastPositionTimestamp == nil, "empty metadata clears seek state")
  let obsolete = Probe()
  obsolete.playbackTime = 100
  obsolete.playbackTime = 200
  let otherTrack = Probe()
  otherTrack.playbackTime = 100
  otherTrack.feed(info(2, 0))
  let legacy = Probe()
  legacy.usesAdapter = false
  var legacyTargets: [Double] = []
  legacy.MRMediaRemoteSetElapsedTime_ = { legacyTargets.append($0) }
  legacy.playbackTime = 80
  check(legacyTargets == [80] && legacy.playbackState.time == 80, "legacy transport sends target with optimistic state")
  legacy.feed(info(1, 80))
  let oldNearTarget = Probe()
  oldNearTarget.lastPositionTimestamp = Date()
  oldNearTarget.playbackTime = 20
  oldNearTarget.feed(MRNowPlayingInfo(dict: ["kMRMediaRemoteNowPlayingInfoTitle": "Track", "kMRMediaRemoteNowPlayingInfoUniqueIdentifier": 1, "kMRMediaRemoteNowPlayingInfoElapsedTime": 19.0, "kMRMediaRemoteNowPlayingInfoTimestamp": Date(timeIntervalSinceNow: -10)]))
  check(oldNearTarget.pendingSeek != nil && oldNearTarget.playbackState.time == 20, "older sample near target cannot confirm seek")
  oldNearTarget.feed(info(1, 20))
  RunLoop.main.run(until: Date(timeIntervalSinceNow: 2.2))
  check(setter.refreshes == 0 && immediate.refreshes == 0 && legacy.refreshes == 0, "confirmed seeks cancel timeout queries")
  check(timeout.refreshes == 1 && timeout.playbackState.time == 45 && timeout.pendingSeek == nil, "timeout queries once and reconciles actual rejected seek")
  check(obsolete.refreshes == 1, "only latest consecutive seek requests timeout query")
  check(stopped.refreshes == 0 && cleared.refreshes == 0 && otherTrack.refreshes == 0, "stopped empty or changed track cancels timeout query")

  print("\(count - failures)/\(count) checks passed")
  if CommandLine.arguments.contains("--require-pass") && failures > 0 { exit(1) }
 }
}
