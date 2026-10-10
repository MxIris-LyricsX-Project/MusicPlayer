# SystemMedia progress regression checks

Build LyricsX with this MusicPlayer checkout (a local package override or isolated dependency checkout). Use the resulting MediaRemoteAdapter framework to run:

```sh
python3 validation/run-system-media-progress-checks.py \
  --adapter-frameworks /path/to/Build/Products/Release/PackageFrameworks \
  --output /tmp/musicplayer-progress-checks
```

The script compiles the progress setter, metadata callback, playback-state callback, and reset method directly from `SystemMedia.swift`, together with the package's actual model types and metadata parser. A test host supplies state storage and recording transports. It neither initializes SystemMedia's live listeners nor controls a real player. Generated host source and compile/test logs remain in the output directory.

The 33 cases cover paused track changes, missing elapsed time, pause/resume continuity, explicit zero, forward/backward and consecutive seeks, stale timestamps, synchronous old replies, invalid targets, and cancellation on stop/empty metadata/track change. Timeout checks run the real setter's scheduled callback and confirm that only an unacknowledged latest request triggers one refresh. The legacy transport is simulated; this is not evidence of old-macOS compatibility.

A full app build is still needed for integration. Live Apple Music checks in LyricsX passed paused track changes, playback/pause transitions, and forward/backward/consecutive seeking. The subsequent stop/empty-state cleanup and stale near-target acknowledgment guards are covered by these offline checks.
