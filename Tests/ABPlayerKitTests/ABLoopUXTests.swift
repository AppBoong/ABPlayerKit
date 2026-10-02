import ABTestSupport
@preconcurrency import AVFoundation
import Foundation
import Testing
@testable import ABPlayerKit

/// Real-AVFoundation checks of looping as a user sees it, against the
/// bundled 0.6 s `tiny.mp4`, so several loops happen within a second.
@Suite("Looping with real AVFoundation: pausing at the loop point sticks", .timeLimit(abScaledMinutes(3)))
@MainActor
struct ABLoopUXTests {
    private func makeLoopingPlayer() throws -> (ABPlayer, ABMediaSource) {
        let url = try #require(Bundle.module.url(forResource: "tiny", withExtension: "mp4"))
        let player = ABPlayer(configuration: ABPlayerConfiguration(isLooping: true, backgroundPolicy: .ignore))
        return (player, ABMediaSource(url: url))
    }

    @Test("A looping item keeps playing across several loops")
    func loopsKeepPlaying() async throws {
        let (player, source) = try makeLoopingPlayer()
        var ends = 0
        let token = player.addObserver { event in
            if case .playedToEnd = event { ends += 1 }
        }
        defer { token.cancel() }

        player.load(source)
        try await waitUntil { ends >= 2 }
        try await Task.sleep(for: .milliseconds(150))

        #expect(player.isPlaying)
        #expect(player.avPlayer?.rate ?? 0 > 0)
    }

    @Test("pause() called the moment the item ends is not undone by the loop restart")
    func pauseAtLoopPointSticks() async throws {
        let (player, source) = try makeLoopingPlayer()
        var paused = false
        let token = player.addObserver { [weak player] event in
            if case .playedToEnd = event, !paused {
                paused = true
                player?.pause()
            }
        }
        defer { token.cancel() }

        player.load(source)
        try await waitUntil { paused }
        try await Task.sleep(for: .milliseconds(800))

        #expect(!player.isPlaying)
        #expect(player.avPlayer?.rate == 0)
    }
}
