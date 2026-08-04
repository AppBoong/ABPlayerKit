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
        /// Consumer-provided formatter, called once per update with
        /// `(elapsedSeconds, referenceDurationSeconds)` — `referenceDurationSeconds`
        /// is the media duration (or `nil` while unknown/live). Its return value is
        /// used verbatim as the *entire* time-label text; `timeLabelLayout`'s
        /// elapsed/total/remaining combination does not apply to `.custom`, since the
        /// formatter already receives both values and is expected to lay out the
        /// whole label itself (round3 Phase4 WP12 — layering the automatic
        /// combination on top of an already-complete `.custom` string previously
        /// produced doubled output, e.g. `"12s/90s/90s/90s"`).
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

    /// Whether tapping the play/pause button while the player has a source but
    /// isn't `.current` promotes it to `.current` and plays, instead of the
    /// button being inert. Defaults to `true` — a player freshly attached at
    /// `.preloaded`/`.instanceOnly` (the common case: a host app promotes to
    /// `.current` only once the user actually wants to watch) would otherwise
    /// leave the whole overlay dead until something outside the controls layer
    /// promoted it. Seek, skip, and the rate control stay disabled until the
    /// player actually reaches `.current` — only the tap that gets it there is
    /// special-cased.
    public var promotesToCurrentOnPlay = true

    public init() {}
}

extension ABPlayerControlsConfiguration.TimeLabelFormat: Equatable {
    /// `.custom` formatters are functions and cannot be compared for equality;
    /// two `.custom` values — even two copies of the exact same configuration —
    /// always compare unequal. Since `ABPlayerControls` (the SwiftUI wrapper)
    /// reassigns `configuration` whenever `!=` its previous value, a `.custom`
    /// time format makes that guard permanently open: `updateUIView` calls
    /// through on *every* SwiftUI update pass, not just on an actual
    /// reassignment. `applyConfiguration(previous:)` only rebuilds the rate
    /// menu when `rateOptions`/`rateInteraction` actually changed (not on
    /// every call `.custom` forces), so the churn this causes is bounded to
    /// cheap, idempotent re-renders (labels, icons) — not a `UIMenu` rebuild
    /// that could close one a user has open mid-interaction.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.automatic, .automatic), (.fixedHours, .fixedHours):
            true
        default:
            false
        }
    }
}
