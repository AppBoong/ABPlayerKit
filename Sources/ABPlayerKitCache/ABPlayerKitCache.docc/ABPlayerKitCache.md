# ``ABPlayerKitCache``

Cache progressive MP4 assets transparently and prefetch HLS assets explicitly.

## Overview

Use ``ABMediaCache/makeAssetFactory(hlsPrefetcher:)`` as an `ABPlayerKit/ABAssetFactory`. Progressive media is intercepted through a custom resource-loader scheme and stored with disk LRU eviction; oversized or unsupported responses pass through without caching.

HLS remains explicit: ``ABHLSPrefetcher`` downloads complete assets with `AVAssetDownloadURLSession`, and only completed downloads are eligible for local playback. Transparent HLS segment caching is intentionally outside this product's scope because it requires a playlist-rewriting reverse proxy.

## Topics

### Progressive Cache

- ``ABCacheConfiguration``
- ``ABMediaCache``

### HLS Prefetch

- ``ABHLSPrefetcher``
- ``ABHLSPrefetchHandle``
- ``ABHLSPrefetchResult``
