import Foundation
import Testing
@testable import ABPlayerKit
@preconcurrency import AVFoundation
import UIKit

/// Engine-level coverage for `ABBackgroundPolicy.continueAudioOnly`: the
/// layer detaches but playback intent is never paused, the mandatory
/// `detachesLayerInBackground` generalization re-attaches on a mid-background
/// policy switch away from a detaching policy, and the policy behaves as a
/// safe `.pause`-like fallback when its preconditions aren't met.
@Suite("ABPlayer's .continueAudioOnly keeps playing and detaches only the layer", .timeLimit(.minutes(3)))
@MainActor
struct ABContinueAudioOnlyTests {
    private let source = ABMediaSource(url: URL(string: "https://example.com/a.mp4")!)

    @Test("Background entry under .continueAudioOnly detaches the layer without pausing")
    func backgroundEntryDetachesLayerOnly() async {
        let center = NotificationCenter()
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(
            configuration: ABPlayerConfiguration(backgroundPolicy: .continueAudioOnly),
            target: target,
            notificationCenter: center
        )
        player.set(source: source, grade: .current)
        player.play()

        center.post(name: UIApplication.willResignActiveNotification, object: nil)
        await Task.yield()
        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        await Task.yield()

        #expect(player.isPlaying)
        #expect(!player.isLayerAttachmentEnabled)
        #expect(!target.calls.contains(.pause))
    }

    /// Deliberately non-`async`, with no `Task.yield()` between the post and
    /// the expectations — the assertion *is* that the detach already happened
    /// by the time `post(name:)` returned.
    ///
    /// iOS keeps background audio alive only when `AVPlayerLayer.player` is
    /// cleared while the app is still handling the background notification.
    /// Deferring the handler by even one main-actor turn lets AVFoundation
    /// stop the still-attached player first; nothing is then playing, so no
    /// audio assertion is granted and the process is suspended seconds later.
    /// Every other test here yields before asserting, which measures the end
    /// state but not the timing — and so passes against a build that fails on
    /// a real device.
    @Test("The layer detaches inside the background notification's own dispatch, not a turn later")
    func backgroundEntryDetachesLayerSynchronously() {
        let center = NotificationCenter()
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(
            configuration: ABPlayerConfiguration(backgroundPolicy: .continueAudioOnly),
            target: target,
            notificationCenter: center
        )
        player.set(source: source, grade: .current)
        player.play()

        center.post(name: UIApplication.willResignActiveNotification, object: nil)
        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        #expect(!player.isLayerAttachmentEnabled)
        #expect(player.isPlaying)
        #expect(!target.calls.contains(.pause))
    }

    /// The companion to the test above, covering the other half of the causal
    /// chain. That one pins the engine's flag; what iOS actually reads is
    /// `AVPlayerLayer.player`, cleared by the bound view in response. Pinning
    /// only the flag would let someone defer the view's own reaction later and
    /// reintroduce the device failure with a fully green suite.
    @Test("The bound view's layer drops its player in the same dispatch, not just the engine's flag")
    func backgroundEntryClearsTheBoundLayerSynchronously() {
        let center = NotificationCenter()
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(
            configuration: ABPlayerConfiguration(backgroundPolicy: .continueAudioOnly),
            target: target,
            notificationCenter: center
        )
        let view = ABPlayerView()
        view.player = player
        player.set(source: source, grade: .current)
        player.play()

        let layer = view.layer as? AVPlayerLayer
        #expect(layer?.player != nil)

        center.post(name: UIApplication.willResignActiveNotification, object: nil)
        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        #expect(layer?.player == nil)
    }

    @Test("Regression: switching away from .continueAudioOnly mid-background re-attaches the layer")
    func switchingAwayFromContinueAudioOnlyMidBackgroundReattachesLayer() async {
        let center = NotificationCenter()
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(
            configuration: ABPlayerConfiguration(backgroundPolicy: .continueAudioOnly),
            target: target,
            notificationCenter: center
        )
        player.set(source: source, grade: .current)
        player.play()

        center.post(name: UIApplication.willResignActiveNotification, object: nil)
        await Task.yield()
        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        await Task.yield()
        #expect(!player.isLayerAttachmentEnabled)

        var configuration = player.configuration
        configuration.backgroundPolicy = .ignore
        player.configuration = configuration

        #expect(player.isLayerAttachmentEnabled)
    }

    @Test("A round trip under .continueAudioOnly with .unmanaged audio session resumes on foreground return, matching .pause's safety net")
    func unmanagedAudioSessionFallsBackToResumeOnForeground() async {
        let center = NotificationCenter()
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(
            configuration: ABPlayerConfiguration(
                backgroundPolicy: .continueAudioOnly,
                audioSessionPolicy: .unmanaged
            ),
            target: target,
            notificationCenter: center
        )
        player.set(source: source, grade: .current)
        player.play()

        center.post(name: UIApplication.willResignActiveNotification, object: nil)
        await Task.yield()
        // Simulate the system suspending playback anyway, since no
        // background-audio entitlement is present in this scenario.
        target.isPlaying = false
        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        await Task.yield()

        let playCallsBeforeForeground = target.calls.filter { $0 == .play }.count
        center.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        await Task.yield()

        #expect(target.calls.filter { $0 == .play }.count == playCallsBeforeForeground + 1)
    }

    @Test("Picture in Picture active suppresses .continueAudioOnly's own background side effects — nothing changes")
    func pictureInPictureActiveSuppressesBackgroundEntry() async {
        let center = NotificationCenter()
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(
            configuration: ABPlayerConfiguration(backgroundPolicy: .continueAudioOnly),
            target: target,
            notificationCenter: center
        )
        player.set(source: source, grade: .current)
        player.play()
        player.setPictureInPictureActive(true)

        center.post(name: UIApplication.willResignActiveNotification, object: nil)
        await Task.yield()
        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        await Task.yield()

        #expect(player.isPlaying)
        #expect(player.isLayerAttachmentEnabled)
        #expect(!target.calls.contains(.pause))
    }

    @Test("An explicit pause() during .continueAudioOnly backgrounding stays paused on foreground return")
    func explicitPauseDuringBackgroundStaysPausedOnForeground() async {
        let center = NotificationCenter()
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(
            configuration: ABPlayerConfiguration(backgroundPolicy: .continueAudioOnly),
            target: target,
            notificationCenter: center
        )
        player.set(source: source, grade: .current)
        player.play()

        center.post(name: UIApplication.willResignActiveNotification, object: nil)
        await Task.yield()
        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        await Task.yield()
        #expect(player.isPlaying)

        // The user pauses explicitly while backgrounded — e.g. the lock
        // screen or Now Playing Center's pause command, or Controls.
        player.pause()
        #expect(!player.isPlaying)

        let playCallsBeforeForeground = target.calls.filter { $0 == .play }.count
        center.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        await Task.yield()

        #expect(!player.isPlaying)
        #expect(target.calls.filter { $0 == .play }.count == playCallsBeforeForeground)
    }

    @Test("Control: .pause policy's own background pause still resumes on foreground return")
    func pausePolicyOwnPauseStillResumesOnForeground() async {
        let center = NotificationCenter()
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(
            configuration: ABPlayerConfiguration(backgroundPolicy: .pause),
            target: target,
            notificationCenter: center
        )
        player.set(source: source, grade: .current)
        player.play()

        center.post(name: UIApplication.willResignActiveNotification, object: nil)
        await Task.yield()
        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        await Task.yield()
        // The policy itself paused this — via `target.pause()`, not the
        // public `pause()` — so the capture that drives resume-on-foreground
        // must survive untouched.
        #expect(!player.isPlaying)

        let playCallsBeforeForeground = target.calls.filter { $0 == .play }.count
        center.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        await Task.yield()

        #expect(player.isPlaying)
        #expect(target.calls.filter { $0 == .play }.count == playCallsBeforeForeground + 1)
    }

    @Test("Recovery: activating Picture in Picture after a .continueAudioOnly background entry re-attaches the layer and resumes playback")
    func pictureInPictureActivationRepairsADetachedLayer() async {
        let center = NotificationCenter()
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(
            configuration: ABPlayerConfiguration(backgroundPolicy: .continueAudioOnly),
            target: target,
            notificationCenter: center
        )
        player.set(source: source, grade: .current)
        player.play()

        center.post(name: UIApplication.willResignActiveNotification, object: nil)
        await Task.yield()
        // Simulate the system having suspended playback anyway (no
        // background-audio entitlement present), leaving the layer
        // detached and playback stopped — exactly the state a Picture in
        // Picture activation race can land in. The explicit
        // `timeControlStatusChanged` emission mirrors the KVO hop a real
        // suspended `AVPlayer` would produce, so `player.isPlaying`
        // reflects the suspension the same way it would outside a test.
        target.isPlaying = false
        target.emit(.timeControlStatusChanged(.paused))
        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        await Task.yield()
        #expect(!player.isPlaying)
        #expect(!player.isLayerAttachmentEnabled)

        let playCallsBeforeRepair = target.calls.filter { $0 == .play }.count
        player.setPictureInPictureActive(true)

        #expect(player.isLayerAttachmentEnabled)
        #expect(target.calls.filter { $0 == .play }.count == playCallsBeforeRepair + 1)
    }
}
