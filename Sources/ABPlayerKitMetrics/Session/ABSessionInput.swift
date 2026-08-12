import ABPlayerKit
import Foundation
@preconcurrency import QuartzCore

/// Core events normalized into metrics-scope inputs. `ABPlayerEvent` isn't
/// consumed directly here so that (1) the AVFoundation dependency stays
/// confined to the translation layer in ``ABMetricsRecorder`` and (2) table
/// tests can exercise transitions without a combinatorial explosion of real
/// player events.
enum ABSessionInput: Equatable {
    case attached(sourceURL: String?, wallClockEpoch: TimeInterval, isPartial: Bool)
    case ttffResolved(ABMetricSample.Outcome)
    case firstFrame
    case bufferingChanged(Bool)
    case stalled
    case stallEnded
    case timeControl(ABTimeControlStatus)
    case scrubbing(Bool)
    case position(seconds: Double, duration: Double?)
    case durationAvailable(seconds: Double)
    case playedToEnd
    case failure(ABPlayerFailure)
    case detached(reason: ABDetachReason, access: ABAccessSnapshot?)
    case finalize(access: ABAccessSnapshot?)
}
