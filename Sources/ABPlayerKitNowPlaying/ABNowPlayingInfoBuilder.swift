/// A snapshot of the fields the builder needs from a live player, decoupled
/// from `ABPlayer`/`AVFoundation` so the builder stays a pure function.
struct ABNowPlayingPlayerSnapshot: Equatable {
    var currentTimeSeconds: Double
    /// `nil` when the item's duration isn't numeric (no item, or not yet
    /// known) — finiteness/positivity is still this builder's job to check.
    var durationSeconds: Double?
    var isPlaying: Bool
    var isBuffering: Bool
    var rate: Float
}

/// Everything `ABNowPlayingCenter` needs to publish, independent of
/// `MediaPlayer`'s dictionary shape — kept as a plain, comparable value so
/// the builder below is golden-testable without linking `MediaPlayer`.
struct ABNowPlayingInfo: Equatable {
    var title: String
    var artist: String?
    var albumTitle: String?
    /// `nil` unless finite and positive.
    var duration: Double?
    var elapsed: Double
    /// The rate to publish as currently playing — `0` while paused or
    /// buffering, so a stalled stream's lock-screen scrubber doesn't keep
    /// advancing.
    var rate: Double
    var defaultRate: Double
    var isLiveStream: Bool
    var mediaType: ABNowPlayingMetadata.MediaType
    var externalContentIdentifier: String?
}

/// Pure `(metadata, snapshot) -> ABNowPlayingInfo` reduction — the actual
/// `MediaPlayer` dictionary shape lives in `ABNowPlayingSurface.swift`, the
/// one file in this target allowed to import `MediaPlayer`.
struct ABNowPlayingInfoBuilder {
    func info(metadata: ABNowPlayingMetadata, snapshot: ABNowPlayingPlayerSnapshot) -> ABNowPlayingInfo {
        let duration: Double? = {
            guard let seconds = snapshot.durationSeconds, seconds.isFinite, seconds > 0 else { return nil }
            return seconds
        }()
        let publishedRate = (snapshot.isPlaying && !snapshot.isBuffering) ? Double(snapshot.rate) : 0

        return ABNowPlayingInfo(
            title: metadata.title,
            artist: metadata.artist,
            albumTitle: metadata.albumTitle,
            duration: duration,
            elapsed: snapshot.currentTimeSeconds,
            rate: publishedRate,
            defaultRate: Double(snapshot.rate),
            isLiveStream: metadata.isLiveStream || duration == nil,
            mediaType: metadata.mediaType,
            externalContentIdentifier: metadata.externalContentIdentifier
        )
    }
}
