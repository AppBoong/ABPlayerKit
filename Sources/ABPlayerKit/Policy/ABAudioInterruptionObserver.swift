@preconcurrency import AVFoundation
import Foundation

/// Subscribes to `AVAudioSession` interruption and route-change
/// notifications for a single `ABPlayer` instance. Follows
/// `ABApplicationStateObserver`'s pattern (Policy/ABApplicationStateObserver.swift):
/// no global/static observers, each instance owns and tears down its own
/// tokens (DESIGN-ABPlayerKit.md §10, weakness #12).
///
/// Deliberately reads real `AVAudioSession.interruptionNotification`/
/// `routeChangeNotification` names and their real `userInfo` key/value
/// types (so production code observes the actual system notification), but
/// never calls `AVAudioSession.sharedInstance()` itself — tests inject a
/// private `NotificationCenter` and post fabricated `userInfo` dictionaries
/// instead of exercising the real, process-global audio session (round3
/// Phase4 WP10.5).
@MainActor
final class ABAudioInterruptionObserver {
    // `nonisolated(unsafe)`: NotificationCenter observer tokens are opaque,
    // thread-safe-to-hold reference types; `removeObserver` itself is safe
    // to call from any thread. Mirrors `ABApplicationStateObserver`.
    private nonisolated(unsafe) var tokens: [NSObjectProtocol] = []
    private let center: NotificationCenter

    init(
        center: NotificationCenter = .default,
        onInterruptionBegan: @escaping @MainActor @Sendable () -> Void,
        onInterruptionEnded: @escaping @MainActor @Sendable (_ shouldResume: Bool) -> Void,
        onRouteChangeDeviceUnavailable: @escaping @MainActor @Sendable () -> Void
    ) {
        self.center = center
        tokens.append(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: nil,
                queue: .main
            ) { notification in
                guard let userInfo = notification.userInfo,
                      let rawType = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
                switch type {
                case .began:
                    Task { @MainActor in onInterruptionBegan() }
                case .ended:
                    let rawOptions = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                    let shouldResume = AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume)
                    Task { @MainActor in onInterruptionEnded(shouldResume) }
                @unknown default:
                    break
                }
            }
        )
        tokens.append(
            center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: nil,
                queue: .main
            ) { notification in
                guard let userInfo = notification.userInfo,
                      let rawReason = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason),
                      reason == .oldDeviceUnavailable else { return }
                Task { @MainActor in onRouteChangeDeviceUnavailable() }
            }
        )
    }

    func invalidate() {
        for token in tokens {
            center.removeObserver(token)
        }
        tokens.removeAll()
    }

    deinit {
        for token in tokens {
            center.removeObserver(token)
        }
    }
}
