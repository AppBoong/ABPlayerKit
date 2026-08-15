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
        /// whole label itself: layering the automatic combination on top of
        /// an already-complete `.custom` string would produce doubled
        /// output, e.g. `"12s/90s/90s/90s"`.
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
    /// Derives the skip glyph's badged number from ``skipInterval``, so a
    /// 30-second skip renders `gobackward.30`.
    ///
    /// `false` does **not** fall back to a neutral arrow — it hard-codes
    /// `gobackward.10`/`goforward.10`, so a 30-second interval then shows a
    /// glyph that reads "10". To get an unnumbered arrow, set an explicit
    /// icon on ``ABPlayerControlsStyle/skipBackwardIcon``/`skipForwardIcon`
    /// instead.
    public var synchronizesSkipIconWithInterval = true
    /// The rates offered by the rate control.
    ///
    /// An empty array hides the rate button entirely, whatever
    /// ``rateInteraction`` says. Values outside `ABPlaybackRate`'s supported
    /// range are clamped when applied, so an out-of-range entry displays one
    /// rate and takes effect as another — keep the array inside the range.
    public var rateOptions: [Float] = ABPlaybackRate.common
    public var rateInteraction: RateInteraction = .menu
    /// How long the overlay stays up before hiding itself.
    ///
    /// `nil` means **never auto-hide**, not "hide immediately". Even a
    /// non-`nil` delay is suppressed while VoiceOver is running, while
    /// buffering, while scrubbing, and — under ``staysVisibleWhilePaused`` —
    /// while paused.
    ///
    /// Setting this alongside `handlesBackgroundTap = false` can leave the
    /// overlay unrecoverable; see ``handlesBackgroundTap``.
    public var autoHideDelay: TimeInterval? = 3
    /// Suppresses auto-hide while playback is paused.
    ///
    /// It gates the hide rather than forcing the overlay visible, and it
    /// applies to an already-scheduled hide as well as a future one —
    /// pausing before the timer fires cancels its effect. Changing it at
    /// runtime cancels and reschedules the timer.
    public var staysVisibleWhilePaused = true
    /// How often the overlay refreshes its elapsed time and scrubber.
    ///
    /// Not a controls-local setting: attaching a player **overwrites**
    /// `ABPlayerConfiguration.periodicTimeInterval` with this value, taking a
    /// lease that restores the app's own value when the controls detach or
    /// deallocate. An app that sets its own interval for other reasons will
    /// see it replaced for as long as controls are attached.
    public var periodicTimeInterval: TimeInterval? = 0.25
    public var showsBufferedProgress = true
    public var showsTimeLabels = true
    /// Which fields the time label shows.
    ///
    /// Ignored entirely when ``timeFormat`` is `.custom`, which produces the
    /// whole string itself. Under `.elapsedAndTotal`, an item with no known
    /// duration shows a localized `LIVE` marker in place of the total rather
    /// than a time.
    public var timeLabelLayout: TimeLabelLayout = .elapsedAndTotal
    /// How a time is rendered.
    ///
    /// The default is `.fixedHours`, which is always zero-padded `HH:MM:SS`
    /// including a zero hours field — a 90-second clip reads `00:01:30`. Use
    /// `.automatic` for the minimal `M:SS` form that most media players show.
    ///
    /// VoiceOver ignores this: it always hears spoken elapsed and duration,
    /// including under `.custom`, which replaces only the on-screen text.
    public var timeFormat: TimeLabelFormat = .fixedHours
    public var showsSkipButtons = true
    /// Whether the play/pause button is shown. `false` hides it the same
    /// way ``showsSkipButtons`` hides the skip buttons.
    public var showsPlayPauseButton = true
    /// Whether the seek bar is shown. `false` collapses the row it occupies.
    public var showsSeekBar = true
    /// Whether a tap on the overlay's background toggles the controls.
    ///
    /// This is the only gesture that can bring hidden controls back, so
    /// `false` combined with a non-`nil` ``autoHideDelay`` leaves the overlay
    /// unreachable until something calls `setControlsVisible(true)`. Even
    /// when `true`, taps landing on a `UIControl` are not treated as
    /// background taps.
    public var handlesBackgroundTap = true
    /// Whether tapping anywhere on the seek bar's track jumps to that
    /// position.
    ///
    /// `false` does more than disable the jump: scrubbing then starts only
    /// when the touch lands within the thumb, inflated on both axes by
    /// ``ABPlayerControlsStyle/thumbTouchInflation``. That style property has
    /// no effect at all while this stays `true`, so the two are coupled
    /// across the style/configuration boundary.
    public var allowsTrackTapToSeek = true
    /// Whether the overlay starts visible or hidden.
    ///
    /// Applied on every player assignment, not only the first — swapping the
    /// player snaps the overlay back to this value and discards whatever the
    /// user's taps or `setControlsVisible(_:)` had established. Changing it
    /// alone does nothing until the next attach.
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
