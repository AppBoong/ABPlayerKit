import Foundation
import UIKit

/// Subscribes to app background/foreground transitions for a single
/// `ABPlayer` instance. No global/static observers — each instance owns
/// and tears down its own tokens.
///
/// Handlers run **synchronously**, inside the notification dispatch, via
/// `MainActor.assumeIsolated` rather than a `Task` hop. This is load-bearing
/// for ``ABBackgroundPolicy/continueAudioOnly``: keeping audio alive in the
/// background requires clearing `AVPlayerLayer.player` *while handling*
/// `didEnterBackgroundNotification`. Deferring that by even one main-actor
/// turn lets AVFoundation stop the still-attached player first, after which
/// nothing is playing, iOS grants no audio assertion, and the process is
/// suspended seconds later. `willResignActive` has the same requirement for
/// a different reason — it captures the live `isPlaying` value, which decode
/// teardown would have already falsified by the next turn.
///
/// `assumeIsolated` cannot trap here: `addObserver(forName:object:queue:)`
/// with `queue: .main` always runs the block on the main thread.
@MainActor
final class ABApplicationStateObserver {
    // `nonisolated(unsafe)`: NotificationCenter observer tokens are opaque,
    // thread-safe-to-hold reference types; `removeObserver` itself is safe
    // to call from any thread. This lets `deinit` (always nonisolated) tear
    // them down without requiring `[any NSObjectProtocol]` to be `Sendable`.
    private nonisolated(unsafe) var tokens: [NSObjectProtocol] = []
    private let center: NotificationCenter

    init(
        center: NotificationCenter = .default,
        onWillResignActive: @escaping @MainActor @Sendable () -> Void = {},
        onBackground: @escaping @MainActor @Sendable () -> Void,
        onForeground: @escaping @MainActor @Sendable () -> Void
    ) {
        self.center = center
        tokens.append(
            center.addObserver(
                forName: UIApplication.willResignActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated { onWillResignActive() }
            }
        )
        tokens.append(
            center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated { onBackground() }
            }
        )
        tokens.append(
            center.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated { onForeground() }
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
