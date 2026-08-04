import ABPlayerKit
import SwiftUI
import Testing
@testable import ABPlayerKitControls

@Suite("SwiftUI convenience player composes video and controls")
@MainActor
struct ABVideoPlayerWithControlsTests {
    @Test("Given a player, the convenience view builds its layered body")
    func buildsBody() {
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        var configuration = ABPlayerControlsConfiguration()
        configuration.skipInterval = 15

        let view = ABVideoPlayerWithControls(
            player: player,
            style: .minimal,
            configuration: configuration
        )

        _ = view.body
    }
}
