import ABPlayerKit
import ABTestSupport
@preconcurrency import AVFoundation
import Foundation
import Testing
@testable import ABPlayerKitControls

/// The presenter flips the icon to "play" on `.playedToEnd`. With
/// `actionAtItemEnd = .none` a looping item never stops, so unless some
/// later event flips it back, the controls would show "play" over a video
/// that is playing.
@Suite("The standard controls' icon while a real item loops", .timeLimit(abScaledMinutes(3)))
@MainActor
struct ABPlayerControlsLoopIconTests {
    @Test("After a loop, the controls show the pause icon because the video is playing")
    func iconStaysPauseWhileLooping() async throws {
        let url = try #require(Bundle.module.url(forResource: "tiny", withExtension: "mp4"))
        let player = ABPlayer(configuration: ABPlayerConfiguration(isLooping: true, backgroundPolicy: .ignore))
        let controls = ABPlayerControlsView()
        controls.player = player
        var ends = 0
        let token = player.addObserver { event in
            if case .playedToEnd = event { ends += 1 }
        }
        defer { token.cancel() }

        player.load(ABMediaSource(url: url))
        try await waitUntil { ends >= 2 }
        try await Task.sleep(for: .milliseconds(150))

        #expect(player.isPlaying)
        #expect(controls.isShowingPauseIcon)
    }
}
