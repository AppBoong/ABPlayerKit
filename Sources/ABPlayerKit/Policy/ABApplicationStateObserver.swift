import Foundation
import UIKit

/// Subscribes to app background/foreground transitions for a single
/// `ABPlayer` instance. No global/static observers — each instance owns
/// and tears down its own registration.
///
/// Handlers run **synchronously**, inside the notification's own dispatch.
/// That is load-bearing for ``ABBackgroundPolicy/continueAudioOnly``: keeping
/// audio alive in the background requires clearing `AVPlayerLayer.player`
/// *while handling* `didEnterBackgroundNotification`. Deferring it by even
/// one main-actor turn lets AVFoundation stop the still-attached player
/// first, after which nothing is playing, iOS grants no audio assertion, and
/// the process is suspended seconds later. `willResignActive` has the same
/// requirement for a different reason — it captures the live `isPlaying`
/// value, which decode teardown would have already falsified by the next
/// turn.
///
/// Hence the selector-based registration rather than the closure-and-queue
/// form: `NotificationCenter` invokes a selector directly, on the posting
/// thread, as part of `post(name:)`. The closure form cannot express this
/// without assuming isolation, which this project prohibits — and its
/// `queue:` parameter buys nothing here, since a queue hop is the very
/// thing that breaks the feature.
///
/// The three notifications this observes are posted by `UIApplication` on
/// the main thread, so the selectors run there. Tests drive them through an
/// injected center from a `@MainActor` context, which holds the same
/// guarantee.
@MainActor
final class ABApplicationStateObserver: NSObject {
    private let center: NotificationCenter
    private let onWillResignActive: @MainActor () -> Void
    private let onBackground: @MainActor () -> Void
    private let onForeground: @MainActor () -> Void

    init(
        center: NotificationCenter = .default,
        onWillResignActive: @escaping @MainActor @Sendable () -> Void = {},
        onBackground: @escaping @MainActor @Sendable () -> Void,
        onForeground: @escaping @MainActor @Sendable () -> Void
    ) {
        self.center = center
        self.onWillResignActive = onWillResignActive
        self.onBackground = onBackground
        self.onForeground = onForeground
        super.init()
        center.addObserver(
            self,
            selector: #selector(applicationWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(applicationDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(applicationWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @objc private func applicationWillResignActive() {
        onWillResignActive()
    }

    @objc private func applicationDidEnterBackground() {
        onBackground()
    }

    @objc private func applicationWillEnterForeground() {
        onForeground()
    }

    func invalidate() {
        center.removeObserver(self)
    }

    deinit {
        center.removeObserver(self)
    }
}
