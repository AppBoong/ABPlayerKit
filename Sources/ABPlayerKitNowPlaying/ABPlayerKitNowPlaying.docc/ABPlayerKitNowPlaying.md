# ``ABPlayerKitNowPlaying``

Lock screen and Control Center integration for `ABPlayerKit`.

## Overview

`ABPlayerKitNowPlaying` bridges an `ABPlayer` to `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter`. Like `ABPlayerConfiguration/audioSessionPolicy`, it is a process-wide resource this library never touches until a consumer opts in — nothing is read from or written to either singleton until the first ``ABNowPlayingCenter/attach(_:metadata:configuration:artwork:)`` call, and the pre-existing state is restored exactly once the last participant relinquishes.

```swift
import ABPlayerKit
import ABPlayerKitNowPlaying

let token = ABNowPlayingCenter.shared.attach(
    player,
    metadata: ABNowPlayingMetadata(title: "Episode 12", artist: "My Show"),
    configuration: ABNowPlayingConfiguration(skipInterval: 15),
    artwork: ABStaticArtworkProvider(image: episodeArtwork)
)
```

Retain the returned `ABObservationToken` (from `ABPlayerKit`) for as long as this player should be eligible to own Now Playing; cancelling it (or letting it deinitialize) detaches.

### Ownership

Only a player at `ABPlaybackGrade/current` may own the surface, and the most recently eligible participant wins (last-eligible-wins, LIFO) — see <doc:RemoteCommands> for the full rule set and the remote-command activation table.

## Topics

### Attaching

- ``ABNowPlayingCenter``
- ``ABNowPlayingMetadata``
- ``ABNowPlayingConfiguration``

### Remote Commands

- <doc:RemoteCommands>
- ``ABRemoteCommandSet``

### Artwork

- ``ABNowPlayingArtworkProviding``
- ``ABStaticArtworkProvider``
