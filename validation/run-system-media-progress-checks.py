#!/usr/bin/env python3
"""Compile production progress methods with recording transports; never controls a real player."""
import argparse
from pathlib import Path
import platform
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--adapter-frameworks", type=Path, required=True,
                    help="Built PackageFrameworks directory containing MediaRemoteAdapter.framework")
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=True)
frameworks = args.adapter_frameworks.resolve()
source = (root / "Sources/MusicPlayer/Players/SystemMedia.swift").read_text()

def extract(signature):
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]

methods = [
    "private func resetPlayback()",
    "private func _handleNowPlayingInfoDidChange(for info: MRNowPlayingInfo)",
    "private func handleNowPlayingInfoDidChange(for infoDict: CFDictionary?)",
    "private func _handleNowPlayingApplicationPlaybackStateDidChange(for rawValue: Int?)",
    "public var playbackTime: TimeInterval",
]
header = """import Foundation
final class RecordingAdapter {
    var positions: [Double] = []
    var onSet: (() -> Void)?
    func setTime(seconds: Double) { positions.append(seconds); onSet?() }
}
final class Probe {
    enum SystemPlaybackState: Int { case terminated = 0, playing = 1, paused = 2, stopped = 3 }
    var systemPlaybackState: SystemPlaybackState? = .paused
    var playbackState: PlaybackState = .paused(time: 45)
    var currentTrack: MusicTrack? = MusicTrack(id: "1", title: "Before", album: nil, artist: nil)
    var lastArtworkData: Data?
    let positionLock = NSRecursiveLock()
    var pendingSeek: (id: UUID, trackID: String?, time: TimeInterval, started: Date)?
    var lastPositionTimestamp: Date?
    var usesAdapter = true
    let adapterController = RecordingAdapter()
    var MRMediaRemoteSetElapsedTime_: ((Double) -> Void)?
    var refreshes = 0
    var onRefresh: (() -> Void)?
    func updatePlayerState() { refreshes += 1; onRefresh?() }
    func feed(_ info: MRNowPlayingInfo) { _handleNowPlayingInfoDidChange(for: info) }
    func stop() { _handleNowPlayingApplicationPlaybackStateDidChange(for: 3) }
    func clear() { handleNowPlayingInfoDidChange(for: nil as CFDictionary?) }
"""
(out / "ProductionProgressHost.swift").write_text(header + "\n".join(extract(m) for m in methods) + "\n}\n")
music = root / "Sources/MusicPlayer"
model = ["MusicPlayer.swift", "MusicTrack.swift", "PlaybackState.swift", "PlayerName.swift",
         "Utilities/Typealias.swift", "Players/Agent.swift", "Utilities/MediaRemoteHelper.swift"]
command = ["xcrun", "swiftc", "-target", platform.machine() + "-apple-macosx12.0",
           "-module-cache-path", str(out / "module-cache"),
           "-I", str(frameworks.parent), "-F", str(frameworks), "-framework", "MediaRemoteAdapter",
           "-Xlinker", "-rpath", "-Xlinker", str(frameworks),
           *[str(music / p) for p in model], str(out / "ProductionProgressHost.swift"),
           str(root / "validation/SystemMediaProgressCases.swift"), "-o", str(out / "ProgressChecks")]
with (out / "compile.log").open("w") as log:
    result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
if result.returncode:
    raise SystemExit(f"Compilation failed: {out / 'compile.log'}")
with (out / "results.log").open("w") as log:
    result = subprocess.run([str(out / "ProgressChecks"), "--require-pass"], stdout=log, stderr=subprocess.STDOUT)
print((out / "results.log").read_text())
raise SystemExit(result.returncode)
