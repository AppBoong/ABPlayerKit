import Foundation
import Testing
@testable import ABPlayerKit
@preconcurrency import AVFoundation

/// Coverage for `preferredMaximumResolution`'s sentinel resolving against
/// the size `ABPlayerView` reports, not the device screen — a feed cell's
/// correct cap is the cell's own size.
@Suite("ABPlayer resolves displaySizeSentinel from reported display size", .timeLimit(.minutes(3)))
@MainActor
struct ABDisplaySizeTuningTests {
    private let source = ABMediaSource(url: URL(string: "https://example.com/a.mp4")!)

    @Test("With no view ever attached, the sentinel resolves to .zero (no cap)")
    func noReportedSizeResolvesToNoCap() {
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore), target: target)

        player.set(source: source, grade: .current)

        let expected = ABPlaybackTuning.displayCapped.resolved(displaySize: .zero)
        #expect(target.calls.contains(.attachItem(source, expected)))
    }

    @Test("reportDisplaySize resolves the sentinel to the reported cell size and re-applies tuning")
    func reportDisplaySizeResolvesSentinelAndReapplies() {
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore), target: target)
        player.set(source: source, grade: .current)
        let applyTuningCallCountBefore = target.calls.filter { if case .applyTuning = $0 { true } else { false } }.count

        let cellSize = CGSize(width: 375, height: 667)
        player.reportDisplaySize(cellSize)

        let expected = ABPlaybackTuning.displayCapped.resolved(displaySize: cellSize)
        #expect(target.calls.contains(.applyTuning(expected)))
        let applyTuningCallCountAfter = target.calls.filter { if case .applyTuning = $0 { true } else { false } }.count
        #expect(applyTuningCallCountAfter == applyTuningCallCountBefore + 1)
    }

    @Test("Reporting the same display size twice does not re-apply tuning (loop guard)")
    func repeatedIdenticalDisplaySizeDoesNotReapply() {
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore), target: target)
        player.set(source: source, grade: .current)
        let cellSize = CGSize(width: 375, height: 667)
        player.reportDisplaySize(cellSize)
        let applyTuningCallCountAfterFirst = target.calls.filter { if case .applyTuning = $0 { true } else { false } }.count

        player.reportDisplaySize(cellSize)

        let applyTuningCallCountAfterSecond = target.calls.filter { if case .applyTuning = $0 { true } else { false } }.count
        #expect(applyTuningCallCountAfterSecond == applyTuningCallCountAfterFirst)
    }

    @Test(".tuningApplied still broadcasts the unresolved preset value, not the resolved pixel cap")
    func tuningAppliedBroadcastsUnresolvedValue() {
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore), target: target)
        var events: [ABPlayerEvent] = []
        let token = player.addObserver { events.append($0) }
        defer { token.cancel() }

        player.set(source: source, grade: .current)

        #expect(events.contains(.tuningApplied(.current, .displayCapped)))
    }
}
