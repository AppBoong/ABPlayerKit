import Foundation

/// Per-attachment settings for how a participant appears in Now Playing.
public struct ABNowPlayingConfiguration: Sendable, Equatable {
    public var commands: ABRemoteCommandSet
    public var skipInterval: TimeInterval
    /// Only meaningful once `commands` includes `.changePlaybackRate` — an
    /// empty list (the default) keeps that command disabled regardless.
    /// Values are clamped by `ABPlaybackRate.clamped` before publishing.
    public var supportedPlaybackRates: [Float]

    public init(
        commands: ABRemoteCommandSet = .default,
        skipInterval: TimeInterval = 15,
        supportedPlaybackRates: [Float] = []
    ) {
        self.commands = commands
        self.skipInterval = skipInterval
        self.supportedPlaybackRates = supportedPlaybackRates
    }
}
