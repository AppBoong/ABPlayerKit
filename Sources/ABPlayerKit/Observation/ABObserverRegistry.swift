import Foundation

/// Internal storage for `ABPlayer`'s multi-observer fan-out. Not part of the
/// public API — `ABPlayer.addObserver` is the only entry point.
///
/// Token cancellation can happen on any thread, so storage is lock-guarded
/// and removal is synchronous without assuming the caller's executor.
@MainActor
final class ABObserverRegistry {
    private final class HandlerBox: @unchecked Sendable {
        private let handler: @MainActor (ABPlayer, ABPlayerEvent) -> Void

        init(_ handler: @escaping @MainActor (ABPlayer, ABPlayerEvent) -> Void) {
            self.handler = handler
        }

        @MainActor
        func callAsFunction(_ player: ABPlayer, _ event: ABPlayerEvent) {
            handler(player, event)
        }
    }

    private final class Storage: @unchecked Sendable {
        private let lock = NSLock()
        private var handlers: [UUID: HandlerBox] = [:]

        func insert(_ handler: HandlerBox, for id: UUID) {
            lock.lock()
            handlers[id] = handler
            lock.unlock()
        }

        func remove(_ id: UUID) {
            lock.lock()
            handlers[id] = nil
            lock.unlock()
        }

        func snapshot() -> [HandlerBox] {
            lock.lock()
            let snapshot = Array(handlers.values)
            lock.unlock()
            return snapshot
        }
    }

    private let storage = Storage()

    func add(_ handler: @escaping @MainActor @Sendable (ABPlayer, ABPlayerEvent) -> Void) -> ABObservationToken {
        let id = UUID()
        storage.insert(HandlerBox(handler), for: id)
        return ABObservationToken { [storage] in
            storage.remove(id)
        }
    }

    func broadcast(_ event: ABPlayerEvent, from player: ABPlayer) {
        for handlerBox in storage.snapshot() {
            handlerBox(player, event)
        }
    }
}
