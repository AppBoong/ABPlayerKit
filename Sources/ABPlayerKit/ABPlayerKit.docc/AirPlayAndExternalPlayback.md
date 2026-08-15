# AirPlay and External Playback

Three passthrough properties, and how to observe whether AirPlay is active.

## Overview

Three ``ABPlayerConfiguration`` properties pass straight through to the matching `AVPlayer` properties. All three default to `AVPlayer`'s own defaults, so adopting this library changes no AirPlay behavior on its own:

```swift
var configuration = ABPlayerConfiguration()
configuration.allowsExternalPlayback = true                           // default
configuration.usesExternalPlaybackWhileExternalScreenIsActive = false  // default
configuration.externalPlaybackVideoGravity = .resizeAspect             // default
```

A screen with several simultaneously-live players — a feed — should set ``ABPlayerConfiguration/allowsExternalPlayback`` to `false` on every instance except the current one. Otherwise any of them can claim the external route.

## Observing the Route

``ABPlayer/isExternalPlaybackActive`` reports whether AirPlay is currently active. It is a plain computed property that re-reads `AVPlayer` on each access, **not** `@Observable`-tracked, so SwiftUI does not re-render when it changes.

For a reactive signal, either observe `player.avPlayer` with KVO directly, or let `AVRoutePickerView` own its own state:

```swift
import AVKit
import SwiftUI

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView { AVRoutePickerView() }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
```

That view is plain AVKit with no ABPlayerKit API in it — it is here because it is the piece most apps need next, not because the library provides it.

## Topics

### Configuration

- ``ABPlayerConfiguration/allowsExternalPlayback``
- ``ABPlayerConfiguration/usesExternalPlaybackWhileExternalScreenIsActive``
- ``ABPlayerConfiguration/externalPlaybackVideoGravity``
- ``ABPlayer/isExternalPlaybackActive``
