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

The skip-backward, play/pause, and skip-forward controls form a centered transport cluster. The seek bar spans the full overlay width with equal leading/trailing padding, sitting near the bottom. Directly below the seek bar's visible track — by exactly ``ABPlayerControlsStyle/seekBarBottomSpacing`` — a compact row holds the elapsed/total time label at the bottom-leading edge and the playback-rate control at the bottom-trailing edge; that row itself sits flush with the overlay's bottom edge, inset by ``ABPlayerControlsStyle/contentInsets``. The seek bar's touch-target row stays a full 44pt tall for accessibility even though its drawn track is much thinner, so it can extend upward past that visible gap — hit-testing always favors the smaller, more specific controls — including ``ABPlayerControlsView/accessoryViews`` — over the seek bar wherever their touch areas overlap.

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

When skip icons are `nil`, the controls derive supported SF Symbols from ``ABPlayerControlsConfiguration/skipInterval``. An explicit icon always wins. ``ABPlayerControlsConfiguration/skipInterval`` defaults to 10 seconds and accepts 5-second steps between 5 and 60; other values are rounded to the nearest step and clamped into that range. Steps with a native `gobackward.N`/`goforward.N` glyph (5, 10, 15, 30, 45, 60) use it directly; other steps (e.g. 20, 25) badge the number over a generic arrow so the rendered icon always matches the configured interval.

This default (10 seconds) is independent of `ABPlayerKitNowPlaying`'s `ABNowPlayingConfiguration.skipInterval`, which defaults to 15 — the two configurations aren't linked, so a consumer using both products on the same player should set both explicitly if the on-screen skip buttons and the lock-screen skip commands should agree.

## Apply a Style Across Several Players

``SwiftUICore/View/playerControlsStyle(_:)`` and ``SwiftUICore/View/playerControlsConfiguration(_:)`` set a style/configuration on every ``ABPlayerControls``/``ABVideoPlayerWithControls`` in that view's subtree, so one modifier can cover a whole screen of players instead of repeating a `style:`/`configuration:` argument at every call site.

```swift
VStack {
    ABVideoPlayerWithControls(url: firstURL)
    ABVideoPlayerWithControls(url: secondURL)
}
.playerControlsStyle(.minimal)
```

An explicit `style:`/`configuration:` initializer argument always wins over the modifier for that one view (the `url:`/`source:` initializers don't take `style:`/`configuration:` — see [Add Application Controls](#Add-Application-Controls) below for the `player:`-owning initializers that do), so a single player can still opt out of the shared appearance:

```swift
VStack {
    ABVideoPlayerWithControls(player: featuredPlayer, style: .tinted) {} // this player only
    ABVideoPlayerWithControls(url: secondURL)
}
.playerControlsStyle(.minimal) // every other player in the stack
```

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

## Show Buffering and Seek Feedback

While `ABPlayer.isBuffering` is `true`, the play/pause button's glyph gets a spinner overlay — the button stays enabled and hit-testable throughout, since a stall can still be paused. Auto-hide is suppressed while buffering, without forcing controls visible.

```swift
configuration.showsBufferingIndicator = true // default
style.bufferingIndicatorColor = .systemPink   // default nil, follows tintColor
```

A skip, double-tap, or VoiceOver-adjustment seek streak shows a cumulative badge (`"+20s"`/`"-10s"`) while it's outstanding, driven entirely by the core's `pendingSeekTime`/`seekTargetChanged` — Controls never accumulates the delta itself:

```swift
style.seekFeedbackTextColor = .white
style.seekFeedbackBackgroundColor = .black.withAlphaComponent(0.45)
style.seekFeedbackFont = .systemFont(ofSize: 15, weight: .semibold)
```

Tapping play after playback has reached the end seeks to zero before playing (replay-from-start) instead of a bare `play()`, which does nothing at the end of an item.

## Hide Individual Controls

``ABPlayerControlsConfiguration/showsPlayPauseButton`` and ``ABPlayerControlsConfiguration/showsSeekBar`` (both default `true`) hide either control the same way ``ABPlayerControlsConfiguration/showsSkipButtons`` already does. Hiding the seek bar collapses the row it occupies rather than leaving blank space.

## Configure Touch Passthrough and Double-Tap Seek

```swift
configuration.touchPassthrough = .whenControlsHidden
configuration.doubleTapSeek = .edges(edgeWidthFraction: 0.3)
configuration.providesHapticFeedback = true
```

``ABControlsTouchPassthrough`` (default ``ABControlsTouchPassthrough/never``) governs touches that miss every control: `.never` keeps the overlay consuming them (identical to before this option existed), `.whenControlsHidden` passes them through only while controls are hidden, and `.always` passes them through regardless of visibility. This never overrides the existing hit-test priority order — it only applies once nothing else has already claimed the touch.

``ABDoubleTapSeek`` (default ``ABDoubleTapSeek/disabled``) installs a double-tap gesture on the overlay's leading/trailing edge bands that seeks by ``ABPlayerControlsConfiguration/skipInterval``. It's disabled by default because installing it requires the background single-tap recognizer to wait out a possible second tap, which delays every single tap by the double-tap timeout — not just for consumers who opt in. ``ABPlayerControlsConfiguration/providesHapticFeedback`` (default `true`) fires a light haptic on an accepted double-tap seek; only double-tap seeking uses this.

## Format the Rate Label and Time Separator

```swift
configuration.rateLabelFormat = .automatic
configuration.timeLabelSeparator = "/"
```

``ABPlayerControlsConfiguration/RateLabelFormat/automatic`` formats the playback rate with a locale-aware `NumberFormatter` (`"1.5"` in `en`, `"1,5"` in `de`); `.custom { rate in ... }` supplies the entire label text, bypassing ``ABRateLabelStyle``'s `.text` template the same way ``ABPlayerControlsConfiguration/TimeLabelFormat/custom(_:)`` bypasses automatic elapsed/total joining. ``ABPlayerControlsConfiguration/timeLabelSeparator`` (default `"/"`) is the string placed between a time label's elapsed and secondary fields; it's ignored by `.custom` time formatting, which lays out its own complete label.

## Place Accessory Views at Additional Slots

Beyond the single legacy position, ``ABControlsSlot`` names three overlay positions for consumer views: ``ABControlsSlot/topTrailing``, ``ABControlsSlot/transportTrailing`` (anchored to the centered transport cluster's trailing edge, in its own stack), and ``ABControlsSlot/bottomTrailing`` (the same position as the legacy ``ABPlayerControlsView/accessoryViews``, which is now an alias for this slot).

```swift
controlsView.setAccessoryViews([captionsButton], in: .topTrailing)
controlsView.setAccessoryViews([fullscreenButton], in: .transportTrailing)
let current = controlsView.accessoryViews(in: .topTrailing)
```

## Play From a Non-Current Player

A player attached at `.preloaded` or `.instanceOnly` (the common pattern: promote to `.current` only once the user actually wants to watch) has every control disabled except play/pause — with ``ABPlayerControlsConfiguration/promotesToCurrentOnPlay`` at its default of `true`, tapping play/pause on a player that already has a source promotes it to `.current` and starts playback in one tap, instead of leaving the whole overlay inert until something outside the controls layer promotes it. Seek, skip, and the rate control stay disabled until the player is actually `.current`. Set the flag to `false` to require an explicit external promotion before play/pause responds at all (the pre-existing behavior).

## Add Application Controls

Place fullscreen, captions, or Picture in Picture buttons at the right edge. Two paths exist side by side, for UIKit and SwiftUI — pick whichever matches how the rest of the button is built. Both land in the same place, next to the rate control, and hit-testing always favors them over the seek bar (see [Understand the Standard Layout](#Understand-the-Standard-Layout) above).

### UIKit

Set ``ABPlayerControlsView/accessoryViews`` directly. Your application owns the actions and accessibility of those views.

```swift
controls.accessoryViews = [captionsButton, fullscreenButton]
```

### SwiftUI

Pass a `@ViewBuilder` trailing closure to ``ABPlayerControls`` or ``ABVideoPlayerWithControls`` instead — no `UIHostingController` wrapping required.

```swift
ABPlayerControls(player: player) {
    HStack(spacing: 8) {
        Button { isCaptionsOn.toggle() } label: { Image(systemName: "captions.bubble") }
        Button { enterFullscreen() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
    }
    .foregroundStyle(.white)
}
```

Internally this hosts your content in a `UIHostingController` that `ABAccessoryHostingBox` attaches as a child of the nearest `UIViewController` it can find by walking up from the controls view once it's actually in a window — attaching as a real child view controller, rather than just embedding its view, is what gives the hosted content safe-area propagation, `UIViewController` appearance callbacks, and trait inheritance for free. **If no `UIViewController` is found** (an unusual hosting setup with no view controller anywhere in the view hierarchy), the accessory view still lays out and renders — but those three guarantees do not hold. The `accessoryViews: [UIView]` initializers above stay the safer choice when you need those guarantees without a real, or reachable, view controller.

The array-based `accessoryViews:` initializers on ``ABPlayerControls``/``ABVideoPlayerWithControls`` (not ``ABPlayerControlsView/accessoryViews`` itself, which stays the primary UIKit API) are deprecated in favor of the `accessories:` closure — see [POLICY-api-stability](../../../../docs/POLICY-api-stability.md) for the deprecation timeline.
