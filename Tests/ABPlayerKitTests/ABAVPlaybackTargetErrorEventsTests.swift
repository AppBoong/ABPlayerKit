import ABTestSupport
import Foundation
import Testing
@testable import ABPlayerKit
@preconcurrency import AVFoundation

/// Coverage for the two failure-diagnostic `NotificationCenter` subscriptions
/// `ABAVPlaybackTarget.observeItem` adds alongside the existing
/// `.status`/`.AVPlayerItemPlaybackStalled` observers: `AVPlayerItemFailedToPlayToEndTime`
/// (a terminal mid-playback failure `.status` KVO does not reliably catch on
/// its own) and `AVPlayerItemNewErrorLogEntry` (a non-terminal diagnostic
/// signal). Both route through the existing `ABTargetEvent.failed(ABPlayerError)`
/// path so a consumer can tell a healthy stall apart from a real problem —
/// see `ABPlayerError.itemFailed`/`.itemErrorLogEntry`.
///
/// Driven by posting the real system notifications against a real
/// `AVPlayerItem` (per this suite's own convention of avoiding real network
/// round trips — `tiny.mp4` is a bundled local fixture), rather than through
/// `ABFakePlaybackTarget`, since the behavior under test lives entirely
/// inside `ABAVPlaybackTarget`'s own `NotificationCenter` wiring.
@Suite("ABAVPlaybackTarget surfaces item failure notifications", .timeLimit(.minutes(3)))
@MainActor
struct ABAVPlaybackTargetErrorEventsTests {
    private func makeAttachedTarget() throws -> (ABAVPlaybackTarget, AVPlayerItem) {
        let target = ABAVPlaybackTarget()
        target.makePlayer()
        let url = try #require(
            Bundle.module.url(forResource: "tiny", withExtension: "mp4"),
            "tiny.mp4 test fixture must be bundled with ABPlayerKitTests"
        )
        let source = ABMediaSource(url: url)
        target.attachItem(source, tuning: .unrestricted, assetFactory: ABDefaultAssetFactory())
        let item = try #require(target.avPlayerItem)
        return (target, item)
    }

    @Test("FailedToPlayToEndTime with an underlying error promotes it to .failed(.itemFailed)")
    func failedToPlayToEndTimeWithUserInfoErrorPromotesToItemFailed() async throws {
        let (target, item) = try makeAttachedTarget()
        var events: [ABTargetEvent] = []
        target.onEvent = { events.append($0) }

        let underlying = NSError(domain: "ABPlayerKitTests", code: 42, userInfo: [
            NSLocalizedDescriptionKey: "network connection lost"
        ])
        NotificationCenter.default.post(
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            userInfo: [AVPlayerItemFailedToPlayToEndTimeErrorKey: underlying]
        )

        try await waitUntil {
            events.contains { event in
                if case .failed(let failure) = event, case .itemFailed(let description) = failure.kind {
                    return description == "network connection lost"
                }
                return false
            }
        }
    }

    @Test("FailedToPlayToEndTime without userInfo falls back to the item's own error")
    func failedToPlayToEndTimeWithoutUserInfoFallsBackToItemError() async throws {
        // A missing local file fails immediately with no real network round
        // trip (matches the fixture convention in
        // `ABPlayerDeinitCleanupTests`/`ABAVPlaybackTargetWaitUntilReadyTests`),
        // giving `item.error` a real, non-nil value to fall back to.
        let target = ABAVPlaybackTarget()
        target.makePlayer()
        let missingURL = URL(fileURLWithPath: "/private/tmp/abplayerkit-error-events-fixture-\(UUID().uuidString).mp4")
        let source = ABMediaSource(url: missingURL)
        target.attachItem(source, tuning: .unrestricted, assetFactory: ABDefaultAssetFactory())
        let item = try #require(target.avPlayerItem)

        // Let the item actually reach `.status == .failed` first so
        // `item.error` is populated, independent of the notification path
        // under test below.
        _ = await target.waitUntilReady(item: item, timeout: 10)
        #expect(item.status == .failed)
        let expectedDescription = try #require(item.error?.localizedDescription)

        var events: [ABTargetEvent] = []
        target.onEvent = { events.append($0) }

        NotificationCenter.default.post(name: .AVPlayerItemFailedToPlayToEndTime, object: item)

        try await waitUntil {
            events.contains { event in
                if case .failed(let failure) = event, case .itemFailed(let description) = failure.kind {
                    return description == expectedDescription
                }
                return false
            }
        }
    }

    @Test("NewErrorLogEntry with no log data yet is a safe no-op")
    func newErrorLogEntryWithoutLogDataIsNoop() async throws {
        let (target, item) = try makeAttachedTarget()
        var events: [ABTargetEvent] = []
        target.onEvent = { events.append($0) }

        // `tiny.mp4` is a valid local fixture, so `item.errorLog()` is
        // nil/empty at this point — there is no public initializer for
        // `AVPlayerItemErrorLogEvent`, so a real one cannot be fabricated
        // from test code. This exercises the guard's graceful no-op path
        // (and confirms it does not crash) rather than the
        // description-formatting path.
        NotificationCenter.default.post(name: .AVPlayerItemNewErrorLogEntry, object: item)

        // A second, independently-verifiable notification for the same
        // item posted right after: `NotificationCenter` delivers same-queue
        // observers in posting order, so waiting for *this* one to land
        // deterministically proves the first was already processed
        // (without crashing or blocking) rather than polling a fixed
        // number of times.
        NotificationCenter.default.post(
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            userInfo: [AVPlayerItemFailedToPlayToEndTimeErrorKey: NSError(domain: "canary", code: 1)]
        )

        try await waitUntil {
            events.contains { event in
                if case .failed(let failure) = event, case .itemFailed = failure.kind { return true }
                return false
            }
        }

        #expect(!events.contains { event in
            if case .failed(let failure) = event, case .itemErrorLogEntry = failure.kind { return true }
            return false
        })
    }

    @Test("A notification queued for a since-replaced item is dropped by the stale-item guard")
    func staleItemNotificationIsDropped() async throws {
        let (target, staleItem) = try makeAttachedTarget()
        var events: [ABTargetEvent] = []
        target.onEvent = { events.append($0) }

        NotificationCenter.default.post(
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: staleItem,
            userInfo: [AVPlayerItemFailedToPlayToEndTimeErrorKey: NSError(domain: "stale", code: 1)]
        )

        // Replace the item before the notification above is delivered
        // (`NotificationCenter`'s `queue:` delivery is not synchronous with
        // `post`, so this ordering is deterministic) — the stale-item guard
        // (mirroring `setPeriodicTimeObserver`'s `onTick`) must drop the
        // queued notification once its `Task` hop observes `avPlayerItem`
        // no longer matches the item it was posted for.
        let secondURL = try #require(
            Bundle.module.url(forResource: "tiny", withExtension: "mp4"),
            "tiny.mp4 test fixture must be bundled with ABPlayerKitTests"
        )
        target.attachItem(
            ABMediaSource(url: secondURL),
            tuning: .unrestricted,
            assetFactory: ABDefaultAssetFactory()
        )
        let currentItem = try #require(target.avPlayerItem)

        // Canary on the new current item confirms the stale notification's
        // queued delivery has already drained before asserting on `events`.
        NotificationCenter.default.post(
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: currentItem,
            userInfo: [AVPlayerItemFailedToPlayToEndTimeErrorKey: NSError(domain: "canary", code: 2)]
        )

        try await waitUntil {
            events.contains { event in
                if case .failed(let failure) = event, case .itemFailed(let description) = failure.kind {
                    return description.contains("canary")
                }
                return false
            }
        }

        #expect(!events.contains { event in
            if case .failed(let failure) = event, case .itemFailed(let description) = failure.kind {
                return description.contains("stale")
            }
            return false
        })
    }
}
