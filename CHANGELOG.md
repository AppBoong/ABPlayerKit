# Changelog

All notable changes to ABPlayerKit are documented in this file.

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
