# Roadmap

Where ABPlayerKit is going after v0.5.1, and why in this order. It comes from a senior video-player review of v0.5.0 (AVFoundation engine, public API, architecture) followed by a design review of each candidate against the current code.

Two constraints shape every item:

- **Stay a thin wrapper.** `avPlayer` and `avPlayerItem` remain public escape hatches. A feature that only works by hiding AVFoundation, or by silently swapping the objects behind those properties, is out of scope or opt-in.
- **Stay additive until 1.0.** Per [POLICY-api-stability](POLICY-api-stability.md), nothing is removed before 1.0.0. Replacements ship first, and the old API is deprecated alongside them.

Effort is S (a day), M (a few days), or L (a week or more). Claims about AVFoundation behaviour that haven't been verified on a device are marked *unverified*.

## v0.5.2 — correctness patch

| Item | Status | Notes |
|---|---|---|
| A pause at the loop point is undone by the loop restart | **Fixed** | Reproduced with real AVFoundation (0.6 s looping fixture): `rate` went back to 1.0. |
| Controls show a play icon while a video loops | **Not a bug** | Suspected from reading the presenter; a real-AVFoundation test shows the pause icon across loops, and now pins it. |
| Cache reads are not chunked | Planned · S | With `requestsAllDataToEndOfResource`, the servicer loads everything from the offset to the end of the file in one call (`ABLoadingRequestServicer`), and the store reads it into a single `Data` on its actor. That can be a whole-file allocation that blocks every other load. Bound each read to about 512 KiB and check cancellation between reads. |
| `AVPlayer.seek`'s `finished` flag is ignored | Planned · S | An interrupted seek still broadcasts `.seekCompleted`. The coalescer serializes ABPlayer's own seeks, so in practice the interrupter is the loop restart. Return `(landed, finished)` from the target. |

## v0.6.0 — streaming-grade AVFoundation

**Theme:** live windows, network-aware ABR, display-aware variant caps, and media selection, all built on the existing seams (the target protocol, `ABPlaybackTuning`, the asset factory). Everything is additive.

Ordered into PR-sized units:

1. **Periodic-time demand API** · S
   - Today the controls lease the player's interval by writing `player.configuration.periodicTimeInterval` and restoring it later. Two controls views on one player restore in the wrong order, and a consumer change made during the lease is lost.
   - Add `requestPeriodicTime(interval:) -> ABObservationToken`. Demands are refcounted, and the effective interval is the finest of the configuration and all demands, the same rule `position` already uses.

2. **Network-aware tuning** · S
   - New `ABPlaybackTuning` fields: `preferredPeakBitRateForExpensiveNetworks`, `preferredMaximumResolutionForExpensiveNetworks`, and `startsOnFirstEligibleVariant` (for faster feed startup).
   - In `ABDefaultAssetFactory`, the `AVURLAsset` network-access options for expensive and constrained networks.

3. **Gravity-aware resolution cap** · S–M
   - `ABPlayerView` reports raw `bounds × scale` as the cap. A 16:9 video in a portrait aspect-fill cell is rendered far larger than those bounds suggest, so the cap can select too low a variant (*unverified*: whether AVFoundation compares per dimension).
   - Resolve the cap with a pure function of view pixels, `presentationSize`, and gravity. Table-test it.

4. **Item configurator** · S
   - `ABItemConfigurator.configure(_ item: AVPlayerItem, for: ABMediaSource)`, called before `replaceCurrentItem`. Excluded from configuration equality, like `assetFactory`.
   - It is the one place for `externalMetadata`, `automaticallyLoadedAssetKeys`, `forwardPlaybackEndTime`, or a FairPlay `contentKeySession` recipe.
   - The asset factory stays synchronous; async preparation such as a token refresh is v0.7 at the earliest.

5. **Media selection that survives re-attach** · M
   - Configure preferences as a `Sendable` value, applied with `AVPlayer.setMediaSelectionCriteria(_:forMediaCharacteristic:)`. The criteria live on the `AVPlayer`, so they carry over to every new item.
   - A read-only option listing plus `select(_:)` for a picker. "Off" uses `allowsEmptySelection`; forced subtitles are handled.
   - This replaces the "re-apply on every `.itemAttached`" advice in *Subtitles and Audio Tracks*.

6. **Extract `ABSeekController`** · M · behaviour-neutral
   - Moves the coalescer, scrub sessions, skip, and the seek worker (about 250 lines) out of the 1,500-line `ABPlayer`.
   - Lands before Live, because Live changes clamping.

7. **Live and DVR** · L · depends on 6
   - New API: `seekableRange`, `isLive`, `seekToLiveEdge()`, and a `.seekableRangeChanged` event. `configuredTimeOffsetFromLive` goes in tuning; `canUseNetworkResourcesForLiveStreamingWhilePaused` goes in configuration.
   - Seeks clamp to `seekableTimeRanges` at the moment they are issued, because the window moves. Today the clamp is `0...duration`, which is wrong for a sliding window.
   - Follow-ups in the same release: Controls (a live scrubber) and the Now Playing `isLiveStream` value.

8. **Seek-aware QoE** · S–M · benefits from 6
   - Buffering after a seek or scrub currently counts as rebuffering.
   - Add a `cause` field to `ABBufferingInterval` and a seek-buffer total on the session summary. A new field, not a new `Phase` case, because `Phase` isn't one of the enums the policy marks non-exhaustive.

9. **Start position** · S
   - `load(_:startAt:autoplay:)`. A prerequisite for resume and for v0.7's recovery.

## v0.7.0 — resilience

- **Error recovery**, in three steps:
  1. `retry(resumingAt:)`.
  2. Rebuild the `AVPlayer` after `mediaServicesWereResetNotification`. This must be announced with an event, since the object behind `avPlayer` changes.
  3. An opt-in `ABRecoveryPolicy` with backoff for retryable network errors, gated on `NWPathMonitor`.
- **Background audio via `audiovisualBackgroundPlaybackPolicy`** (iOS 15) instead of detaching the layer, which is the mechanism `.continueAudioOnly` uses today.
- **HLS download reconciliation:**
  - Tag tasks with `taskDescription` and reconcile them with `getAllTasks` when the session is created. A completion that arrives after a relaunch currently orphans its `.movpkg`.
  - Count downloads against a disk budget.
  - Document it as an offline download; the `.preloaded` grade already does preload buffering.
- **Contract cleanup:**
  - Deprecate `.failed` in favour of `.failureReported`, and `.playbackRejected` in favour of `.callRejected`.
  - Queue events within a grade transition, so an observer that calls back into the player can't see a half-applied transition.
- **SwiftUI controls parity:** `onEvent:` and a visibility binding on `ABVideoPlayerWithControls`, and slot-keyed accessories through a modifier instead of more initializers.
- **Trick play:** seek-bar thumbnails from HLS I-frame playlists. `AVAssetImageGenerator` alone does not work for HLS.

## Later, or not here

| Item | Decision | Why |
|---|---|---|
| Gapless looping with `AVPlayerLooper` | Later, opt-in | It needs `AVQueuePlayer` and plays replica items, so `avPlayerItem` would no longer be the item that was attached, and per-item events would be dropped by the identity check. Revisit as a separate target conformer. |
| Async asset factory | Later | It makes the synchronous attach path async, which means redesigning the grade planner. |
| Decoder budget across preloaded players | Elsewhere | Orchestrating a feed window is a feed library's job, not the player's. |
| CMCD request headers | Later | Platform support needs checking first. |
| FairPlay | Not as a feature | A documented recipe through the item configurator instead. A DRM layer would be exactly the abstraction this package avoids. |
| HDR | Documentation | `AVPlayer.eligibleForHDRPlayback` is a single static check. |
