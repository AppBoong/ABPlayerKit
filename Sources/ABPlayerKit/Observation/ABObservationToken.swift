import Foundation

/// A release-guaranteed subscription handle. Cancelling it — explicitly or
/// via `deinit` — unregisters the underlying observation, which structurally
/// rules out the "permanently registered stall observer" failure mode this
/// library's reference implementation had.
///
/// Marked `@unchecked Sendable` (rather than the plain `Sendable` sketched in
/// the design doc) because it guards a one-shot cancel with an internal
/// lock, matching `ABObservationBag`'s own "invalidate from any thread"
/// contract.
public final class ABObservationToken: @unchecked Sendable, Hashable {
    private let lock = NSLock()
    private var onCancel: (() -> Void)?

    /// Creates a token around an idempotent cancellation closure.
    ///
    /// Extension targets can use this initializer to expose observation APIs
    /// with the same lifetime contract as ABPlayerKit.
    public init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    public func cancel() {
        lock.lock()
        let action = onCancel
        onCancel = nil
        lock.unlock()
        action?()
    }

    /// Explicit storage API so a consumer who forgets to hold a `let`
    /// doesn't have the subscription die immediately.
    public func store(in set: inout Set<ABObservationToken>) {
        set.insert(self)
    }

    public static func == (lhs: ABObservationToken, rhs: ABObservationToken) -> Bool {
        lhs === rhs
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    deinit {
        cancel()
    }
}
