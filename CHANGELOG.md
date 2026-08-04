# Changelog

All notable changes to ABPlayerKit are documented in this file.

## [Unreleased]

### Added

- `ABPlayer` is now `@Observable`, so SwiftUI views can read `grade`, `isScrubbing`, `hasDisplayedFirstFrame`, `lastError`, `source`, and `configuration` directly and re-render on change — no observer bridge required. The token-based `addObserver`/`ABPlayerEvent` system is unchanged and stays available in parallel for anything needing the *reason* a value changed.
- Added `ABInterruptionPolicy` (`.ignore` default / `.pauseAndResume`) and `ABPlayerConfiguration.interruptionPolicy` — opt-in automatic pause on an `AVAudioSession` interruption (phone call, Siri, another app taking the session) and resume once it ends, reactivating the audio session through the same coordinator `audioSessionPolicy` uses.
- Added `ABPlayerConfiguration.pausesOnRouteChangeDeviceUnavailable` (default `true`) — pauses when the current audio output device disappears (e.g. headphones unplugged), independent of `interruptionPolicy`.
- Added `ABPlayerEvent.audioInterruptionBegan`, `.audioInterruptionEnded(resumed:)`, and `.audioRouteChangedDeviceUnavailable`.
- Added `ABCacheConfiguration.passthroughGapThreshold` (default 2MB) — a request whose offset sits this far ahead of the cache's linear fill prefix now skips waiting for the fill and is served via a direct, chunked (≤1MB per round trip) network passthrough instead, bounding worst-case time-to-first-byte for a distant seek against a non-faststart file.

### Changed

- Audio session apply/restore now goes through a process-wide `ABAudioSessionCoordinator` shared across every `ABPlayer` instance, so concurrent players (a feed of preload/current cells) coordinate one snapshot and refcount instead of one instance's `release()` disrupting a sibling still relying on the session. `play()`/grade promotion now always reactivates the session rather than memoizing "already applied," so playback correctly resumes audibly once an interruption ends.
- Concurrent cold-key `ABCacheStore.load` calls now coalesce onto a single in-flight metadata `HEAD` request instead of each issuing its own.

### Fixed

- `ABAVPlaybackTarget`'s periodic time observer is now always removed on the main thread, including from `deinit` (nonisolated even on this `@MainActor` type) — closes a race with the observer's own main-queue callback.
- An `AVAudioSession` category/mode/options restore no longer force-deactivates the session unconditionally; it only deactivates when this player actually succeeded in activating it, so it can no longer silence a host app (or a sibling player) that was already relying on the session.
- `ABPlayerControlsConfiguration.TimeLabelFormat.custom` labels are no longer double-combined with `timeLabelLayout`'s automatic elapsed/total joining (e.g. `"12s/90s"` was rendered as `"12s/90s/90s/90s"`); the formatter's return value is now used verbatim as the complete label.

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

[0.2.0]: https://github.com/AppBoong/ABPlayerKit/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/AppBoong/ABPlayerKit/releases/tag/v0.1.0
