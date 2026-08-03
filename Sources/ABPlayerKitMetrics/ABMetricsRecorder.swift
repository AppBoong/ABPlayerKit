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
    private var ttffStarts: [ABPlayerID: TTFFStart] = [:]

    public init(sink: any ABMetricsSink, clock: any ABClock = ABMonotonicClock()) {
        self.sink = sink
        self.clock = clock
    }

    public func attach(to player: ABPlayer) -> ABObservationToken {
        player.addObserver { [weak self, weak player] event in
            guard let self, let player else { return }
            self.handle(event, from: player)
        }
    }

    public func beginTTFF(
        for player: ABPlayer,
        at time: CFTimeInterval? = nil,
        resumedFromTime: CFTimeInterval? = nil
    ) {
        let startedAt = time ?? clock.now
        if player.hasDisplayedFirstFrame {
            sink.record(.ttff(ABMetricSample(
                playerID: player.id,
                startedAt: startedAt,
                outcome: .hit,
                resumedFromTime: resumedFromTime
            )))
            return
        }
        ttffStarts[player.id] = TTFFStart(
            startedAt: startedAt,
            resumedFromTime: resumedFromTime
        )
    }

    public func abandonTTFF(for player: ABPlayer) {
        guard let start = ttffStarts.removeValue(forKey: player.id) else { return }
        sink.record(.ttff(ABMetricSample(
            playerID: player.id,
            startedAt: start.startedAt,
            outcome: .abandoned,
            resumedFromTime: start.resumedFromTime
        )))
    }

    private func handle(_ event: ABPlayerEvent, from player: ABPlayer) {
        switch event {
        case .firstFrameDisplayed(let displayedAt):
            guard let start = ttffStarts.removeValue(forKey: player.id) else { return }
            let milliseconds = max(0, displayedAt - start.startedAt) * 1_000
            sink.record(.ttff(ABMetricSample(
                playerID: player.id,
                startedAt: start.startedAt,
                outcome: .waited(ms: milliseconds),
                resumedFromTime: start.resumedFromTime
            )))
        case .playbackStalled:
            sink.record(.stall(playerID: player.id, at: clock.now))
        case .gradeChanged(_, .preloaded):
            sink.record(.preloadStarted(playerID: player.id, at: clock.now))
        case .itemDetached(let reason):
            sink.record(.itemDetached(
                playerID: player.id,
                reason: reason,
                access: accessSnapshot(for: player.avPlayerItem)
            ))
        case .tuningApplied(let role, _):
            sink.record(.tuning(playerID: player.id, role: role))
        default:
            break
        }
    }

    private func accessSnapshot(for item: AVPlayerItem?) -> ABAccessSnapshot? {
        guard let event = item?.accessLog()?.events.last else { return nil }
        return ABAccessSnapshot(
            numberOfBytesTransferred: event.numberOfBytesTransferred,
            indicatedBitrate: event.indicatedBitrate,
            observedBitrate: event.observedBitrate,
            startupTime: event.startupTime,
            stallCount: event.numberOfStalls
        )
    }
}
