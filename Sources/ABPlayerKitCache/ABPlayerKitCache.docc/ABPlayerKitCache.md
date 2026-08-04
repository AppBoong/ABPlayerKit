# ``ABPlayerKitCache``

Cache progressive MP4 assets transparently and prefetch HLS assets explicitly.

## Overview

Use ``ABMediaCache/makeAssetFactory(hlsPrefetcher:)`` as an `ABPlayerKit/ABAssetFactory`. Progressive media is intercepted through a custom resource-loader scheme and stored with disk LRU eviction; oversized or unsupported responses pass through without caching.

Progressive caching fills a linear prefix from byte 0 forward, not sparse ranges. A request whose offset sits ``ABCacheConfiguration/passthroughGapThreshold`` (default 2MB) or more ahead of that prefix skips waiting for the fill and is served directly over the network instead, streamed back in ≤1MB chunks. The background fill is unaffected — this is a one-off fallback for that request, bounding worst-case latency for a distant seek against a non-faststart file.

HLS remains explicit: ``ABHLSPrefetcher`` downloads complete assets with `AVAssetDownloadURLSession`, and only completed downloads are eligible for local playback. Transparent HLS segment caching is intentionally outside this product's scope because it requires a playlist-rewriting reverse proxy.

## Topics

### Progressive Cache

- ``ABCacheConfiguration``
- ``ABMediaCache``

### HLS Prefetch

- ``ABHLSPrefetcher``
- ``ABHLSPrefetchHandle``
- ``ABHLSPrefetchResult``
