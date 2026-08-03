import Foundation

/// Internal storage for `ABPlayer`'s multi-observer fan-out. Not part of the
/// public API — `ABPlayer.addObserver` is the only entry point.
///
/// Cancellation is expected to happen on the main actor, consistent with
/// every other type in this registry's call chain (`ABPlayer`,
/// `ABPlayerObserver`) being `@MainActor`. This is unrelated to — and does
/// not contradict — the design's prohibition on `MainActor.assumeIsolated`
/// for AVFoundation KVO/`NotificationCenter` callbacks, which arrive on
/// arbitrary threads; a consumer calling `token.cancel()` or letting a
/// `let token` go out of scope does so from its own main-actor code.
@MainActor
final class ABObserverRegistry {
    private var handlers: [UUID: (ABPlayer, ABPlayerEvent) -> Void] = [:]

    func add(_ handler: @escaping (ABPlayer, ABPlayerEvent) -> Void) -> ABObservationToken {
        let id = UUID()
        handlers[id] = handler
        return ABObservationToken { [weak self] in
            MainActor.assumeIsolated {
                self?.handlers[id] = nil
            }
        }
    }

    func broadcast(_ event: ABPlayerEvent, from player: ABPlayer) {
        for handler in handlers.values {
            handler(player, event)
        }
    }
}
