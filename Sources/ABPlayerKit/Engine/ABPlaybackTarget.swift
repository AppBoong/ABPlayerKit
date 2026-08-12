@preconcurrency import AVFoundation
import CoreGraphics

/// Signals the concrete target reports back to `ABPlayer`, independent of
/// the commands `ABPlayer` issues *to* the target. Kept as a plain enum
/// rather than a delegate protocol so the test seam stays at exactly one
/// protocol (`ABPlaybackTarget` itself).
enum ABTargetEvent: Sendable, Equatable {
    case itemStatusChanged(ABItemStatus)
    case playbackStalled
    case playedToEnd
    case timeControlStatusChanged(ABTimeControlStatus)
    /// Carries provenance alongside classification — internal seam, not
    /// subject to the additive-only policy that scopes `ABPlayerEvent`.
    case failed(ABPlayerFailure)
    /// `isPlaybackLikelyToKeepUp`/`isPlaybackBufferEmpty` changed.
    case bufferStateChanged
    /// `AVPlayerItem.duration` KVO fired — `ABPlayer` decides whether the
    /// new value is finite/broadcast-worthy.
    case durationChanged
    case presentationSizeChanged(CGSize)
}

enum ABPrerollResult: Sendable, Equatable {
    case success
    case timedOut
    case failed
    case cancelled
}

/// The `AVPlayer` external-playback (AirPlay) knobs, bundled so
/// `applyExternalPlayback(_:)` has a single argument to apply at player
/// creation and on every subsequent configuration change.
struct ABExternalPlaybackSettings: Equatable {
    var allowsExternalPlayback: Bool
    var usesExternalPlaybackWhileExternalScreenIsActive: Bool
    var externalPlaybackVideoGravity: AVLayerVideoGravity
}

/// The one seam between `ABPlayer` and real `AVFoundation` calls. Kept
/// `internal` — consumers reach real playback through `ABPlayer`'s public
/// surface, never through this protocol (`@testable import` is how tests
/// reach it).
///
/// Expanded slightly beyond the design doc's literal method list
/// (`avPlayer`/`avPlayerItem` accessors, `seek`/`setMuted`/`isPlaying`/
/// `currentTime`/`duration`, and the `onEvent` callback) because
/// `ABPlayer`'s public API needs a uniform way to reach these regardless of
/// whether the backing target is the real `AVFoundation` one or a test
/// fake — without that, `ABPlayer.avPlayer` couldn't be implemented against
/// the protocol at all.
@MainActor
protocol ABPlaybackTarget: AnyObject {
    var avPlayer: AVPlayer? { get }
    var avPlayerItem: AVPlayerItem? { get }
    var isPlaying: Bool { get }
    var currentTime: CMTime { get }
    var duration: CMTime? { get }
    var bufferedUntil: CMTime? { get }
    /// Raw buffering signals — `ABPlayer` feeds these into
    /// `ABBufferingEvaluator` rather than deriving a buffering verdict here,
    /// so the judgment stays a pure, AVFoundation-free function.
    var isPlaybackLikelyToKeepUp: Bool { get }
    var isPlaybackBufferEmpty: Bool { get }
    var timeControlStatus: ABTimeControlStatus { get }
    /// `AVPlayer.reasonForWaitingToPlay == .noItemToPlay` — suppresses a
    /// buffering verdict that would otherwise fire while nothing is queued.
    var isWaitingWithNoItem: Bool { get }
    var presentationSize: CGSize { get }
    var isExternalPlaybackActive: Bool { get }

    /// Fired for events the target observes on its own (item status,
    /// stalls, end-of-playback, time control status, failures).
    var onEvent: ((ABTargetEvent) -> Void)? { get set }

    func makePlayer()
    func releasePlayer()
    func attachItem(_ source: ABMediaSource, tuning: ABPlaybackTuning, assetFactory: any ABAssetFactory)
    func detachItem()
    @discardableResult
    func applyTuning(_ tuning: ABPlaybackTuning) -> Bool
    func play()
    func pause()
    func setRate(_ rate: Float)
    func setMuted(_ muted: Bool)
    func setLooping(_ isLooping: Bool)
    func applyExternalPlayback(_ settings: ABExternalPlaybackSettings)
    /// Waits for `status == .readyToPlay` (or `prerollTimeout` to elapse),
    /// then `preroll(atRate:)`. Reports timeout, failure, and cancellation
    /// separately so `ABPlayer` can surface the correct public event.
    func preroll(rate: Float, timeout: TimeInterval) async -> ABPrerollResult
    func seekToStart() async
    func seek(to time: CMTime, tolerance: ABSeekTolerance) async -> CMTime
    func setPeriodicTimeObserver(
        interval: TimeInterval?,
        onTick: (@MainActor @Sendable (CMTime) -> Void)?
    )
}
