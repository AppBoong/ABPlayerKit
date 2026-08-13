import ABPlayerKit
import AVFoundation
import AVKit
import SwiftUI

/// Picker-friendly wrapper over `AVLayerVideoGravity`, mirroring
/// `DemoBackgroundPolicy` in `DemoModel.swift` — only the two gravities the
/// AirPlay checklist item asks a tester to compare.
enum DeviceExternalPlaybackGravity: String, CaseIterable, Identifiable {
    case aspect
    case aspectFill

    var id: Self { self }

    var title: String {
        switch self {
        case .aspect: "Aspect"
        case .aspectFill: "Aspect fill"
        }
    }

    var gravity: AVLayerVideoGravity {
        switch self {
        case .aspect: .resizeAspect
        case .aspectFill: .resizeAspectFill
        }
    }

    init(_ gravity: AVLayerVideoGravity) {
        self = gravity == .resizeAspectFill ? .aspectFill : .aspect
    }
}

/// Owns a player separate from `DemoModel.player`. This screen exists to
/// destroy its player while Picture in Picture is active (checklist item
/// 6) and to compare `startsAutomaticallyFromInline` against backgrounding
/// (checklist item 2) — neither should ever tear down the Playback tab's
/// own session, and binding one `ABPlayer` to two `ABPlayerView`s at once
/// invites contention.
@MainActor
@Observable
final class DeviceModel {
    let player: ABPlayer
    let pipSession = ABPictureInPictureSession()

    var selectedMedia = DemoMedia.hls
    var isPlaying = false
    /// Refreshed by `pollExternalPlaybackState()` — see that method for why
    /// this can't just be a computed passthrough to `player`.
    var isExternalPlaybackActive = false

    private var eventToken: ABObservationToken?

    init() {
        var configuration = ABPlayerConfiguration()
        // Picture in Picture and background continuation both need an
        // active playback audio session on a real device. The demo's
        // Info.plist already declares UIBackgroundModes = [audio].
        configuration.audioSessionPolicy = .playback(mixWithOthers: false)
        let player = ABPlayer(configuration: configuration)
        self.player = player
        eventToken = player.addObserver { [weak self] event in
            guard let self, case .timeControlStatusChanged(let status) = event else { return }
            self.isPlaying = status == .playing
        }
        // No set(source:grade:) here on purpose. TabView builds every tab's
        // content value — including this model's default — when the root
        // view's body is evaluated, so this initializer runs at app launch,
        // before the tester has ever opened this tab. Setting a source here
        // would start loading a network stream and activate the audio
        // session (both synchronous work) for a screen nobody asked for.
        // togglePlayback() sets the source lazily the first time Play is
        // pressed.
    }

    func togglePlayback() {
        guard player.grade == .current else {
            player.set(source: selectedMedia.source, grade: .current)
            player.play()
            return
        }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
    }

    /// One of the two check-6 paths that can destroy the player while PiP
    /// is active — replaces the current item outright via `set(source:
    /// grade:)` rather than merely pausing it.
    func swapSource() {
        selectedMedia = selectedMedia == .hls ? .mp4 : .hls
        player.set(source: selectedMedia.source, grade: .current)
        player.play()
    }

    /// The other check-6 path — calls `release()` directly.
    func releasePlayer() {
        player.release()
    }

    func setAllowsExternalPlayback(_ allowed: Bool) {
        var configuration = player.configuration
        guard configuration.allowsExternalPlayback != allowed else { return }
        configuration.allowsExternalPlayback = allowed
        player.configuration = configuration
    }

    func setUsesExternalPlaybackWhileExternalScreenIsActive(_ uses: Bool) {
        var configuration = player.configuration
        guard configuration.usesExternalPlaybackWhileExternalScreenIsActive != uses else { return }
        configuration.usesExternalPlaybackWhileExternalScreenIsActive = uses
        player.configuration = configuration
    }

    func setExternalPlaybackGravity(_ preset: DeviceExternalPlaybackGravity) {
        var configuration = player.configuration
        guard DeviceExternalPlaybackGravity(configuration.externalPlaybackVideoGravity) != preset else { return }
        configuration.externalPlaybackVideoGravity = preset.gravity
        player.configuration = configuration
    }

    /// `ABPlayer.isExternalPlaybackActive` re-reads the underlying
    /// `AVPlayer` on every access and is documented as not
    /// `@Observable`-tracked, so nothing re-renders this screen when
    /// AirPlay routing changes on its own. Polling twice a second is what
    /// makes the value visible without the tester having to background and
    /// foreground the app to force a redraw — this is the entire point of
    /// the checklist's AirPlay item, so a value frozen at `false` would
    /// make the check useless.
    func pollExternalPlaybackState() async {
        while !Task.isCancelled {
            isExternalPlaybackActive = player.isExternalPlaybackActive
            try? await Task.sleep(for: .milliseconds(500))
        }
    }
}

struct DeviceScreen: View {
    @State private var model = DeviceModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ABVideoPlayer(
                        player: model.player,
                        videoGravity: .resizeAspect,
                        pictureInPicture: model.pipSession
                    )
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .background(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    Text("No controls overlay here on purpose — Picture in Picture is supported only on this explicit-ownership initializer, not the ABVideoPlayerWithControls convenience API the Playback tab uses.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text("Black until you press Play. Nothing loads when this tab opens — the source is only set the first time you press Play — so opening this screen costs nothing.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

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

                    GroupBox("Picture in Picture") {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("isSupported", value: ABPictureInPictureSession.isSupported ? "true" : "false")
                            LabeledContent("isPossible", value: model.pipSession.isPossible ? "true" : "false")
                            LabeledContent("isActive", value: model.pipSession.isActive ? "true" : "false")
                            LabeledContent("lastFailure", value: model.pipSession.lastFailure?.description ?? "none")
                            LabeledContent("Player grade", value: model.player.grade.shortLabel)
                            LabeledContent("Playing", value: model.isPlaying ? "true" : "false")

                            Text("isSupported is false in Simulator — that's expected, not a bug. Real start/stop/active behavior can only be observed on a device.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            Divider()
                                .padding(.vertical, 4)

                            HStack {
                                Button("Start PiP") { model.pipSession.start() }
                                    .buttonStyle(.bordered)
                                Button("Stop PiP") { model.pipSession.stop() }
                                    .buttonStyle(.bordered)
                            }

                            Toggle("Auto PiP", isOn: autoPiPBinding)
                            Text("Backgrounding the app enters PiP automatically; returning to the foreground leaves PiP and resumes inline. Must be off for checklist item 6 — with it on, returning to the app to check on a floating PiP window stops PiP as a side effect, so the destroy-the-player action runs against a session that already stopped, and \"nothing happened\" reads as a false pass.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            Toggle("Requires linear playback", isOn: requiresLinearPlaybackBinding)
                        }
                    }

                    GroupBox("Audio session") {
                        Text("This screen's player uses audioSessionPolicy = .playback(mixWithOthers: false), separate from the Playback tab's session — Picture in Picture and background continuation both need an active playback session to keep working once the app leaves the foreground.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    GroupBox("AirPlay") {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Allows external playback", isOn: allowsExternalPlaybackBinding)
                            Toggle("Uses external playback while screen active", isOn: usesExternalPlaybackWhileExternalScreenIsActiveBinding)

                            Picker("External playback gravity", selection: externalPlaybackGravityBinding) {
                                ForEach(DeviceExternalPlaybackGravity.allCases) { preset in
                                    Text(preset.title).tag(preset)
                                }
                            }
                            .pickerStyle(.segmented)

                            LabeledContent("isExternalPlaybackActive", value: model.isExternalPlaybackActive ? "true" : "false")
                            Text("Polled twice a second — this property isn't Observable-tracked. A real AirPlay receiver is required to see it flip to true.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            // Collapsed by default: AVRoutePickerView() does
                            // synchronous XPC route discovery on creation.
                            // Building it eagerly here would put that cost
                            // back on the tab transition this screen exists
                            // to keep cheap — the DisclosureGroup defers
                            // instantiation until the tester deliberately
                            // expands it to check AirPlay routing.
                            DisclosureGroup("Route picker") {
                                HStack {
                                    Spacer()
                                    AirPlayRoutePickerView()
                                        .frame(width: 32, height: 32)
                                    Spacer()
                                }
                                .padding(.top, 4)
                            }
                        }
                    }

                    GroupBox("Destroy the player") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Both actions below destroy this screen's player, even while Picture in Picture is active — for checklist item 6. Swap source replaces the current item via set(source:grade:); Release calls player.release() directly.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            HStack {
                                Button("Swap source (\(model.selectedMedia == .hls ? "HLS → MP4" : "MP4 → HLS"))") {
                                    model.swapSource()
                                }
                                .buttonStyle(.bordered)

                                Button("Release player", role: .destructive) {
                                    model.releasePlayer()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Device")
        }
        .task {
            await model.pollExternalPlaybackState()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Symmetric with startsAutomaticallyFromInline's background
            // entry: gated on the Auto PiP toggle itself, not on whether
            // this particular PiP session happened to start automatically
            // or via the manual Start PiP button — the session doesn't
            // record which, and a tester who flips Auto PiP on after
            // starting PiP manually still expects returning to the
            // foreground to behave the same way. stop() is a no-op if PiP
            // already stopped itself (e.g. the tester used the PiP
            // window's own return button before the app finished
            // reactivating), so this can't race that path into a bad
            // state.
            guard newPhase == .active, model.pipSession.startsAutomaticallyFromInline, model.pipSession.isActive else { return }
            model.pipSession.stop()
        }
    }

    private var autoPiPBinding: Binding<Bool> {
        Binding(
            get: { model.pipSession.startsAutomaticallyFromInline },
            set: { model.pipSession.startsAutomaticallyFromInline = $0 }
        )
    }

    private var requiresLinearPlaybackBinding: Binding<Bool> {
        Binding(
            get: { model.pipSession.requiresLinearPlayback },
            set: { model.pipSession.requiresLinearPlayback = $0 }
        )
    }

    private var allowsExternalPlaybackBinding: Binding<Bool> {
        Binding(
            get: { model.player.configuration.allowsExternalPlayback },
            set: { model.setAllowsExternalPlayback($0) }
        )
    }

    private var usesExternalPlaybackWhileExternalScreenIsActiveBinding: Binding<Bool> {
        Binding(
            get: { model.player.configuration.usesExternalPlaybackWhileExternalScreenIsActive },
            set: { model.setUsesExternalPlaybackWhileExternalScreenIsActive($0) }
        )
    }

    private var externalPlaybackGravityBinding: Binding<DeviceExternalPlaybackGravity> {
        Binding(
            get: { DeviceExternalPlaybackGravity(model.player.configuration.externalPlaybackVideoGravity) },
            set: { model.setExternalPlaybackGravity($0) }
        )
    }
}

/// Lets the tester pick an AirPlay route without leaving the app — Control
/// Center works too, but staying in-app makes it easier to watch
/// `isExternalPlaybackActive` flip alongside the route change.
private struct AirPlayRoutePickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = true
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
