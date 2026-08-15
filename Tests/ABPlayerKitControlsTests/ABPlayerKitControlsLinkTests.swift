import ABPlayerKit
import ABPlayerKitControls
import ABTestSupport
import Testing

@Suite("ABPlayerKitControls target links to the core player", .timeLimit(abScaledMinutes(3)))
struct ABPlayerKitControlsLinkTests {
    @Test("Given both imports, core playback values remain available")
    func linksCoreTarget() {
        #expect(ABPlaybackRate.common.contains(1.0))
    }
}
