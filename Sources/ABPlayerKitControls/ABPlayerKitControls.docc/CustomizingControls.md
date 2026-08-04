# Customizing Playback Controls

Build a control appearance without changing playback behavior.

## Start with a Preset

Use ``ABPlayerControlsStyle/default`` for white controls over a dark bottom gradient, ``ABPlayerControlsStyle/minimal`` for an inline player, or ``ABPlayerControlsStyle/tinted`` for a material background with the system tint.

```swift
let controls = ABPlayerControlsView(style: .minimal)
controls.player = player
```

All style values apply live. Updating colors does not recreate the controls or invalidate layout; changing dimensions updates the existing constraints and layers.

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

When skip icons are `nil`, the controls derive supported SF Symbols from ``ABPlayerControlsConfiguration/skipInterval``. An explicit icon always wins.

## Configure Interactions

```swift
var configuration = ABPlayerControlsConfiguration()
configuration.skipInterval = 15
configuration.rateOptions = [0.5, 1, 1.5, 2]
configuration.rateInteraction = .menu
configuration.autoHideDelay = 3
configuration.timeLabelLayout = .elapsedAndRemaining

controls.configuration = configuration
```

Set ``ABPlayerControlsConfiguration/periodicTimeInterval`` to tune UI update frequency. The default is 0.25 seconds. The controls suppress auto-hide while VoiceOver is running and honor Reduce Motion when ``ABPlayerControlsStyle/respectsReduceMotion`` is enabled.

## Add Application Controls

Place fullscreen, captions, or Picture in Picture buttons at the right edge through ``ABPlayerControlsView/accessoryViews``. Your application owns the actions and accessibility of those views.

```swift
controls.accessoryViews = [captionsButton, fullscreenButton]
```
