# ``ABPlayerKit``

A thin, measurable AVPlayer wrapper with an explicit four-grade playback state machine.

## Overview

ABPlayerKit separates playback resource ownership from rendering. Move an ``ABPlayer`` through ``ABPlaybackGrade/released``, ``ABPlaybackGrade/instanceOnly``, ``ABPlaybackGrade/preloaded``, and ``ABPlaybackGrade/current`` to make allocation, preload, promotion, and release explicit.

Render the same player with ``ABPlayerView`` in UIKit or ``ABVideoPlayer`` in SwiftUI. Observe lifecycle and readiness through token-based events without occupying a delegate slot.

Time to first frame ends only when both the player layer is ready for display and the current item is ready to play.

### Scrubbing

Call ``ABPlayer/beginScrubbing()`` when an interactive drag starts, send every new destination through ``ABPlayer/scrub(to:)``, and await ``ABPlayer/endScrubbing()`` when it ends. ABPlayerKit coalesces intermediate seeks so only the newest pending destination survives, then commits the final destination precisely.

Periodic time events pause during that session and resume with an immediate snapshot after the final seek. Configure their cadence with ``ABPlayerConfiguration/periodicTimeInterval``.

### Building Custom UI

``ABSeekBarGeometry`` provides UIKit-independent coordinate and time conversion for custom timelines. ``ABTimeFormatter`` supplies stable `M:SS`/`H:MM:SS` media-time labels, omitting the hours field under one hour. Use ``ABPlaybackTime`` from ``ABPlayer/playbackTime`` or ``ABPlayerEvent/periodicTime(_:)`` to render current and buffered progress.

Treat ``ABPlayerEvent`` and ``ABPlayerError`` as non-exhaustive. Minor releases may add cases, so switches outside ABPlayerKit should include a `default` branch.

## Topics

### Playback

- ``ABPlayer``
- ``ABPlaybackGrade``
- ``ABMediaSource``
- ``ABPlayerConfiguration``
- ``ABPlaybackTuning``
- ``ABPlaybackTime``
- ``ABSeekTolerance``
- ``ABPlaybackRate``

### Playback Control

- ``ABPlayer/play()``
- ``ABPlayer/pause()``
- ``ABPlayer/setRate(_:)``
- ``ABPlayer/skip(by:)``
- ``ABPlayer/seek(to:tolerance:)``
- ``ABPlayer/beginScrubbing()``
- ``ABPlayer/scrub(to:)``
- ``ABPlayer/endScrubbing()``

### Rendering

- ``ABPlayerView``
- ``ABVideoPlayer``

### Building Custom UI

- ``ABSeekBarGeometry``
- ``ABTimeFormatter``

### Events and Policy

- ``ABPlayerEvent``
- ``ABObservationToken``
- ``ABBackgroundPolicy``
- ``ABAudioSession``

### Extension Seams

- ``ABAssetFactory``
- ``ABGradePlanner``
