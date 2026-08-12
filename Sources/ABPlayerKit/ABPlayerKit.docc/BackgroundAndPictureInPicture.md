# Background Policy and Picture in Picture

How ``ABBackgroundPolicy`` and ``ABPictureInPictureSession`` interact.

## Overview

`AVPictureInPictureController` renders from the same `AVPlayerLayer` a background policy's automatic side effects would otherwise pause or detach. Left unresolved, backgrounding while PiP is active would kill the very thing PiP exists to keep alive. This library resolves the conflict with one rule:

**While a ``ABPictureInPictureSession`` bound to a player is active, every ``ABBackgroundPolicy``'s automatic background/foreground side effects are suppressed for that player.**

The suppression covers only automatic side effects — a background policy reacting to `willResignActive`/`didEnterBackground`/`willEnterForeground`. It does not cover anything the consumer does explicitly.

## Policy × Picture in Picture Matrix

| Policy | PiP inactive | PiP active |
|---|---|---|
| `.ignore` | Unaffected (already PiP-compatible) | Unaffected |
| `.pause` (default) | Pauses in background, resumes on return | **Keeps playing** — the default configuration now supports PiP |
| `.pauseAndDetachLayer` | Pauses + detaches in background, restores on return | **Layer stays attached, keeps playing** — the PiP window stays alive |
| `.demoteToInstance` | Demotes to `.instanceOnly` in background | Unaffected (nothing to demote — PiP requires an item) |
| `.continueAudioOnly` | Detaches the layer only, keeps playing | **Layer stays attached too** — PiP needs the video, not only the audio |

When PiP is inactive, every policy's behavior is byte-identical to before this suppression existed.

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
