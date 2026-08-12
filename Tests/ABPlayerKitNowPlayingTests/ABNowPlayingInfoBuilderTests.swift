import Testing
@testable import ABPlayerKitNowPlaying

/// Golden coverage for `ABNowPlayingInfoBuilder` — pure `(metadata,
/// snapshot) -> ABNowPlayingInfo`, no `MediaPlayer`/`AVFoundation` needed.
@Suite("ABNowPlayingInfoBuilder reduces metadata and a player snapshot to publishable info")
struct ABNowPlayingInfoBuilderTests {
    private let builder = ABNowPlayingInfoBuilder()
    private let metadata = ABNowPlayingMetadata(title: "Title", artist: "Artist")

    @Test("A finite duration is published and does not mark the item live")
    func finiteDurationPublishes() {
        let info = builder.info(
            metadata: metadata,
            snapshot: ABNowPlayingPlayerSnapshot(
                currentTimeSeconds: 10,
                durationSeconds: 120,
                isPlaying: true,
                isBuffering: false,
                rate: 1
            )
        )

        #expect(info.duration == 120)
        #expect(!info.isLiveStream)
    }

    @Test("An unknown/non-finite duration omits the duration and marks the item live")
    func nonFiniteDurationOmitsAndMarksLive() {
        let info = builder.info(
            metadata: metadata,
            snapshot: ABNowPlayingPlayerSnapshot(
                currentTimeSeconds: 10,
                durationSeconds: nil,
                isPlaying: true,
                isBuffering: false,
                rate: 1
            )
        )

        #expect(info.duration == nil)
        #expect(info.isLiveStream)
    }

    @Test("metadata.isLiveStream forces the live flag even with a finite duration")
    func metadataLiveStreamOverridesFiniteDuration() {
        var liveMetadata = metadata
        liveMetadata.isLiveStream = true

        let info = builder.info(
            metadata: liveMetadata,
            snapshot: ABNowPlayingPlayerSnapshot(
                currentTimeSeconds: 10,
                durationSeconds: 120,
                isPlaying: true,
                isBuffering: false,
                rate: 1
            )
        )

        #expect(info.isLiveStream)
    }

    @Test("A stalled (buffering) stream publishes rate 0 even while intending to play")
    func bufferingPublishesZeroRate() {
        let info = builder.info(
            metadata: metadata,
            snapshot: ABNowPlayingPlayerSnapshot(
                currentTimeSeconds: 10,
                durationSeconds: 120,
                isPlaying: true,
                isBuffering: true,
                rate: 1
            )
        )

        #expect(info.rate == 0)
        #expect(info.defaultRate == 1)
    }

    @Test("A paused stream publishes rate 0")
    func pausedPublishesZeroRate() {
        let info = builder.info(
            metadata: metadata,
            snapshot: ABNowPlayingPlayerSnapshot(
                currentTimeSeconds: 10,
                durationSeconds: 120,
                isPlaying: false,
                isBuffering: false,
                rate: 1.5
            )
        )

        #expect(info.rate == 0)
        #expect(info.defaultRate == 1.5)
    }

    @Test("A playing, non-buffering stream publishes its actual rate")
    func playingPublishesActualRate() {
        let info = builder.info(
            metadata: metadata,
            snapshot: ABNowPlayingPlayerSnapshot(
                currentTimeSeconds: 10,
                durationSeconds: 120,
                isPlaying: true,
                isBuffering: false,
                rate: 1.5
            )
        )

        #expect(info.rate == 1.5)
    }

    @Test("Zero and negative durations are treated as unknown, the same as non-finite")
    func nonPositiveDurationIsTreatedAsUnknown() {
        let zero = builder.info(
            metadata: metadata,
            snapshot: ABNowPlayingPlayerSnapshot(currentTimeSeconds: 0, durationSeconds: 0, isPlaying: false, isBuffering: false, rate: 1)
        )
        let negative = builder.info(
            metadata: metadata,
            snapshot: ABNowPlayingPlayerSnapshot(currentTimeSeconds: 0, durationSeconds: -1, isPlaying: false, isBuffering: false, rate: 1)
        )

        #expect(zero.duration == nil)
        #expect(negative.duration == nil)
    }

    @Test("Title/artist/albumTitle/mediaType/externalContentIdentifier pass through unchanged")
    func passthroughFieldsAreCarriedVerbatim() {
        let fullMetadata = ABNowPlayingMetadata(
            title: "T",
            artist: "A",
            albumTitle: "Album",
            mediaType: .audio,
            externalContentIdentifier: "id-1"
        )

        let info = builder.info(
            metadata: fullMetadata,
            snapshot: ABNowPlayingPlayerSnapshot(currentTimeSeconds: 5, durationSeconds: 10, isPlaying: false, isBuffering: false, rate: 1)
        )

        #expect(info.title == "T")
        #expect(info.artist == "A")
        #expect(info.albumTitle == "Album")
        #expect(info.mediaType == .audio)
        #expect(info.externalContentIdentifier == "id-1")
        #expect(info.elapsed == 5)
    }
}
