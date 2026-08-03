import Foundation
import Testing
@testable import ABPlayerKit

@Suite("ABGradePlanner covers every (from, to, sourceChanged) transition")
struct ABGradePlannerTransitionTests {
    private let planner = ABGradePlanner()
    private let source = ABMediaSource(url: URL(string: "https://example.com/a.mp4")!)

    /// All 16 grade pairs × sourceChanged (32 cases total) must produce a
    /// plan without crashing and without violating the structural
    /// invariants that hold across the whole table.
    @Test(
        "Every grade pair, with and without a source change, plans without violating I1/I3/I4",
        arguments: ABPlaybackGrade.allCases, ABPlaybackGrade.allCases
    )
    func everyTransitionRespectsStructuralInvariants(from: ABPlaybackGrade, to: ABPlaybackGrade) {
        for sourceChanged in [false, true] {
            let actions = planner.actions(from: from, to: to, source: source, sourceChanged: sourceChanged)

            // I1, as a true global biconditional: .detachItem appears
            // exactly once if and only if the grade drops below
            // .holdsItem. Reattaching at the same item-holding grade never
            // needs a .detachItem — .attachItem's replaceCurrentItem(with:)
            // already replaces whatever item (if any) was attached.
            let detachCount = actions.filter { $0 == .detachItem }.count
            let shouldDetach = from.holdsItem && !to.holdsItem
            #expect(
                detachCount == (shouldDetach ? 1 : 0),
                "from: \(from) to: \(to) sourceChanged: \(sourceChanged)"
            )

            // I3 (scoped to the table's literal cells: only .preloaded has
            // outstanding preload work to cancel).
            if from == .preloaded, to < .preloaded {
                #expect(actions.contains(.cancelPreload), "from: \(from) to: \(to) sourceChanged: \(sourceChanged)")
            }

            // I4: whenever .attachItem appears, an .applyTuning for the same
            // batch precedes or accompanies it — never the reverse.
            if let attachIndex = actions.firstIndex(where: { if case .attachItem = $0 { return true } else { return false } }) {
                let precedingTunings = actions[..<attachIndex].filter { if case .applyTuning = $0 { return true } else { return false } }
                #expect(!precedingTunings.isEmpty, "from: \(from) to: \(to) sourceChanged: \(sourceChanged)")
            }
        }
    }

    /// I2, scoped to transitions that land on a grade that actually holds an
    /// item: whenever the grade changes (or the source changes while
    /// staying at the same item-holding grade), .applyTuning fires at least
    /// once.
    @Test(
        "Every transition into an item-holding grade applies tuning at least once",
        arguments: ABPlaybackGrade.allCases, ABPlaybackGrade.allCases
    )
    func tuningAppliedOnEveryRelevantChange(from: ABPlaybackGrade, to: ABPlaybackGrade) {
        guard to.holdsItem else { return }
        for sourceChanged in [false, true] {
            guard from != to || sourceChanged else { continue }
            let actions = planner.actions(from: from, to: to, source: source, sourceChanged: sourceChanged)
            let tuningCount = actions.filter { if case .applyTuning = $0 { return true } else { return false } }.count
            #expect(tuningCount >= 1, "from: \(from) to: \(to) sourceChanged: \(sourceChanged)")
        }
    }

    /// I5: the planner is a pure function — calling it twice with identical
    /// input yields identical output (a prerequisite for the deeper
    /// "applying it twice leaves the same observable state" property, which
    /// ABPlayerEngineTests verifies against the fake target).
    @Test(
        "The same (from, to, source, sourceChanged) always yields the same actions",
        arguments: ABPlaybackGrade.allCases, ABPlaybackGrade.allCases
    )
    func plannerIsPure(from: ABPlaybackGrade, to: ABPlaybackGrade) {
        for sourceChanged in [false, true] {
            let first = planner.actions(from: from, to: to, source: source, sourceChanged: sourceChanged)
            let second = planner.actions(from: from, to: to, source: source, sourceChanged: sourceChanged)
            #expect(first == second, "from: \(from) to: \(to) sourceChanged: \(sourceChanged)")
        }
    }

    // MARK: - Exact-sequence snapshots (locks in the table itself)

    @Test("released to released is a true no-op")
    func releasedToReleased() {
        #expect(planner.actions(from: .released, to: .released, source: nil, sourceChanged: false).isEmpty)
    }

    @Test("released to instanceOnly only creates the player")
    func releasedToInstanceOnly() {
        #expect(planner.actions(from: .released, to: .instanceOnly, source: nil, sourceChanged: false) == [.createPlayer])
    }

    @Test("released to preloaded creates, tunes, attaches, and arms preroll")
    func releasedToPreloaded() {
        let actions = planner.actions(from: .released, to: .preloaded, source: source, sourceChanged: false)
        #expect(actions == [.createPlayer, .applyTuning(.preload), .attachItem(source), .armPreroll])
    }

    @Test("released to current creates, tunes, and attaches without prerolling")
    func releasedToCurrent() {
        let actions = planner.actions(from: .released, to: .current, source: source, sourceChanged: false)
        #expect(actions == [.createPlayer, .applyTuning(.current), .attachItem(source)])
    }

    @Test("instanceOnly to released only releases the player")
    func instanceOnlyToReleased() {
        #expect(planner.actions(from: .instanceOnly, to: .released, source: nil, sourceChanged: false) == [.releasePlayer])
    }

    @Test("instanceOnly to instanceOnly is a no-op regardless of sourceChanged")
    func instanceOnlyToInstanceOnly() {
        #expect(planner.actions(from: .instanceOnly, to: .instanceOnly, source: source, sourceChanged: true).isEmpty)
        #expect(planner.actions(from: .instanceOnly, to: .instanceOnly, source: nil, sourceChanged: false).isEmpty)
    }

    @Test("preloaded to current is the exact inverse of current to preloaded")
    func promoteDemoteSymmetry() {
        let promote = planner.actions(from: .preloaded, to: .current, source: source, sourceChanged: false)
        #expect(promote == [.cancelPreload, .applyTuning(.current)])

        let demote = planner.actions(from: .current, to: .preloaded, source: source, sourceChanged: false)
        #expect(demote == [.pause, .applyTuning(.preload)])
    }

    @Test("preloaded to released tears everything down through detachItem")
    func preloadedToReleased() {
        let actions = planner.actions(from: .preloaded, to: .released, source: nil, sourceChanged: false)
        #expect(actions == [.cancelPreload, .pause, .detachItem, .teardownObservers, .releasePlayer])
    }

    @Test("current to released tears everything down through detachItem")
    func currentToReleased() {
        let actions = planner.actions(from: .current, to: .released, source: nil, sourceChanged: false)
        #expect(actions == [.pause, .detachItem, .teardownObservers, .releasePlayer])
    }

    @Test("preloaded to preloaded with a source change detaches and reattaches")
    func preloadedToPreloadedSourceChanged() {
        let actions = planner.actions(from: .preloaded, to: .preloaded, source: source, sourceChanged: true)
        #expect(actions == [.cancelPreload, .pause, .applyTuning(.preload), .attachItem(source), .armPreroll])
    }

    @Test("current to preloaded with rewindOnDemotion seeks to start")
    func currentToPreloadedRewinds() {
        let actions = planner.actions(
            from: .current, to: .preloaded, source: nil, sourceChanged: false, rewindOnDemotion: true
        )
        #expect(actions == [.pause, .applyTuning(.preload), .seekToStart])
    }
}
