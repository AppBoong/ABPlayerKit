# Troubleshooting

Symptoms that come up first, and what each one usually means.

## Overview

**The video area is black and nothing plays.**
A player only loads media once it holds an item. Confirm the player holds an item: call `load(_:)`, or `set(source:grade:)` at `.current` or `.preloaded`. At `.instanceOnly` a player deliberately holds no item and makes no network requests. Then check `player.lastFailure` for a terminal failure. Note that `lastDiagnostic` carrying an `.itemErrorLogEntry` is normal for a healthy stream and is not the cause.

**`play()`, `pause()`, or `seek()` seem to do nothing.**
Playback control calls are ignored — not thrown — while `grade != .current`. Observe `.callRejected(ABRejectedCall, grade:)` to see which call was dropped and at what grade.

**There's no sound, or sound stops when the silent switch is on.**
`audioSessionPolicy` defaults to `.unmanaged`, meaning this library never touches `AVAudioSession`. Set `configuration.audioSessionPolicy = .playback(mixWithOthers: false)` for playback that ignores the silent switch.

**The host app's own audio stops when a player is released.**
If the app had already activated `AVAudioSession` before the first managed player applied a policy, the restore on last release can deactivate it. `AVAudioSession` has no public "was already active" getter, so this can't be detected — see <doc:AudioSessionAndInterruptions>.

**Background audio stops as soon as the app backgrounds.**
`.continueAudioOnly` needs all three conditions in <doc:BackgroundAndPictureInPicture>, including `UIBackgroundModes` containing `audio` in the **host app's** `Info.plist`. Missing any one makes it silently behave like `.pause`.

**Playback stays paused after returning from the background.**
That's intended if `pause()` was called while backgrounded — an explicit pause is authoritative. The automatic resume only covers the system suspending playback on its own.

**The Picture in Picture button does nothing.**
Check `ABPictureInPictureSession.isSupported` (usually `false` in the simulator — test on a device) and `session.isPossible`, which requires the bound layer to be ready for display. PiP also needs `audioSessionPolicy != .unmanaged`, and works **only** on the `player:` explicit-ownership initializers.

**Lock screen controls don't appear, or some buttons are missing.**
Link `ABPlayerKitNowPlaying` and call `attach`, retaining the returned token. Only a `.current` player is eligible. Change-rate and next/previous-track are **not** in `ABRemoteCommandSet.default` and need explicit opt-in — see [Remote Commands](https://appboong.github.io/ABPlayerKit/documentation/abplayerkitnowplaying/remotecommands/).

**A `switch` over `ABPlayerEvent`, `ABMetricEvent`, or `ABBackgroundPolicy` stopped compiling after an update.**
These are non-exhaustive by policy; minor releases may add cases. Add a `default` branch.

**A subtitle or audio track selection is lost.**
Every source change, demotion, or `release()` attaches a **new** `AVPlayerItem`. Re-apply the selection on each `.itemAttached(source:)` event — this library stores no selection state.

**Playback stutters in a feed with several live players.**
Keep off-screen cells at `.preloaded` or `.instanceOnly` rather than `.current`, keep `preloadTuning` conservative, and set `allowsExternalPlayback = false` on every instance except the current one.
