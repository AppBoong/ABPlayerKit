import ABTestSupport
import Foundation
import Testing
@testable import ABPlayerKit
@preconcurrency import AVFoundation

/// Engine-level coverage for the observable mirrors and event surface,
/// driven through `ABFakePlaybackTarget` so buffering/duration/
/// presentation-size transitions are exercised without a real
/// `AVPlayerItem`.
@Suite("ABPlayer's new event surface and observable mirrors", .timeLimit(abScaledMinutes(3)))
@MainActor
struct ABObservabilityEventsTests {
    private let source = ABMediaSource(url: URL(string: "https://example.com/a.mp4")!)

    private func makePlayer() -> (ABPlayer, ABFakePlaybackTarget) {
        let target = ABFakePlaybackTarget()
        target.avPlayerItem = AVPlayerItem(url: URL(fileURLWithPath: "/private/tmp/abplayerkit-observability-fixture.mp4"))
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore), target: target)
        return (player, target)
    }

    @Test("play() synchronously flips isPlaying to true — no KVO round trip required")
    func playIsSynchronous() {
        let (player, _) = makePlayer()
        player.set(source: source, grade: .current)

        player.play()

        #expect(player.isPlaying)
    }

    @Test("pause() synchronously flips isPlaying to false")
    func pauseIsSynchronous() {
        let (player, _) = makePlayer()
        player.set(source: source, grade: .current)
        player.play()

        player.pause()

        #expect(!player.isPlaying)
    }

    @Test("bufferingChanged broadcasts only on an actual value change")
    func bufferingChangedBroadcastsOnlyOnChange() {
        let (player, target) = makePlayer()
        player.set(source: source, grade: .current)
        player.play()
        var events: [Bool] = []
        let token = player.addObserver { event in
            if case .bufferingChanged(let value) = event { events.append(value) }
        }
        defer { token.cancel() }

        target.timeControlStatus = .waitingToPlay
        target.emit(.timeControlStatusChanged(.waitingToPlay))
        // Re-emitting the same status must not re-broadcast.
        target.emit(.timeControlStatusChanged(.waitingToPlay))
        target.timeControlStatus = .playing
        target.emit(.timeControlStatusChanged(.playing))

        #expect(events == [true, false])
        #expect(!player.isBuffering)
    }

    @Test("isBuffering combined with isPlaying identifies a stalled-but-intending-to-play state")
    func isPlayingAndIsBufferingComposeForStallDetection() {
        let (player, target) = makePlayer()
        player.set(source: source, grade: .current)
        player.play()

        target.timeControlStatus = .waitingToPlay
        target.emit(.timeControlStatusChanged(.waitingToPlay))

        #expect(player.isPlaying)
        #expect(player.isBuffering)
    }

    @Test("durationAvailable broadcasts once per finite value, again after detach and re-attach")
    func durationAvailableBroadcastsOncePerItemLifecycle() {
        let (player, target) = makePlayer()
        player.set(source: source, grade: .current)
        var durations: [CMTime] = []
        let token = player.addObserver { event in
            if case .durationAvailable(let time) = event { durations.append(time) }
        }
        defer { token.cancel() }

        let finiteDuration = CMTime(seconds: 30, preferredTimescale: 600)
        target.duration = finiteDuration
        target.emit(.durationChanged)
        target.emit(.durationChanged)

        #expect(durations == [finiteDuration])

        player.release()
        target.avPlayerItem = AVPlayerItem(url: URL(fileURLWithPath: "/private/tmp/abplayerkit-observability-fixture-2.mp4"))
        player.set(source: source, grade: .current)
        target.duration = finiteDuration
        target.emit(.durationChanged)

        #expect(durations == [finiteDuration, finiteDuration])
    }

    @Test("itemAttached broadcasts before tuningApplied, from the same attach action")
    func itemAttachedPrecedesTuningApplied() {
        let (player, _) = makePlayer()
        var events: [ABPlayerEvent] = []
        let token = player.addObserver { events.append($0) }
        defer { token.cancel() }

        player.set(source: source, grade: .current)

        let attachedIndex = events.firstIndex(of: .itemAttached(source: source))
        let tuningIndex = events.firstIndex { if case .tuningApplied = $0 { true } else { false } }
        #expect(attachedIndex != nil && tuningIndex != nil)
        #expect(attachedIndex! < tuningIndex!)
    }

    @Test("callRejected broadcasts immediately after playbackRejected, identifying the call and grade")
    func callRejectedFollowsPlaybackRejected() {
        let (player, _) = makePlayer()
        var events: [ABPlayerEvent] = []
        let token = player.addObserver { events.append($0) }
        defer { token.cancel() }

        player.play()

        let rejectedIndex = events.firstIndex(of: .playbackRejected)
        let callRejectedIndex = events.firstIndex(of: .callRejected(.play, grade: .released))
        #expect(rejectedIndex != nil && callRejectedIndex != nil)
        #expect(rejectedIndex! < callRejectedIndex!)
    }

    @Test("mutedChanged broadcasts only when isMuted actually changes")
    func mutedChangedBroadcastsOnActualChange() {
        let (player, _) = makePlayer()
        player.set(source: source, grade: .current)
        var events: [ABPlayerEvent] = []
        let token = player.addObserver { events.append($0) }
        defer { token.cancel() }

        player.setMuted(true)
        player.setMuted(true)

        #expect(events.filter { $0 == .mutedChanged(true) }.count == 1)
    }

    @Test("stallEnded broadcasts once, only after an outstanding playbackStalled reaches .playing")
    func stallEndedBroadcastsOnceForOutstandingStall() {
        let (player, target) = makePlayer()
        player.set(source: source, grade: .current)
        player.play()
        var stallEndedCount = 0
        let token = player.addObserver { event in
            if event == .stallEnded { stallEndedCount += 1 }
        }
        defer { token.cancel() }

        target.emit(.playbackStalled)
        target.timeControlStatus = .playing
        target.emit(.timeControlStatusChanged(.playing))
        // A second `.playing` transition with no new stall must not re-fire.
        target.emit(.timeControlStatusChanged(.playing))

        #expect(stallEndedCount == 1)
    }

    @Test("presentationSizeChanged suppresses .zero and duplicate values")
    func presentationSizeChangedSuppressesZeroAndDuplicates() {
        let (player, target) = makePlayer()
        player.set(source: source, grade: .current)
        var sizes: [CGSize] = []
        let token = player.addObserver { event in
            if case .presentationSizeChanged(let size) = event { sizes.append(size) }
        }
        defer { token.cancel() }

        target.emit(.presentationSizeChanged(.zero))
        let size = CGSize(width: 1920, height: 1080)
        target.emit(.presentationSizeChanged(size))
        target.emit(.presentationSizeChanged(size))

        #expect(sizes == [size])
    }
}
