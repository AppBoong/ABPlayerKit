# Changelog

All notable changes to ABPlayerKit are documented in this file.

## [Unreleased]

### Added

- Added `ABVideoPlayer.init(url:videoGravity:autoplay:configuration:)` and `init(source:videoGravity:autoplay:configuration:)` — the view creates and owns an `ABPlayer` for its SwiftUI identity's lifetime, releasing it when that identity is discarded (never on `onDisappear`, since that signals "not visible," not "gone for good"). `autoplay` defaults to `true`.
- Added the matching `ABVideoPlayerWithControls.init(url:videoGravity:autoplay:playerConfiguration:)` / `init(source:videoGravity:autoplay:playerConfiguration:)`, each with an `accessories:`-taking overload — same ownership, plus the standard controls overlay. This is the new one-line Quick Start path.
- Added `.playerControlsStyle(_:)` and `.playerControlsConfiguration(_:)` view modifiers, backed by new `EnvironmentValues.playerControlsStyle`/`playerControlsConfiguration` — set once on an ancestor view to cover every `ABPlayerControls`/`ABVideoPlayerWithControls` in its subtree. An explicit `style:`/`configuration:` initializer argument always wins over the modifier for that one view.
- `ABPlayerKitMetrics` now tracks whole playback sessions, not just TTFF: `ABMetricsRecorder.endSession(for:)` and `snapshot(for:)`, and four new `ABMetricEvent` cases — `.sessionStarted`, `.buffering`, `.failure`, `.sessionSummary` — covering rebuffer intervals (with buffering-before-first-frame kept out of the rebuffer ratio), watch time, completion ratio, and failure classification. New public types: `ABSessionAnchor`, `ABBufferingInterval`, `ABFailureRecord`, `ABSessionSummary`, `ABQoESummary`, `ABLatencyDistribution`.
- Added `ABPlaybackStatistics.waited` — a latency distribution over `.waited` samples only, alongside the legacy `p50`/`p95`/`max`, which keep folding `.hit` in as `0` ms.
- Added `ABAccessSnapshot` fields folded from the *entire* access log instead of only its last entry: `totalBytesTransferred`, `totalStallCount`, `droppedVideoFrameCount`, `bitrateSwitchCount`, `segmentsDownloadedCount` (always `0` — see Migration notes), `mediaRequestCount`, `durationWatchedSeconds`, `observedBitrateAverage`, `initialStartupTimeSeconds`, `entryCount`.
- Added `ABClock.wallClockEpoch` (default `Date().timeIntervalSince1970`) — maps a session's monotonic timeline onto a wall-clock instant once, at session open, for joining against server-side logs.
- `ABJSONLinesMetricsSink.flush()` is now `public`. Added `writeFailureCount`/`lastWriteErrorDescription` (a persistent write failure no longer fails silently) and file rotation via `init(fileURL:maxFileSizeBytes:maxRotatedFiles:)`.
- `ABMetricsRecorder.init` gained `includesSourceURL: Bool` (default `true`) — set `false` to keep signed/tokenized source URLs out of session anchors and summaries.
- Added `ABPlayer.lastFailure`/`.lastDiagnostic` (both `ABPlayerFailure?`) — a failure's classification (the existing `ABPlayerError`) paired with its originating subsystem via the new `ABErrorOrigin` (`domain`/`code`, reduced from the underlying `NSError` to `Sendable`/`Equatable` primitives), when known. Terminal failures land in `lastFailure`, cleared on the next attach/source change/detach/release; the one non-terminal case (`.itemErrorLogEntry`, which a still-loading or still-playing stream routinely surfaces on its own) lands in `lastDiagnostic` instead, so it can never masquerade as a real failure. `ABPlayer.lastError` is unchanged, now a computed projection of `lastFailure?.kind`. Broadcast through the new `ABPlayerEvent.failureReported(ABPlayerFailure)`, alongside the legacy `.failed(ABPlayerError)` at the same site — new code should prefer `.failureReported` for the provenance.
- Added `ABRejectedCall` and `ABPlayerEvent.callRejected(ABRejectedCall, grade:)` — identifies which call (`play`/`pause`/`seek`/`skip`/`beginScrubbing`/`scrub`/`endScrubbing`) was ignored because `grade != .current`, and at what grade, broadcast alongside the existing `.playbackRejected` at the same site. Previously `.playbackRejected` alone gave no way to tell which call triggered it.
- Added `ABPlayerEvent.itemAttached(source:)` — broadcast once per attach, immediately after the item attaches and before that action's `.tuningApplied`.
- Added `ABPlaybackTuning.audioTimePitchAlgorithm` (default `nil`, leaving `AVFoundation`'s own default algorithm unchanged) — passes through to `AVPlayerItem.audioTimePitchAlgorithm`, for a consumer using non-`1.0` `ABPlaybackRate` values who wants to opt into (or explicitly out of) time-pitch correction. Added at the end of `ABPlaybackTuning.init`'s parameter list to keep existing positional-adjacent call sites source-compatible.
- Added `ABPlayerEvent.bufferingChanged(Bool)`, `.durationAvailable(CMTime)`, `.stallEnded`, `.presentationSizeChanged(CGSize)`, and `.mutedChanged(Bool)` — event-stream counterparts for state a consumer previously had to poll: `isBuffering`/`duration` changing, a `.playbackStalled` resolving back to playing (the boundary signal for a stall left unresolved by a detach/release stays `.itemDetached`), the item's rendered size becoming known, and `ABPlayerConfiguration.isMuted` actually reaching the target.
- Added `ABBackgroundPolicy.continueAudioOnly` — keeps playing in the background instead of pausing, by detaching `AVPlayerLayer.player` (the condition iOS requires for backgrounded audio to continue) and re-attaching on foreground return. Requires the host app's `UIBackgroundModes` to include `audio` and `ABPlayerConfiguration.audioSessionPolicy` to be something other than `.unmanaged`; without both, it falls back to `.pause`-like behavior (resumes on foreground return). See the README's new "Background Policy" section.
- Added `ABPictureInPictureSession` and `ABPlayerView.pictureInPictureSession` — bind a session to a view to enable Picture in Picture for that view's backing layer, without exposing `AVPlayerLayer` itself. Added the matching `ABVideoPlayer.init(player:videoGravity:pictureInPicture:)` for SwiftUI's explicit-ownership path. While a session is active, every `ABBackgroundPolicy`'s automatic background/foreground side effects are suppressed for that player, so PiP keeps rendering instead of being paused/detached out from under itself. Picture in Picture is supported only on the explicit-ownership path — see the README's new "Picture in Picture" section for scope and platform prerequisites.
- Added `ABPlayerConfiguration.allowsExternalPlayback` (default `true`), `.usesExternalPlaybackWhileExternalScreenIsActive` (default `false`), and `.externalPlaybackVideoGravity` (default `.resizeAspect`) — direct passthroughs to the matching `AVPlayer` AirPlay properties, all defaulting to `AVPlayer`'s own defaults. Added the matching read-only `ABPlayer.isExternalPlaybackActive`. See the README's new "AirPlay" section.
- Added the `ABPlayerKitNowPlaying` target: an opt-in bridge from `ABPlayer` to `MPNowPlayingInfoCenter`/`MPRemoteCommandCenter`, entered through `ABNowPlayingCenter.shared.attach(_:metadata:configuration:artwork:)`. Ownership is exclusive and automatic — only a `.current` player is eligible, and the most recently eligible one owns the surface (last-eligible-wins), restoring whatever state existed before the first attach once the last participant relinquishes. Remote commands activate only when a corresponding action exists. See the README's new "Now Playing and Remote Commands" section and the target's own DocC catalog.
- Added a buffering indicator: `ABPlayerControlsView` overlays a spinner on the play/pause button's glyph while `ABPlayer.isBuffering` is true (button stays enabled and hit-testable throughout — a stall can still be paused). Controlled by `ABPlayerControlsConfiguration.showsBufferingIndicator` (default `true`) and `ABPlayerControlsStyle.bufferingIndicatorColor` (default `nil`, follows `tintColor`). Auto-hide is suppressed while buffering, without forcing controls visible.
- Added `ABControlsSlot` (`.topTrailing`, `.transportTrailing`, `.bottomTrailing`) and `ABPlayerControlsView.accessoryViews(in:)`/`setAccessoryViews(_:in:)` — place consumer views at additional overlay positions. The existing `accessoryViews` property is now an alias for `.bottomTrailing`, with identical behavior.
- Added `ABPlayerControlsConfiguration.showsPlayPauseButton`/`.showsSeekBar` (both default `true`) — hide either control the same way `showsSkipButtons` already does.
- Added `ABControlsTouchPassthrough` (`.never`/`.whenControlsHidden`/`.always`) and `ABPlayerControlsConfiguration.touchPassthrough` (default `.never`) — let touches that miss every control pass through to whatever is behind the overlay. Never overrides the existing hit-test priority order; only applies when nothing else claimed the touch.
- Added `ABDoubleTapSeek` (`.disabled`/`.edges(edgeWidthFraction:)`) and `ABPlayerControlsConfiguration.doubleTapSeek` (default `.disabled`) — double-tapping the overlay's leading/trailing edge bands seeks by `skipInterval`. Disabled by default so the background single-tap recognizer never waits out a double-tap timeout for consumers who don't opt in.
- Added `ABPlayerControlsConfiguration.providesHapticFeedback` (default `true`) — a light haptic on an accepted double-tap seek.
- Added a cumulative seek-feedback badge ("+20s"/"-10s") shown while a skip/double-tap/VoiceOver-adjustment seek streak is outstanding, driven entirely by the core's `pendingSeekTime`/`seekTargetChanged` — Controls never accumulates the delta itself. Styled via `ABPlayerControlsStyle.seekFeedbackTextColor`/`.seekFeedbackBackgroundColor`/`.seekFeedbackFont`.
- Added replay-from-start: tapping play after playback reaches the end now seeks to zero before playing, instead of a bare `play()` (which does nothing at the end of an item).
- Added `ABPlayerControlsConfiguration.RateLabelFormat` (`.automatic`/`.custom`) and `.rateLabelFormat` (default `.automatic`) — `.automatic` formats the playback rate with a locale-aware `NumberFormatter` (`"1.5"` in `en`, `"1,5"` in `de`) instead of the previous `%g`-based, always-dot-separated formatting. The rate menu's item titles now use the same formatting path as the button's own title (previously the menu always hardcoded a `"×"` suffix independent of `ABPlayerControlsStyle.rateLabelStyle`).
- Added `ABPlayerControlsConfiguration.timeLabelSeparator` (default `"/"`) — the string between a time label's elapsed and secondary fields, previously hardcoded.
- Added accessibility hints (`accessibilityHint`) on the play/pause, skip, and rate buttons and the seek bar, localized in `en`/`ko`.

### Changed

- `ABPlayerControls`'s and `ABVideoPlayerWithControls`'s `style:`/`configuration:` initializer parameters are now `Optional` (default `nil`) instead of defaulting to `.default`/`.init()`, so the new Environment modifiers above can be distinguished from an explicit argument. Source-compatible: every existing call site that passes a value or omits the parameter keeps compiling and resolves to the exact same behavior, since an unset `Optional` and the old default resolve to the same fallback.
- `ABVideoPlayer`'s `Coordinator` associated type changed from `Void` to a concrete (still-opaque, no public members) class backing the new `url:`/`source:` ownership. Only affects code that references `ABVideoPlayer.Coordinator` by name directly, which no consumer in this repository does.
- The play/pause icon now reflects `isPlaying || isBuffering` instead of `isPlaying` alone, so a stall no longer flips the icon back to the play glyph while the user's intent is still to play (covers both the default `automaticallyWaitsToMinimizeStalling` tuning and the `== false` variant). A play/pause tap's live-value branch was extended the same way.
- The visible "LIVE" duration marker is now Controls' own localized key (`controls.liveMarker`, en/ko) instead of reading `ABTimeFormatter.liveMarker` from the core module directly. The `en` value is unchanged (`"LIVE"`); this only changes which module owns the string.
- `ABPlayerControlsStyle`, `ABControlIcon`, `ABControlsBackgroundStyle`, `ABTrackCornerRadius`, and `ABRateLabelStyle` are now `Sendable`. `ABPlayerControlsStyle.default`/`.minimal`/`.tinted` no longer require `@MainActor` isolation to be stored as global `static let`s, since the type itself is `Sendable` now — the `@MainActor` attribute on those three declarations was removed. See **Migration notes** below.

### Fixed

- `ABBackgroundPolicy.continueAudioOnly` now actually keeps audio playing in the background. The app-lifecycle handlers ran one main-actor turn after the notification that triggered them, so `AVPlayerLayer.player` was still attached at the moment iOS decided whether to grant the app an audio assertion; AVFoundation stopped playback first, nothing was playing, and the process was suspended a few seconds later — the policy behaved like `.pause` with a foreground resume. The handlers now run synchronously inside the notification's own dispatch, which is what clearing the layer's player in the background handler requires. `willResignActive` is fixed the same way: it captures whether playback was live, and that value had already been falsified by decode teardown a turn later.
- Progressive cache: resuming a partial download now validates the origin hasn't changed (`If-Range`/`ETag`/`Last-Modified`, with a defensive `Content-Range` offset/length check for origins with no validator) before appending to the cached prefix, instead of silently mixing bytes from two different versions of the resource.
- `ABMediaCache.removeAll()`/`remove(_:)` no longer fail playback that's in progress for the deleted key — the current read completes over the network and the cache refills as playback continues.
- A VoiceOver-adjustment seek streak's cumulative badge ("+20s") now shows the real accumulated move; it previously showed one `skipInterval` less than the actual distance (e.g. two 10s forward adjustments showed "+0s" then "+10s" instead of "+10s" then "+20s"). The spoken position (`accessibilityValue`) and the actual seek commands were never affected — only the visual badge's own delta. Skip-button and double-tap seeking, which don't share the accessibility path's optimistic pre-render, were unaffected.

### Migration notes

#### `removeAll()`/`remove(_:)` no longer interrupt in-progress playback

Calling `removeAll()`/`remove(_:)` during active playback for the affected source no longer interrupts that playback; it continues over the network instead of failing. No code changes required.

#### `ABMetricEvent` gained 4 cases

`.sessionStarted`, `.buffering`, `.failure`, and `.sessionSummary` were added. A `switch` over `ABMetricEvent` outside this package needs a `default` branch to stay source-compatible — the same non-exhaustive convention already documented on `ABPlayerEvent`.

#### `ABAccessSnapshot`/`ABPlaybackStatistics` gained fields; existing field values are unchanged

`ABPlaybackStatistics.p50`/`p95`/`max` remain the legacy distribution (`.hit` folded in as `0` ms) — new code should read `waited` instead, which excludes `.hit`. `ABAccessSnapshot`'s existing 5 fields keep their v1 values (the last access-log entry); the new fields are folded across every entry. `segmentsDownloadedCount` always reads `0` on this platform: the underlying `AVPlayerItemAccessLogEvent.numberOfSegmentsDownloaded` has been API-unavailable in Swift since iOS 7, superseded by `numberOfMediaRequests`. It's kept in the schema for forward compatibility.

#### `ABClock` gained a `wallClockEpoch` requirement

A default implementation (`Date().timeIntervalSince1970`) is provided, so existing conforming types compile unmodified. Override it in a test fake for a deterministic value.

#### `ABMetricsRecorder.endSession(for:)`/`snapshot(for:)` were added

`attach(to:)`'s returned token has no cancellation hook the recorder can observe, so cancelling it alone produces no final `.sessionSummary`. Call `endSession(for:)` before cancelling the token if you want one.

#### `ABBackgroundPolicy` is now non-exhaustive

`ABBackgroundPolicy` gained a new case (`continueAudioOnly`). Code that `switch`es over `ABBackgroundPolicy` must add a `default` branch to keep compiling.

#### `ABPlaybackTarget` changes are not consumer-visible

The internal `ABPlaybackTarget` protocol (used only as this library's own `AVFoundation` test seam) gained `isExternalPlaybackActive` and `applyExternalPlayback(_:)`. This protocol is `internal`, not part of the public API, so no consumer code is affected.
#### Playback-rate formatting is now locale-aware by default

`ABPlayerControlsConfiguration.rateLabelFormat` defaults to `.automatic`, which now formats rate values with `NumberFormatter` for the current locale instead of the previous `String(format: "%g", rate)`. In `en` (and most locales), rendered text is unchanged (`"1.5"`, `"1"`); locales with a comma decimal separator (e.g. `de`) now render `"1,5"` instead of `"1.5"`. Consumers that need the previous, always-`en`-style formatting regardless of locale can set `rateLabelFormat = .custom { rate in String(format: "%g", rate) }`.

#### `ABPlayerControlsStyle.default`/`.minimal`/`.tinted` are no longer `@MainActor`-isolated

Code that accessed these presets with `await` (needed only because of the old `@MainActor` isolation) now gets a "no async operations occur within 'await' expression" warning, not a source break — the `await` is simply no longer necessary and can be dropped. No behavior changes; these were always main-actor-only values in practice (`ABPlayerControlsStyle` wasn't `Sendable` before), just now expressed without the isolation annotation.

#### Play/pause icon and tap-branch now consider buffering, not just `isPlaying`

Both the play/pause icon and the live-value branch a play/pause tap uses now read `isPlaying || isBuffering` instead of `isPlaying` alone. A consumer observing `ABControlsEvent.playPauseTapped(isPlayingAfterTap:)` may now occasionally see `true` at a moment `ABPlayer.isPlaying` itself still reads `false` (mid-stall, intent-to-play). No action needed unless code was relying on those two values always agreeing.

## [0.3.0] - 2026-08-05

### Added

- `ABPlayer` is now `@Observable`, so SwiftUI views can read `grade`, `isScrubbing`, `hasDisplayedFirstFrame`, `lastError`, `source`, and `configuration` directly and re-render on change — no observer bridge required. The token-based `addObserver`/`ABPlayerEvent` system is unchanged and stays available in parallel for anything needing the *reason* a value changed.
- Added `ABInterruptionPolicy` (`.ignore` default / `.pauseAndResume`) and `ABPlayerConfiguration.interruptionPolicy` — opt-in automatic pause on an `AVAudioSession` interruption (phone call, Siri, another app taking the session) and resume once it ends, reactivating the audio session through the same coordinator `audioSessionPolicy` uses.
- Added `ABPlayerConfiguration.pausesOnRouteChangeDeviceUnavailable` (default `true`) — pauses when the current audio output device disappears (e.g. headphones unplugged), independent of `interruptionPolicy`.
- Added `ABPlayerEvent.audioInterruptionBegan`, `.audioInterruptionEnded(resumed:)`, and `.audioRouteChangedDeviceUnavailable`.
- Added `ABCacheConfiguration.passthroughGapThreshold` (default 2MB) — a request whose offset sits this far ahead of the cache's linear fill prefix now skips waiting for the fill and is served via a direct, chunked (≤1MB per round trip) network passthrough instead, bounding worst-case time-to-first-byte for a distant seek against a non-faststart file.
- Added `@ViewBuilder accessories:` initializers to `ABPlayerControls` and `ABVideoPlayerWithControls`, so SwiftUI overlay content (fullscreen/captions buttons, custom badges) no longer needs to be wrapped in a `UIView`/`UIHostingController` by hand — pass a trailing closure instead. `ABPlayerControlsView.accessoryViews` (the UIKit `[UIView]` property) is unaffected and remains the primary UIKit-side API. See `docs/DESIGN-OPEN-QUESTIONS.md` and `docs/POLICY-api-stability.md`.
- `ABPlayer` now surfaces mid-playback item failures, not only failures during initial load: a stream that starts fine and later breaks now promotes to the existing `ABPlayerError.itemFailed` case and broadcasts through the existing `.failed` event, the same way an initial-load failure already did.
- Added `ABPlayerError.itemErrorLogEntry(description:)` — a non-terminal diagnostic signal raised when the underlying item logs a new error-log entry (e.g. a recoverable network hiccup). Lets a consumer distinguish "still loading, but something's already gone wrong underneath" from a genuine terminal failure via `ABPlayer.lastError`.

### Changed

- Audio session apply/restore now goes through a process-wide `ABAudioSessionCoordinator` shared across every `ABPlayer` instance, so concurrent players (a feed of preload/current cells) coordinate one snapshot and refcount instead of one instance's `release()` disrupting a sibling still relying on the session. Grade promotion and an explicit `audioSessionPolicy` switch always reactivate the session rather than memoizing "already applied." `play()` reactivates only when the session might actually have gone inactive since the last successful activation (an observed interruption or a return from background) rather than on every call, so playback still correctly resumes audibly once an interruption ends, without a redundant `setActive` round trip on every `play()` tap.
- Concurrent cold-key `ABCacheStore.load` calls now coalesce onto a single in-flight metadata `HEAD` request instead of each issuing its own.

### Deprecated

- `ABPlayerControls.init(player:style:configuration:accessoryViews:onEvent:)` and `ABVideoPlayerWithControls.init(player:videoGravity:style:configuration:accessoryViews:)` — use the new `@ViewBuilder accessories:` initializers instead. Scheduled for removal in 1.0.0; not removed before then, per `docs/POLICY-api-stability.md`. A bare `ABPlayerControls(player: player)` / `ABVideoPlayerWithControls(player: player)` call (no accessories argument) also resolves to the deprecated initializer and warns. See **Migration notes** below.

### Fixed

- `ABAVPlaybackTarget`'s periodic time observer is now always removed on the main thread, including from `deinit` (nonisolated even on this `@MainActor` type) — closes a race with the observer's own main-queue callback.
- An `AVAudioSession` category/mode/options restore no longer force-deactivates the session unconditionally; it only deactivates when this player actually succeeded in activating it, so it can no longer silence a host app (or a sibling player) that was already relying on the session.
- `ABPlayerControlsConfiguration.TimeLabelFormat.custom` labels are no longer double-combined with `timeLabelLayout`'s automatic elapsed/total joining (e.g. `"12s/90s"` was rendered as `"12s/90s/90s/90s"`); the formatter's return value is now used verbatim as the complete label. See **Migration notes** below.

### Migration notes

#### `.custom` time-label formatter now returns the complete label

Before 0.3.0, `timeLabelLayout`'s automatic elapsed/total joining was layered on top of a `.custom` formatter's return value, so a formatter written to return only the elapsed portion happened to work — the total was appended for you:

```swift
// 0.2.0 — relying on automatic elapsed/total joining
configuration.timeFormat = .custom { elapsed, _ in
    "\(Int(elapsed))s"
}
// Rendered "12s/90s"
```

In 0.3.0 the formatter's return value is used verbatim as the entire label — nothing is appended after it. A formatter written the old way now renders only `"12s"`. Compose the full label yourself, using the formatter's second parameter (the total duration, `nil` while unknown/live):

```swift
// 0.3.0 — the formatter owns the complete label
configuration.timeFormat = .custom { elapsed, total in
    guard let total else { return "\(Int(elapsed))s" }
    return "\(Int(elapsed))s/\(Int(total))s"
}
// Renders "12s/90s"
```

#### `accessoryViews:` initializers deprecated in favor of `accessories:`

`ABPlayerControls`/`ABVideoPlayerWithControls`'s array-based `accessoryViews:` initializers are deprecated. A bare call with no accessory argument at all also resolves to them, so it now warns too:

```swift
// 0.2.0
ABPlayerControls(player: player, accessoryViews: [captionsButton, fullscreenButton])

// or, with no accessories at all:
ABPlayerControls(player: player)
```

Replace `accessoryViews:` with a trailing `@ViewBuilder` closure:

```swift
// 0.3.0
ABPlayerControls(player: player) {
    HStack {
        CaptionsButton()
        FullscreenButton()
    }
}

// or, with no accessories at all — an empty closure routes to the new
// initializer instead of the deprecated one:
ABPlayerControls(player: player) {}
```

If you need to keep passing raw `UIView`s, wrap each in `UIViewRepresentable` first, or keep using `ABPlayerControlsView.accessoryViews` directly (the UIKit property, which is not deprecated).

## [0.2.0] - 2026-08-04

### Added

- Added the opt-in `ABPlayerKitControls` product with an accessible UIKit controls overlay, SwiftUI wrapper, and video-plus-controls convenience view.
- Added configurable play/pause and skip controls, buffered and played timeline tracks, draggable scrubbing, playback-rate menu/cycling, auto-hide, accessory views, and live style presets.
- Added English and Korean accessibility labels, adjustable timeline actions, VoiceOver-safe visibility, Reduce Motion behavior, and Dynamic Type time labels.
- Added `ABPlaybackRate`, `ABSeekTolerance`, and `ABPlaybackTime` to the core engine.
- Added playback-rate control, tolerance-aware seeking, range-clamped skipping, coalesced interactive scrubbing, and opt-in periodic time events to `ABPlayer`.
- Added the public, UIKit-independent `ABSeekBarGeometry` and `ABTimeFormatter` helpers for custom controls and downstream UI packages.
- Added controls documentation, bilingual setup and customization guides, and an interactive controls showcase to the demo app.

### Changed

- `ABPlayerEvent` now includes `rateChanged`, `scrubbingChanged`, `seekCompleted`, and `periodicTime`. Source switches should include a `default` branch because new public enum cases can make exhaustive consumer switches fail to compile.
- `ABPlayerConfiguration` now supports playback rate, scrub tolerance, and periodic time observation. All defaults preserve v0.1 playback behavior unless the new features are used.
- Standard controls now center the transport cluster, place the timeline and rate control along the bottom, and show combined fixed-hour elapsed/total time above the timeline. Default, minimal, and tinted presets use lighter scrims that preserve the video beneath them.

## [0.1.0] - 2026-08-03

### Added

- Initial release with the four-grade playback state machine, UIKit and SwiftUI rendering, TTFF metrics, progressive media caching, and explicit HLS prefetch.

[0.3.0]: https://github.com/AppBoong/ABPlayerKit/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/AppBoong/ABPlayerKit/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/AppBoong/ABPlayerKit/releases/tag/v0.1.0
