import Foundation

/// Collects invalidation closures (KVO observations, `NotificationCenter`
/// tokens, `ABObservationToken`s, ...) and tears every one of them down
/// together, from `release()`/`deinit` — either can run on any thread, so
/// this type is deliberately **not** actor-isolated (DESIGN-ABPlayerKit.md
/// §3).
final class ABObservationBag: @unchecked Sendable {
    private let lock = NSLock()
    private var invalidators: [() -> Void] = []

    init() {}

    func add(_ invalidate: @escaping () -> Void) {
        lock.lock()
        invalidators.append(invalidate)
        lock.unlock()
    }

    func invalidateAll() {
        lock.lock()
        let pending = invalidators
        invalidators.removeAll()
        lock.unlock()
        for invalidate in pending {
            invalidate()
        }
    }

    deinit {
        invalidateAll()
    }
}
