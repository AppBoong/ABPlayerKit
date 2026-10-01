import ABPlayerKit
import ABPlayerKitControls
import SwiftUI

/// The README's Quick Start, one screen per step. The player code in each
/// screen is the README/DocC sample's; only the media URLs and the read-only
/// state readouts are the demo's own.
///
/// Launch with `-ABDemoUsage oneLine|ownPlayer|feed` to open a step directly
/// (used to take the README screenshots, since `simctl` can't tap).
enum UsageStep: String, CaseIterable, Identifiable, Hashable {
    case oneLine
    case ownPlayer
    case feed

    var id: Self { self }

    var title: String {
        switch self {
        case .oneLine: "1. One line"
        case .ownPlayer: "2. Own the player"
        case .feed: "3. A feed with preloading"
        }
    }

    var summary: String {
        switch self {
        case .oneLine: "The view owns the player and releases it when SwiftUI discards the view."
        case .ownPlayer: "@State player, load() in .task, observable position for time."
        case .feed: "One .current player, neighbours .preloaded, the rest released."
        }
    }

    static var launchArgument: UsageStep? {
        UserDefaults.standard.string(forKey: "ABDemoUsage").flatMap(UsageStep.init(rawValue:))
    }
}

enum UsageMedia {
    static let url = URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/bipbop_16x9_variant.m3u8")!

    static let feed: [ABMediaSource] = [
        "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/bipbop_16x9_variant.m3u8",
        "https://media.w3.org/2010/05/sintel/trailer.mp4",
        "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/bipbop_4x3_variant.m3u8",
        "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8"
    ].map { ABMediaSource(url: URL(string: $0)!) }
}

struct UsageScreen: View {
    @State private var path: [UsageStep] = UsageStep.launchArgument.map { [$0] } ?? []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    ForEach(UsageStep.allCases) { step in
                        NavigationLink(value: step) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(step.title).font(.headline)
                                Text(step.summary).font(.footnote).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } footer: {
                    Text("Each screen runs the matching README Quick Start step.")
                }
            }
            .navigationTitle("Usage")
            .navigationDestination(for: UsageStep.self) { step in
                switch step {
                case .oneLine: OneLineUsage()
                case .ownPlayer: OwnedPlayerUsage(url: UsageMedia.url)
                case .feed: FeedUsage(sources: UsageMedia.feed)
                }
            }
        }
    }
}

// MARK: - 1. One line

private struct OneLineUsage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // README › Quick Start
                ABVideoPlayerWithControls(url: UsageMedia.url)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .background(.black)

                UsageCodeCard("""
                ABVideoPlayerWithControls(url: url)
                    .aspectRatio(16 / 9, contentMode: .fit)
                """)
                UsageNote("No player to create, attach, or release. Dropping the view releases every playback resource.")
            }
            .padding()
        }
        .navigationTitle("One line")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 2. Own the player

private struct OwnedPlayerUsage: View {
    let url: URL
    @State private var player = ABPlayer()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // README › Owning the Player Yourself
                ABVideoPlayerWithControls(player: player, videoGravity: .resizeAspect)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .background(.black)
                    .task {
                        player.load(ABMediaSource(url: url))
                    }
                    .onDisappear {
                        player.pause()
                    }

                // README › Showing Playback Time
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: player.position.time.progress ?? 0)
                    Text(player.position.time.currentTime.seconds, format: .number.precision(.fractionLength(0)))
                        .font(.title2.monospacedDigit().bold())
                }

                PlayerStateReadout(player: player)

                UsageCodeCard("""
                @State private var player = ABPlayer()

                ABVideoPlayerWithControls(player: player)
                    .task { player.load(ABMediaSource(url: url)) }
                    .onDisappear { player.pause() }

                ProgressView(value: player.position.time.progress ?? 0)
                """)
                UsageNote("The progress bar and the seconds label read player.position, a separate @Observable object, so only they re-render on each tick.")
            }
            .padding()
        }
        .navigationTitle("Own the player")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PlayerStateReadout: View {
    let player: ABPlayer

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
            GridRow {
                Text("grade").foregroundStyle(.secondary)
                Text(String(describing: player.grade)).monospaced()
            }
            GridRow {
                Text("isPlaying").foregroundStyle(.secondary)
                Text(String(player.isPlaying)).monospaced()
            }
            GridRow {
                Text("isBuffering").foregroundStyle(.secondary)
                Text(String(player.isBuffering)).monospaced()
            }
        }
        .font(.footnote)
    }
}

// MARK: - 3. A feed with preloading

/// The `ReelsFeed` sample from the DocC article "Choosing an Ownership Model",
/// plus a read-only overlay that shows each player's grade. Two deviations,
/// both for the demo's sake: `.resizeAspect`, because these sample streams
/// are landscape, and `-ABDemoFeedIndex <n>` to open on a given row.
private struct FeedUsage: View {
    let sources: [ABMediaSource]
    @State private var players: [ABPlayer] = []
    @State private var visibleIndex: Int? = 0

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(players.indices, id: \.self) { index in
                    ABVideoPlayer(player: players[index], videoGravity: .resizeAspect)
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
            // Demo-only: jump to a launch-argument row once the rows exist.
            let launchIndex = UserDefaults.standard.integer(forKey: "ABDemoFeedIndex")
            if launchIndex > 0 {
                DispatchQueue.main.async { visibleIndex = launchIndex }
            }
        }
        .onChange(of: visibleIndex) { updateGrades() }
        .background(.black)
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .bottom) {
            GradeStrip(players: players, visibleIndex: visibleIndex)
                .padding()
        }
        .navigationTitle("Feed")
        .navigationBarTitleDisplayMode(.inline)
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

private struct GradeStrip: View {
    let players: [ABPlayer]
    let visibleIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Swipe up — each row is one ABPlayer")
                .font(.caption.bold())
            ForEach(players.indices, id: \.self) { index in
                HStack {
                    Text("Video \(index + 1)")
                    Spacer()
                    Text(String(describing: players[index].grade))
                        .monospaced()
                        .foregroundStyle(color(for: players[index].grade))
                }
                .font(.caption)
                .fontWeight(index == visibleIndex ? .bold : .regular)
            }
        }
        .padding(12)
        .frame(maxWidth: 260)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func color(for grade: ABPlaybackGrade) -> Color {
        switch grade {
        case .current: .green
        case .preloaded: .orange
        case .instanceOnly: .secondary
        case .released: .secondary
        }
    }
}

// MARK: - Shared

private struct UsageCodeCard: View {
    let code: String

    init(_ code: String) {
        self.code = code
    }

    var body: some View {
        Text(code)
            .font(.system(.caption, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct UsageNote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}
