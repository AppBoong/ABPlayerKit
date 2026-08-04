@preconcurrency import AVFoundation

/// Keeps at most one seek in flight and one newest pending destination.
struct ABSeekCoalescer: Equatable {
    enum Decision: Equatable {
        case issue(CMTime, tolerance: ABSeekTolerance)
        case hold
    }

    struct Pending: Equatable {
        let time: CMTime
        let tolerance: ABSeekTolerance
    }

    private(set) var inFlight: CMTime?
    private(set) var pending: Pending?

    mutating func request(_ time: CMTime, tolerance: ABSeekTolerance) -> Decision {
        guard inFlight == nil else {
            pending = Pending(time: time, tolerance: tolerance)
            return .hold
        }
        inFlight = time
        return .issue(time, tolerance: tolerance)
    }

    mutating func completed() -> Decision {
        guard inFlight != nil else { return .hold }
        inFlight = nil
        guard let pending else { return .hold }
        self.pending = nil
        inFlight = pending.time
        return .issue(pending.time, tolerance: pending.tolerance)
    }

    mutating func flush(finalTolerance: ABSeekTolerance) -> Decision {
        if let inFlight {
            let finalTime = pending?.time ?? inFlight
            pending = Pending(time: finalTime, tolerance: finalTolerance)
            return .hold
        }
        guard let pending else { return .hold }
        self.pending = nil
        inFlight = pending.time
        return .issue(pending.time, tolerance: finalTolerance)
    }

    mutating func reset() {
        inFlight = nil
        pending = nil
    }
}
