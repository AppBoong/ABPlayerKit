import ABPlayerKit
@preconcurrency import AVFoundation
import Foundation

@MainActor
public final class ABMetricsRecorder {
    private struct TTFFStart {
        let startedAt: CFTimeInterval
        let resumedFromTime: CFTimeInterval?
    }

    private let sink: any ABMetricsSink
    private let clock: any ABClock
    private let includesSourceURL: Bool
    private var ttffStarts: [ABPlayerID: TTFFStart] = [:]
    private var sessions: [ABPlayerID: ABPlaybackSessionAccumulator] = [:]
    /// The item an open session's player currently holds. Captured at
    /// `.itemAttached`, the one point `player.avPlayerItem` is guaranteed
    /// non-nil for it, and read back at `.itemDetached`, since by the time
    /// that event reaches this observer the core has already nilled
    /// `player.avPlayerItem`.
    private var heldItems: [ABPlayerID: AVPlayerItem] = [:]

    /// - Parameters:
    ///   - sink: Where records go.
    ///   - clock: The monotonic timeline sessions are measured on.
    ///   - includesSourceURL: Whether `.sessionStarted`/`.sessionSummary`
    ///     carry the media URL, for joining against server-side logs.
    ///     **Defaults to `true`**, so a signed or tokenized URL — a
    ///     credential — is recorded verbatim unless this is `false`. This
    ///     package applies no masking policy of its own; mask in a custom
    ///     ``ABMetricsSink`` if the URL is needed in a redacted form.
    public init(
        sink: any ABMetricsSink,
        clock: any ABClock = ABMonotonicClock(),
        includesSourceURL: Bool = true
    ) {
        self.sink = sink
        self.clock = clock
        self.includesSourceURL = includesSourceURL
    }

    /// Starts recording `player`'s events.
    ///
    /// The returned token stops observation, but the recorder has no hook on
    /// its cancellation — dropping or cancelling it produces **no** final
    /// `.sessionSummary`, and the open session is simply abandoned. Call
    /// ``endSession(for:)`` first when a summary is wanted. Since the token
    /// also cancels from its own `deinit`, that includes letting it go out of
    /// scope.
    public func attach(to player: ABPlayer) -> ABObservationToken {
        player.addObserver { [weak self, weak player] event in
            guard let self, let player else { return }
            self.handle(event, from: player)
        }
    }

    /// Opens a time-to-first-frame measurement for `player`.
    ///
    /// If the player has *already* displayed its first frame, nothing is
    /// opened: a `.hit` sample is recorded synchronously and the call
    /// returns. A caller waiting for the paired `.firstFrameDisplayed` will
    /// wait forever — check `player.hasDisplayedFirstFrame`, or handle
    /// `.ttff` itself, rather than assuming a later event is coming.
    public func beginTTFF(
        for player: ABPlayer,
        at time: CFTimeInterval? = nil,
        resumedFromTime: CFTimeInterval? = nil
    ) {
        let startedAt = time ?? clock.now
        if player.hasDisplayedFirstFrame {
            let sample = ABMetricSample(
                playerID: player.id,
                startedAt: startedAt,
                outcome: .hit,
                resumedFromTime: resumedFromTime
            )
            sink.record(.ttff(sample))
            resolveTTFF(sample.outcome, playerID: player.id)
            return
        }
        ttffStarts[player.id] = TTFFStart(
            startedAt: startedAt,
            resumedFromTime: resumedFromTime
        )
    }

    public func abandonTTFF(for player: ABPlayer) {
        recordAbandonedTTFF(for: player.id)
    }

    /// Closes the open session for `player`, if any — same effect as the
    /// defensive `.itemDetached` boundary, callable directly. Idempotent.
    ///
    /// `attach(to:)`'s token has no cancellation hook the recorder can
    /// observe, so a consumer who wants a final `.sessionSummary` before
    /// cancelling must call this first — cancelling the token alone
    /// produces no events.
    public func endSession(for player: ABPlayer) {
        var accumulator = sessions[player.id] ?? ABPlaybackSessionAccumulator()
        let access = accessSnapshot(for: heldItems[player.id])
        let events = accumulator.ingest(.finalize(access: access), playerID: player.id, at: clock.now)
        heldItems.removeValue(forKey: player.id)
        sessions[player.id] = accumulator
        record(events)
    }

    /// A non-mutating, non-sunk snapshot of `player`'s open session as of
    /// now — for live display. Returns `nil` when no session is open.
    public func snapshot(for player: ABPlayer) -> ABSessionSummary? {
        guard let accumulator = sessions[player.id] else { return nil }
        let access = accessSnapshot(for: heldItems[player.id])
        return accumulator.snapshot(playerID: player.id, at: clock.now, access: access)
    }

    private func handle(_ event: ABPlayerEvent, from player: ABPlayer) {
        if case .itemAttached = event {
            heldItems[player.id] = player.avPlayerItem
        }
        handleLegacy(event, from: player)
        _ = ingest(event, playerID: player.id, hasItem: player.avPlayerItem != nil, at: clock.now)
    }

    /// Unchanged from v1 — every emission site and its ordering stays
    /// exactly as it was so the v1 JSONL byte stream doesn't move.
    private func handleLegacy(_ event: ABPlayerEvent, from player: ABPlayer) {
        switch event {
        case .firstFrameDisplayed(let displayedAt):
            guard let start = ttffStarts.removeValue(forKey: player.id) else { return }
            let milliseconds = max(0, displayedAt - start.startedAt) * 1_000
            let sample = ABMetricSample(
                playerID: player.id,
                startedAt: start.startedAt,
                outcome: .waited(ms: milliseconds),
                resumedFromTime: start.resumedFromTime
            )
            sink.record(.ttff(sample))
            resolveTTFF(sample.outcome, playerID: player.id)
        case .playbackStalled:
            sink.record(.stall(playerID: player.id, at: clock.now))
        case .gradeChanged(let from, .preloaded) where from < .preloaded:
            sink.record(.preloadStarted(playerID: player.id, at: clock.now))
        case .gradeChanged(let from, let to) where from.holdsItem && !to.holdsItem:
            recordAbandonedTTFF(for: player.id)
        case .itemDetached(let reason):
            recordAbandonedTTFF(for: player.id)
            sink.record(.itemDetached(
                playerID: player.id,
                reason: reason,
                access: accessSnapshot(for: heldItems[player.id])
            ))
        case .tuningApplied(let role, _):
            sink.record(.tuning(playerID: player.id, role: role))
        default:
            break
        }
    }

    /// The testable translation seam: turns one `ABPlayerEvent` into zero or
    /// more v2 metric events, given only the facts a real player can't hide
    /// behind AVFoundation (`hasItem`) or that already ride the event
    /// itself. `hasItem` is read by the caller from `player.avPlayerItem`
    /// before the item is torn down (see `handle(_:from:)`).
    @discardableResult
    internal func ingest(
        _ event: ABPlayerEvent,
        playerID: ABPlayerID,
        hasItem: Bool,
        at now: CFTimeInterval
    ) -> [ABMetricEvent] {
        var accumulator = sessions[playerID] ?? ABPlaybackSessionAccumulator()
        var events: [ABMetricEvent] = []

        switch event {
        case .itemAttached(let source):
            events += accumulator.ingest(
                .attached(
                    sourceURL: includesSourceURL ? source.url.absoluteString : nil,
                    wallClockEpoch: clock.wallClockEpoch,
                    isPartial: false
                ),
                playerID: playerID,
                at: now
            )
        case .itemDetached(let reason):
            let access = accessSnapshot(for: heldItems.removeValue(forKey: playerID))
            events += accumulator.ingest(.detached(reason: reason, access: access), playerID: playerID, at: now)
        case .gradeChanged(let from, let to) where from.holdsItem && !to.holdsItem:
            let access = accessSnapshot(for: heldItems.removeValue(forKey: playerID))
            events += accumulator.ingest(.finalize(access: access), playerID: playerID, at: now)
        default:
            if !accumulator.isOpen, hasItem, Self.isPartialSessionTrigger(event) {
                events += accumulator.ingest(
                    .attached(sourceURL: nil, wallClockEpoch: clock.wallClockEpoch, isPartial: true),
                    playerID: playerID,
                    at: now
                )
            }
            if let input = Self.translate(event) {
                events += accumulator.ingest(input, playerID: playerID, at: now)
            }
        }

        sessions[playerID] = accumulator
        record(events)
        return events
    }

    private static func isPartialSessionTrigger(_ event: ABPlayerEvent) -> Bool {
        switch event {
        case .itemStatusChanged, .firstFrameDisplayed, .timeControlStatusChanged, .periodicTime, .bufferingChanged:
            return true
        default:
            return false
        }
    }

    private static func translate(_ event: ABPlayerEvent) -> ABSessionInput? {
        switch event {
        case .firstFrameDisplayed:
            return .firstFrame
        case .bufferingChanged(let isBuffering):
            return .bufferingChanged(isBuffering)
        case .playbackStalled:
            return .stalled
        case .stallEnded:
            return .stallEnded
        case .timeControlStatusChanged(let status):
            return .timeControl(status)
        case .scrubbingChanged(let isScrubbing):
            return .scrubbing(isScrubbing)
        case .periodicTime(let time):
            guard time.currentTime.seconds.isFinite else { return nil }
            let durationSeconds = time.duration?.seconds
            return .position(
                seconds: time.currentTime.seconds,
                duration: (durationSeconds?.isFinite == true) ? durationSeconds : nil
            )
        case .seekCompleted(let time):
            guard time.seconds.isFinite else { return nil }
            return .position(seconds: time.seconds, duration: nil)
        case .durationAvailable(let time):
            guard time.seconds.isFinite, time.seconds > 0 else { return nil }
            return .durationAvailable(seconds: time.seconds)
        case .playedToEnd:
            return .playedToEnd
        case .failureReported(let failure):
            return .failure(failure)
        default:
            return nil
        }
    }

    private func resolveTTFF(_ outcome: ABMetricSample.Outcome, playerID: ABPlayerID) {
        guard var accumulator = sessions[playerID] else { return }
        let events = accumulator.ingest(.ttffResolved(outcome), playerID: playerID, at: clock.now)
        sessions[playerID] = accumulator
        record(events)
    }

    private func recordAbandonedTTFF(for playerID: ABPlayerID) {
        guard let start = ttffStarts.removeValue(forKey: playerID) else { return }
        let sample = ABMetricSample(
            playerID: playerID,
            startedAt: start.startedAt,
            outcome: .abandoned,
            resumedFromTime: start.resumedFromTime
        )
        sink.record(.ttff(sample))
        resolveTTFF(sample.outcome, playerID: playerID)
    }

    private func record(_ events: [ABMetricEvent]) {
        for event in events {
            sink.record(event)
        }
    }

    private func accessSnapshot(for item: AVPlayerItem?) -> ABAccessSnapshot? {
        guard let events = item?.accessLog()?.events, !events.isEmpty else { return nil }
        return ABAccessLogFolder.fold(events.map { event in
            ABAccessLogEntry(
                numberOfBytesTransferred: event.numberOfBytesTransferred,
                indicatedBitrate: event.indicatedBitrate,
                observedBitrate: event.observedBitrate,
                startupTime: event.startupTime,
                numberOfStalls: event.numberOfStalls,
                numberOfDroppedVideoFrames: event.numberOfDroppedVideoFrames,
                durationWatched: event.durationWatched,
                // `AVPlayerItemAccessLogEvent.numberOfSegmentsDownloaded` has
                // been API-unavailable in Swift since iOS 7 (superseded by
                // `numberOfMediaRequests`) — reported as unknown (negative)
                // so the fold excludes it rather than reading a fabricated 0.
                segmentsDownloadedCount: -1,
                numberOfMediaRequests: event.numberOfMediaRequests
            )
        })
    }
}
