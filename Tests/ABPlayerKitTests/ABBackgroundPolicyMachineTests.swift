import Foundation
import Testing
@testable import ABPlayerKit

/// Table coverage for `ABBackgroundPolicyMachine` — every
/// `(signal, policy, grade, wasPlayingBeforeBackground)` combination the
/// background/foreground lifecycle fixes depend on. Pure logic, no
/// `AVFoundation`/`UIKit`, exactly like `ABGradePlannerTests`.
@Suite("ABBackgroundPolicyMachine reduces lifecycle signals to actions")
struct ABBackgroundPolicyMachineTests {
    private let machine = ABBackgroundPolicyMachine()
    private let policies: [ABBackgroundPolicy] = [.ignore, .pause, .pauseAndDetachLayer, .demoteToInstance]
    private let grades: [ABPlaybackGrade] = [.released, .instanceOnly, .preloaded, .current]

    @Test("willResignActive only captures isPlaying for .pause/.pauseAndDetachLayer")
    func willResignActiveCapturesOnlyForPausingPolicies() {
        for policy in policies {
            let actions = machine.actions(
                for: .willResignActive,
                policy: policy,
                grade: .current,
                wasPlayingBeforeBackground: false,
                hasCapturedGrade: false
            )
            switch policy {
            case .pause, .pauseAndDetachLayer:
                #expect(actions == [.capturePlaying], "\(policy)")
            case .ignore, .demoteToInstance:
                #expect(actions.isEmpty, "\(policy)")
            }
        }
    }

    @Test("didEnterBackground pauses only when .current, detaches the layer only under .pauseAndDetachLayer, demotes unconditionally under .demoteToInstance", arguments: [
        ABPlaybackGrade.released, .instanceOnly, .preloaded, .current
    ])
    func didEnterBackgroundActionsMatchPolicy(grade: ABPlaybackGrade) {
        for policy in policies {
            let actions = machine.actions(
                for: .didEnterBackground,
                policy: policy,
                grade: grade,
                wasPlayingBeforeBackground: false,
                hasCapturedGrade: false
            )
            switch policy {
            case .ignore:
                #expect(actions.isEmpty, "\(policy)/\(grade)")
            case .pause:
                #expect(actions == (grade == .current ? [.pause] : []), "\(policy)/\(grade)")
            case .pauseAndDetachLayer:
                let expected: [ABBackgroundAction] = (grade == .current ? [.pause] : []) + [.setLayerAttachment(false)]
                #expect(actions == expected, "\(policy)/\(grade)")
            case .demoteToInstance:
                #expect(actions == [.demoteToInstance], "\(policy)/\(grade)")
            }
        }
    }

    @Test("willEnterForeground always marks the audio session dirty, even under .ignore")
    func willEnterForegroundAlwaysMarksAudioSessionDirty() {
        for policy in policies {
            let actions = machine.actions(
                for: .willEnterForeground,
                policy: policy,
                grade: .current,
                wasPlayingBeforeBackground: false,
                hasCapturedGrade: false
            )
            #expect(actions.first == .markAudioSessionDirty, "\(policy)")
        }
    }

    @Test("willEnterForeground resumes play only when .current and wasPlayingBeforeBackground, and always clears the capture", arguments: [
        (ABPlaybackGrade.current, true), (.current, false), (.preloaded, true), (.instanceOnly, false)
    ])
    func willEnterForegroundResumesConditionally(grade: ABPlaybackGrade, wasPlaying: Bool) {
        for policy in [ABBackgroundPolicy.pause, .pauseAndDetachLayer] {
            let actions = machine.actions(
                for: .willEnterForeground,
                policy: policy,
                grade: grade,
                wasPlayingBeforeBackground: wasPlaying,
                hasCapturedGrade: false
            )
            let shouldResume = grade == .current && wasPlaying
            #expect(actions.contains(.resumePlay) == shouldResume, "\(policy)/\(grade)/\(wasPlaying)")
            #expect(actions.contains(.clearCapture), "\(policy)/\(grade)/\(wasPlaying)")
            if policy == .pauseAndDetachLayer {
                #expect(actions.contains(.setLayerAttachment(true)), "\(policy)")
            }
        }
    }

    @Test("willEnterForeground under .demoteToInstance restores the captured grade only if one was captured", arguments: [true, false])
    func willEnterForegroundRestoresCapturedGradeConditionally(hasCapturedGrade: Bool) {
        let actions = machine.actions(
            for: .willEnterForeground,
            policy: .demoteToInstance,
            grade: .instanceOnly,
            wasPlayingBeforeBackground: false,
            hasCapturedGrade: hasCapturedGrade
        )
        #expect(actions.contains(.restoreCapturedGrade) == hasCapturedGrade)
    }

    @Test("willEnterForeground under .ignore does nothing beyond marking the session dirty")
    func willEnterForegroundIgnorePolicyIsMinimal() {
        let actions = machine.actions(
            for: .willEnterForeground,
            policy: .ignore,
            grade: .current,
            wasPlayingBeforeBackground: true,
            hasCapturedGrade: true
        )
        #expect(actions == [.markAudioSessionDirty])
    }
}
