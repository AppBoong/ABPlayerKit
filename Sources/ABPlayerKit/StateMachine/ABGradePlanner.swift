/// Turns a `(from, to)` grade transition into the ordered list of actions
/// needed to realize it. Pure — no `AVFoundation` import, no state, 100%
/// unit-testable.
///
/// Deviations from the literal from/to transition table this planner
/// implements, chosen to keep invariants I1–I5 internally consistent
/// (documented at each call site below and in the final implementation
/// report):
/// - `.applyTuning` is always ordered *before* the matching `.attachItem`
///   (the table's prose lists them the other way around in a couple of
///   cells, but invariant I4 is explicit that tuning must land before
///   `replaceCurrentItem`).
/// - The `current → current` cell is missing from the table (the row only
///   has 3 data cells). Treated the same as the other diagonal cells:
///   identity when `sourceChanged == false`, re-attach when
///   `sourceChanged == true`.
/// - Every "stay at the same item-holding grade but the source changed"
///   cell (`preloaded → preloaded`, `preloaded → current`,
///   `current → preloaded`, `current → current`, all with
///   `sourceChanged == true`) re-attaches via `.attachItem` alone, **without**
///   a preceding `.detachItem` — even though the table's prose spells out
///   "detachItem→attachItem" for the `preloaded → preloaded` cell.
///   `.attachItem` means `replaceCurrentItem(with:)`, which does not require
///   passing `nil` first, so the extra detach is unnecessary. Dropping it
///   uniformly is what makes I1 a true global biconditional (`.detachItem`
///   appears if and only if `from.holdsItem && !to.holdsItem`) instead of a
///   one-directional rule with the table's literal cell as an exception.
/// - I3 ("to < .preloaded ⇒ .cancelPreload") is scoped to `from == .preloaded`
///   transitions, matching the table exactly (the `current` row's cells
///   never mention `.cancelPreload`, since nothing is preloading once a
///   player is `.current`).
public struct ABGradePlanner: Sendable {
    public init() {}

    public func actions(
        from: ABPlaybackGrade,
        to: ABPlaybackGrade,
        source: ABMediaSource?,
        sourceChanged: Bool,
        rewindOnDemotion: Bool = false
    ) -> [ABGradeAction] {
        switch (from, to) {
        case (.released, .released):
            return []

        case (.released, .instanceOnly):
            return [.createPlayer]

        case (.released, .preloaded):
            return [.createPlayer] + attach(.preload, source: source, armPreroll: true)

        case (.released, .current):
            return [.createPlayer] + attach(.current, source: source, armPreroll: false)

        case (.instanceOnly, .released):
            return [.releasePlayer]

        case (.instanceOnly, .instanceOnly):
            // "source만 갱신" — no item is held, nothing to attach/detach.
            return []

        case (.instanceOnly, .preloaded):
            return attach(.preload, source: source, armPreroll: true)

        case (.instanceOnly, .current):
            return attach(.current, source: source, armPreroll: false)

        case (.preloaded, .released):
            return [.cancelPreload, .pause, .detachItem, .teardownObservers, .releasePlayer]

        case (.preloaded, .instanceOnly):
            return [.cancelPreload, .pause, .detachItem]

        case (.preloaded, .preloaded):
            guard sourceChanged else { return [] }
            return [.cancelPreload, .pause] + attach(.preload, source: source, armPreroll: true)

        case (.preloaded, .current):
            var result: [ABGradeAction] = [.cancelPreload, .applyTuning(.current)]
            if sourceChanged, let source {
                // No .detachItem: .attachItem itself replaces whatever item
                // is currently attached (replaceCurrentItem(with:) doesn't
                // require going through nil first). Keeping .detachItem out
                // here is what keeps I1 a true global biconditional — see
                // the type-level doc comment.
                result.append(.attachItem(source))
            }
            return result

        case (.current, .released):
            return [.pause, .detachItem, .teardownObservers, .releasePlayer]

        case (.current, .instanceOnly):
            return [.pause, .detachItem]

        case (.current, .preloaded):
            var result: [ABGradeAction] = [.pause, .applyTuning(.preload)]
            if sourceChanged, let source {
                result.append(.attachItem(source))
                result.append(.armPreroll)
            }
            if rewindOnDemotion {
                result.append(.seekToStart)
            }
            return result

        case (.current, .current):
            guard sourceChanged, let source else { return [] }
            return [.pause, .applyTuning(.current), .attachItem(source)]
        }
    }

    /// `.applyTuning` before `.attachItem` before optional `.armPreroll` —
    /// satisfies I4 (tuning applied before `replaceCurrentItem`). Returns an
    /// empty list if no source is available, since attaching requires one;
    /// `ABPlayer` never reaches this with `to.holdsItem && source == nil`
    /// (illegal combinations are clamped before the planner is consulted).
    private func attach(
        _ role: ABTuningRole,
        source: ABMediaSource?,
        armPreroll: Bool
    ) -> [ABGradeAction] {
        guard let source else { return [] }
        var result: [ABGradeAction] = [.applyTuning(role), .attachItem(source)]
        if armPreroll {
            result.append(.armPreroll)
        }
        return result
    }
}
