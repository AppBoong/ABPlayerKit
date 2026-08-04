import ABPlayerKit
import ABPlayerKitControls
import AVFoundation
import SwiftUI

struct PlaybackScreen: View {
    let model: DemoModel
    @State private var selectedControlsStyle = DemoControlsStyle.default
    @State private var accessoryTapCount = 0
    private let accessoryButton = DemoAccessoryButton()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ABVideoPlayerWithControls(
                        player: model.player,
                        videoGravity: .resizeAspect,
                        style: selectedControlsStyle.style,
                        configuration: controlsConfiguration,
                        accessoryViews: [accessoryButton]
                    )
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .background(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .onAppear {
                            accessoryButton.onTap = { accessoryTapCount += 1 }
                        }

                    Text("Accessory taps: \(accessoryTapCount)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    GroupBox("Controls") {
                        Picker("Style", selection: $selectedControlsStyle) {
                            ForEach(DemoControlsStyle.allCases) { controlsStyle in
                                Text(controlsStyle.title).tag(controlsStyle)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text("Choose Current grade, then compare the light scrims while the centered transport cluster, bottom timeline, and rate control remain in place.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }

                    GroupBox("Media") {
                        Picker("Source", selection: mediaBinding) {
                            ForEach(DemoMedia.allCases) { media in
                                Text(media.rawValue).tag(media)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    GroupBox("Playback grade") {
                        Picker("Grade", selection: gradeBinding) {
                            ForEach(ABPlaybackGrade.allCases, id: \.rawValue) { grade in
                                Text(grade.shortLabel).tag(grade)
                            }
                        }
                        .pickerStyle(.segmented)

                        Button {
                            model.togglePlayback()
                        } label: {
                            Label(
                                model.isPlaying ? "Pause" : "Play",
                                systemImage: model.isPlaying ? "pause.fill" : "play.fill"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 8)

                        Divider()
                            .padding(.vertical, 4)

                        HStack {
                            Button("Arm preroll") {
                                model.armPreroll()
                            }
                            .buttonStyle(.bordered)

                            Button("Cancel preload", role: .destructive) {
                                model.cancelPreload()
                            }
                            .buttonStyle(.bordered)
                        }
                        .disabled(model.player.grade != .preloaded)

                        Text("Preroll controls are available only in Preloaded. Completion and cancellation appear in Latest event.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    GroupBox("Live configuration") {
                        VStack(spacing: 12) {
                            Toggle("Muted", isOn: mutedBinding)
                            Toggle("Loop playback", isOn: loopingBinding)
                            LabeledContent("Preload tuning", value: "Conservative (fixed)")
                            Picker("Current tuning", selection: tuningBinding) {
                                ForEach(DemoTuningPreset.allCases) { preset in
                                    Text(preset.title).tag(preset)
                                }
                            }
                            Text("Preloaded always uses .conservativePreload. This picker changes only currentTuning, making promotion and demotion apply distinct roles.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    LabeledContent("Latest event", value: model.latestEvent)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("ABPlayerKit")
        }
    }

    private var mediaBinding: Binding<DemoMedia> {
        Binding(
            get: { model.selectedMedia },
            set: { media in model.selectMedia(media) }
        )
    }

    // Reads `player.grade` directly — `ABPlayer` is `@Observable` (round3
    // Phase3 WP9), so this view re-renders on grade changes with no
    // observer-bridge mirror needed in `DemoModel`.
    private var gradeBinding: Binding<ABPlaybackGrade> {
        Binding(
            get: { model.player.grade },
            set: { grade in model.setGrade(grade) }
        )
    }

    private var mutedBinding: Binding<Bool> {
        Binding(
            get: { model.isMuted },
            set: { muted in model.setMuted(muted) }
        )
    }

    private var loopingBinding: Binding<Bool> {
        Binding(
            get: { model.isLooping },
            set: { looping in model.setLooping(looping) }
        )
    }

    private var tuningBinding: Binding<DemoTuningPreset> {
        Binding(
            get: { model.selectedTuning },
            set: { tuning in model.setTuning(tuning) }
        )
    }

    private var controlsConfiguration: ABPlayerControlsConfiguration {
        var configuration = ABPlayerControlsConfiguration()
        configuration.skipInterval = 20
        configuration.rateOptions = [0.5, 1, 1.5, 2]
        configuration.rateInteraction = .menu
        return configuration
    }
}

/// A minimal `accessoryViews` demonstration/verification vehicle: a plain
/// UIButton placed at the controls' right edge, next to the rate button, to
/// exercise (and let a human tap-test) hit-test priority over the seek bar.
@MainActor
private final class DemoAccessoryButton: UIButton {
    var onTap: (() -> Void)?

    init() {
        super.init(frame: .zero)
        setImage(UIImage(systemName: "star.fill"), for: .normal)
        tintColor = .white
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 44),
            heightAnchor.constraint(equalToConstant: 44)
        ])
        addAction(UIAction { [weak self] _ in self?.onTap?() }, for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private enum DemoControlsStyle: String, CaseIterable, Identifiable {
    case `default`
    case minimal
    case tinted

    var id: Self { self }

    var title: String {
        switch self {
        case .default: "Default"
        case .minimal: "Minimal"
        case .tinted: "Tinted"
        }
    }

    @MainActor
    var style: ABPlayerControlsStyle {
        switch self {
        case .default: .default
        case .minimal: .minimal
        case .tinted: .tinted
        }
    }
}
