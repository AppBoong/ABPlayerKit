import ABTestSupport
import Foundation
import Testing
@testable import ABPlayerKit
@preconcurrency import AVFoundation

/// Coverage for `lastFailure`/`lastDiagnostic`/`lastError` resetting on
/// every attach, source change, detach, and release, instead of leaving a
/// stale failure set forever.
@Suite("ABPlayer resets failure/diagnostic state on attach/source-change/detach/release", .timeLimit(abScaledMinutes(3)))
@MainActor
struct ABFailureLifecycleTests {
    private let source = ABMediaSource(url: URL(string: "https://example.com/a.mp4")!)
    private let otherSource = ABMediaSource(url: URL(string: "https://example.com/b.mp4")!)

    private func makePlayer() -> (ABPlayer, ABFakePlaybackTarget) {
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore), target: target)
        return (player, target)
    }

    @Test("A terminal failure is cleared by attaching a new source")
    func terminalFailureClearedByNewAttach() {
        let (player, target) = makePlayer()
        player.set(source: source, grade: .current)
        target.emit(.failed(.init(kind: .itemFailed(description: "boom"))))
        #expect(player.lastError != nil)

        player.set(source: otherSource, grade: .current)

        #expect(player.lastError == nil)
        #expect(player.lastFailure == nil)
    }

    @Test("A terminal failure is cleared by detach (demotion below .preloaded)")
    func terminalFailureClearedByDetach() {
        let (player, target) = makePlayer()
        player.set(source: source, grade: .current)
        target.emit(.failed(.init(kind: .itemFailed(description: "boom"))))
        #expect(player.lastError != nil)

        player.set(source: source, grade: .instanceOnly)

        #expect(player.lastError == nil)
    }

    @Test("A terminal failure is cleared by release()")
    func terminalFailureClearedByRelease() {
        let (player, target) = makePlayer()
        player.set(source: source, grade: .current)
        target.emit(.failed(.init(kind: .itemFailed(description: "boom"))))
        #expect(player.lastError != nil)

        player.release()

        #expect(player.lastError == nil)
        #expect(player.lastFailure == nil)
    }

    @Test("A non-terminal diagnostic routes to lastDiagnostic, not lastError, and is cleared the same way")
    func diagnosticRoutesSeparatelyAndClears() {
        let (player, target) = makePlayer()
        player.set(source: source, grade: .current)

        target.emit(.failed(.init(kind: .itemErrorLogEntry(description: "HTTP 403 (Forbidden)"))))

        #expect(player.lastError == nil)
        #expect(player.lastDiagnostic != nil)

        player.set(source: otherSource, grade: .current)

        #expect(player.lastDiagnostic == nil)
    }

    @Test("Both .failed and .failureReported broadcast from the same failure, in that order")
    func failedAndFailureReportedBroadcastTogether() {
        let (player, target) = makePlayer()
        player.set(source: source, grade: .current)
        var events: [ABPlayerEvent] = []
        let token = player.addObserver { events.append($0) }
        defer { token.cancel() }

        let error = ABPlayerError.itemFailed(description: "boom")
        target.emit(.failed(.init(kind: error)))

        let failedIndex = events.firstIndex(of: .failed(error))
        let reportedIndex = events.firstIndex { event in
            if case .failureReported(let failure) = event { return failure.kind == error }
            return false
        }
        #expect(failedIndex != nil && reportedIndex != nil)
        #expect(failedIndex! < reportedIndex!)
    }

    @Test("An audio session apply failure carries its NSError domain/code as origin")
    func audioSessionFailureCarriesOrigin() {
        let controller = ABFakeAudioSessionController()
        let underlying = NSError(domain: "test.audioSession", code: 7, userInfo: [NSLocalizedDescriptionKey: "denied"])
        controller.activateError = underlying
        let coordinator = ABAudioSessionCoordinator(controller: controller)
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(
            configuration: ABPlayerConfiguration(backgroundPolicy: .ignore, audioSessionPolicy: .ambient),
            target: target,
            audioSessionCoordinator: coordinator
        )

        player.set(source: source, grade: .current)

        #expect(player.lastFailure?.origin == ABErrorOrigin(domain: "test.audioSession", code: 7))
    }
}
