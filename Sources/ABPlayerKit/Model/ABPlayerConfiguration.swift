import Foundation
@preconcurrency import AVFoundation

/// Every knob an `ABPlayer` needs, gathered into one injectable value.
/// No DI container — init injection only.
public struct ABPlayerConfiguration: Sendable, Equatable {
    public var preloadTuning: ABPlaybackTuning
    public var currentTuning: ABPlaybackTuning
    /// Restarts the item at its end instead of stopping.
    ///
    /// Loop boundaries are still visible on the event stream, and read as
    /// end-of-playback:
    /// ``ABPlayerEvent/playedToEnd`` fires on *every* iteration, before the
    /// internal restart seek. That restart deliberately emits no
    /// ``ABPlayerEvent/seekCompleted(to:)``, so a UI driven by
    /// `.playedToEnd` needs to check this flag rather than assume playback
    /// has stopped.
    public var isLooping: Bool
    public var isMuted: Bool
    /// The desired playback rate. Values are clamped by ``ABPlayer``.
    public var playbackRate: Float
    /// The tolerance used for intermediate interactive scrubbing seeks.
    public var scrubTolerance: ABSeekTolerance
    /// `nil` disables periodic playback-time events.
    public var periodicTimeInterval: TimeInterval?
    /// `nil` means "do not preroll".
    public var prerollRate: Float?
    public var prerollTimeout: TimeInterval
    /// `true` seeks to `.zero` on demotion.
    public var rewindOnDemotion: Bool
    /// What happens to playback when the app backgrounds.
    ///
    /// Defaults to ``ABBackgroundPolicy/pause``, not to doing nothing: an
    /// `ABPlayer` installs `NotificationCenter` app-state observers at init
    /// and pauses on background entry without being asked. Choose
    /// ``ABBackgroundPolicy/ignore`` to opt out entirely.
    ///
    /// ``ABBackgroundPolicy/continueAudioOnly`` degrades silently to
    /// `.pause`-like behavior unless the host app declares the `audio`
    /// background mode *and* `audioSessionPolicy` is something other than
    /// `.unmanaged`. There is no runtime warning when a prerequisite is
    /// missing.
    public var backgroundPolicy: ABBackgroundPolicy
    public var audioSessionPolicy: ABAudioSessionPolicy
    /// Opt-in `AVAudioSession` interruption handling.
    /// Defaults to `.ignore` — matches `audioSessionPolicy`'s "do nothing
    /// unless asked" convention.
    public var interruptionPolicy: ABInterruptionPolicy
    /// Pauses playback when `AVAudioSessionRouteChangeReasonKey` reports
    /// `.oldDeviceUnavailable` (e.g. headphones unplugged) while this player
    /// is `.current` — independent of `interruptionPolicy`, since this is
    /// its own notification with its own default (`true`, matching the
    /// platform HIG convention that content should pause rather than
    /// continue playing out loud when the listening device disappears).
    /// Governs only device-unavailable route-change pausing; audio session
    /// interruption handling is controlled separately via
    /// `interruptionPolicy`.
    public var pausesOnRouteChangeDeviceUnavailable: Bool
    /// How the layer fits video into its bounds.
    ///
    /// ``ABPlayer`` never reads this — ``ABPlayerView`` does, when a player is
    /// assigned to it. Changing it on a live player therefore does nothing
    /// until the next assignment; set ``ABPlayerView/videoGravity`` to change
    /// it in place. `ABVideoPlayer` overwrites it from its own `videoGravity`
    /// parameter, and ``ABPlayerView/adaptsGravityToAspectRatio`` overrides it
    /// again from the item's presentation size once that is known.
    ///
    /// The default is `.resizeAspectFill`, not `AVPlayerLayer`'s own
    /// `.resizeAspect`.
    public var videoGravity: AVLayerVideoGravity
    /// `AVPlayer.allowsExternalPlayback`. Default `true` — matches
    /// `AVPlayer`'s own default, so existing consumers see no behavior
    /// change. A screen with several concurrently-live players (a feed)
    /// should set this `false` on every instance except the current one.
    public var allowsExternalPlayback: Bool
    /// `AVPlayer.usesExternalPlaybackWhileExternalScreenIsActive`. Default
    /// `false`, matching `AVPlayer`'s own default.
    public var usesExternalPlaybackWhileExternalScreenIsActive: Bool
    /// `AVPlayer.externalPlaybackVideoGravity`. Default `.resizeAspect`,
    /// matching `AVPlayer`'s own default.
    public var externalPlaybackVideoGravity: AVLayerVideoGravity
    /// Builds the `AVAsset` for a source — the seam `ABPlayerKitCache` uses to
    /// insert its resource loader.
    ///
    /// Read only at attach time, so swapping it on a live player has no effect
    /// until the next attach. It is also the one property excluded from `==`,
    /// so two configurations differing only in asset factory compare equal.
    public var assetFactory: any ABAssetFactory

    public init(
        preloadTuning: ABPlaybackTuning = .conservativePreload,
        currentTuning: ABPlaybackTuning = .displayCapped,
        isLooping: Bool = false,
        isMuted: Bool = false,
        playbackRate: Float = 1.0,
        scrubTolerance: ABSeekTolerance = .scrubbing,
        periodicTimeInterval: TimeInterval? = nil,
        prerollRate: Float? = 1.0,
        prerollTimeout: TimeInterval = 10,
        rewindOnDemotion: Bool = false,
        backgroundPolicy: ABBackgroundPolicy = .pause,
        audioSessionPolicy: ABAudioSessionPolicy = .unmanaged,
        interruptionPolicy: ABInterruptionPolicy = .ignore,
        pausesOnRouteChangeDeviceUnavailable: Bool = true,
        videoGravity: AVLayerVideoGravity = .resizeAspectFill,
        allowsExternalPlayback: Bool = true,
        usesExternalPlaybackWhileExternalScreenIsActive: Bool = false,
        externalPlaybackVideoGravity: AVLayerVideoGravity = .resizeAspect,
        assetFactory: any ABAssetFactory = ABDefaultAssetFactory()
    ) {
        self.preloadTuning = preloadTuning
        self.currentTuning = currentTuning
        self.isLooping = isLooping
        self.isMuted = isMuted
        self.playbackRate = playbackRate
        self.scrubTolerance = scrubTolerance
        self.periodicTimeInterval = periodicTimeInterval
        self.prerollRate = prerollRate
        self.prerollTimeout = prerollTimeout
        self.rewindOnDemotion = rewindOnDemotion
        self.backgroundPolicy = backgroundPolicy
        self.audioSessionPolicy = audioSessionPolicy
        self.interruptionPolicy = interruptionPolicy
        self.pausesOnRouteChangeDeviceUnavailable = pausesOnRouteChangeDeviceUnavailable
        self.videoGravity = videoGravity
        self.allowsExternalPlayback = allowsExternalPlayback
        self.usesExternalPlaybackWhileExternalScreenIsActive = usesExternalPlaybackWhileExternalScreenIsActive
        self.externalPlaybackVideoGravity = externalPlaybackVideoGravity
        self.assetFactory = assetFactory
    }

    /// Compares every stored property **except** ``assetFactory``, which is
    /// an existential with no `Equatable` requirement.
    ///
    /// The consequence is worth knowing before building change detection on
    /// this: switching between the default factory and `ABPlayerKitCache`'s
    /// leaves two configurations comparing equal, so a diff keyed on `==`
    /// will not see it.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.preloadTuning == rhs.preloadTuning
            && lhs.currentTuning == rhs.currentTuning
            && lhs.isLooping == rhs.isLooping
            && lhs.isMuted == rhs.isMuted
            && lhs.playbackRate == rhs.playbackRate
            && lhs.scrubTolerance == rhs.scrubTolerance
            && lhs.periodicTimeInterval == rhs.periodicTimeInterval
            && lhs.prerollRate == rhs.prerollRate
            && lhs.prerollTimeout == rhs.prerollTimeout
            && lhs.rewindOnDemotion == rhs.rewindOnDemotion
            && lhs.backgroundPolicy == rhs.backgroundPolicy
            && lhs.audioSessionPolicy == rhs.audioSessionPolicy
            && lhs.interruptionPolicy == rhs.interruptionPolicy
            && lhs.pausesOnRouteChangeDeviceUnavailable == rhs.pausesOnRouteChangeDeviceUnavailable
            && lhs.videoGravity == rhs.videoGravity
            && lhs.allowsExternalPlayback == rhs.allowsExternalPlayback
            && lhs.usesExternalPlaybackWhileExternalScreenIsActive == rhs.usesExternalPlaybackWhileExternalScreenIsActive
            && lhs.externalPlaybackVideoGravity == rhs.externalPlaybackVideoGravity
    }
}
