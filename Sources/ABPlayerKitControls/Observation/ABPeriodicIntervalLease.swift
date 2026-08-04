import ABPlayerKit
import Foundation

final class ABPeriodicIntervalLease: @unchecked Sendable {
    private let lock = NSLock()
    private var hasRestored = false
    private let restoreAction: @MainActor @Sendable () -> Void

    @MainActor
    init(player: ABPlayer, previousInterval: TimeInterval?) {
        restoreAction = { [weak player] in
            player?.configuration.periodicTimeInterval = previousInterval
        }
    }

    @MainActor
    func restore() {
        guard claimRestore() else { return }
        restoreAction()
    }

    private func claimRestore() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !hasRestored else { return false }
        hasRestored = true
        return true
    }

    deinit {
        guard claimRestore() else { return }
        let restoreAction = restoreAction
        Task { @MainActor in restoreAction() }
    }
}
