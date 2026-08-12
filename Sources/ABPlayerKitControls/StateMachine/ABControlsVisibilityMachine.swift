import Foundation

struct ABControlsVisibilityMachine: Equatable {
    enum Visibility: Equatable {
        case visible
        case hidden
    }

    enum Input: Equatable {
        case attached(initial: Visibility)
        case tapped
        case controlInteracted
        case scrubBegan
        case scrubEnded
        case playbackStateChanged(isPlaying: Bool)
        case bufferingChanged(Bool)
        case autoHideFired
        case setVisible(Bool)
        case configurationChanged(autoHideDelay: TimeInterval?, staysVisibleWhilePaused: Bool)
        case detached
    }

    enum Effect: Equatable {
        case show
        case hide
        case scheduleAutoHide(after: TimeInterval)
        case cancelAutoHide
        case notifyVisibility(Bool)
    }

    private(set) var visibility: Visibility = .hidden
    private(set) var isScrubbing = false
    private(set) var isBuffering = false
    private(set) var isPlaying = false
    private(set) var autoHideDelay: TimeInterval? = 3
    private(set) var staysVisibleWhilePaused = true

    mutating func handle(_ input: Input) -> [Effect] {
        switch input {
        case .attached(let initial):
            visibility = initial
            let visible = initial == .visible
            var effects: [Effect] = [visible ? .show : .hide, .notifyVisibility(visible)]
            effects.append(contentsOf: scheduleEffectsIfNeeded())
            return effects

        case .tapped:
            if visibility == .hidden {
                visibility = .visible
                return [.show, .notifyVisibility(true)] + scheduleEffectsIfNeeded()
            }
            visibility = .hidden
            return [.cancelAutoHide, .hide, .notifyVisibility(false)]

        case .controlInteracted:
            return [.cancelAutoHide] + scheduleEffectsIfNeeded()

        case .scrubBegan:
            isScrubbing = true
            if visibility == .hidden {
                visibility = .visible
                return [.cancelAutoHide, .show, .notifyVisibility(true)]
            }
            return [.cancelAutoHide]

        case .scrubEnded:
            isScrubbing = false
            return scheduleEffectsIfNeeded()

        case .playbackStateChanged(let isPlaying):
            self.isPlaying = isPlaying
            if isPlaying {
                return scheduleEffectsIfNeeded()
            }
            if staysVisibleWhilePaused {
                return [.cancelAutoHide]
            }
            return scheduleEffectsIfNeeded()

        case .bufferingChanged(let buffering):
            isBuffering = buffering
            return buffering ? [.cancelAutoHide] : scheduleEffectsIfNeeded()

        case .autoHideFired:
            guard visibility == .visible,
                  !isScrubbing,
                  !isBuffering,
                  isPlaying || !staysVisibleWhilePaused else { return [] }
            visibility = .hidden
            return [.hide, .notifyVisibility(false)]

        case .setVisible(let visible):
            let newVisibility: Visibility = visible ? .visible : .hidden
            guard visibility != newVisibility else { return [] }
            visibility = newVisibility
            if visible {
                return [.cancelAutoHide, .show, .notifyVisibility(true)] + scheduleEffectsIfNeeded()
            }
            return [.cancelAutoHide, .hide, .notifyVisibility(false)]

        case .configurationChanged(let delay, let staysVisible):
            autoHideDelay = delay
            staysVisibleWhilePaused = staysVisible
            return [.cancelAutoHide] + scheduleEffectsIfNeeded()

        case .detached:
            isScrubbing = false
            isBuffering = false
            return [.cancelAutoHide]
        }
    }

    private func scheduleEffectsIfNeeded() -> [Effect] {
        guard visibility == .visible,
              !isScrubbing,
              !isBuffering,
              isPlaying || !staysVisibleWhilePaused,
              let autoHideDelay else { return [] }
        return [.scheduleAutoHide(after: autoHideDelay)]
    }
}
