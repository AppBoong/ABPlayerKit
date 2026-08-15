import Foundation

/// Per-attachment settings for how a participant appears in Now Playing.
public struct ABNowPlayingConfiguration: Sendable, Equatable {
    /// Which remote commands this participant asks for.
    ///
    /// Membership is necessary but **not sufficient** — three commands carry
    /// a second condition, and none of them warn at runtime when it is
    /// unmet:
    ///
    /// - `.changePlaybackRate` also needs a non-empty
    ///   ``supportedPlaybackRates``.
    /// - `.nextTrack`/`.previousTrack` also need track-navigation handlers;
    ///   this library has no queue concept of its own.
    /// - `.changePlaybackPosition` is disabled automatically whenever the
    ///   item's duration is not finite and positive (a live stream), and
    ///   re-evaluated as the duration becomes known — so its enabled state
    ///   changes without any configuration change.
    ///
    /// `.default` also omits the first three entirely; add them explicitly.
    public var commands: ABRemoteCommandSet
    /// How far the lock-screen skip commands move.
    ///
    /// Defaults to **15** seconds, deliberately different from
    /// `ABPlayerControlsConfiguration.skipInterval`, which defaults to 10.
    /// Set both if the on-screen and lock-screen buttons should agree.
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
