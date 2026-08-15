# Background Policy and Picture in Picture

How ``ABBackgroundPolicy`` and ``ABPictureInPictureSession`` interact.

## Overview

`AVPictureInPictureController` renders from the same `AVPlayerLayer` a background policy's automatic side effects would otherwise pause or detach. Left unresolved, backgrounding while PiP is active would kill the very thing PiP exists to keep alive. This library resolves the conflict with one rule:

**While a ``ABPictureInPictureSession`` bound to a player is active, every ``ABBackgroundPolicy``'s automatic background/foreground side effects are suppressed for that player.**

The suppression covers only automatic side effects — a background policy reacting to `willResignActive`/`didEnterBackground`/`willEnterForeground`. It does not cover anything the consumer does explicitly.

## What Each Policy Does

``ABPlayerConfiguration/backgroundPolicy`` controls what happens to a `.current` player when the app leaves the foreground. The default is `.pause` — this library installs app-state observers and acts on them unless you choose `.ignore`.

| Policy | On background entry | On foreground return |
|---|---|---|
| `.ignore` | Nothing | Nothing (besides re-marking the audio session for reactivation) |
| `.pause` (default) | Pauses if `.current` | Resumes if it was playing |
| `.pauseAndDetachLayer` | Pauses if `.current`; detaches `AVPlayerLayer.player` (releases the decoder) | Re-attaches the layer; resumes if it was playing |
| `.demoteToInstance` | Demotes to `.instanceOnly` (drops the item; blocks network entirely) | Restores the prior grade |
| `.continueAudioOnly` | Detaches `AVPlayerLayer.player` only — playback keeps running | Re-attaches the layer; resumes only if the system suspended playback anyway, never overriding an explicit `pause()` |

That table describes a player with no active PiP session. When one *is* active, the matrix in the next section takes over.

`ABBackgroundPolicy` is non-exhaustive — a `switch` over it outside this package should include a `default` branch.

### Who Wins While Backgrounded

`.continueAudioOnly` is the only policy where playback keeps running while backgrounded, so it is the only one where the user can pause it there — from the lock screen, Now Playing, or a controls overlay.

An explicit ``ABPlayer/pause()`` while backgrounded is authoritative: playback stays paused on the return to foreground. The resume in the table above is a safety net for the system suspending playback on its own, and it does not fire when a `pause()` came in between.

### Prerequisites for `.continueAudioOnly`

Without all three, it silently degrades to `.pause`-like behavior. There is no runtime warning.

| # | Condition | Who sets it |
|---|---|---|
| 1 | `UIBackgroundModes` includes `audio` | The host app's `Info.plist` — this library cannot do it for you |
| 2 | ``ABPlayerConfiguration/audioSessionPolicy`` is `.playback(mixWithOthers:)` or `.ambient` | The app |
| 3 | ``ABPlayerConfiguration/backgroundPolicy`` is `.continueAudioOnly` | The app |

## Policy × Picture in Picture Matrix

| Policy | PiP inactive | PiP active |
|---|---|---|
| `.ignore` | Unaffected (already PiP-compatible) | Unaffected |
| `.pause` (default) | Pauses in background, resumes on return | **Keeps playing** — the default configuration now supports PiP |
| `.pauseAndDetachLayer` | Pauses + detaches in background, restores on return | **Layer stays attached, keeps playing** — the PiP window stays alive |
| `.demoteToInstance` | Demotes to `.instanceOnly` in background | Unaffected (nothing to demote — PiP requires an item) |
| `.continueAudioOnly` | Detaches the layer only, keeps playing | **Layer stays attached too** — PiP needs the video, not only the audio |

When PiP is inactive, every policy's behavior is byte-identical to before this suppression existed.

## Binding a Session

Bind an ``ABPictureInPictureSession`` to an ``ABPlayerView``, or pass one to ``ABVideoPlayer``'s explicit-ownership initializer:

```swift
import ABPlayerKit
import SwiftUI

struct VideoScreen: View {
    let player: ABPlayer
    @State private var pictureInPicture = ABPictureInPictureSession()

    var body: some View {
        ABVideoPlayer(player: player, pictureInPicture: pictureInPicture)
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay(alignment: .topTrailing) {
                if pictureInPicture.isPossible {
                    Button(pictureInPicture.isActive ? "Stop PiP" : "Start PiP") {
                        pictureInPicture.isActive ? pictureInPicture.stop() : pictureInPicture.start()
                    }
                }
            }
    }
}
```

``ABPictureInPictureSession/isPossible`` gates the button because the layer has to be ready for display before PiP can start; ``ABPictureInPictureSession/isSupported`` is the device-level check, and is usually `false` in the simulator.

## What Isn't Suppressed

The suppression is scoped to the background policy's own automatic actions. These are never suppressed, even with an active PiP session:

- **`player.release()`** — ends PiP. The session observes `isActive` becoming `false` via KVO and releases its hold on the bound view.
- **Demoting below `.current`** (`promote(to:)`) — ends PiP for the same reason.
- **A source change on the same instance** — treated as ending PiP; the session's KVO-driven state tracks whatever `AVPictureInPictureController` actually reports.
- **Reassigning `ABPlayerView.player`** — ends PiP; the session stays bound to the *view*, and can restart once a new player attaches and the layer becomes possible again.
- **An audio interruption** (phone call, Siri) — still pauses. If the phone rings, the PiP window should pause too.
- **A route change with the output device disappearing** (headphones unplugged) — still pauses, matching platform HIG expectations.
- **`.playedToEnd`** — the PiP window stops at the final frame; this library does not restart or replay automatically.

## The Background-Entry Race

`canStartPictureInPictureAutomaticallyFromInline` (mirrored by ``ABPictureInPictureSession/startsAutomaticallyFromInline``, default `false`) starts PiP at the moment of backgrounding. The platform does not guarantee whether the background-policy notification or PiP's own activation KVO lands first — if the policy runs first, PiP can start against an already-paused, already-detached player.

`ABPlayer` repairs this: when PiP activation is reported, if the layer is detached it re-attaches, and if the player was playing before backgrounding but the repair finds it stopped, it resumes. This repair path can therefore surface as a brief pause-then-resume when `startsAutomaticallyFromInline` is enabled. The primary supported path remains **starting PiP explicitly while in the foreground**.

## Prerequisites

| Prerequisite | Who provides it |
|---|---|
| `UIBackgroundModes` includes `audio` (for PiP or `.continueAudioOnly` to survive backgrounding) | The host app's `Info.plist` — this library cannot do it for you |
| `ABPlayerConfiguration/audioSessionPolicy` isn't `.unmanaged` | The app |
| Device/OS supports Picture in Picture | ``ABPictureInPictureSession/isSupported`` — usually `false` in the simulator |
| The bound layer is ready for display | ``ABPictureInPictureSession/isPossible`` |

## Scope

Picture in Picture is supported only on the explicit-ownership path (`ABVideoPlayer.init(player:videoGravity:pictureInPicture:)`). The convenience `url:`/`source:` initializers release their owned player when the SwiftUI identity is discarded, which would cut PiP short — extending that path is tracked as future work, not implemented here.
