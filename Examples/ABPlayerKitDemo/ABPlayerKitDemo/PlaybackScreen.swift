import ABPlayerKit
import AVFoundation
import SwiftUI

struct PlaybackScreen: View {
    let model: DemoModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ABVideoPlayer(player: model.player, videoGravity: .resizeAspect)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .background(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

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
                        .disabled(model.grade != .preloaded)

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

    private var gradeBinding: Binding<ABPlaybackGrade> {
        Binding(
            get: { model.grade },
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
}
