import ABTestSupport
import Foundation
import SwiftUI
import Testing
@testable import ABPlayerKit

// Verbatim copies of the SwiftUI samples in ChoosingAnOwnershipModel.md,
// plus README's "Showing Playback Time" (the one README sample that needs
// only the core target).
// They exist to be compiled: an API change that breaks the documented
// integration breaks this target instead of silently rotting the article.

private struct VideoScreen: View {
    let url: URL
    @State private var player = ABPlayer()

    var body: some View {
        VStack {
            ABVideoPlayer(player: player)
                .aspectRatio(16 / 9, contentMode: .fit)
            Text(player.position.time.currentTime.seconds, format: .number.precision(.fractionLength(0)))
        }
        .task { player.load(ABMediaSource(url: url)) }
        .onDisappear { player.pause() }
    }
}

private struct ReelsFeed: View {
    let sources: [ABMediaSource]
    @State private var players: [ABPlayer] = []
    @State private var visibleIndex: Int? = 0

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(players.indices, id: \.self) { index in
                    ABVideoPlayer(player: players[index])
                        .containerRelativeFrame([.horizontal, .vertical])
                        .id(index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $visibleIndex)
        .onAppear {
            if players.isEmpty {
                players = sources.map { _ in ABPlayer() }
            }
            updateGrades()
        }
        .onChange(of: visibleIndex) { updateGrades() }
    }

    private func updateGrades() {
        guard let visibleIndex else { return }
        for (index, player) in players.enumerated() {
            switch abs(index - visibleIndex) {
            case 0: player.load(sources[index])
            case 1: player.set(source: sources[index], grade: .preloaded)
            default: player.release()
            }
        }
    }
}

private struct PlaybackTimeSample: View {
    let player: ABPlayer

    var body: some View {
        VStack {
            ABVideoPlayer(player: player)
            ProgressView(value: player.position.time.progress ?? 0)
            Text(player.position.time.currentTime.seconds, format: .number.precision(.fractionLength(0)))
        }
    }
}

@Suite("Documentation samples compile against the current API", .timeLimit(abScaledMinutes(3)))
@MainActor
struct ABDocumentationSnippetTests {
    @Test("The ownership article's samples build as SwiftUI views")
    func samplesBuild() {
        let url = URL(string: "https://example.com/snippet.mp4")!
        _ = VideoScreen(url: url).body
        _ = ReelsFeed(sources: [ABMediaSource(url: url)]).body
        _ = PlaybackTimeSample(player: ABPlayer()).body
    }
}
