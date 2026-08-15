# ``ABPlayerKitControls``

An opt-in, accessible playback-controls layer for ABPlayerKit.

## Overview

ABPlayerKitControls provides a UIKit overlay and SwiftUI wrappers while keeping the playback engine in `ABPlayerKit`. Link this product only when an app wants the standard timeline, playback-rate, skip, and auto-hide experience.

The standard overlay centers its transport buttons and places the timeline at the bottom. A fixed-hour elapsed/total label sits immediately below the timeline's visible track at the leading edge, while playback rate sits at the trailing edge. The default white controls use a subtle dark scrim that preserves the video image beneath them.

A stall shows a spinner over the play/pause glyph (``ABPlayerControlsConfiguration/showsBufferingIndicator``); a skip or double-tap seek shows a cumulative feedback badge (``ABPlayerControlsStyle/seekFeedbackTextColor`` and friends); and ``ABControlsSlot`` places consumer accessory views at additional overlay positions beyond the default bottom-trailing spot. See <doc:CustomizingControls> for all of these.

## Getting Started

Create an `ABPlayerKit/ABPlayer`, assign it to ``ABPlayerControlsView`` in UIKit, or compose it with ``ABVideoPlayerWithControls`` in SwiftUI. The controls install periodic time observation while attached and restore the player's previous interval when detached.

``ABPlayerControlsView`` renders nothing but the overlay. In UIKit, place it **over** an `ABPlayerKit/ABPlayerView` and give both the same player — the two are separate views by design, so an app can keep the video and replace the controls.

```swift
import ABPlayerKit
import ABPlayerKitControls

let player = ABPlayer()
let controls = ABPlayerControlsView()
controls.player = player
```

## Customizing Appearance

Appearance and behavior are independent value types. Change ``ABPlayerControlsStyle`` to update colors, icons, dimensions, and the background live. Change ``ABPlayerControlsConfiguration`` for skip intervals, rate choices, time labels, and auto-hide behavior.

For a complete appearance example, see <doc:CustomizingControls>.

## Auto-Hide Behavior

Controls hide after ``ABPlayerControlsConfiguration/autoHideDelay`` while playing. Interactions rearm the timer, scrubbing cancels it until the final seek lands, and pausing keeps the overlay visible by default. Set the delay to `nil` to keep controls visible. Auto-hide is suppressed whenever VoiceOver is running.

## Topics

### UIKit

- ``ABPlayerControlsView``

### SwiftUI

- ``ABPlayerControls``
- ``ABVideoPlayerWithControls``

### SwiftUI Environment

Set a style or configuration once on an ancestor view to cover every player-controls view in its subtree — an explicit `style:`/`configuration:` initializer argument still overrides it locally.

- ``SwiftUICore/View/playerControlsStyle(_:)``
- ``SwiftUICore/View/playerControlsConfiguration(_:)``
- ``SwiftUICore/EnvironmentValues/playerControlsStyle``
- ``SwiftUICore/EnvironmentValues/playerControlsConfiguration``

### Appearance

- ``ABPlayerControlsStyle``
- ``ABControlIcon``
- ``ABControlsBackgroundStyle``
- ``ABTrackCornerRadius``
- ``ABRateLabelStyle``
- <doc:CustomizingControls>

### Behavior and Events

- ``ABPlayerControlsConfiguration``
- ``ABControlsEvent``
- ``ABControlsSlot``
- ``ABControlsTouchPassthrough``
- ``ABDoubleTapSeek``
