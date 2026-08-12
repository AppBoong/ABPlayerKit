# Remote Commands and Ownership

Which lock-screen commands activate, and how ownership moves between players.

## Overview

## The "no empty handlers" invariant

**A remote command is enabled only if it has a real, observable action behind it.** A Control Center button that does nothing when pressed is worse than no button at all.

| Command | Default | Maps to | Activates when |
|---|---|---|---|
| Play | On | `player.play()` | Always (the owner is always `.current`) |
| Pause | On | `player.pause()` | Always |
| Toggle Play/Pause | On | `isPlaying ? pause() : play()` | Always — this is the real path a headset button takes |
| Skip Forward | On | `player.skip(by: +interval)` | Always — `interval` is ``ABNowPlayingConfiguration/skipInterval`` |
| Skip Backward | On | `player.skip(by: -interval)` | Always |
| Change Playback Position | On | `player.seek(to:)` | Only while the current item's duration is finite — re-evaluated whenever duration becomes known or the item changes |
| Change Playback Rate | Off | `player.setRate(_:)` | Only when ``ABNowPlayingConfiguration/supportedPlaybackRates`` is non-empty |
| Next Track | Off | The `next` handler from `setTrackNavigationHandlers(next:previous:for:)` | Only when a handler is installed — this library has no queue/playlist concept of its own |
| Previous Track | Off | The `previous` handler | Only when a handler is installed |

Out of scope entirely: continuous seek (`seekForward`/`seekBackward`), `changeRepeatMode`, `changeShuffleMode`, `like`/`dislike`/`rating`/`bookmark`, and `stop` — none has a corresponding concept in `ABPlayerKit`.

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
