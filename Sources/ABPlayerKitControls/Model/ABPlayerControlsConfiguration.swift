import ABPlayerKit
import Foundation

/// Behavior settings for ``ABPlayerControlsView``.
public struct ABPlayerControlsConfiguration: Sendable, Equatable {
    public enum RateInteraction: Sendable, Equatable {
        case menu
        case cycle
        case hidden
    }

    public enum TimeLabelLayout: Sendable, Equatable {
        case elapsedAndTotal
        case elapsedAndRemaining
        case elapsedOnly
    }

    public enum InitialVisibility: Sendable, Equatable {
        case visible
        case hidden
    }

    /// How time-label text is formatted.
    public enum TimeLabelFormat: Sendable {
        /// `MM:SS` under one hour, `HH:MM:SS` once the total duration reaches one hour.
        case automatic
        /// Always `HH:MM:SS`, matching the elapsed/total labels shown by default.
        case fixedHours
        /// Consumer-provided formatter, called with `(seconds, referenceDurationSeconds)`.
        /// `referenceDurationSeconds` is the same value for every label in a render pass
        /// (the media duration, or the remaining-time base), so a formatter can keep
        /// field widths consistent across the elapsed/total/remaining labels it renders.
        case custom(@Sendable (TimeInterval, TimeInterval?) -> String)
    }

    /// Skip-button seek amount, in seconds. Restricted to 5-second steps between
    /// 5 and 60 — assignments are rounded to the nearest step and clamped into
    /// that range (e.g. `7` becomes `5`, `63` becomes `60`).
    public var skipInterval: TimeInterval = 10 {
        didSet { skipInterval = Self.clampedSkipInterval(skipInterval) }
    }

    private static let skipIntervalRange: ClosedRange<TimeInterval> = 5...60
    private static let skipIntervalStep: TimeInterval = 5

    private static func clampedSkipInterval(_ value: TimeInterval) -> TimeInterval {
        guard value.isFinite else { return 10 }
        let stepped = (value / skipIntervalStep).rounded() * skipIntervalStep
        return min(max(stepped, skipIntervalRange.lowerBound), skipIntervalRange.upperBound)
    }
    public var synchronizesSkipIconWithInterval = true
    public var rateOptions: [Float] = ABPlaybackRate.common
    public var rateInteraction: RateInteraction = .menu
    public var autoHideDelay: TimeInterval? = 3
    public var staysVisibleWhilePaused = true
    public var periodicTimeInterval: TimeInterval? = 0.25
    public var showsBufferedProgress = true
    public var showsTimeLabels = true
    public var timeLabelLayout: TimeLabelLayout = .elapsedAndTotal
    public var timeFormat: TimeLabelFormat = .fixedHours
    public var showsSkipButtons = true
    public var handlesBackgroundTap = true
    public var allowsTrackTapToSeek = true
    public var initialVisibility: InitialVisibility = .visible

    public init() {}
}

extension ABPlayerControlsConfiguration.TimeLabelFormat: Equatable {
    /// `.custom` formatters are functions and cannot be compared for equality;
    /// two `.custom` values always compare unequal, which only costs an extra
    /// (harmless) label re-render on a configuration reassignment.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.automatic, .automatic), (.fixedHours, .fixedHours):
            true
        default:
            false
        }
    }
}
