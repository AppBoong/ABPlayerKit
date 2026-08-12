import ABPlayerKit
import Foundation
@preconcurrency import QuartzCore

/// Pure per-player session state machine. Normalizes ``ABSessionInput``
/// transitions into v2 metric events and QoE totals — no AVFoundation, no
/// wall-clock reads, no I/O, so every transition is table-testable.
///
/// One instance tracks at most one open session at a time. A second
/// `.attached` input while a session is still open (a source change that
/// replaces the item without an intervening `.itemDetached` — see
/// `ABGradePlanner`'s `preloaded -> preloaded`/`current -> current` cells)
/// finalizes the open session before opening the new one, so every opened
/// session eventually gets exactly one summary.
struct ABPlaybackSessionAccumulator: Equatable {
    private struct OpenBuffering: Equatable {
        let startedAt: CFTimeInterval
        let trigger: ABBufferingInterval.Trigger
        let phase: ABBufferingInterval.Phase
    }

    private struct OpenPlayback: Equatable {
        let since: CFTimeInterval
    }

    private(set) var isOpen = false
    private var sessionStartedAt: CFTimeInterval = 0
    private var wallClockEpoch: TimeInterval = 0
    private var sourceURL: String?
    private var isPartial = false

    private var hasSeenFirstFrame = false
    private var startupOutcome: ABMetricSample.Outcome?
    private var openBuffering: OpenBuffering?
    private var startupBufferMilliseconds: Double = 0
    private var rebufferMilliseconds: Double = 0
    private var rebufferCount = 0
    private var stallEventCount = 0

    private var openPlayback: OpenPlayback?
    private var lastTimeControlStatus: ABTimeControlStatus?
    private var isScrubbing = false
    private var watchedMilliseconds: Double = 0

    private var terminalFailureCount = 0
    private var diagnosticCount = 0
    private var lastFailure: ABPlayerFailure?

    private var playedToEnd = false
    private var lastPositionSeconds: Double?
    private var durationSeconds: Double?

    /// Transitions state and returns the v2 events this input produced, in
    /// order. Legacy events (`.ttff`/`.stall`/`.preloadStarted`/
    /// `.itemDetached`/`.tuning`) are never produced here — the recorder
    /// emits those directly, at the same sites as v1 (see F-1w brief §9).
    mutating func ingest(
        _ input: ABSessionInput,
        playerID: ABPlayerID,
        at now: CFTimeInterval
    ) -> [ABMetricEvent] {
        switch input {
        case .attached(let sourceURL, let wallClockEpoch, let isPartial):
            var events: [ABMetricEvent] = []
            if isOpen {
                events += close(playerID: playerID, endReason: .finalized, access: nil, at: now)
            }
            events += open(
                playerID: playerID,
                at: now,
                sourceURL: sourceURL,
                wallClockEpoch: wallClockEpoch,
                isPartial: isPartial
            )
            return events

        case .ttffResolved(let outcome):
            guard isOpen else { return [] }
            startupOutcome = outcome
            return []

        case .firstFrame:
            guard isOpen else { return [] }
            hasSeenFirstFrame = true
            return []

        case .bufferingChanged(let isBuffering):
            guard isOpen else { return [] }
            return isBuffering
                ? openBufferingInterval(trigger: .buffering, at: now)
                : closeBufferingInterval(end: .resumed, playerID: playerID, at: now)

        case .stalled:
            guard isOpen else { return [] }
            stallEventCount += 1
            return openBufferingInterval(trigger: .stall, at: now)

        case .stallEnded:
            guard isOpen else { return [] }
            return closeBufferingInterval(end: .resumed, playerID: playerID, at: now)

        case .timeControl(let status):
            guard isOpen else { return [] }
            lastTimeControlStatus = status
            switch status {
            case .playing:
                if !isScrubbing, openPlayback == nil {
                    openPlayback = OpenPlayback(since: now)
                }
            case .paused, .waitingToPlay:
                closePlaybackAccumulation(at: now)
            }
            return []

        case .scrubbing(let active):
            guard isOpen else { return [] }
            isScrubbing = active
            if active {
                closePlaybackAccumulation(at: now)
            } else if lastTimeControlStatus == .playing, openPlayback == nil {
                openPlayback = OpenPlayback(since: now)
            }
            return []

        case .position(let seconds, let duration):
            guard isOpen else { return [] }
            lastPositionSeconds = seconds
            if let duration {
                durationSeconds = duration
            }
            return []

        case .durationAvailable(let seconds):
            guard isOpen else { return [] }
            durationSeconds = seconds
            return []

        case .playedToEnd:
            guard isOpen else { return [] }
            playedToEnd = true
            return []

        case .failure(let failure):
            return handleFailure(failure, playerID: playerID, at: now)

        case .detached(let reason, let access):
            return close(playerID: playerID, endReason: .detached(reason), access: access, at: now)

        case .finalize(let access):
            guard isOpen else { return [] }
            return close(playerID: playerID, endReason: .finalized, access: access, at: now)
        }
    }

    /// Non-mutating. Virtually closes any open buffering/playback span as of
    /// `now`, without persisting that closure — used for live display
    /// (`ABMetricsRecorder/snapshot(for:)`), never sunk to a metrics sink.
    func snapshot(playerID: ABPlayerID, at now: CFTimeInterval, access: ABAccessSnapshot?) -> ABSessionSummary? {
        guard isOpen else { return nil }
        return buildSummary(playerID: playerID, endedAt: now, endReason: .active, access: access)
    }

    // MARK: - Buffering spans

    private mutating func openBufferingInterval(
        trigger: ABBufferingInterval.Trigger,
        at now: CFTimeInterval
    ) -> [ABMetricEvent] {
        guard openBuffering == nil else { return [] }
        let phase: ABBufferingInterval.Phase = hasSeenFirstFrame ? .rebuffer : .startup
        openBuffering = OpenBuffering(startedAt: now, trigger: trigger, phase: phase)
        return []
    }

    private mutating func closeBufferingInterval(
        end: ABBufferingInterval.End,
        playerID: ABPlayerID,
        at now: CFTimeInterval
    ) -> [ABMetricEvent] {
        guard let pending = openBuffering else { return [] }
        openBuffering = nil
        let interval = ABBufferingInterval(
            playerID: playerID,
            sessionStartedAt: sessionStartedAt,
            startedAt: pending.startedAt,
            endedAt: max(now, pending.startedAt),
            phase: pending.phase,
            trigger: pending.trigger,
            end: end
        )
        switch pending.phase {
        case .startup:
            startupBufferMilliseconds += interval.milliseconds
        case .rebuffer:
            rebufferMilliseconds += interval.milliseconds
            rebufferCount += 1
        }
        return [.buffering(interval)]
    }

    // MARK: - Playback accumulation

    private mutating func closePlaybackAccumulation(at now: CFTimeInterval) {
        guard let pending = openPlayback else { return }
        openPlayback = nil
        watchedMilliseconds += max(0, now - pending.since) * 1_000
    }

    // MARK: - Failures

    private mutating func handleFailure(
        _ failure: ABPlayerFailure,
        playerID: ABPlayerID,
        at now: CFTimeInterval
    ) -> [ABMetricEvent] {
        var events: [ABMetricEvent] = [.failure(ABFailureRecord(
            playerID: playerID,
            sessionStartedAt: isOpen ? sessionStartedAt : nil,
            at: now,
            failure: failure
        ))]
        guard isOpen else { return events }
        if failure.isTerminal {
            terminalFailureCount += 1
            lastFailure = failure
            events += closeBufferingInterval(end: .failed, playerID: playerID, at: now)
        } else {
            diagnosticCount += 1
        }
        return events
    }

    // MARK: - Open / close

    private mutating func open(
        playerID: ABPlayerID,
        at now: CFTimeInterval,
        sourceURL: String?,
        wallClockEpoch: TimeInterval,
        isPartial: Bool
    ) -> [ABMetricEvent] {
        self = ABPlaybackSessionAccumulator()
        isOpen = true
        sessionStartedAt = now
        self.wallClockEpoch = wallClockEpoch
        self.sourceURL = sourceURL
        self.isPartial = isPartial
        return [.sessionStarted(ABSessionAnchor(
            playerID: playerID,
            startedAt: now,
            wallClockEpoch: wallClockEpoch,
            sourceURL: sourceURL,
            isPartial: isPartial
        ))]
    }

    private mutating func close(
        playerID: ABPlayerID,
        endReason: ABSessionSummary.EndReason,
        access: ABAccessSnapshot?,
        at now: CFTimeInterval
    ) -> [ABMetricEvent] {
        guard isOpen else { return [] }
        var events: [ABMetricEvent] = []
        let bufferingEnd: ABBufferingInterval.End = {
            switch endReason {
            case .detached: return .detached
            case .finalized, .active: return .finalized
            }
        }()
        events += closeBufferingInterval(end: bufferingEnd, playerID: playerID, at: now)
        closePlaybackAccumulation(at: now)
        events.append(.sessionSummary(buildSummary(
            playerID: playerID,
            endedAt: now,
            endReason: endReason,
            access: access
        )))
        isOpen = false
        return events
    }

    private func buildSummary(
        playerID: ABPlayerID,
        endedAt: CFTimeInterval,
        endReason: ABSessionSummary.EndReason,
        access: ABAccessSnapshot?
    ) -> ABSessionSummary {
        var watched = watchedMilliseconds
        if let openPlayback {
            watched += max(0, endedAt - openPlayback.since) * 1_000
        }
        var startupBuffer = startupBufferMilliseconds
        var rebuffer = rebufferMilliseconds
        var rebufferCountValue = rebufferCount
        if let openBuffering {
            let milliseconds = max(0, endedAt - openBuffering.startedAt) * 1_000
            switch openBuffering.phase {
            case .startup:
                startupBuffer += milliseconds
            case .rebuffer:
                rebuffer += milliseconds
                rebufferCountValue += 1
            }
        }
        return ABSessionSummary(
            playerID: playerID,
            startedAt: sessionStartedAt,
            wallClockEpoch: wallClockEpoch,
            endedAt: endedAt,
            endReason: endReason,
            isPartial: isPartial,
            sourceURL: sourceURL,
            startupOutcome: startupOutcome,
            hasDisplayedFirstFrame: hasSeenFirstFrame,
            watchedMilliseconds: watched,
            startupBufferMilliseconds: startupBuffer,
            rebufferMilliseconds: rebuffer,
            rebufferCount: rebufferCountValue,
            stallEventCount: stallEventCount,
            terminalFailureCount: terminalFailureCount,
            diagnosticCount: diagnosticCount,
            lastFailure: lastFailure,
            playedToEnd: playedToEnd,
            lastPositionSeconds: lastPositionSeconds,
            durationSeconds: durationSeconds,
            access: access
        )
    }
}
