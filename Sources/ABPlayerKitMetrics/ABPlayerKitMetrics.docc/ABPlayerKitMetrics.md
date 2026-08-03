# ``ABPlayerKitMetrics``

Measure playback readiness and aggregate TTFF outcomes without adding metrics code to applications that do not link this product.

## Overview

Attach an ``ABMetricsRecorder`` to an `ABPlayerKit/ABPlayer` with an observation token. Start a TTFF measurement at the user-action boundary, then record a hit, wait duration, or abandonment when playback events arrive.

Choose an ``ABMetricsSink`` for in-memory inspection, JSON Lines persistence, or OSLog output. Use ``ABPlaybackStatistics/aggregate(_:)`` to calculate percentiles and rates from fixed samples.

## Topics

### Recording

- ``ABMetricsRecorder``
- ``ABClock``
- ``ABMonotonicClock``

### Events

- ``ABMetricSample``
- ``ABMetricEvent``
- ``ABAccessSnapshot``

### Sinks

- ``ABMetricsSink``
- ``ABInMemoryMetricsSink``
- ``ABJSONLinesMetricsSink``
- ``ABOSLogMetricsSink``

### Aggregation

- ``ABPlaybackStatistics``
