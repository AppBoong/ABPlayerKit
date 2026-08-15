import ABTestSupport
import Foundation
import Testing

/// Guards the wiring between `ABPLAYERKIT_WAIT_SCALE` and the suite time
/// limits every test target declares.
///
/// The limits used to be written as `.timeLimit(.minutes(3))` — a literal the
/// scale could not reach. On a loaded CI runner that fired on every test in
/// flight at once, which reads as hundreds of product failures rather than as
/// the one slow machine it is. This suite fails if the literal comes back.
@Suite("Suite time limits honor ABPLAYERKIT_WAIT_SCALE", .timeLimit(abScaledMinutes(3)))
struct ABTestSupportScalingTests {
    private var waitScale: Double? {
        ProcessInfo.processInfo.environment["ABPLAYERKIT_WAIT_SCALE"].flatMap(Double.init)
    }

    @Test("A scaled limit exceeds its base when the environment asks for more time")
    func scaledLimitGrowsWithTheEnvironment() {
        let trait: TimeLimitTrait = .timeLimit(abScaledMinutes(3))
        if let scale = waitScale, scale > 1 {
            #expect(trait.timeLimit > .seconds(180))
        } else {
            #expect(trait.timeLimit == .seconds(180))
        }
    }

    @Test("A scaled limit is never shorter than its base")
    func scaledLimitNeverShrinks() {
        for minutes in 1...5 {
            let trait: TimeLimitTrait = .timeLimit(abScaledMinutes(minutes))
            #expect(trait.timeLimit >= .seconds(minutes * 60))
        }
    }

    @Test("A scaled limit never outgrows the cap, however large the scale")
    func scaledLimitStaysUnderTheCap() {
        // The cap is what keeps the per-test limit inside the workflow's own
        // timeout-minutes. Without it, a scale sized for second-scale
        // deadlines turns a 3-minute limit into something the job timeout
        // beats to the punch, and the hang detector stops detecting.
        for minutes in 1...5 {
            let trait: TimeLimitTrait = .timeLimit(abScaledMinutes(minutes))
            #expect(trait.timeLimit <= .seconds(abMaximumScaledMinutes * 60))
        }
    }

    @Test("A base already past the cap is not shrunk by it")
    func capNeverShrinksABaseAboveIt() {
        let base = abMaximumScaledMinutes + 5
        let trait: TimeLimitTrait = .timeLimit(abScaledMinutes(base))
        #expect(trait.timeLimit >= .seconds(base * 60))
    }

    @Test("A scaled ad-hoc timeout tracks the same scale")
    func scaledTimeoutTracksTheSameScale() {
        let scaled = abScaledTimeout(.seconds(2))
        if let scale = waitScale, scale > 1 {
            #expect(scaled > .seconds(2))
        } else {
            #expect(scaled == .seconds(2))
        }
    }
}
