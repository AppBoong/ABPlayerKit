import Foundation
@preconcurrency import AVFoundation

/// Every knob an `ABPlayer` needs, gathered into one injectable value.
/// No DI container — init injection only (PLANNING.md §6).
public struct ABPlayerConfiguration: Sendable, Equatable {
    public var preloadTuning: ABPlaybackTuning
    public var currentTuning: ABPlaybackTuning
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
    public var backgroundPolicy: ABBackgroundPolicy
    public var audioSessionPolicy: ABAudioSessionPolicy
    /// Opt-in `AVAudioSession` interruption handling (round3 Phase4 WP10).
    /// Defaults to `.ignore` — matches `audioSessionPolicy`'s "do nothing
    /// unless asked" convention.
    public var interruptionPolicy: ABInterruptionPolicy
    /// Pauses playback when `AVAudioSessionRouteChangeReasonKey` reports
    /// `.oldDeviceUnavailable` (e.g. headphones unplugged) while this player
    /// is `.current` — independent of `interruptionPolicy`, since this is
    /// its own notification with its own default (`true`, matching the
    /// platform HIG convention that content should pause rather than
    /// continue playing out loud when the listening device disappears).
    /// Round3 Phase4 WP10.3.
    public var pausesOnRouteChangeDeviceUnavailable: Bool
    public var videoGravity: AVLayerVideoGravity
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
        self.assetFactory = assetFactory
    }

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
    }
}
