# Remote Commands and Ownership

Which lock-screen commands activate, and how ownership moves between players.

## Overview

## The "no empty handlers" invariant

**A remote command is enabled only if it has a real, observable action behind it.** A Control Center button that does nothing when pressed is worse than no button at all.

A command activates only when **both** of these hold: (1) it's included in `ABNowPlayingConfiguration.commands` (an ``ABRemoteCommandSet``), and (2) the action it maps to actually exists. ``ABRemoteCommandSet/default`` — the `commands` default — is `.play, .pause, .togglePlayPause, .skipForward, .skipBackward, .changePlaybackPosition`; it **excludes** `.changePlaybackRate`, `.nextTrack`, and `.previousTrack`. Supplying a rates list or a handler alone, without also expanding `commands`, leaves those three disabled with no runtime signal that anything is missing:

| Command | In `.default`? | Maps to | Also requires |
|---|---|---|---|
| Play | Yes | `player.play()` | Nothing further — always enabled |
| Pause | Yes | `player.pause()` | Nothing further — always enabled |
| Toggle Play/Pause | Yes | `isPlaying ? pause() : play()` | Nothing further — this is the real path a headset button takes |
| Skip Forward | Yes | `player.skip(by: +interval)` | Nothing further — `interval` is ``ABNowPlayingConfiguration/skipInterval`` |
| Skip Backward | Yes | `player.skip(by: -interval)` | Nothing further |
| Change Playback Position | Yes | `player.seek(to:)` | The current item's duration to be finite — re-evaluated whenever duration becomes known or the item changes |
| Change Playback Rate | **No** | `player.setRate(_:)` | `commands` must include `.changePlaybackRate`, **and** ``ABNowPlayingConfiguration/supportedPlaybackRates`` must be non-empty |
| Next Track | **No** | The `next` handler from `setTrackNavigationHandlers(next:previous:for:)` | `commands` must include `.nextTrack`, **and** a handler must be installed — this library has no queue/playlist concept of its own |
| Previous Track | **No** | The `previous` handler | `commands` must include `.previousTrack`, **and** a handler must be installed |

Enabling the three off-by-default commands needs both an expanded `commands` set and the matching action:

```swift
var configuration = ABNowPlayingConfiguration()
configuration.commands = .default.union([.nextTrack, .previousTrack, .changePlaybackRate])
configuration.supportedPlaybackRates = [1, 1.5, 2]

let token = ABNowPlayingCenter.shared.attach(player, metadata: metadata, configuration: configuration)
ABNowPlayingCenter.shared.setTrackNavigationHandlers(
    next: { player.skipToNextEpisode() },
    previous: { player.skipToPreviousEpisode() },
    for: player
)
```

Out of scope entirely: continuous seek (`seekForward`/`seekBackward`), `changeRepeatMode`, `changeShuffleMode`, `like`/`dislike`/`rating`/`bookmark`, and `stop` — none has a corresponding concept in `ABPlayerKit`.

``ABNowPlayingConfiguration/skipInterval`` defaults to 15 seconds — a different default than `ABPlayerKitControls`' `ABPlayerControlsConfiguration.skipInterval` (10 seconds). The two configurations are independent: a consumer using both `ABPlayerKitControls` and `ABPlayerKitNowPlaying` on the same player should set both explicitly if the on-screen skip buttons and the lock-screen skip commands should agree.

## Ownership rules

`MPNowPlayingInfoCenter`/`MPRemoteCommandCenter` are exclusive, process-wide singletons — unlike `ABPlayer`, which is designed to have several concurrent instances (a feed). ``ABNowPlayingCenter`` reconciles the two with a small set of rules:

1. **Eligibility**: only a participant whose player is `ABPlaybackGrade/current` may own the surface.
2. **Acquisition**: the most recently eligible participant takes ownership immediately (last-eligible-wins).
3. **Relinquishing**: an owner that loses eligibility, has its token cancelled, or is deallocated hands ownership to whichever eligible participant is next on the stack.
4. **Contention**: if two participants are `.current` simultaneously, the one that became eligible more recently owns; the other waits. If the current owner relinquishes, the waiting one resumes ownership automatically.
5. **Restoration**: once the last participant relinquishes, whatever `MPNowPlayingInfoCenter`/`MPRemoteCommandCenter` state existed before the first `attach` is restored exactly.
6. **No touch**: while no participant is eligible, this bridge reads and writes neither singleton at all.

## What isn't covered

Actual lock-screen/Control Center display, real headset/remote button presses, and Now Playing contention with another app can only be verified on a physical device — the simulator has no real Now Playing surface to observe against.
