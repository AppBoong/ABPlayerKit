import ABPlayerKit
import Foundation

@MainActor
final class ABControlsObserverRegistry {
    private final class HandlerBox: @unchecked Sendable {
        private let handler: @MainActor (ABControlsEvent) -> Void

        init(_ handler: @escaping @MainActor (ABControlsEvent) -> Void) {
            self.handler = handler
        }

        @MainActor
        func callAsFunction(_ event: ABControlsEvent) {
            handler(event)
        }
    }

    private final class Storage: @unchecked Sendable {
        private let lock = NSLock()
        private var handlers: [UUID: HandlerBox] = [:]

        func insert(_ handler: HandlerBox, id: UUID) {
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

    func add(
        _ handler: @escaping @MainActor @Sendable (ABControlsEvent) -> Void
    ) -> ABObservationToken {
        let id = UUID()
        storage.insert(HandlerBox(handler), id: id)
        return ABObservationToken { [storage] in storage.remove(id) }
    }

    func broadcast(_ event: ABControlsEvent) {
        for handler in storage.snapshot() {
            handler(event)
        }
    }
}
