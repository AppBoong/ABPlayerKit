import ABPlayerKit
import ABPlayerKitControls
import AVFoundation
import SwiftUI

struct PlaybackScreen: View {
    let model: DemoModel
    @State private var selectedControlsStyle = DemoControlsStyle.default
    @State private var accessoryTapCount = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ABVideoPlayerWithControls(
                        player: model.player,
                        videoGravity: .resizeAspect,
                        style: selectedControlsStyle.style,
                        configuration: controlsConfiguration
                    ) {
                        // `@ViewBuilder accessories:` demonstration/verification
                        // vehicle: a plain SwiftUI button placed at the controls'
                        // right edge, next to the rate button, to exercise (and
                        // let a human tap-test) hit-test priority over the seek
                        // bar. See `DESIGN-OPEN-QUESTIONS.md` Q6-A.
                        Button {
                            accessoryTapCount += 1
                        } label: {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                        }
                    }
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .background(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

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

                    GroupBox("Now Playing") {
                        Toggle("Show on lock screen / Control Center", isOn: nowPlayingBinding)
                        Text("Publishes to MPNowPlayingInfoCenter only while this player is Current and this toggle is on.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Divider()
                            .padding(.vertical, 4)

                        Toggle("Extended commands", isOn: nowPlayingCommandsExtendedBinding)
                        Text("Adds next/previous track and playback rate to Control Center. Requires a supported-rates list and installed handlers, not just the command flags, so this toggle exercises all three at once.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        if model.nowPlayingCommandsExtended {
                            LabeledContent(
                                "Track navigation",
                                value: "Next: \(model.nextTrackCount) / Previous: \(model.previousTrackCount)"
                            )
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
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

                            Divider()
                                .padding(.vertical, 4)

                            Picker("Background policy", selection: backgroundPolicyBinding) {
                                ForEach(DemoBackgroundPolicy.allCases) { preset in
                                    Text(preset.title).tag(preset)
                                }
                            }
                            Text("Continue audio only needs a managed audio session and UIBackgroundModes = audio (already declared for this demo target) to keep playing once the app leaves the foreground. Selecting it also switches the audio session to managed if it wasn't already — background it on a real device to verify.")
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

    private var nowPlayingBinding: Binding<Bool> {
        Binding(
            get: { model.nowPlayingEnabled },
            set: { enabled in model.setNowPlayingEnabled(enabled) }
        )
    }

    private var nowPlayingCommandsExtendedBinding: Binding<Bool> {
        Binding(
            get: { model.nowPlayingCommandsExtended },
            set: { extended in model.setNowPlayingCommandsExtended(extended) }
        )
    }

    private var tuningBinding: Binding<DemoTuningPreset> {
        Binding(
            get: { model.selectedTuning },
            set: { tuning in model.setTuning(tuning) }
        )
    }

    private var backgroundPolicyBinding: Binding<DemoBackgroundPolicy> {
        Binding(
            get: { model.selectedBackgroundPolicy },
            set: { preset in model.setBackgroundPolicy(preset) }
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
