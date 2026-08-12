@preconcurrency import AVKit
@preconcurrency import AVFoundation
import Observation

/// The originating subsystem of a Picture in Picture start failure, reduced
/// the same way ``ABErrorOrigin`` reduces every other AVFoundation-sourced
/// failure in this library.
public struct ABPictureInPictureFailure: Sendable, Equatable {
    public let description: String
    public let origin: ABErrorOrigin?

    public init(description: String, origin: ABErrorOrigin? = nil) {
        self.description = description
        self.origin = origin
    }
}

/// A Picture in Picture session bound to a single ``ABPlayerView``'s
/// backing `AVPlayerLayer`. Owns the `AVPictureInPictureController` for
/// that layer so the layer itself never needs to be exposed publicly.
///
/// While ``isActive`` is `true`, this session strongly holds its bound
/// view — PiP must keep rendering after the source view leaves the
/// SwiftUI/UIKit hierarchy, and the backing `AVPlayerLayer` is what PiP
/// actually renders from. The hold is released the moment ``isActive``
/// returns to `false`.
@MainActor
@Observable
public final class ABPictureInPictureSession {
    public init() {}

    /// Whether the current device/OS supports Picture in Picture at all.
    /// Usually `false` in the simulator.
    public static var isSupported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }

    /// Mirrors `AVPictureInPictureController.isPictureInPicturePossible`.
    /// `false` until the bound layer is `readyForDisplay`.
    public private(set) var isPossible = false
    /// Mirrors `AVPictureInPictureController.isPictureInPictureActive`.
    public private(set) var isActive = false
    /// The most recent start failure. Reset to `nil` at the start of every
    /// ``start()`` call.
    public private(set) var lastFailure: ABPictureInPictureFailure?

    /// Mirrors `canStartPictureInPictureAutomaticallyFromInline`. Default
    /// `false` — enabling it opts into the background-race repair path
    /// documented on ``ABBackgroundPolicy``.
    public var startsAutomaticallyFromInline = false {
        didSet {
            guard startsAutomaticallyFromInline != oldValue else { return }
            avController?.canStartPictureInPictureAutomaticallyFromInline = startsAutomaticallyFromInline
        }
    }
    /// Mirrors `AVPictureInPictureController.requiresLinearPlayback`.
    public var requiresLinearPlayback = false {
        didSet {
            guard requiresLinearPlayback != oldValue else { return }
            avController?.requiresLinearPlayback = requiresLinearPlayback
        }
    }

    /// Called when PiP is stopping and the original UI needs to be
    /// restored. Return `true` on success. Leaving this unset is treated
    /// as always succeeding.
    public var restoreUserInterfaceHandler: (@MainActor () async -> Bool)?

    /// Escape hatch for delegate/knob access this type doesn't otherwise
    /// cover. Reassigning `controller.delegate` stops ``lastFailure`` and
    /// ``restoreUserInterfaceHandler`` from being driven —
    /// ``isPossible``/``isActive`` are KVO-based and unaffected.
    public var controller: AVPictureInPictureController? { avController }

    @ObservationIgnored
    private var avController: AVPictureInPictureController?
    @ObservationIgnored
    private var delegateProxy: ABPictureInPictureDelegateProxy?
    @ObservationIgnored
    private var possibleObservation: NSKeyValueObservation?
    @ObservationIgnored
    private var activeObservation: NSKeyValueObservation?
    /// The view currently wired to `avController`. `nil` when unbound.
    /// `weak` — this session does not keep a view alive on its own; only
    /// ``retainedView`` does, and only while ``isActive`` is `true`.
    @ObservationIgnored
    private(set) weak var boundView: ABPlayerView?
    /// Strong hold kept only while ``isActive`` is `true` — see this
    /// type's doc comment.
    @ObservationIgnored
    private var retainedView: ABPlayerView?
    /// Set when `unbind(from:)` arrives while still active; completed once
    /// ``isActive`` returns to `false`.
    @ObservationIgnored
    private var pendingUnbind = false

    public func start() {
        lastFailure = nil
        avController?.startPictureInPicture()
    }

    public func stop() {
        avController?.stopPictureInPicture()
    }

    // MARK: - Internal binding API (used exclusively by `ABPlayerView`)

    /// Wires this session to `view`'s backing layer. If already bound to a
    /// different, inactive view, that binding is torn down first. If the
    /// other view's binding is active, the request is ignored and recorded
    /// in ``lastFailure`` — a session binds to at most one view at a time.
    func bind(to view: ABPlayerView, layer: AVPlayerLayer) {
        if let boundView, boundView !== view {
            guard !isActive else {
                lastFailure = ABPictureInPictureFailure(
                    description: "This session is already active for a different view."
                )
                return
            }
            tearDownController()
        } else if boundView === view, avController != nil {
            return
        }
        boundView = view
        pendingUnbind = false
        setUpController(for: layer)
    }

    /// Requests unbinding `view`. While active, teardown is deferred until
    /// ``isActive`` returns to `false` — the strong hold above is what
    /// keeps `view` alive in the meantime.
    func unbind(from view: ABPlayerView) {
        guard boundView === view else { return }
        guard !isActive else {
            pendingUnbind = true
            return
        }
        tearDownController()
        boundView = nil
    }

    // MARK: - Private

    private func setUpController(for layer: AVPlayerLayer) {
        guard let newController = AVPictureInPictureController(playerLayer: layer) else {
            avController = nil
            updateIsPossible(false)
            return
        }
        newController.canStartPictureInPictureAutomaticallyFromInline = startsAutomaticallyFromInline
        newController.requiresLinearPlayback = requiresLinearPlayback

        let proxy = ABPictureInPictureDelegateProxy()
        proxy.onFailure = { [weak self] failure in self?.lastFailure = failure }
        proxy.onRestoreUserInterface = { [weak self] in
            guard let handler = self?.restoreUserInterfaceHandler else { return true }
            return await handler()
        }
        newController.delegate = proxy

        avController = newController
        delegateProxy = proxy

        possibleObservation = newController.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] observed, _ in
            let value = observed.isPictureInPicturePossible
            Task { @MainActor in
                guard let self, self.avController === observed else { return }
                self.updateIsPossible(value)
            }
        }
        activeObservation = newController.observe(\.isPictureInPictureActive, options: [.initial, .new]) { [weak self] observed, _ in
            let value = observed.isPictureInPictureActive
            Task { @MainActor in
                guard let self, self.avController === observed else { return }
                self.updateIsActive(value)
            }
        }
    }

    private func tearDownController() {
        possibleObservation?.invalidate()
        possibleObservation = nil
        activeObservation?.invalidate()
        activeObservation = nil
        avController?.delegate = nil
        avController = nil
        delegateProxy = nil
        updateIsPossible(false)
    }

    /// Not `private` — driven directly by unit tests standing in for KVO,
    /// which the simulator's usual lack of PiP support otherwise never
    /// exercises.
    func updateIsPossible(_ newValue: Bool) {
        guard newValue != isPossible else { return }
        isPossible = newValue
    }

    /// Not `private` — see ``updateIsPossible(_:)``.
    func updateIsActive(_ newValue: Bool) {
        guard newValue != isActive else { return }
        isActive = newValue
        if newValue {
            retainedView = boundView
        }
        boundView?.player?.setPictureInPictureActive(newValue)
        guard !newValue else { return }
        retainedView = nil
        if pendingUnbind {
            pendingUnbind = false
            tearDownController()
            boundView = nil
        }
    }
}

/// `AVPictureInPictureControllerDelegate` conformer kept as a separate
/// `NSObject` (rather than ``ABPictureInPictureSession`` itself conforming)
/// so a consumer who reassigns `controller.delegate` cleanly detaches this
/// type's failure/restore wiring without disturbing anything else.
@MainActor
private final class ABPictureInPictureDelegateProxy: NSObject, @preconcurrency AVPictureInPictureControllerDelegate {
    var onFailure: ((ABPictureInPictureFailure) -> Void)?
    var onRestoreUserInterface: (() async -> Bool)?

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: any Error
    ) {
        let nsError = error as NSError
        onFailure?(ABPictureInPictureFailure(
            description: nsError.localizedDescription,
            origin: ABErrorOrigin(domain: nsError.domain, code: nsError.code)
        ))
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        guard let onRestoreUserInterface else {
            completionHandler(true)
            return
        }
        Task { @MainActor in
            let restored = await onRestoreUserInterface()
            completionHandler(restored)
        }
    }
}
