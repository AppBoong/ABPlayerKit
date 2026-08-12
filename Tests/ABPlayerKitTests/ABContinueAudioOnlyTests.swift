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
