@preconcurrency import AVFoundation
import Foundation

/// Watches `AVPlayerLayer.isReadyForDisplay` and `AVPlayerItem.status`
/// together and reports the first moment both are true for the *current*
/// item — the TTFF (time-to-first-frame) end point.
///
/// The AND-decision itself is a pure, fully unit-testable function
/// (`shouldReport`); only the KVO wiring around it needs a live
/// `AVPlayerLayer`/`AVPlayerItem` and is exercised by the demo app instead.
@MainActor
final class ABFirstFrameDetector {
    /// `reportedItem`/`currentItem` are `ObjectIdentifier`s rather than the
    /// items themselves so this stays a plain value comparison — no
    /// `AVFoundation` types cross into the pure decision.
    static func shouldReport(
        layerReady: Bool,
        itemStatus: ABItemStatus,
        reportedItem: ObjectIdentifier?,
        currentItem: ObjectIdentifier?
    ) -> Bool {
        guard layerReady, itemStatus == .readyToPlay, let currentItem else { return false }
        return reportedItem != currentItem
    }

    private let bag = ABObservationBag()
    private let onReport: (CFTimeInterval) -> Void

    private var layerReady = false
    private var itemStatus: ABItemStatus = .unknown
    private var reportedItem: ObjectIdentifier?
    private weak var observedItem: AVPlayerItem?

    init(onReport: @escaping (CFTimeInterval) -> Void) {
        self.onReport = onReport
    }

    /// Starts observing `layer`/`item` for this player attachment. Callers
    /// must `invalidate()` first when swapping players so the previous
    /// item's observations are torn down before the new ones are set up.
    func observe(layer: AVPlayerLayer, item: AVPlayerItem?) {
        layerReady = false
        itemStatus = .unknown
        observedItem = item

        let layerObservation = layer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
            // Capture the timestamp on the callback thread immediately —
            // queue-hopping delay must not leak into the TTFF measurement.
            let ready = layer.isReadyForDisplay
            let time = CACurrentMediaTime()
            Task { @MainActor [weak self] in
                self?.handleLayerReady(ready, at: time, expectedItem: item)
            }
        }
        bag.add { layerObservation.invalidate() }

        guard let item else { return }
        let statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] observedItem, _ in
            let status = ABItemStatus(observedItem.status)
            let time = CACurrentMediaTime()
            Task { @MainActor [weak self] in
                self?.handleItemStatus(status, at: time, expectedItem: item)
            }
        }
        bag.add { statusObservation.invalidate() }
    }

    func invalidate() {
        bag.invalidateAll()
        layerReady = false
        itemStatus = .unknown
        reportedItem = nil
        observedItem = nil
    }

    private func handleLayerReady(_ ready: Bool, at time: CFTimeInterval, expectedItem: AVPlayerItem?) {
        // Re-validate after the hop: the layer may already be showing a
        // different item by the time we land on the main actor.
        guard observedItem === expectedItem else { return }
        layerReady = ready
        evaluate(at: time)
    }

    private func handleItemStatus(_ status: ABItemStatus, at time: CFTimeInterval, expectedItem: AVPlayerItem?) {
        guard observedItem === expectedItem else { return }
        itemStatus = status
        evaluate(at: time)
    }

    private func evaluate(at time: CFTimeInterval) {
        let currentIdentity = observedItem.map(ObjectIdentifier.init)
        guard Self.shouldReport(
            layerReady: layerReady,
            itemStatus: itemStatus,
            reportedItem: reportedItem,
            currentItem: currentIdentity
        ) else { return }
        reportedItem = currentIdentity
        onReport(time)
    }
}

private extension ABItemStatus {
    init(_ status: AVPlayerItem.Status) {
        switch status {
        case .unknown: self = .unknown
        case .readyToPlay: self = .readyToPlay
        case .failed: self = .failed
        @unknown default: self = .unknown
        }
    }
}
