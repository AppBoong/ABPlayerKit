import Foundation

/// Generic multi-observer fan-out storage — every `ABPlayer` notification
/// channel (events, layer-attachment) is exactly this shape once the
/// payload is a single value (`ABPlayer.addObserver(_ observer:)` captures
/// `[weak self]` itself and calls `observer?.player(self, didEmit:)` rather
/// than threading the player through as a second payload value).
///
/// Not part of the public API — `ABPlayer.addObserver`/
/// `addLayerAttachmentObserver` are the only entry points.
///
/// Token cancellation can happen on any thread, so storage is lock-guarded
/// and removal is synchronous without assuming the caller's executor.
@MainActor
final class ABHandlerRegistry<Payload> {
    private final class HandlerBox: @unchecked Sendable {
        private let handler: @MainActor (Payload) -> Void

        init(_ handler: @escaping @MainActor (Payload) -> Void) {
            self.handler = handler
        }

        @MainActor
        func callAsFunction(_ payload: Payload) {
            handler(payload)
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

    func add(_ handler: @escaping @MainActor @Sendable (Payload) -> Void) -> ABObservationToken {
        let id = UUID()
        storage.insert(HandlerBox(handler), for: id)
        return ABObservationToken { [storage] in
            storage.remove(id)
        }
    }

    func broadcast(_ payload: Payload) {
        for handlerBox in storage.snapshot() {
            handlerBox(payload)
        }
    }
}
