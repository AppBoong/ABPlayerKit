import Foundation
@testable import ABPlayerKitNowPlaying

/// Records every call `ABNowPlayingCenter` makes, without touching
/// `MediaPlayer` — the seam that lets ownership/publishing/routing be
/// verified by "what would we have told the real surface to do" instead of
/// an actual lock screen.
@MainActor
final class ABFakeNowPlayingSurface: ABNowPlayingSurface {
    enum Call: Equatable {
        case setInfo([String: String])
        case setCommand(ABRemoteCommandKey, enabled: Bool, hasHandler: Bool)
        case restoreCommandEnablement([ABRemoteCommandKey: Bool])
        case setSkipInterval(TimeInterval)
        case setSupportedPlaybackRates([Float])
    }

    private(set) var calls: [Call] = []
    private(set) var setInfoCallCount = 0
    private(set) var lastInfo: [String: Any]?
    private(set) var handlers: [ABRemoteCommandKey: @MainActor (ABRemoteCommandIntent) -> ABRemoteCommandOutcome] = [:]
    private(set) var enablement: [ABRemoteCommandKey: Bool] = [:]

    var preSeededInfo: [String: Any]?
    var preSeededCommandEnablement: [ABRemoteCommandKey: Bool] = [:]

    func snapshotInfo() -> [String: Any]? {
        preSeededInfo
    }

    func setInfo(_ info: [String: Any]?) {
        setInfoCallCount += 1
        lastInfo = info
        // Reduced to `[String: String]` for `Equatable` call-log
        // comparisons — the values that matter for these tests
        // (title/elapsed/rate/etc.) all stringify losslessly enough to
        // assert against; `MPMediaItemArtwork` doesn't conform to
        // `Equatable` at all.
        let reduced = (info ?? [:]).reduce(into: [String: String]()) { partial, entry in
            partial[entry.key] = "\(entry.value)"
        }
        calls.append(.setInfo(reduced))
    }

    func snapshotCommandEnablement() -> [ABRemoteCommandKey: Bool] {
        preSeededCommandEnablement
    }

    func setCommand(
        _ key: ABRemoteCommandKey,
        enabled: Bool,
        handler: (@MainActor (ABRemoteCommandIntent) -> ABRemoteCommandOutcome)?
    ) {
        calls.append(.setCommand(key, enabled: enabled, hasHandler: handler != nil))
        enablement[key] = enabled
        handlers[key] = handler
    }

    func restoreCommandEnablement(_ snapshot: [ABRemoteCommandKey: Bool]) {
        calls.append(.restoreCommandEnablement(snapshot))
        enablement = snapshot
        handlers.removeAll()
    }

    func setSkipInterval(_ interval: TimeInterval) {
        calls.append(.setSkipInterval(interval))
    }

    func setSupportedPlaybackRates(_ rates: [Float]) {
        calls.append(.setSupportedPlaybackRates(rates))
    }

    /// Test helper — simulates the system invoking a previously-installed
    /// command's target, the same way pressing a lock-screen button would.
    func trigger(_ key: ABRemoteCommandKey, intent: ABRemoteCommandIntent) -> ABRemoteCommandOutcome? {
        handlers[key]?(intent)
    }
}
