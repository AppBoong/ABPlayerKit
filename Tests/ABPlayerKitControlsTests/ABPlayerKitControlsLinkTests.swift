import ABPlayerKit
import ABPlayerKitControls
import Testing

@Suite("ABPlayerKitControls target links to the core player")
struct ABPlayerKitControlsLinkTests {
    @Test("Given both imports, core playback values remain available")
    func linksCoreTarget() {
        #expect(ABPlaybackRate.common.contains(1.0))
    }
}
