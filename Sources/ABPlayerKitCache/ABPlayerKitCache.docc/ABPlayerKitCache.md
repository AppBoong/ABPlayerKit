# ``ABPlayerKitCache``

Cache progressive MP4 assets transparently and prefetch HLS assets explicitly.

## Overview

Use ``ABMediaCache/makeAssetFactory(hlsPrefetcher:)`` as an `ABPlayerKit/ABAssetFactory`. Progressive media is intercepted through a custom resource-loader scheme and stored with disk LRU eviction; oversized or unsupported responses pass through without caching.

Progressive caching fills a linear prefix from byte 0 forward, not sparse ranges. A request whose offset sits ``ABCacheConfiguration/passthroughGapThreshold`` (default 2MB) or more ahead of that prefix skips waiting for the fill and is served directly over the network instead, streamed back in ≤1MB chunks. The background fill is unaffected — this is a one-off fallback for that request, bounding worst-case latency for a distant seek against a non-faststart file.

HLS remains explicit: ``ABHLSPrefetcher`` downloads complete assets with `AVAssetDownloadURLSession`, and only completed downloads are eligible for local playback.

### Wiring the factory

```swift
import ABPlayerKitCache

let cache = try ABMediaCache()
let hlsPrefetcher = ABHLSPrefetcher()

// Build and retain this factory. Release the current item before replacing it.
let assetFactory = cache.makeAssetFactory(hlsPrefetcher: hlsPrefetcher)
player.release()
var configuration = player.configuration
configuration.assetFactory = assetFactory
player.configuration = configuration

let handle = hlsPrefetcher.prefetch(hlsSource)
if await handle.result == .completed {
    player.set(source: hlsSource, grade: .current)
    player.play() // the factory resolves the completed local HLS asset
}
```

Two things in that snippet are easy to lose and expensive to rediscover:

- **Retain the factory.** `AVAssetResourceLoader.setDelegate(_:queue:)` does not retain its delegate, so the factory is what keeps each one alive. Drop the factory and interception stops without an error — playback simply goes to the network.
- **Release before replacing.** `assetFactory` is read at attach time only, so an item already attached keeps the old factory. Releasing first is what makes the next attach pick up the new one.

### Why transparent HLS caching is out of scope

`AVAssetResourceLoader` cannot intercept ordinary HTTP(S) HLS master or media playlists. Doing it transparently would mean running a local reverse proxy that rewrites playlists and then handles relative URLs, encryption keys, and background lifetime on its own. That is a substantially larger failure surface than the progressive path, so it is kept separate deliberately rather than left unimplemented by accident. The reasoning is recorded in [DESIGN-OPEN-QUESTIONS Q1](https://github.com/AppBoong/ABPlayerKit/blob/main/docs/DESIGN-OPEN-QUESTIONS.md) and [DESIGN-ABPlayerKit §9](https://github.com/AppBoong/ABPlayerKit/blob/main/docs/DESIGN-ABPlayerKit.md).

## Known constraints

- **Resume validation.** Resuming a partial download sends `If-Range` to validate the cached prefix against the origin; if the origin changed, the partial file is discarded and refilled from scratch. Origins that provide neither an `ETag` nor a `Last-Modified` header are defended only by checking that the resumed response's starting offset and total length match what was recorded — a same-length content change on such an origin can't be detected on resume.
- **Revalidation.** Each asset session performs one conditional metadata check the first time it's read. A failed or inconclusive revalidation fails open: playback continues from the cached bytes rather than being blocked on the round trip succeeding.
- **Delete semantics.** `removeAll()`/`remove(_:)` delete immediately. Playback already in progress for a deleted key doesn't fail — it continues over the network for the remainder of that read, and the cache fills again from wherever playback continues.
- **Delete scope when caching several sources at once.** The delete-safety mechanism above tracks purges with a single store-wide counter, not one per cache key. When several `ABMediaSource`s are being cached concurrently (e.g. a multi-player feed), calling `remove`/`removeAll` for one source can — in a narrow timing window — cause a different source's just-started, not-yet-responded fill to be served once over the network instead of from the cache for that one read. The bytes served are still correct; only that single read bypasses the cache, and the affected source's background fill and subsequent reads are unaffected and self-heal on the next read.
- **LRU eviction cost (carried over).** Eviction sorts every entry on each pass (O(n log n) per eviction), recency is tracked by wall-clock timestamp, and a write counts as an access. Harmless at the disk sizes this cache targets; optimizing it is intentionally deferred.
- **Actor-internal disk I/O (carried over).** Disk reads and writes run synchronously inside the cache's actor. Per-chunk file handle churn has been removed — a fill's writer handle now stays open for the fill's lifetime — but offloading the I/O itself to a separate executor would need a dedicated writer-serialization design and hasn't been done.

## Topics

### Progressive Cache

- ``ABCacheConfiguration``
- ``ABMediaCache``

### HLS Prefetch

- ``ABHLSPrefetcher``
- ``ABHLSPrefetchHandle``
- ``ABHLSPrefetchResult``
