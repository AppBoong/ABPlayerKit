# ``ABPlayerKit``

A thin, measurable AVPlayer wrapper with an explicit four-grade playback state machine.

## Overview

ABPlayerKit separates playback resource ownership from rendering. Move an ``ABPlayer`` through ``ABPlaybackGrade/released``, ``ABPlaybackGrade/instanceOnly``, ``ABPlaybackGrade/preloaded``, and ``ABPlaybackGrade/current`` to make allocation, preload, promotion, and release explicit.

Render the same player with ``ABPlayerView`` in UIKit or ``ABVideoPlayer`` in SwiftUI. Observe lifecycle and readiness through token-based events without occupying a delegate slot.

Time to first frame ends only when both the player layer is ready for display and the current item is ready to play.

### Getting Started

One line puts a video on screen. The view owns the player and releases it when SwiftUI discards the view:

```swift
import ABPlayerKit
import SwiftUI

ABVideoPlayer(url: url)
    .aspectRatio(16 / 9, contentMode: .fit)
```

Own the player when a screen needs to pause it, observe it, or share it:

```swift
@State private var player = ABPlayer()

ABVideoPlayer(player: player)
    .task { player.load(ABMediaSource(url: url)) }  // a no-op on later appearances
    .onDisappear { player.pause() }
```

<doc:ChoosingAnOwnershipModel> explains when to take each step, and how grades preload a feed.

In UIKit, render a player with ``ABPlayerView``:

```swift
import ABPlayerKit
import UIKit

@MainActor
final class PlayerViewController: UIViewController {
    private let player = ABPlayer()
    private let playerView = ABPlayerView()

    override func viewDidLoad() {
        super.viewDidLoad()

        playerView.frame = view.bounds
        playerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        playerView.player = player
        view.addSubview(playerView)

        player.load(ABMediaSource(url: URL(string: "https://example.com/video.mp4")!))
    }
}
```

Events support multiple independent consumers. The returned token is what keeps the subscription alive — discard it and observation stops:

```swift
let token = player.addObserver { event in
    if case .firstFrameDisplayed(let timestamp) = event {
        print("First frame displayed at \(timestamp)")
    }
}

// Retain token for as long as observation is needed.
token.cancel()
```

### Scrubbing

Call ``ABPlayer/beginScrubbing()`` when an interactive drag starts, send every new destination through ``ABPlayer/scrub(to:)``, and await ``ABPlayer/endScrubbing()`` when it ends. ABPlayerKit coalesces intermediate seeks so only the newest pending destination survives, then commits the final destination precisely.

Periodic time events pause during that session and resume with an immediate snapshot after the final seek. Configure their cadence with ``ABPlayerConfiguration/periodicTimeInterval``.

### Building Custom UI

``ABSeekBarGeometry`` provides UIKit-independent coordinate and time conversion for custom timelines. ``ABTimeFormatter`` supplies stable `M:SS`/`H:MM:SS` media-time labels, omitting the hours field under one hour. In SwiftUI, read ``ABPlayer/position`` — an `@Observable` ``ABPlaybackPosition`` that invalidates only the views reading it. Outside SwiftUI, use ``ABPlaybackTime`` from ``ABPlayer/playbackTime`` or ``ABPlayerEvent/periodicTime(_:)`` to render current and buffered progress.

Treat ``ABPlayerEvent``, ``ABPlayerError``, and ``ABBackgroundPolicy`` as non-exhaustive. Minor releases may add cases, so switches outside ABPlayerKit should include a `default` branch.

## Topics

### Essentials

- <doc:ChoosingAnOwnershipModel>
- <doc:TuningPlayback>
- <doc:Troubleshooting>

### Playback

- ``ABPlayer``
- ``ABPlaybackGrade``
- ``ABMediaSource``
- ``ABPlayerConfiguration``
- ``ABPlaybackTuning``
- ``ABPlaybackTime``
- ``ABPlaybackPosition``
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

### Picture in Picture

- <doc:BackgroundAndPictureInPicture>
- ``ABPictureInPictureSession``
- ``ABPictureInPictureFailure``

### Building Custom UI

- ``ABSeekBarGeometry``
- ``ABTimeFormatter``

### Events and Policy

- ``ABPlayerEvent``
- ``ABObservationToken``
- ``ABBackgroundPolicy``

### Audio Session and Interruptions

- <doc:AudioSessionAndInterruptions>
- ``ABAudioSession``
- ``ABAudioSessionPolicy``
- ``ABInterruptionPolicy``

### AirPlay and External Playback

- <doc:AirPlayAndExternalPlayback>

### Subtitles and Audio Tracks

- <doc:SubtitlesAndAudioTracks>

### Failures, Diagnostics, and Rejected Calls

- <doc:FailuresAndDiagnostics>
- ``ABPlayerError``
- ``ABPlayerFailure``
- ``ABErrorOrigin``
- ``ABRejectedCall``

### Extension Seams

- ``ABAssetFactory``

### Grade State Machine

Public so the transition table can be read and tested on its own, not as an extension seam. See the API stability policy's "Public types that are not extension seams".

- ``ABGradePlanner``
- ``ABGradeAction``
