import Foundation
import Observation
import Testing
@testable import ABPlayerKit

/// Coverage for round3 Phase4 WP9: `ABPlayer` is `@Observable`, so SwiftUI
/// views reading `grade`/`isScrubbing`/`hasDisplayedFirstFrame`/`lastError`/
/// `source`/`configuration` directly must actually receive Observation
/// change notifications — not just have the underlying value change. This
/// is the property the manual, mirrored-into-a-separate-`var` pattern
/// (see the demo app's `DemoModel` before this WP) could never verify: the
/// old code had no way to fail if `@Observable` tracking silently didn't
/// fire.
@Suite("ABPlayer's @Observable properties notify Observation on change", .timeLimit(.minutes(3)))
@MainActor
struct ABPlayerObservationTests {
    private let source = ABMediaSource(url: URL(string: "https://example.com/a.mp4")!)

    /// `withObservationTracking`'s `onChange` closure fires on an
    /// unspecified execution context (this package targets iOS 17, so the
    /// isolated-`onChange` overload added later isn't available) — this
    /// lock-protected box lets the test observe it from any thread while
    /// `waitUntil` (always `@MainActor`) polls it deterministically,
    /// mirroring `ABAVPlaybackTarget.ReadyWaitState`'s pattern for the same
    /// "signalled from an unknown thread" shape.
    private final class ChangeFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var fired = false

        func markFired() {
            lock.lock()
            fired = true
            lock.unlock()
        }

        var hasFired: Bool {
            lock.lock()
            defer { lock.unlock() }
            return fired
        }
    }

    private func makePlayer() -> (ABPlayer, ABFakePlaybackTarget) {
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore), target: target)
        return (player, target)
    }

    @Test("Changing grade fires an Observation notification")
    func gradeChangeFiresObservation() async throws {
        let (player, _) = makePlayer()
        let flag = ChangeFlag()

        withObservationTracking {
            _ = player.grade
        } onChange: {
            flag.markFired()
        }

        player.set(source: source, grade: .current)

        try await waitUntil { flag.hasFired }
    }

    @Test("Changing isScrubbing fires an Observation notification")
    func isScrubbingChangeFiresObservation() async throws {
        let (player, _) = makePlayer()
        player.set(source: source, grade: .current)
        let flag = ChangeFlag()

        withObservationTracking {
            _ = player.isScrubbing
        } onChange: {
            flag.markFired()
        }

        player.beginScrubbing()

        try await waitUntil { flag.hasFired }
    }

    @Test("Changing configuration fires an Observation notification")
    func configurationChangeFiresObservation() async throws {
        let (player, _) = makePlayer()
        let flag = ChangeFlag()

        withObservationTracking {
            _ = player.configuration
        } onChange: {
            flag.markFired()
        }

        // Any mutation replaces the whole `configuration` struct (it's a
        // single stored property with a `didSet`), so a single unrelated
        // field is enough to prove the property itself is tracked — this
        // is the one review N6 called out specifically, since
        // `configuration` is also the only one of the six documented
        // properties with a `didSet` (`applyConfigurationChange`), making
        // it the likeliest candidate for the macro expansion to interact
        // badly with (round3 Phase3 WP9.2's concern, empirically ruled out
        // in REVIEW-round3-final.md but never pinned down by a test).
        player.configuration.isMuted.toggle()

        try await waitUntil { flag.hasFired }
    }

    @Test("Changing lastError fires an Observation notification")
    func lastErrorChangeFiresObservation() {
        let (player, target) = makePlayer()
        player.set(source: source, grade: .current)
        let flag = ChangeFlag()

        withObservationTracking {
            _ = player.lastError
        } onChange: {
            flag.markFired()
        }

        // `target.emit(.failed(_))` drives `ABPlayer.handle(_:)`, which
        // updates `lastError` synchronously — no `waitUntil` needed, unlike
        // the audio-session/interruption paths elsewhere in this suite
        // that hop through real async notification delivery.
        target.emit(.failed(.itemFailed(description: "boom")))

        #expect(flag.hasFired)
    }

    @Test("Reading only avPlayer (a non-tracked computed property) does not fire on a grade change")
    func untrackedComputedPropertyDoesNotFireObservation() async throws {
        let (player, _) = makePlayer()
        let flag = ChangeFlag()

        withObservationTracking {
            _ = player.avPlayer
        } onChange: {
            flag.markFired()
        }

        player.set(source: source, grade: .current)

        // `avPlayer` reads `target.avPlayer` — a property on a non-`@Observable`
        // type, not one of `ABPlayer`'s own tracked stored properties — so
        // this grade change must not (falsely) fire the tracking registered
        // above. A short bounded wait proves nothing arrives, matching the
        // "asserting an absence" pattern used elsewhere in this test suite.
        for _ in 0..<20 {
            await Task.yield()
        }
        #expect(!flag.hasFired)
    }
}
