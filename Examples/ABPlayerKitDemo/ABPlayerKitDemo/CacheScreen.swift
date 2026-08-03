import SwiftUI

struct CacheScreen: View {
    let model: DemoModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Progressive MP4") {
                    Toggle("Use transparent cache", isOn: cacheBinding)
                        .disabled(!model.cacheIsAvailable)
                    LabeledContent("Disk usage", value: model.cacheSizeLabel)

                    Button("Replay MP4 through cache") {
                        model.replayMP4()
                    }
                    .disabled(!model.cacheIsAvailable)

                    Button("Remove all cached media", role: .destructive) {
                        Task {
                            await model.removeAllCachedMedia()
                        }
                    }
                    .disabled(!model.cacheIsAvailable || model.cacheSize == 0)

                    Text("Play the MP4 once to fill the progressive cache, then tap Replay to create a fresh asset backed by the cached bytes.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("HLS prefetch") {
                    LabeledContent("Status", value: model.prefetchState.title)

                    Button("Prefetch Apple bipbop") {
                        model.startHLSPrefetch()
                    }
                    .disabled(model.prefetchState == .downloading)

                    Button("Cancel prefetch", role: .destructive) {
                        model.cancelHLSPrefetch()
                    }
                    .disabled(model.prefetchState != .downloading)

                    Button("Play local HLS download") {
                        model.playPrefetchedHLS()
                    }
                    .disabled(model.prefetchState != .available)

                    Text("HLS uses explicit AVAssetDownloadURLSession prefetching. It is never intercepted by the transparent MP4 cache.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let cacheError = model.cacheError {
                    Section("Cache unavailable") {
                        Text(cacheError)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Cache")
        }
    }

    private var cacheBinding: Binding<Bool> {
        Binding(
            get: { model.cacheEnabled },
            set: { enabled in model.setCacheEnabled(enabled) }
        )
    }
}
