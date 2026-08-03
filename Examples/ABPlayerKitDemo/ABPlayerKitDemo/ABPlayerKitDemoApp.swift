import SwiftUI

@main
struct ABPlayerKitDemoApp: App {
    @State private var model = DemoModel()

    var body: some Scene {
        WindowGroup {
            DemoRootView(model: model)
        }
    }
}
