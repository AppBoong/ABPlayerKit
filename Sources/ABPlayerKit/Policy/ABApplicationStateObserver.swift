import Foundation
import UIKit

/// Subscribes to app background/foreground transitions for a single
/// `ABPlayer` instance. No global/static observers (DESIGN-ABPlayerKit.md
/// §10, weakness #12) — each instance owns and tears down its own tokens.
@MainActor
public final class ABApplicationStateObserver {
    private var tokens: [NSObjectProtocol] = []
    private let center: NotificationCenter

    public init(
        center: NotificationCenter = .default,
        onBackground: @escaping @MainActor () -> Void,
        onForeground: @escaping @MainActor () -> Void
    ) {
        self.center = center
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

    public func invalidate() {
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
