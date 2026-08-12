# ``ABPlayerKitMetrics``

Measure playback readiness and aggregate TTFF outcomes without adding metrics code to applications that do not link this product.

## Overview

Attach an ``ABMetricsRecorder`` to an `ABPlayerKit/ABPlayer` with an observation token. Start a TTFF measurement at the user-action boundary, then record a hit, wait duration, or abandonment when playback events arrive.

Choose an ``ABMetricsSink`` for in-memory inspection, JSON Lines persistence, or OSLog output. Use ``ABPlaybackStatistics/aggregate(_:)`` to calculate percentiles and rates from fixed samples.

### QoE sessions

The same attach also tracks whole playback sessions, keyed by `(playerID, sessionStartedAt)` — there is no separate session identifier, so every v2 event carries both. A session opens on `ABPlayerKit/ABPlayerEvent/itemAttached(source:)` and closes on `ABPlayerKit/ABPlayerEvent/itemDetached(reason:)`, emitting ``ABMetricEvent/sessionStarted(_:)`` and ``ABMetricEvent/sessionSummary(_:)`` respectively. Call ``ABMetricsRecorder/endSession(for:)`` before cancelling the observation token if you want a final summary — the token has no cancellation hook the recorder can observe, so cancelling it alone produces no more events. ``ABMetricsRecorder/snapshot(for:)`` returns a live, unsunk summary for a session that's still open.

``ABSessionSummary/rebufferRatio`` is `rebufferMilliseconds / (rebufferMilliseconds + watchedMilliseconds)`, `nil` when both are `0`. Buffering before the first frame counts toward `startupBufferMilliseconds`, not `rebufferMilliseconds` — TTFF already measures that wait, so counting it as a rebuffer too would double-count the same stall across both metrics.

``ABSessionSummary/completionRatio``'s precision improves when `ABPlayerKit/ABPlayerConfiguration/periodicTimeInterval` is set; ``ABSessionSummary/watchedMilliseconds`` is accurate regardless, since it's derived from `ABPlayerKit/ABPlayerEvent/timeControlStatusChanged(_:)` transitions, not periodic position samples.

`ABSessionAnchor/sourceURL` and `ABSessionSummary/sourceURL` carry the media URL for joining against server-side logs. A source using a signed or tokenized URL should either pass `includesSourceURL: false` to ``ABMetricsRecorder/init(sink:clock:includesSourceURL:)`` or mask the field in a custom ``ABMetricsSink`` — this package does not bake in a masking policy.

`ABMetricEvent` is non-exhaustive, the same convention as `ABPlayerKit/ABPlayerEvent`: a `switch` outside this package should include a `default` branch, since minor releases may add cases.

## Topics

### Recording

- ``ABMetricsRecorder``
- ``ABClock``
- ``ABMonotonicClock``

### Events

- ``ABMetricSample``
- ``ABMetricEvent``
- ``ABAccessSnapshot``

### QoE

- ``ABSessionAnchor``
- ``ABBufferingInterval``
- ``ABFailureRecord``
- ``ABSessionSummary``
- ``ABQoESummary``

### Sinks

- ``ABMetricsSink``
- ``ABInMemoryMetricsSink``
- ``ABJSONLinesMetricsSink``
- ``ABOSLogMetricsSink``

### Aggregation

- ``ABPlaybackStatistics``
- ``ABLatencyDistribution``
