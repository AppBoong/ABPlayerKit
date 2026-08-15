# Audio Session and Interruptions

How ``ABPlayer`` shares the process-global `AVAudioSession`, and what it does when something interrupts playback.

## Overview

``ABPlayer`` never touches the process-global `AVAudioSession` unless you opt in. Both policies are off by default:

```swift
var configuration = ABPlayerConfiguration()
configuration.audioSessionPolicy = .playback(mixWithOthers: false)
configuration.interruptionPolicy = .pauseAndResume
player.configuration = configuration
```

Leaving them alone is a real choice, not an oversight: a library that activates a category behind your back can silence the host app's own audio.

## Applying a Category

``ABPlayerConfiguration/audioSessionPolicy`` defaults to `.unmanaged`.

Set to `.playback` or `.ambient`, the category is applied the moment the player becomes `.current` — or when ``ABPlayer/play()`` starts, whichever comes first — and restored automatically afterward.

Concurrent players share one process-wide participant count rather than each applying the category for themselves. A feed of `.preloaded`/`.current` cells is the case this exists for: the previous category is captured before the **first** participating player applies its policy, and restored only once the **last** one releases. One cell's ``ABPlayer/release()`` therefore never disrupts a sibling still relying on the session.

> Important: If the host app had already activated `AVAudioSession` itself before the first participant applied a policy, restoring on the last release can still deactivate the session out from under the app. `AVAudioSession` exposes no public getter for "was already active", so that case cannot be distinguished from "we activated it". Plan the app's own session handling with this in mind.

``ABAudioSession`` is the type to reach for when you want to apply or deactivate a policy directly rather than through a player's grade transitions.

## Interruptions

``ABPlayerConfiguration/interruptionPolicy`` defaults to `.ignore`.

Set it to `.pauseAndResume` to pause automatically when a phone call, Siri, or another app interrupts playback, and to resume once the interruption ends.

Resumption is conditional on **both** of the following, so an interruption never restarts playback the user had already stopped:

- the system reports `AVAudioSessionInterruptionOptionKey.shouldResume`, and
- this player was actually playing before the interruption began.

Resuming reactivates the audio session through the same shared participant count that ``ABPlayerConfiguration/audioSessionPolicy`` uses, so the two policies compose without extra wiring.

## Route Changes

``ABPlayerConfiguration/pausesOnRouteChangeDeviceUnavailable`` defaults to `true` and is independent of the interruption policy. It pauses when the current output device disappears — headphones unplugged, for example — matching the platform convention that content should stop rather than continue playing out loud. Set it to `false` to opt out.

## Observing All Three

Every one of these paths reports through the same ``ABPlayerEvent`` stream rather than a separate delegate:

- ``ABPlayerEvent/audioInterruptionBegan``
- ``ABPlayerEvent/audioInterruptionEnded(resumed:)``
- ``ABPlayerEvent/audioRouteChangedDeviceUnavailable``

## Topics

### Policies

- ``ABAudioSessionPolicy``
- ``ABInterruptionPolicy``
- ``ABAudioSession``
