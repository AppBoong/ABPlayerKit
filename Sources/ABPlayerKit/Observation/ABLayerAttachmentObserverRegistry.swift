import Foundation

@MainActor
final class ABLayerAttachmentObserverRegistry {
    private final class HandlerBox: @unchecked Sendable {
        private let handler: @MainActor (Bool) -> Void

        init(_ handler: @escaping @MainActor (Bool) -> Void) {
            self.handler = handler
        }

        @MainActor
        func callAsFunction(_ isEnabled: Bool) {
            handler(isEnabled)
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

    func add(_ handler: @escaping @MainActor @Sendable (Bool) -> Void) -> ABObservationToken {
        let id = UUID()
        storage.insert(HandlerBox(handler), for: id)
        return ABObservationToken { [storage] in
            storage.remove(id)
        }
    }

    func broadcast(_ isEnabled: Bool) {
        for handlerBox in storage.snapshot() {
            handlerBox(isEnabled)
        }
    }
}
