import Foundation
import Testing
@testable import ABPlayerKit
@preconcurrency import AVFoundation
import UIKit

private final class WeakReference<Object: AnyObject> {
    weak var value: Object?

    init(_ value: Object) {
        self.value = value
    }
}

@Suite("ABDefaultAssetFactory uses public AVFoundation API")
struct ABDefaultAssetFactoryTests {
    @Test("Custom headers remain stored on the source while core asset creation preserves the URL")
    func headersAreDeferredToCacheTarget() {
        let source = ABMediaSource(
            url: URL(string: "https://example.com/video.mp4")!,
            httpHeaders: ["Authorization": "Bearer token"]
        )

        let asset = ABDefaultAssetFactory().makeAsset(for: source)

        #expect(source.httpHeaders == ["Authorization": "Bearer token"])
        #expect(asset.url == source.url)
    }
}

@Suite("Every release path calls detachItem exactly once")
@MainActor
struct ABPlayerReleasePathTests {
    private let source = ABMediaSource(url: URL(string: "https://example.com/a.mp4")!)

    private func makePlayer() -> (ABPlayer, ABFakePlaybackTarget) {
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(
            configuration: ABPlayerConfiguration(backgroundPolicy: .ignore),
            target: target
        )
        return (player, target)
    }

    @Test("Releasing from .preloaded detaches exactly once")
    func releaseFromPreloaded() {
        let (player, target) = makePlayer()
        player.set(source: source, grade: .preloaded)
        player.release()
        #expect(target.detachCount() == 1)
        #expect(target.calls.contains(.releasePlayer))
    }

    @Test("Releasing from .current detaches exactly once")
    func releaseFromCurrent() {
        let (player, target) = makePlayer()
        player.set(source: source, grade: .current)
        player.release()
        #expect(target.detachCount() == 1)
        #expect(target.calls.contains(.releasePlayer))
    }

    @Test("Releasing from .instanceOnly never detaches (no item was held)")
    func releaseFromInstanceOnly() {
        let (player, target) = makePlayer()
        player.set(source: nil, grade: .instanceOnly)
        player.release()
        #expect(target.detachCount() == 0)
        #expect(target.calls.contains(.releasePlayer))
    }

    @Test("Releasing an already-released player is a true no-op")
    func releaseFromReleasedIsNoop() {
        let (player, target) = makePlayer()
        player.release()
        #expect(target.calls.isEmpty)
    }

    @Test("Calling release() twice from .current only detaches once")
    func doubleReleaseDoesNotDoubleDetach() {
        let (player, target) = makePlayer()
        player.set(source: source, grade: .current)
        player.release()
        player.release()
        #expect(target.detachCount() == 1)
    }

    @Test("Demoting from .current to .instanceOnly detaches exactly once")
    func demoteToInstanceOnly() {
        let (player, target) = makePlayer()
        player.set(source: source, grade: .current)
        player.set(source: source, grade: .instanceOnly)
        #expect(target.detachCount() == 1)
    }

    @Test("Changing source while staying .preloaded never detaches (attachItem replaces in place)")
    func sourceSwapWhilePreloaded() {
        let (player, target) = makePlayer()
        let otherSource = ABMediaSource(url: URL(string: "https://example.com/b.mp4")!)
        player.set(source: source, grade: .preloaded)
        player.set(source: otherSource, grade: .preloaded)
        #expect(target.detachCount() == 0)
        #expect(target.calls.contains(.attachItem(otherSource, .conservativePreload)))
    }
}

@Suite("ABPlayer grade transitions broadcast the expected events")
@MainActor
struct ABPlayerEventBroadcastTests {
    private let source = ABMediaSource(url: URL(string: "https://example.com/a.mp4")!)

    @Test("Promoting to .current applies tuning and reports the grade change")
    func promotionBroadcastsEvents() {
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore), target: target)

        var events: [ABPlayerEvent] = []
        let token = player.addObserver { events.append($0) }
        defer { token.cancel() }

        player.set(source: source, grade: .current)

        #expect(events.contains(.gradeChanged(from: .released, to: .current)))
        #expect(events.contains(.sourceChanged(source)))
        #expect(events.contains(.tuningApplied(.current, .displayCapped)))
    }

    @Test("Cancelling preload stops the readiness wait and emits once")
    func cancelPreloadStopsWait() async {
        let target = ABFakePlaybackTarget()
        target.waitsForPrerollCancellation = true
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore), target: target)
        var events: [ABPlayerEvent] = []
        let token = player.addObserver { events.append($0) }
        defer { token.cancel() }

        player.set(source: source, grade: .preloaded)
        while !target.calls.contains(.preroll(rate: 1.0)) {
            await Task.yield()
        }

        player.cancelPreload()
        while !target.prerollWasCancelled {
            await Task.yield()
        }
        player.cancelPreload()

        #expect(events.filter { $0 == .preloadCancelled }.count == 1)
    }

    @Test("Preroll timeout updates lastError and emits failure")
    func prerollTimeoutEmitsFailure() async {
        let target = ABFakePlaybackTarget()
        target.prerollResult = .timedOut
        let timeout: TimeInterval = 0.25
        let configuration = ABPlayerConfiguration(prerollTimeout: timeout, backgroundPolicy: .ignore)
        let player = ABPlayer(configuration: configuration, target: target)
        var events: [ABPlayerEvent] = []
        let token = player.addObserver { events.append($0) }
        defer { token.cancel() }

        player.set(source: source, grade: .preloaded)
        while player.lastError == nil {
            await Task.yield()
        }

        let expectedError = ABPlayerError.prerollTimedOut(after: timeout)
        #expect(player.lastError == expectedError)
        #expect(events.contains(.failed(expectedError)))
        #expect(events.contains(.prerollCompleted(success: false)))
    }

    @Test("Preroll failure updates lastError and emits failure")
    func prerollFailureEmitsFailure() async {
        let target = ABFakePlaybackTarget()
        target.prerollResult = .failed
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore), target: target)
        var events: [ABPlayerEvent] = []
        let token = player.addObserver { events.append($0) }
        defer { token.cancel() }

        player.set(source: source, grade: .preloaded)
        while player.lastError == nil {
            await Task.yield()
        }

        #expect(player.lastError == .prerollFailed)
        #expect(events.contains(.failed(.prerollFailed)))
        #expect(events.contains(.prerollCompleted(success: false)))
    }

    @Test("Release cancels readiness waiting without retaining the item")
    func releaseDoesNotRetainItem() async {
        let configuration = ABPlayerConfiguration(prerollTimeout: 10, backgroundPolicy: .ignore)
        let player = ABPlayer(configuration: configuration)
        let pendingSource = ABMediaSource(url: URL(fileURLWithPath: "/private/tmp/abplayerkit-pending.mp4"))

        player.set(source: pendingSource, grade: .preloaded)
        let releasedItem = WeakReference(player.avPlayerItem!)
        #expect(releasedItem.value != nil)

        player.release()
        for _ in 0..<20 where releasedItem.value != nil {
            await Task.yield()
        }
        if releasedItem.value != nil {
            try? await Task.sleep(for: .milliseconds(100))
        }

        #expect(releasedItem.value == nil)
    }

    @Test("Requesting a held grade with no source clamps to .instanceOnly")
    func illegalCombinationClamps() {
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore), target: target)

        var events: [ABPlayerEvent] = []
        let token = player.addObserver { events.append($0) }
        defer { token.cancel() }

        player.set(source: nil, grade: .current)

        #expect(player.grade == .instanceOnly)
        #expect(events.contains(.invalidGradeForSource(requested: .current)))
    }

    @Test("play()/pause() outside .current are rejected, not silently dropped")
    func playbackRejectedOutsideCurrent() {
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore), target: target)

        var events: [ABPlayerEvent] = []
        let token = player.addObserver { events.append($0) }
        defer { token.cancel() }

        player.play()

        #expect(events.contains(.playbackRejected))
        #expect(!target.calls.contains(.play))
    }

    @Test("Mute survives attaching and swapping sources")
    func muteSurvivesSourceSwap() {
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore), target: target)
        let otherSource = ABMediaSource(url: URL(string: "https://example.com/b.mp4")!)

        player.setMuted(true)
        player.set(source: source, grade: .current)
        player.set(source: otherSource, grade: .current)

        #expect(player.configuration.isMuted)
        #expect(target.calls.filter { $0 == .setMuted(true) }.count == 3)
        #expect(!target.calls.contains(.setMuted(false)))
    }

    @Test("Configuration does not report tuning when no item exists")
    func configurationDoesNotReportUnappliedTuning() {
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore), target: target)
        var events: [ABPlayerEvent] = []
        let token = player.addObserver { events.append($0) }
        defer { token.cancel() }

        player.set(source: source, grade: .instanceOnly)
        player.configuration.currentTuning = .unrestricted

        #expect(!events.contains { event in
            if case .tuningApplied = event { return true }
            return false
        })
    }

    @Test("Changing background policy installs and removes observation")
    func backgroundPolicyReconcilesObservation() async {
        let center = NotificationCenter()
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(
            configuration: ABPlayerConfiguration(backgroundPolicy: .ignore),
            target: target,
            notificationCenter: center
        )
        player.set(source: source, grade: .current)
        player.play()

        player.configuration.backgroundPolicy = .pause
        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        await Task.yield()
        let pauseCount = target.calls.filter { $0 == .pause }.count
        #expect(pauseCount == 1)

        player.configuration.backgroundPolicy = .ignore
        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        await Task.yield()
        #expect(target.calls.filter { $0 == .pause }.count == pauseCount)
    }

    @Test("Background demotion reports the background policy detach reason")
    func backgroundDemotionReportsPolicyReason() async {
        let center = NotificationCenter()
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(
            configuration: ABPlayerConfiguration(backgroundPolicy: .demoteToInstance),
            target: target,
            notificationCenter: center
        )
        var events: [ABPlayerEvent] = []
        let token = player.addObserver { events.append($0) }
        defer { token.cancel() }
        player.set(source: source, grade: .current)

        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        while !events.contains(.itemDetached(reason: .backgroundPolicy)) {
            await Task.yield()
        }

        #expect(player.grade == .instanceOnly)
        #expect(events.contains(.itemDetached(reason: .backgroundPolicy)))
    }
}

@Suite("ABPlayerView follows player lifecycle")
@MainActor
struct ABPlayerViewLifecycleTests {
    private let source = ABMediaSource(url: URL(string: "https://example.com/a.mp4")!)

    @Test("Assigning the view before promotion rebinds the created player")
    func rebindsAfterGradeChange() {
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore), target: target)
        let view = ABPlayerView()
        view.player = player

        #expect((view.layer as? AVPlayerLayer)?.player == nil)
        player.set(source: source, grade: .current)

        #expect((view.layer as? AVPlayerLayer)?.player === target.avPlayer)

        player.release()
        #expect((view.layer as? AVPlayerLayer)?.player == nil)
    }

    @Test("Direct video gravity survives a grade transition")
    func directVideoGravitySurvivesGradeTransition() {
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore), target: target)
        let view = ABPlayerView()
        view.player = player
        view.videoGravity = .resizeAspect

        player.set(source: source, grade: .current)

        #expect(view.videoGravity == .resizeAspect)
    }

    @Test("pauseAndDetachLayer detaches in background and reattaches in foreground")
    func backgroundPolicyDetachesAndReattachesLayer() async {
        let center = NotificationCenter()
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(
            configuration: ABPlayerConfiguration(backgroundPolicy: .pauseAndDetachLayer),
            target: target,
            notificationCenter: center
        )
        let view = ABPlayerView()
        view.player = player
        player.set(source: source, grade: .current)
        player.play()
        #expect((view.layer as? AVPlayerLayer)?.player === target.avPlayer)

        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        while (view.layer as? AVPlayerLayer)?.player != nil {
            await Task.yield()
        }
        #expect((view.layer as? AVPlayerLayer)?.player == nil)

        center.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        while (view.layer as? AVPlayerLayer)?.player == nil {
            await Task.yield()
        }
        #expect((view.layer as? AVPlayerLayer)?.player === target.avPlayer)
        #expect(target.calls.contains(.play))
    }
}

@Suite("ABObservationToken lifecycle")
@MainActor
struct ABObservationTokenLifecycleTests {
    private let source = ABMediaSource(url: URL(string: "https://example.com/a.mp4")!)

    @Test("Cancelling a token stops further delivery")
    func cancelStopsDelivery() {
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore), target: target)

        var receivedCount = 0
        let token = player.addObserver { _ in receivedCount += 1 }

        player.set(source: source, grade: .instanceOnly)
        let countAfterFirstEvent = receivedCount
        #expect(countAfterFirstEvent > 0)

        token.cancel()
        player.set(source: source, grade: .preloaded)

        #expect(receivedCount == countAfterFirstEvent)
    }

    @Test("Cancelling a layer observer removes it synchronously")
    func layerObserverCancellationIsSynchronous() async {
        let registry = ABLayerAttachmentObserverRegistry()
        var receivedCount = 0
        let token = registry.add { _ in receivedCount += 1 }

        await Task.detached {
            token.cancel()
        }.value
        registry.broadcast(true)

        #expect(receivedCount == 0)
    }

    @Test("Letting a token deinit auto-unsubscribes")
    func deinitAutoUnsubscribes() {
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore), target: target)

        var receivedCount = 0
        do {
            let token = player.addObserver { _ in receivedCount += 1 }
            player.set(source: source, grade: .instanceOnly)
            _ = token // keep alive until end of scope
        }
        // `token` has gone out of scope and deinitialized here.

        let countAfterScopeExit = receivedCount
        player.set(source: source, grade: .preloaded)

        #expect(receivedCount == countAfterScopeExit)
    }

    @Test("Multiple observers are all notified independently")
    func multipleObserversAreIndependent() {
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore), target: target)

        var firstCount = 0
        var secondCount = 0
        let firstToken = player.addObserver { _ in firstCount += 1 }
        let secondToken = player.addObserver { _ in secondCount += 1 }

        // released -> instanceOnly with a source change broadcasts 2 events
        // (.gradeChanged + .sourceChanged).
        player.set(source: source, grade: .instanceOnly)
        let countAfterFirstSet = firstCount
        #expect(countAfterFirstSet == secondCount)
        firstToken.cancel()

        // instanceOnly -> preloaded (no further source change) broadcasts
        // .tuningApplied + .gradeChanged.
        player.set(source: source, grade: .preloaded)

        #expect(firstCount == countAfterFirstSet, "cancelled observer must not receive further events")
        #expect(secondCount > countAfterFirstSet, "still-subscribed observer must receive the second batch")
        secondToken.cancel()
    }

    @Test("Letting a token deinit off-main does not trap")
    func deinitOffMainDoesNotTrap() async {
        await Task.detached {
            var token: ABObservationToken? = await MainActor.run {
                let registry = ABObserverRegistry()
                return registry.add { _, _ in }
            }
            #expect(token != nil)
            token = nil
        }.value
    }
}

/// Regression coverage for the deinit-vs-`NSInternalInconsistencyException`
/// fix: dropping a still-attached player/target without calling `release()`
/// must not crash, and must actually clean up (not merely "not crash").
@Suite("Dropping a player/target without release() cleans up deterministically")
@MainActor
struct ABPlayerDeinitCleanupTests {
    // A local, non-existent file URL — unlike an `https://` source, this
    // fails immediately with no real network round trip, so it does not
    // keep `AVPlayer`/`AVPlayerItem` alive via in-flight loading and skew
    // the deinit-timing assertions below (matches the fixture used by
    // "Release cancels readiness waiting without retaining the item").
    private let source = ABMediaSource(url: URL(fileURLWithPath: "/private/tmp/abplayerkit-deinit-fixture.mp4"))

    @Test("ABAVPlaybackTarget deinit removes the periodic time observer")
    func targetDeinitRemovesPeriodicTimeObserver() async {
        var target: ABAVPlaybackTarget? = ABAVPlaybackTarget()
        target?.makePlayer()
        target?.attachItem(source, tuning: .unrestricted, assetFactory: ABDefaultAssetFactory())
        target?.setPeriodicTimeObserver(interval: 0.1) { _ in }
        let weakPlayer = WeakReference(target!.avPlayer!)

        // Drop the only strong reference without calling `releasePlayer()`.
        target = nil

        // -Onone can extend a local's lifetime past its last use, so poll
        // deterministically (per existing convention in this file) instead
        // of asserting immediately after nil-ing the reference.
        for _ in 0..<20 where weakPlayer.value != nil {
            await Task.yield()
        }
        if weakPlayer.value != nil {
            try? await Task.sleep(for: .milliseconds(100))
        }

        // If the periodic time observer were still registered, `AVPlayer`
        // would raise `NSInternalInconsistencyException` on dealloc instead
        // of reaching this line.
        #expect(weakPlayer.value == nil)
    }

    @Test("ABPlayer deinit cancels an outstanding preroll task")
    func playerDeinitCancelsPrerollTask() async {
        let target = ABFakePlaybackTarget()
        target.waitsForPrerollCancellation = true
        do {
            let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore), target: target)
            player.set(source: source, grade: .preloaded)
            while !target.calls.contains(.preroll(rate: 1.0)) {
                await Task.yield()
            }
            // `player` goes out of scope here without `release()`, while the
            // preroll task is still awaiting cancellation.
        }
        while !target.prerollWasCancelled {
            await Task.yield()
        }
        #expect(target.prerollWasCancelled)
    }
}
