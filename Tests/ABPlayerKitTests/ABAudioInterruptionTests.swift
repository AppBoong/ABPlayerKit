import Foundation
import Testing
@testable import ABPlayerKit
@preconcurrency import AVFoundation

/// Coverage for round3 Phase4 WP10: `ABPlayer` reacting to
/// `AVAudioSession.interruptionNotification`/`routeChangeNotification`.
/// Never touches the real, process-global `AVAudioSession` — a private
/// `NotificationCenter` is injected (the same test seam
/// `ABApplicationStateObserver` coverage already uses) and fed fabricated
/// `userInfo` dictionaries with the real notification names/keys, per
/// WP10.5.
@Suite("ABPlayer reacts to AVAudioSession interruption/route-change notifications", .timeLimit(.minutes(1)))
@MainActor
struct ABAudioInterruptionTests {
    private let source = ABMediaSource(url: URL(string: "https://example.com/a.mp4")!)

    private func makePlayer(
        interruptionPolicy: ABInterruptionPolicy = .pauseAndResume,
        pausesOnRouteChangeDeviceUnavailable: Bool = true
    ) -> (ABPlayer, ABFakePlaybackTarget, NotificationCenter) {
        let target = ABFakePlaybackTarget()
        let center = NotificationCenter()
        let configuration = ABPlayerConfiguration(
            backgroundPolicy: .ignore,
            interruptionPolicy: interruptionPolicy,
            pausesOnRouteChangeDeviceUnavailable: pausesOnRouteChangeDeviceUnavailable
        )
        let player = ABPlayer(configuration: configuration, target: target, notificationCenter: center)
        return (player, target, center)
    }

    private func postInterruption(
        _ center: NotificationCenter,
        type: AVAudioSession.InterruptionType,
        options: AVAudioSession.InterruptionOptions = []
    ) {
        var userInfo: [AnyHashable: Any] = [AVAudioSessionInterruptionTypeKey: type.rawValue]
        if type == .ended {
            userInfo[AVAudioSessionInterruptionOptionKey] = options.rawValue
        }
        center.post(name: AVAudioSession.interruptionNotification, object: nil, userInfo: userInfo)
    }

    private func postRouteChange(_ center: NotificationCenter, reason: AVAudioSession.RouteChangeReason) {
        let userInfo: [AnyHashable: Any] = [AVAudioSessionRouteChangeReasonKey: reason.rawValue]
        center.post(name: AVAudioSession.routeChangeNotification, object: nil, userInfo: userInfo)
    }

    @Test(".ignore interruption policy + route flag disabled installs no observer at all")
    func ignorePolicyDoesNothing() async throws {
        let (player, target, center) = makePlayer(
            interruptionPolicy: .ignore,
            pausesOnRouteChangeDeviceUnavailable: false
        )
        player.set(source: source, grade: .current)
        player.play()

        postInterruption(center, type: .began)

        // No observer is installed when both `interruptionPolicy == .ignore`
        // and `pausesOnRouteChangeDeviceUnavailable == false` — this
        // notification has no subscriber, so the absence holds regardless
        // of timing (there's nothing pending to wait out).
        #expect(!target.calls.contains(.pause))
    }

    @Test("Interruption began pauses .current playback and broadcasts .audioInterruptionBegan")
    func interruptionBeganPauses() async throws {
        let (player, target, center) = makePlayer()
        player.set(source: source, grade: .current)
        player.play()
        var events: [ABPlayerEvent] = []
        let token = player.addObserver { events.append($0) }
        defer { token.cancel() }

        postInterruption(center, type: .began)

        try await waitUntil { target.calls.contains(.pause) }
        #expect(events.contains(.audioInterruptionBegan))
    }

    @Test("Interruption ended with .shouldResume resumes playback under .pauseAndResume")
    func interruptionEndedResumesWhenShouldResume() async throws {
        let (player, target, center) = makePlayer(interruptionPolicy: .pauseAndResume)
        player.set(source: source, grade: .current)
        player.play()
        postInterruption(center, type: .began)
        try await waitUntil { target.calls.contains(.pause) }
        let playCallsBeforeEnd = target.calls.filter { $0 == .play }.count

        var events: [ABPlayerEvent] = []
        let token = player.addObserver { events.append($0) }
        defer { token.cancel() }

        postInterruption(center, type: .ended, options: .shouldResume)

        try await waitUntil { events.contains(.audioInterruptionEnded(resumed: true)) }
        // `play()` was called again — the same path that reactivates the
        // audio session through `ABAudioSessionCoordinator` (round3 Phase3
        // WP2 M1), so resuming here composes with `audioSessionPolicy`.
        #expect(target.calls.filter { $0 == .play }.count == playCallsBeforeEnd + 1)
    }

    @Test("Interruption ended without .shouldResume does not resume")
    func interruptionEndedWithoutShouldResumeStaysPaused() async throws {
        let (player, target, center) = makePlayer(interruptionPolicy: .pauseAndResume)
        player.set(source: source, grade: .current)
        player.play()
        postInterruption(center, type: .began)
        try await waitUntil { target.calls.contains(.pause) }
        let playCallsBeforeEnd = target.calls.filter { $0 == .play }.count

        var events: [ABPlayerEvent] = []
        let token = player.addObserver { events.append($0) }
        defer { token.cancel() }

        postInterruption(center, type: .ended, options: [])

        try await waitUntil { events.contains(.audioInterruptionEnded(resumed: false)) }
        #expect(target.calls.filter { $0 == .play }.count == playCallsBeforeEnd)
    }

    @Test("Interruption ended under .ignore policy never resumes and broadcasts nothing")
    func interruptionEndedUnderIgnorePolicyDoesNothing() async throws {
        let (player, _, center) = makePlayer(
            interruptionPolicy: .ignore,
            pausesOnRouteChangeDeviceUnavailable: true
        )
        player.set(source: source, grade: .current)
        player.play()
        var events: [ABPlayerEvent] = []
        let token = player.addObserver { events.append($0) }
        defer { token.cancel() }

        postInterruption(center, type: .began)
        postInterruption(center, type: .ended, options: .shouldResume)

        // A route-change observer *is* installed (the flag is on), so give
        // the notification queue a turn, then assert the interruption path
        // specifically never engaged.
        for _ in 0..<10 { await Task.yield() }
        #expect(!events.contains(.audioInterruptionBegan))
        #expect(!events.contains { if case .audioInterruptionEnded = $0 { true } else { false } })
    }

    @Test("Route change to .oldDeviceUnavailable pauses .current playback and broadcasts")
    func routeChangeDeviceUnavailablePauses() async throws {
        let (player, target, center) = makePlayer()
        player.set(source: source, grade: .current)
        player.play()
        var events: [ABPlayerEvent] = []
        let token = player.addObserver { events.append($0) }
        defer { token.cancel() }

        postRouteChange(center, reason: .oldDeviceUnavailable)

        try await waitUntil { target.calls.contains(.pause) }
        #expect(events.contains(.audioRouteChangedDeviceUnavailable))
    }

    @Test("pausesOnRouteChangeDeviceUnavailable disabled skips the pause")
    func routeChangeFlagDisabledSkipsPause() async throws {
        let (player, target, center) = makePlayer(
            interruptionPolicy: .ignore,
            pausesOnRouteChangeDeviceUnavailable: false
        )
        player.set(source: source, grade: .current)
        player.play()

        postRouteChange(center, reason: .oldDeviceUnavailable)

        // No observer is installed here either — same "no subscriber"
        // argument as `ignorePolicyDoesNothing` above.
        #expect(!target.calls.contains(.pause))
    }

    @Test("Route change reasons other than .oldDeviceUnavailable are ignored")
    func otherRouteChangeReasonsIgnored() async throws {
        let (player, target, center) = makePlayer()
        player.set(source: source, grade: .current)
        player.play()

        postRouteChange(center, reason: .newDeviceAvailable)

        // The reason filter runs synchronously inside the NotificationCenter
        // callback, before any further `Task` is ever created, so this
        // absence holds regardless of how long the test waits.
        for _ in 0..<10 { await Task.yield() }
        #expect(!target.calls.contains(.pause))
    }
}
