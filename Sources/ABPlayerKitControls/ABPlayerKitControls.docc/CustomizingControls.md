# Customizing Playback Controls

Build a control appearance without changing playback behavior.

## Start with a Preset

Use ``ABPlayerControlsStyle/default`` for white controls over a subtle dark scrim, ``ABPlayerControlsStyle/minimal`` for the lightest bottom scrim, or ``ABPlayerControlsStyle/tinted`` for blue accents over a translucent blue-to-dark scrim. All three presets keep the video visible beneath the overlay.

```swift
let controls = ABPlayerControlsView(style: .minimal)
controls.player = player
```

All style values apply live. Updating colors does not recreate the controls or invalidate layout; changing dimensions updates the existing constraints and layers.

## Understand the Standard Layout

The skip-backward, play/pause, and skip-forward controls form a centered transport cluster. The timeline stays at the bottom, with its combined `HH:mm:ss/HH:mm:ss` elapsed-and-total label directly above the leading edge. The playback-rate control occupies the bottom-trailing edge beside the timeline. Other time-label modes keep the same position and fixed-hour clock format.

## Change the Timeline

The track, played progress, buffered progress, and thumb each have independent styling.

```swift
var style = ABPlayerControlsStyle.default
style.trackColor = .white.withAlphaComponent(0.2)
style.progressColor = .systemPink
style.bufferedColor = .white.withAlphaComponent(0.45)
style.trackHeight = 4
style.trackHeightWhileScrubbing = 7
style.thumbColor = .systemPink
style.thumbSize = CGSize(width: 14, height: 14)
style.thumbSizeWhileScrubbing = CGSize(width: 20, height: 20)

controls.style = style
```

Set ``ABPlayerControlsStyle/isThumbHidden`` for a slim timeline with no pointer. Track interactions still reach exact 0 and 1 progress at the physical endpoints.

## Replace Icons

Use an SF Symbol name, a custom image, or hide a button with ``ABControlIcon/none``.

```swift
style.playIcon = .system("play.circle.fill")
style.pauseIcon = .image(customPauseImage)
style.skipBackwardIcon = .none
controls.style = style
```

When skip icons are `nil`, the controls derive supported SF Symbols from ``ABPlayerControlsConfiguration/skipInterval``. An explicit icon always wins. ``ABPlayerControlsConfiguration/skipInterval`` accepts 5-second steps between 5 and 60; other values are rounded to the nearest step and clamped into that range. Steps with a native `gobackward.N`/`goforward.N` glyph (5, 10, 15, 30, 45, 60) use it directly; other steps (e.g. 20, 25) badge the number over a generic arrow so the rendered icon always matches the configured interval.

## Configure Interactions

```swift
var configuration = ABPlayerControlsConfiguration()
configuration.skipInterval = 15
configuration.rateOptions = [0.5, 1, 1.5, 2]
configuration.rateInteraction = .menu
configuration.autoHideDelay = 3
configuration.timeLabelLayout = .elapsedAndRemaining
configuration.timeFormat = .automatic

controls.configuration = configuration
```

``ABPlayerControlsConfiguration/timeFormat`` controls how time labels render: `.fixedHours` (the default) always shows `HH:MM:SS`, `.automatic` drops the hours field under one hour, and `.custom` takes a `(seconds, referenceDurationSeconds) -> String` closure — every label in a render pass (elapsed, total, remaining) receives the same `referenceDurationSeconds` so a custom formatter can keep field widths consistent.

Set ``ABPlayerControlsConfiguration/periodicTimeInterval`` to tune UI update frequency. The default is 0.25 seconds. The controls suppress auto-hide while VoiceOver is running and honor Reduce Motion when ``ABPlayerControlsStyle/respectsReduceMotion`` is enabled.

## Add Application Controls

Place fullscreen, captions, or Picture in Picture buttons at the right edge through ``ABPlayerControlsView/accessoryViews``. Your application owns the actions and accessibility of those views.

```swift
controls.accessoryViews = [captionsButton, fullscreenButton]
```
