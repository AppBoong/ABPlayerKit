import Foundation
import Testing
@testable import ABPlayerKit

@Suite("ABFirstFrameDetector.shouldReport truth table", .timeLimit(.minutes(3)))
@MainActor
struct ABFirstFrameDetectorTests {
    // Retained for the struct's lifetime: an `ObjectIdentifier` is only
    // guaranteed unique while its object is alive. Taking the identifier of
    // a bare `NSObject()` temporary lets ARC deallocate it immediately,
    // which can make an unrelated later temporary reuse the same address
    // and collide.
    private let objectA = NSObject()
    private let objectB = NSObject()
    private var itemA: ObjectIdentifier { ObjectIdentifier(objectA) }
    private var itemB: ObjectIdentifier { ObjectIdentifier(objectB) }

    @Test("Reports only when the layer is ready and the item is ready for the current item")
    func reportsOnlyWhenBothReadyForCurrentItem() {
        #expect(
            ABFirstFrameDetector.shouldReport(
                layerReady: true, itemStatus: .readyToPlay, reportedItem: nil, currentItem: itemA
            ) == true
        )
    }

    @Test("Does not report when the layer is not ready yet")
    func layerNotReady() {
        #expect(
            ABFirstFrameDetector.shouldReport(
                layerReady: false, itemStatus: .readyToPlay, reportedItem: nil, currentItem: itemA
            ) == false
        )
    }

    @Test("Does not report when the item is not ready yet")
    func itemNotReady() {
        #expect(
            ABFirstFrameDetector.shouldReport(
                layerReady: true, itemStatus: .unknown, reportedItem: nil, currentItem: itemA
            ) == false
        )
        #expect(
            ABFirstFrameDetector.shouldReport(
                layerReady: true, itemStatus: .failed, reportedItem: nil, currentItem: itemA
            ) == false
        )
    }

    @Test("Does not report when there is no current item")
    func noCurrentItem() {
        #expect(
            ABFirstFrameDetector.shouldReport(
                layerReady: true, itemStatus: .readyToPlay, reportedItem: nil, currentItem: nil
            ) == false
        )
    }

    @Test("Does not report again for an item that was already reported")
    func alreadyReportedItemIsSkipped() {
        #expect(
            ABFirstFrameDetector.shouldReport(
                layerReady: true, itemStatus: .readyToPlay, reportedItem: itemA, currentItem: itemA
            ) == false
        )
    }

    @Test("Reports again for a new item even if a previous item was already reported")
    func newItemAfterPreviousReportIsReported() {
        #expect(
            ABFirstFrameDetector.shouldReport(
                layerReady: true, itemStatus: .readyToPlay, reportedItem: itemA, currentItem: itemB
            ) == true
        )
    }

    @Test("Full truth table over layerReady x itemStatus")
    func fullTruthTable() {
        let statuses: [ABItemStatus] = [.unknown, .readyToPlay, .failed]
        for layerReady in [false, true] {
            for status in statuses {
                let result = ABFirstFrameDetector.shouldReport(
                    layerReady: layerReady, itemStatus: status, reportedItem: nil, currentItem: itemA
                )
                let expected = layerReady && status == .readyToPlay
                #expect(result == expected, "layerReady: \(layerReady) status: \(status)")
            }
        }
    }
}
