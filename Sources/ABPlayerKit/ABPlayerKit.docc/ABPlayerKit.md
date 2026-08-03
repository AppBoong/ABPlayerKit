# ``ABPlayerKit``

A thin, measurable AVPlayer wrapper with an explicit four-grade playback state machine.

## Overview

ABPlayerKit separates playback resource ownership from rendering. Move an ``ABPlayer`` through ``ABPlaybackGrade/released``, ``ABPlaybackGrade/instanceOnly``, ``ABPlaybackGrade/preloaded``, and ``ABPlaybackGrade/current`` to make allocation, preload, promotion, and release explicit.

Render the same player with ``ABPlayerView`` in UIKit or ``ABVideoPlayer`` in SwiftUI. Observe lifecycle and readiness through token-based events without occupying a delegate slot.

Time to first frame ends only when both the player layer is ready for display and the current item is ready to play.

## Topics

### Playback

- ``ABPlayer``
- ``ABPlaybackGrade``
- ``ABMediaSource``
- ``ABPlayerConfiguration``
- ``ABPlaybackTuning``

### Rendering

- ``ABPlayerView``
- ``ABVideoPlayer``

### Events and Policy

- ``ABPlayerEvent``
- ``ABObservationToken``
- ``ABBackgroundPolicy``
- ``ABAudioSession``

### Extension Seams

- ``ABAssetFactory``
- ``ABGradePlanner``
