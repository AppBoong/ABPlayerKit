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

    public var skipInterval: TimeInterval = 10
    public var synchronizesSkipIconWithInterval = true
    public var rateOptions: [Float] = ABPlaybackRate.common
    public var rateInteraction: RateInteraction = .menu
    public var autoHideDelay: TimeInterval? = 3
    public var staysVisibleWhilePaused = true
    public var periodicTimeInterval: TimeInterval? = 0.25
    public var showsBufferedProgress = true
    public var showsTimeLabels = true
    public var timeLabelLayout: TimeLabelLayout = .elapsedAndTotal
    public var showsSkipButtons = true
    public var handlesBackgroundTap = true
    public var allowsTrackTapToSeek = true
    public var initialVisibility: InitialVisibility = .visible

    public init() {}
}
