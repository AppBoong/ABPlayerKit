# ``ABPlayerKitMetrics``

Measure playback readiness and aggregate TTFF outcomes without adding metrics code to applications that do not link this product.

## Overview

Attach an ``ABMetricsRecorder`` to an `ABPlayerKit/ABPlayer` with an observation token. Start a TTFF measurement at the user-action boundary, then record a hit, wait duration, or abandonment when playback events arrive.

Choose an ``ABMetricsSink`` for in-memory inspection, JSON Lines persistence, or OSLog output. Use ``ABPlaybackStatistics/aggregate(_:)`` to calculate percentiles and rates from fixed samples.

### Recording TTFF

```swift
import ABPlayerKit
import ABPlayerKitMetrics

@MainActor
final class PlaybackSession {
    let player = ABPlayer()

    private let sink: ABInMemoryMetricsSink
    private let recorder: ABMetricsRecorder
    private var tokens: Set<ABObservationToken> = []

    init() {
        let sink = ABInMemoryMetricsSink()
        self.sink = sink
        // `includesSourceURL` defaults to `true`. Pass `false` when the
        // source URL is signed or tokenized — see Privacy below.
        self.recorder = ABMetricsRecorder(sink: sink)

        recorder.attach(to: player).store(in: &tokens)
        player.addObserver { [weak self] event in
            guard case .firstFrameDisplayed = event else { return }
            Task { @MainActor [weak self] in
                self?.refreshStatistics()
            }
        }.store(in: &tokens)
    }

    func play(_ source: ABMediaSource) {
        let startedAt = ABMonotonicClock().now
        player.set(source: source, grade: .current)
        recorder.beginTTFF(for: player, at: startedAt)
        player.play()
    }

    private func refreshStatistics() {
        let samples = sink.events.compactMap { event -> ABMetricSample? in
            guard case .ttff(let sample) = event else { return nil }
            return sample
        }
        let statistics = ABPlaybackStatistics.aggregate(samples)
        print(statistics.waited.p50, statistics.waited.p95, statistics.hitRate)
    }
}
```

Hold that object for the whole measurement — as a property of the screen or coordinator. The sink, the recorder, and the observation tokens all have to outlive the asynchronous first-frame event, and an `ABPlayerKit/ABObservationToken` cancels from its own `deinit`.

Two things about the numbers it prints:

- ``ABPlaybackStatistics/waited`` covers `.waited` samples only. The flat ``ABPlaybackStatistics/p50``, ``ABPlaybackStatistics/p95``, and ``ABPlaybackStatistics/max`` are the legacy distribution, which folds every `.hit` in as `0` ms — in a feed with plenty of preload hits they collapse toward zero and stop describing anything a viewer experienced.
- An abandoned sample stays in the denominator of ``ABPlaybackStatistics/hitRate`` and ``ABPlaybackStatistics/abandonRate``. It is never silently discarded, so viewers bailing before the first frame move both rates.

### QoE sessions

```swift
recorder.attach(to: player).store(in: &tokens)

// Before cancelling the token, if a final summary is needed:
recorder.endSession(for: player)

// Or read a live, still-open summary at any point:
let inProgress = recorder.snapshot(for: player)
```

The same attach also tracks whole playback sessions, keyed by `(playerID, sessionStartedAt)` — there is no separate session identifier, so every v2 event carries both. A session opens on `ABPlayerKit/ABPlayerEvent/itemAttached(source:)` and closes on `ABPlayerKit/ABPlayerEvent/itemDetached(reason:)`, emitting ``ABMetricEvent/sessionStarted(_:)`` and ``ABMetricEvent/sessionSummary(_:)`` respectively. Call ``ABMetricsRecorder/endSession(for:)`` before cancelling the observation token if you want a final summary — the token has no cancellation hook the recorder can observe, so cancelling it alone produces no more events. ``ABMetricsRecorder/snapshot(for:)`` returns a live, unsunk summary for a session that's still open.

``ABSessionSummary/rebufferRatio`` is `rebufferMilliseconds / (rebufferMilliseconds + watchedMilliseconds)`, `nil` when both are `0`. Buffering before the first frame counts toward `startupBufferMilliseconds`, not `rebufferMilliseconds` — TTFF already measures that wait, so counting it as a rebuffer too would double-count the same stall across both metrics.

``ABSessionSummary/completionRatio``'s precision improves when `ABPlayerKit/ABPlayerConfiguration/periodicTimeInterval` is set; ``ABSessionSummary/watchedMilliseconds`` is accurate regardless, since it's derived from `ABPlayerKit/ABPlayerEvent/timeControlStatusChanged(_:)` transitions, not periodic position samples.

### Privacy

``ABSessionAnchor/sourceURL`` and ``ABSessionSummary/sourceURL`` carry the media URL for joining against server-side logs.

`includesSourceURL` **defaults to `true`**, so a signed or tokenized URL — a credential — is recorded verbatim unless you say otherwise. Either pass `includesSourceURL: false` to ``ABMetricsRecorder/init(sink:clock:includesSourceURL:)``, or mask the field in a custom ``ABMetricsSink``. This package bakes in no masking policy of its own.

Where a record lands matters after that decision. ``ABJSONLinesMetricsSink`` writes inside the app's own container. ``ABOSLogMetricsSink`` writes to the device-wide unified log, which outlives the app and is collected by a sysdiagnose — so it logs only the event's kind unredacted and leaves the payload under `OSLog`'s default `.private`. Its Console output reads `sessionStarted <private>` unless a logging profile is installed.

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
