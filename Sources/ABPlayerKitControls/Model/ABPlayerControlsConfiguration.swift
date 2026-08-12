import ABPlayerKit
import Foundation

/// How touches that land on the controls overlay but don't hit any specific
/// control are handled.
public enum ABControlsTouchPassthrough: Sendable, Equatable {
    /// The overlay consumes every touch in its bounds (current behavior).
    case never
    /// While controls are hidden, touches that miss every control pass
    /// through to whatever is behind the overlay.
    case whenControlsHidden
    /// Touches that miss every control always pass through, regardless of
    /// visibility.
    case always
}

/// Whether — and where — a double tap on the controls overlay seeks.
public enum ABDoubleTapSeek: Sendable, Equatable {
    /// No double-tap gesture is installed (default).
    case disabled
    /// Double-tapping the leading/trailing edge bands seeks by
    /// ``ABPlayerControlsConfiguration/skipInterval``. `edgeWidthFraction` is
    /// each band's width as a fraction of the overlay's width, clamped to
    /// `0.1...0.5`.
    case edges(edgeWidthFraction: Double = 0.3)
}

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

    /// How the playback-rate value is turned into text.
    public enum RateLabelFormat: Sendable {
        /// Locale-aware formatting via `NumberFormatter` (e.g. `"1.5"` in
        /// `en`, `"1,5"` in `de`). ``ABPlayerControlsStyle/rateLabelStyle``'s
        /// `.text` template still wraps the result (`"%@×"` → `"1.5×"`).
        case automatic
        /// Consumer-provided formatter. Its return value is used verbatim as
        /// the *entire* label — `rateLabelStyle`'s `.text` template does not
        /// apply, matching ``TimeLabelFormat/custom(_:)``'s contract.
        case custom(@Sendable (Float) -> String)
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
    /// Whether the play/pause button is shown. `false` hides it the same
    /// way ``showsSkipButtons`` hides the skip buttons.
    public var showsPlayPauseButton = true
    /// Whether the seek bar is shown. `false` collapses the row it occupies.
    public var showsSeekBar = true
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

    /// Whether a buffering stall shows the spinner overlay described in
    /// ``ABPlayerControlsView``'s buffering behavior. `false` disables both
    /// the spinner and the play/pause glyph suppression that accompanies it.
    public var showsBufferingIndicator = true

    /// How touches that miss every control are handled. Defaults to
    /// ``ABControlsTouchPassthrough/never`` — identical hit-testing to before
    /// this option existed.
    public var touchPassthrough: ABControlsTouchPassthrough = .never

    /// Double-tap-to-seek on the overlay's edge bands. Defaults to
    /// ``ABDoubleTapSeek/disabled`` — installing the gesture requires the
    /// background single-tap recognizer to wait out a possible second tap
    /// (`require(toFail:)`), which delays every single tap by the double-tap
    /// timeout for every consumer, not just ones that want the feature.
    public var doubleTapSeek: ABDoubleTapSeek = .disabled

    /// Whether an accepted double-tap seek triggers a light haptic. Only
    /// double-tap seeking uses this — skip buttons, rate changes, and
    /// scrubbing are existing, non-opt-in interactions this round doesn't
    /// change the feel of.
    public var providesHapticFeedback = true

    /// How the playback-rate value is formatted, on the button and in the
    /// rate menu alike. Not part of `rateMenuContentsChanged`'s rebuild
    /// gate in `applyConfiguration` — under `.custom`, every SwiftUI update
    /// pass would otherwise recreate the `UIMenu` (see
    /// `TimeLabelFormat.custom`'s Equatable doc comment for the same issue).
    public var rateLabelFormat: RateLabelFormat = .automatic

    /// The string placed between the elapsed and secondary time-label
    /// fields (`"01:05/02:05"`'s `"/"`). Ignored by ``TimeLabelFormat/custom(_:)``,
    /// which lays out its own complete label.
    public var timeLabelSeparator = "/"

    public init() {}
}

extension ABPlayerControlsConfiguration.RateLabelFormat: Equatable {
    /// `.custom` formatters can't be compared for equality — see
    /// `TimeLabelFormat`'s identical conformance for the full rationale.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.automatic, .automatic):
            true
        default:
            false
        }
    }
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
