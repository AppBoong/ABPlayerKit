import ABPlayerKit
import Testing
@testable import ABPlayerKitNowPlaying

/// Table coverage for `ABNowPlayingOwnership`'s R1–R4 rules — pure, no
/// `MediaPlayer`/`ABPlayer` instance required.
@Suite("ABNowPlayingOwnership resolves exclusive, LIFO ownership")
struct ABNowPlayingOwnershipTests {
    @Test("Registering an eligible participant acquires ownership immediately")
    func registeringEligibleParticipantAcquires() {
        var ownership = ABNowPlayingOwnership()
        let id = ABPlayerID()

        let effect = ownership.register(id, isEligible: true)

        #expect(effect == .acquire(id))
        #expect(ownership.owner == id)
    }

    @Test("Registering an ineligible participant has no effect and leaves owner nil")
    func registeringIneligibleParticipantHasNoEffect() {
        var ownership = ABNowPlayingOwnership()
        let idA = ABPlayerID()
        let idB = ABPlayerID()

        #expect(ownership.register(idA, isEligible: false) == .none)
        #expect(ownership.register(idB, isEligible: false) == .none)
        #expect(ownership.owner == nil)

        // Unregistering a participant that was never eligible (never
        // acquired ownership) has nothing to relinquish.
        #expect(ownership.unregister(idA) == .none)
        #expect(ownership.owner == nil)
    }

    @Test("Becoming eligible later acquires ownership the same way an eligible registration does")
    func becomingEligibleLaterAcquires() {
        var ownership = ABNowPlayingOwnership()
        let id = ABPlayerID()

        #expect(ownership.register(id, isEligible: false) == .none)
        let effect = ownership.setEligible(id, true)

        #expect(effect == .acquire(id))
        #expect(ownership.owner == id)
    }

    @Test("Two-participant LIFO: B acquires over A, A auto-returns once B relinquishes")
    func twoParticipantLIFOAutoReturn() {
        var ownership = ABNowPlayingOwnership()
        let idA = ABPlayerID()
        let idB = ABPlayerID()

        #expect(ownership.register(idA, isEligible: true) == .acquire(idA))
        #expect(ownership.owner == idA)

        #expect(ownership.register(idB, isEligible: true) == .acquire(idB))
        #expect(ownership.owner == idB)

        let effect = ownership.unregister(idB)

        #expect(effect == .acquire(idA))
        #expect(ownership.owner == idA)
    }

    @Test("Contention: the later-eligible participant owns; losing eligibility (not unregistering) also returns ownership to the earlier one")
    func contentionReturnsOwnershipOnEligibilityLoss() {
        var ownership = ABNowPlayingOwnership()
        let idA = ABPlayerID()
        let idB = ABPlayerID()

        ownership.register(idA, isEligible: true)
        ownership.register(idB, isEligible: true)
        #expect(ownership.owner == idB)

        let effect = ownership.setEligible(idB, false)

        #expect(effect == .acquire(idA))
        #expect(ownership.owner == idA)
    }

    @Test("Unregistering the sole owner relinquishes all the way down")
    func unregisteringSoleOwnerRelinquishesAll() {
        var ownership = ABNowPlayingOwnership()
        let id = ABPlayerID()
        ownership.register(id, isEligible: true)

        let effect = ownership.unregister(id)

        #expect(effect == .relinquishAll)
        #expect(ownership.owner == nil)
    }

    @Test("Unregistering a non-owner participant does not disturb the current owner")
    func unregisteringNonOwnerLeavesOwnerUntouched() {
        var ownership = ABNowPlayingOwnership()
        let idA = ABPlayerID()
        let idB = ABPlayerID()
        ownership.register(idA, isEligible: true)
        ownership.register(idB, isEligible: true)
        #expect(ownership.owner == idB)

        let effect = ownership.unregister(idA)

        #expect(effect == .none)
        #expect(ownership.owner == idB)
    }

    @Test("Re-registering the current owner as eligible again is a no-op")
    func reRegisteringCurrentOwnerIsANoOp() {
        var ownership = ABNowPlayingOwnership()
        let id = ABPlayerID()
        ownership.register(id, isEligible: true)

        let effect = ownership.setEligible(id, true)

        #expect(effect == .none)
        #expect(ownership.owner == id)
    }
}
