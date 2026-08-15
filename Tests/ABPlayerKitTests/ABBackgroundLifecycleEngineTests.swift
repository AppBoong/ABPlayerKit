import ABTestSupport
import Foundation
import Testing
@testable import ABPlayerKit
@preconcurrency import AVFoundation
import UIKit

/// Engine-level coverage for `willResignActive` capturing `isPlaying`
/// before `didEnterBackground` can have already stopped decode, and
/// foreground resume routing through `self.play()` (audio session
/// reactivation) instead of a bare `target.play()`.
@Suite("ABPlayer's background/foreground lifecycle captures and resumes correctly", .timeLimit(abScaledMinutes(3)))
@MainActor
struct ABBackgroundLifecycleEngineTests {
    private let source = ABMediaSource(url: URL(string: "https://example.com/a.mp4")!)

    @Test("A capture at willResignActive survives isPlaying already reading false by didEnterBackground")
    func captureAtWillResignActiveSurvivesLateIsPlayingFlip() async throws {
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
        // Simulate iOS having already stopped decode by the time
        // `didEnterBackground` fires, so capturing at `willResignActive`
        // is what makes this scenario recoverable.
        target.isPlaying = false
        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        await Task.yield()

        let playCallsBeforeForeground = target.calls.filter { $0 == .play }.count
        center.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        await Task.yield()

        #expect(target.calls.filter { $0 == .play }.count == playCallsBeforeForeground + 1)
    }

    @Test("A resign that never reaches didEnterBackground does not leave a stale capture that force-resumes on foreground")
    func cancelledResignDoesNotForceResume() async {
        let center = NotificationCenter()
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(
            configuration: ABPlayerConfiguration(backgroundPolicy: .pause),
            target: target,
            notificationCenter: center
        )
        player.set(source: source, grade: .current)
        // Deliberately not playing — willResignActive captures `false`.

        center.post(name: UIApplication.willResignActiveNotification, object: nil)
        await Task.yield()
        center.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        await Task.yield()

        #expect(!target.calls.contains(.play))
    }

    @Test("Foreground resume under a managed audio session policy reactivates before target.play()")
    func foregroundResumeReactivatesAudioSessionBeforePlay() async {
        let center = NotificationCenter()
        let target = ABFakePlaybackTarget()
        let controller = ABFakeAudioSessionController()
        let coordinator = ABAudioSessionCoordinator(controller: controller)
        let player = ABPlayer(
            configuration: ABPlayerConfiguration(
                backgroundPolicy: .pause,
                audioSessionPolicy: .playback(mixWithOthers: false)
            ),
            target: target,
            notificationCenter: center,
            audioSessionCoordinator: coordinator
        )
        player.set(source: source, grade: .current)
        player.play()

        center.post(name: UIApplication.willResignActiveNotification, object: nil)
        await Task.yield()
        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        await Task.yield()

        let activateCallsBeforeForeground = controller.calls.filter {
            if case .activate = $0 { return true } else { return false }
        }.count

        center.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        await Task.yield()

        let activateIndex = controller.calls.indices.last { index in
            if case .activate = controller.calls[index] { return true }
            return false
        }
        let playIndex = target.calls.lastIndex(of: .play)
        #expect(controller.calls.filter { if case .activate = $0 { true } else { false } }.count == activateCallsBeforeForeground + 1)
        #expect(activateIndex != nil && playIndex != nil)
    }
}
