import ABPlayerKit

/// Pure LIFO ownership rules for the single, process-wide Now Playing
/// surface. Exclusive, not refcounted — the last participant to become
/// eligible owns it, and relinquishing hands ownership back to whichever
/// eligible participant is next on the stack.
///
/// No `MediaPlayer`/`ABPlayer` dependency — every rule is table-testable
/// against bare `ABPlayerID` values.
struct ABNowPlayingOwnership: Equatable {
    enum Effect: Equatable {
        /// Ownership transferred to this participant — publish and enable
        /// commands for it.
        case acquire(ABPlayerID)
        /// The last participant relinquished — restore whatever was
        /// captured before the first acquisition.
        case relinquishAll
        case none
    }

    /// Currently-eligible participants in acquisition order; the last
    /// element is the current owner.
    private var stack: [ABPlayerID] = []

    var owner: ABPlayerID? { stack.last }

    /// Registers a participant. Only takes effect on the stack if
    /// `isEligible` — an ineligible registration is remembered nowhere,
    /// since a later `setEligible(_:true)` call re-derives eligibility from
    /// scratch.
    @discardableResult
    mutating func register(_ id: ABPlayerID, isEligible: Bool) -> Effect {
        isEligible ? promote(id) : .none
    }

    /// A registered participant's eligibility changed (typically a grade
    /// crossing `.current`).
    @discardableResult
    mutating func setEligible(_ id: ABPlayerID, _ eligible: Bool) -> Effect {
        eligible ? promote(id) : demote(id)
    }

    /// The participant is gone for good (token cancelled, or the instance
    /// itself deallocated).
    @discardableResult
    mutating func unregister(_ id: ABPlayerID) -> Effect {
        demote(id)
    }

    private mutating func promote(_ id: ABPlayerID) -> Effect {
        guard owner != id else { return .none }
        stack.removeAll { $0 == id }
        stack.append(id)
        return .acquire(id)
    }

    private mutating func demote(_ id: ABPlayerID) -> Effect {
        let wasOwner = owner == id
        stack.removeAll { $0 == id }
        guard wasOwner else { return .none }
        if let newOwner = stack.last {
            return .acquire(newOwner)
        }
        return .relinquishAll
    }
}
