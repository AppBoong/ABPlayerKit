# Subtitles and Audio Tracks

Reaching `AVMediaSelectionGroup` yourself, and why this library does not do it for you.

## Overview

Subtitle and audio-track selection UI, and the state management behind it, are **not provided**. This is a scope decision rather than a gap: a selection model that survives source changes belongs to the app that knows what the user picked and why, and a wrapper that guessed would be wrong for half its consumers.

The escape hatch is ``ABPlayer/avPlayerItem``. `loadMediaSelectionGroup(for:)` is `async`, so this needs an async context:

```swift
if let item = player.avPlayerItem,
   let group = try? await item.asset.loadMediaSelectionGroup(for: .audible) {
    let options = group.options
    // Present `options`, then:
    item.select(options[0], in: group)
}
```

## Three Constraints

1. ``ABPlayer/avPlayerItem`` is non-`nil` only from `.preloaded` upward — see ``ABPlaybackGrade/holdsItem``.
2. A source change, a demotion, or ``ABPlayer/release()`` builds a **new** `AVPlayerItem`. A selection made on the previous one does not carry over. Re-apply it on every ``ABPlayerEvent/itemAttached(source:)``.
3. This library remembers no selection state across attaches. Holding onto the user's choice, and re-applying it, is entirely the app's responsibility.

The second constraint is the one that bites, because nothing reports it: playback continues normally with the default track after a source change, and the selection is simply gone.
