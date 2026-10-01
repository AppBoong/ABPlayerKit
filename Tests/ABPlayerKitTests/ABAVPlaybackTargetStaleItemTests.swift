import ABTestSupport
@preconcurrency import AVFoundation
import Foundation
import Testing
@testable import ABPlayerKit

/// A notification observer registered with `queue: .main` runs inline when
/// the notification is posted on the main thread, and the observer's
/// `Task { @MainActor in }` hop runs *after* the current synchronous turn.
/// Posting for item A and replacing A with B in the same turn therefore
/// reproduces the real race deterministically: the hop lands while B is
/// current. Without an identity check after the hop, A's event is
/// attributed to B.
@Suite("ABAVPlaybackTarget drops events from an item that was replaced before the main-actor hop ran", .timeLimit(abScaledMinutes(3)))
@MainActor
struct ABAVPlaybackTargetStaleItemTests {
    private func fixtureSource() throws -> ABMediaSource {
        let url = try #require(Bundle.module.url(forResource: "tiny", withExtension: "mp4"))
        return ABMediaSource(url: url)
    }

    private func drainMainActor() async {
        for _ in 0..<5 {
            await Task.yield()
        }
    }

    @Test("A stall posted for the previous item is not reported against the new one")
    func staleStallIsDropped() async throws {
        let target = ABAVPlaybackTarget()
        target.makePlayer()
        let source = try fixtureSource()
        target.attachItem(source, tuning: .unrestricted, assetFactory: ABDefaultAssetFactory())
        let previousItem = try #require(target.avPlayerItem)
        var stalls = 0
        target.onEvent = { event in
            if case .playbackStalled = event { stalls += 1 }
        }

        NotificationCenter.default.post(name: .AVPlayerItemPlaybackStalled, object: previousItem)
        target.attachItem(source, tuning: .unrestricted, assetFactory: ABDefaultAssetFactory())
        await drainMainActor()

        #expect(target.avPlayerItem !== previousItem)
        #expect(stalls == 0)
    }

    @Test("Played-to-end posted for the previous item is not reported against the new one")
    func stalePlayedToEndIsDropped() async throws {
        let target = ABAVPlaybackTarget()
        target.makePlayer()
        let source = try fixtureSource()
        target.attachItem(source, tuning: .unrestricted, assetFactory: ABDefaultAssetFactory())
        let previousItem = try #require(target.avPlayerItem)
        var ends = 0
        target.onEvent = { event in
            if case .playedToEnd = event { ends += 1 }
        }

        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: previousItem)
        target.attachItem(source, tuning: .unrestricted, assetFactory: ABDefaultAssetFactory())
        await drainMainActor()

        #expect(ends == 0)
    }

    @Test("A stall for the item that is still current is reported")
    func currentStallIsReported() async throws {
        let target = ABAVPlaybackTarget()
        target.makePlayer()
        target.attachItem(try fixtureSource(), tuning: .unrestricted, assetFactory: ABDefaultAssetFactory())
        let item = try #require(target.avPlayerItem)
        var stalls = 0
        target.onEvent = { event in
            if case .playbackStalled = event { stalls += 1 }
        }

        NotificationCenter.default.post(name: .AVPlayerItemPlaybackStalled, object: item)
        await drainMainActor()

        #expect(stalls == 1)
    }
}

/// `deliver(_:from:)` is the single check every item-scoped callback goes
/// through, including the status KVO path, whose stale `.failed` is the
/// case that matters most (it lands in `lastFailure` and makes `load()`
/// re-attach a healthy item) but which can't be triggered on demand.
@Suite("ABAVPlaybackTarget.deliver reports only events from the attached item", .timeLimit(abScaledMinutes(3)))
@MainActor
struct ABAVPlaybackTargetDeliverTests {
    @Test("A failed status from a replaced item is dropped; the same from the attached item is reported")
    func deliverChecksIdentity() throws {
        let target = ABAVPlaybackTarget()
        target.makePlayer()
        let url = try #require(Bundle.module.url(forResource: "tiny", withExtension: "mp4"))
        target.attachItem(ABMediaSource(url: url), tuning: .unrestricted, assetFactory: ABDefaultAssetFactory())
        let replaced = try #require(target.avPlayerItem)
        target.attachItem(ABMediaSource(url: url), tuning: .unrestricted, assetFactory: ABDefaultAssetFactory())
        let attached = try #require(target.avPlayerItem)
        var received: [ABTargetEvent] = []
        target.onEvent = { received.append($0) }
        let failure = ABPlayerFailure(kind: .itemFailed(description: "boom"))

        target.deliver([.itemStatusChanged(.failed), .failed(failure)], from: replaced)
        #expect(received.isEmpty)

        target.deliver([.itemStatusChanged(.failed), .failed(failure)], from: attached)
        #expect(received == [.itemStatusChanged(.failed), .failed(failure)])
    }
}
