@preconcurrency import AVFoundation

/// Signals the concrete target reports back to `ABPlayer`, independent of
/// the commands `ABPlayer` issues *to* the target. Kept as a plain enum
/// rather than a delegate protocol so the test seam stays at exactly one
/// protocol (`ABPlaybackTarget` itself) per PLANNING.md §6.
enum ABTargetEvent: Sendable, Equatable {
    case itemStatusChanged(ABItemStatus)
    case playbackStalled
    case playedToEnd
    case timeControlStatusChanged(ABTimeControlStatus)
    case failed(ABPlayerError)
}

enum ABPrerollResult: Sendable, Equatable {
    case success
    case timedOut
    case failed
    case cancelled
}

/// The one seam between `ABPlayer` and real `AVFoundation` calls. Kept
/// `internal` — consumers reach real playback through `ABPlayer`'s public
/// surface, never through this protocol (`@testable import` is how tests
/// reach it, per DESIGN-ABPlayerKit.md §7).
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
    /// Waits for `status == .readyToPlay` (or `prerollTimeout` to elapse),
    /// then `preroll(atRate:)`. Reports timeout, failure, and cancellation
    /// separately so `ABPlayer` can surface the correct public event.
    func preroll(rate: Float, timeout: TimeInterval) async -> ABPrerollResult
    func seekToStart() async
    func seek(to time: CMTime, tolerance: ABSeekTolerance) async -> CMTime
}
