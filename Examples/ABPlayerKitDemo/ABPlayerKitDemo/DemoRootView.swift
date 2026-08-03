import SwiftUI

struct DemoRootView: View {
    let model: DemoModel

    var body: some View {
        TabView {
            PlaybackScreen(model: model)
                .tabItem {
                    Label("Playback", systemImage: "play.rectangle")
                }

            MetricsScreen(model: model)
                .tabItem {
                    Label("Metrics", systemImage: "chart.xyaxis.line")
                }

            CacheScreen(model: model)
                .tabItem {
                    Label("Cache", systemImage: "internaldrive")
                }
        }
        .task {
            await model.monitorCacheSize()
        }
    }
}
