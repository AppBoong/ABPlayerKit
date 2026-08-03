import Foundation

/// Internal storage for `ABPlayer`'s multi-observer fan-out. Not part of the
/// public API — `ABPlayer.addObserver` is the only entry point.
///
/// Token cancellation can happen on any thread, so removal always hops to
/// the main actor instead of assuming the caller's executor.
@MainActor
final class ABObserverRegistry {
    private var handlers: [UUID: (ABPlayer, ABPlayerEvent) -> Void] = [:]

    func add(_ handler: @escaping (ABPlayer, ABPlayerEvent) -> Void) -> ABObservationToken {
        let id = UUID()
        handlers[id] = handler
        return ABObservationToken { [weak self] in
            Task { @MainActor in
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
