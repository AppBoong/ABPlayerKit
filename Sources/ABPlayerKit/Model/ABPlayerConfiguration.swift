import Foundation
@preconcurrency import AVFoundation

/// Every knob an `ABPlayer` needs, gathered into one injectable value.
/// No DI container — init injection only (PLANNING.md §6).
public struct ABPlayerConfiguration: Sendable, Equatable {
    public var preloadTuning: ABPlaybackTuning
    public var currentTuning: ABPlaybackTuning
    public var isLooping: Bool
    public var isMuted: Bool
    /// `nil` means "do not preroll".
    public var prerollRate: Float?
    public var prerollTimeout: TimeInterval
    /// `true` seeks to `.zero` on demotion.
    public var rewindOnDemotion: Bool
    public var backgroundPolicy: ABBackgroundPolicy
    public var audioSessionPolicy: ABAudioSessionPolicy
    public var videoGravity: AVLayerVideoGravity
    public var assetFactory: any ABAssetFactory

    public init(
        preloadTuning: ABPlaybackTuning = .conservativePreload,
        currentTuning: ABPlaybackTuning = .displayCapped,
        isLooping: Bool = false,
        isMuted: Bool = false,
        prerollRate: Float? = 1.0,
        prerollTimeout: TimeInterval = 10,
        rewindOnDemotion: Bool = false,
        backgroundPolicy: ABBackgroundPolicy = .pause,
        audioSessionPolicy: ABAudioSessionPolicy = .unmanaged,
        videoGravity: AVLayerVideoGravity = .resizeAspectFill,
        assetFactory: any ABAssetFactory = ABDefaultAssetFactory()
    ) {
        self.preloadTuning = preloadTuning
        self.currentTuning = currentTuning
        self.isLooping = isLooping
        self.isMuted = isMuted
        self.prerollRate = prerollRate
        self.prerollTimeout = prerollTimeout
        self.rewindOnDemotion = rewindOnDemotion
        self.backgroundPolicy = backgroundPolicy
        self.audioSessionPolicy = audioSessionPolicy
        self.videoGravity = videoGravity
        self.assetFactory = assetFactory
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.preloadTuning == rhs.preloadTuning
            && lhs.currentTuning == rhs.currentTuning
            && lhs.isLooping == rhs.isLooping
            && lhs.isMuted == rhs.isMuted
            && lhs.prerollRate == rhs.prerollRate
            && lhs.prerollTimeout == rhs.prerollTimeout
            && lhs.rewindOnDemotion == rhs.rewindOnDemotion
            && lhs.backgroundPolicy == rhs.backgroundPolicy
            && lhs.audioSessionPolicy == rhs.audioSessionPolicy
            && lhs.videoGravity == rhs.videoGravity
    }
}
