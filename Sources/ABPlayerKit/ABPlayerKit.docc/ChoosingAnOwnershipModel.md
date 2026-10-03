# Choosing an Ownership Model

Start with one line, and take ownership of the player only when a screen needs it.

## Overview

A SwiftUI integration has three steps. Each one adds exactly one responsibility, and the step after it is only needed when that responsibility is:

| You need | Use | You own |
|---|---|---|
| A video on screen | `ABVideoPlayer(url:)` | Nothing |
| To pause, observe, or share the player | `@State` ``ABPlayer`` + ``ABPlayer/load(_:autoplay:)`` | The player's lifetime |
| Many players in a feed, with preloading | ``ABPlaybackGrade`` per player | Which player is `.current` |

The code samples use ``ABVideoPlayer``. `ABPlayerKitControls`' `ABVideoPlayerWithControls` has the same `url:`/`source:`/`player:` initializers, with the standard controls on top.

### Step 1: Let the view own the player

```swift
ABVideoPlayer(url: url)
    .aspectRatio(16 / 9, contentMode: .fit)
```

The view creates an ``ABPlayer``, attaches the source, and starts playback. It releases every resource when SwiftUI discards the view. It never releases on `onDisappear`, because that means "not visible", not "gone".

That rule is also the limit of this step. The view gives you no handle on the player, so a video scrolled off-screen, or covered by a pushed screen, keeps playing for as long as the view exists. When that matters, go to step 2.

### Step 2: Own the player

```swift
struct VideoScreen: View {
    let url: URL
    @State private var player = ABPlayer()

    var body: some View {
        VStack {
            ABVideoPlayer(player: player)
                .aspectRatio(16 / 9, contentMode: .fit)
            Text(player.position.time.currentTime.seconds, format: .number.precision(.fractionLength(0)))
        }
        .task { player.load(ABMediaSource(url: url)) }
        .onDisappear { player.pause() }
    }
}
```

Three details make this correct:

- **`load` in `.task`, not in the initializer.** SwiftUI re-evaluates a `@State` initial value every time it rebuilds the view value and throws all but the first away. An initializer that attached an item would build, and start loading, throwaway `AVPlayerItem`s. `ABPlayer()` itself allocates no `AVPlayer`.
- **`load` is idempotent.** `.task` runs again on every appearance. Loading the source that is already loaded does nothing, so coming back to the screen neither restarts the video nor resumes one the user paused.
- **Pause on disappear, don't release.** Releasing would throw away the item and the playback position. The player is released when the `@State` storage goes away.

``ABPlayer/position`` is the observable way to show time. ``ABPlayer/currentTime`` is re-read from `AVPlayer` on every access, so SwiftUI can't track it. `position` is a separate `@Observable` object, so each tick re-renders only the views that read it. The periodic observer behind it starts on first access, so a player whose position is never read pays nothing.

Picture in Picture, Now Playing, and metrics recording all need a player reference, so they all start from this step.

### Step 3: A feed, with preloading

In a vertical feed the expensive part is not playing a video but starting one: fetching the playlist, creating the item, and buffering the first segments. Grades let a neighbour get that done before it is swiped to:

- **`.current`**: attached and playing.
- **`.preloaded`**: attached with the conservative preload tuning, prerolled, and paused.
- **`.instanceOnly`**: no item; the `AVPlayer` stays alive for reuse.
- **`.released`**: nothing is allocated.

```swift
struct ReelsFeed: View {
    let sources: [ABMediaSource]
    @State private var players: [ABPlayer] = []
    @State private var visibleIndex: Int? = 0

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(players.indices, id: \.self) { index in
                    ABVideoPlayer(player: players[index])
                        .containerRelativeFrame([.horizontal, .vertical])
                        .id(index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $visibleIndex)
        .onAppear {
            if players.isEmpty {
                players = sources.map { _ in ABPlayer() }
            }
            updateGrades()
        }
        .onChange(of: visibleIndex) { updateGrades() }
    }

    private func updateGrades() {
        guard let visibleIndex else { return }
        for (index, player) in players.enumerated() {
            switch abs(index - visibleIndex) {
            case 0: player.load(sources[index])
            case 1: player.set(source: sources[index], grade: .preloaded)
            default: player.release()
            }
        }
    }
}
```

When the user swipes to a neighbour, `load` promotes an item that is already attached and buffered. It swaps the tuning to ``ABPlayerConfiguration/currentTuning`` and plays, so nothing is re-created. The player being left behind is demoted to `.preloaded`, which pauses it. Anything two or more rows away is released.

This recipe needs iOS 17's `scrollPosition(id:)`, which is this package's deployment target.

### Driving grades by hand

`load(_:)` is shorthand for `set(source:grade: .current)` followed by `play()`. Use `set(source:grade:)` directly once a screen needs the other grades. Create one player and drive all source/grade changes through it when a screen needs to prepare media before it becomes visible — a feed cell a few rows away, for example:

```swift
import ABPlayerKit

let source = ABMediaSource(
    url: URL(string: "https://example.com/video.m3u8")!,
    kind: .hls
)

let player = ABPlayer()
player.set(source: source, grade: .preloaded)

// When the media becomes visible:
player.set(source: source, grade: .current)
player.play()

// When it leaves the preload window:
player.set(source: source, grade: .instanceOnly)
```

| Grade | Resources held | Intended use |
|---|---|---|
| `.released` | Nothing | Return all playback resources |
| `.instanceOnly` | `AVPlayer`, no item | Keep identity while guaranteeing zero item network activity |
| `.preloaded` | Player + item, preload tuning | Prepare nearby media without allowing `play()` |
| `.current` | Player + item, current tuning | Visible media; playback controls are accepted |

- Every release path that holds an item routes through `detachItem`.
- Moving between `.preloaded` and `.current` reapplies the matching tuning role, so demotion is the exact inverse of promotion.
- Playback control calls are accepted only at `.current` — see <doc:FailuresAndDiagnostics>.
- `ABMediaSource`'s `kind:` is inferred from the URL's extension (`.m3u8` → `.hls`, anything else → `.progressive`). Pass it explicitly only for a signed or extensionless URL where that inference would guess wrong.

## See Also

- <doc:BackgroundAndPictureInPicture>
- ``ABPlaybackGrade``
- ``ABPlaybackPosition``
