/// The three app-lifecycle moments `ABPlayer` reacts to. `willResignActive`
/// fires strictly before `didEnterBackground` (a platform-level guarantee),
/// which is what lets the "was this player playing before backgrounding"
/// capture happen earlier than the pause/detach/demote side effects
/// themselves — by the time `didEnterBackground` fires, decode may already
/// have stopped and `isPlaying` would read `false`.
enum ABAppLifecycleSignal: Equatable {
    case willResignActive
    case didEnterBackground
    case willEnterForeground
}

/// One step `ABBackgroundPolicyMachine` prescribes for a lifecycle signal.
/// Pure data — `ABPlayer` interprets these against its own live state.
enum ABBackgroundAction: Equatable {
    case capturePlaying
    case pause
    case setLayerAttachment(Bool)
    case demoteToInstance
    case restoreCapturedGrade
    /// Resolved as `self.play()` (not a direct target call) so a resume
    /// after backgrounding still routes through audio session reactivation.
    case resumePlay
    case markAudioSessionDirty
    case clearCapture
}

/// Turns an `(ABAppLifecycleSignal, ABBackgroundPolicy)` pair into the
/// ordered actions `ABPlayer` should perform. Pure — no `AVFoundation`/
/// `UIKit` import, no state, table-testable the same way `ABGradePlanner`
/// is.
struct ABBackgroundPolicyMachine: Sendable {
    func actions(
        for signal: ABAppLifecycleSignal,
        policy: ABBackgroundPolicy,
        grade: ABPlaybackGrade,
        wasPlayingBeforeBackground: Bool,
        hasCapturedGrade: Bool
    ) -> [ABBackgroundAction] {
        switch signal {
        case .willResignActive:
            return willResignActiveActions(policy: policy)
        case .didEnterBackground:
            return didEnterBackgroundActions(policy: policy, grade: grade)
        case .willEnterForeground:
            return willEnterForegroundActions(
                policy: policy,
                grade: grade,
                wasPlayingBeforeBackground: wasPlayingBeforeBackground,
                hasCapturedGrade: hasCapturedGrade
            )
        }
    }

    private func willResignActiveActions(policy: ABBackgroundPolicy) -> [ABBackgroundAction] {
        switch policy {
        case .ignore, .demoteToInstance:
            return []
        case .pause, .pauseAndDetachLayer:
            return [.capturePlaying]
        }
    }

    private func didEnterBackgroundActions(
        policy: ABBackgroundPolicy,
        grade: ABPlaybackGrade
    ) -> [ABBackgroundAction] {
        switch policy {
        case .ignore:
            return []
        case .pause:
            return grade == .current ? [.pause] : []
        case .pauseAndDetachLayer:
            return (grade == .current ? [.pause] : []) + [.setLayerAttachment(false)]
        case .demoteToInstance:
            return [.demoteToInstance]
        }
    }

    private func willEnterForegroundActions(
        policy: ABBackgroundPolicy,
        grade: ABPlaybackGrade,
        wasPlayingBeforeBackground: Bool,
        hasCapturedGrade: Bool
    ) -> [ABBackgroundAction] {
        // The system may have deactivated the audio session while
        // backgrounded regardless of `policy` — unconditional, even under
        // `.ignore`, so a later `play()` reactivates instead of being
        // skipped by the dirty-flag optimization.
        var actions: [ABBackgroundAction] = [.markAudioSessionDirty]
        switch policy {
        case .ignore:
            break
        case .pause:
            if grade == .current && wasPlayingBeforeBackground {
                actions.append(.resumePlay)
            }
            actions.append(.clearCapture)
        case .pauseAndDetachLayer:
            actions.append(.setLayerAttachment(true))
            if grade == .current && wasPlayingBeforeBackground {
                actions.append(.resumePlay)
            }
            actions.append(.clearCapture)
        case .demoteToInstance:
            if hasCapturedGrade {
                actions.append(.restoreCapturedGrade)
            }
        }
        return actions
    }
}
