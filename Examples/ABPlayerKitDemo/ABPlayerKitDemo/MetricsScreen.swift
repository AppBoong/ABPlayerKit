import SwiftUI

struct MetricsScreen: View {
    let model: DemoModel

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("TTFF begins when playback is promoted to current and is abandoned when it is demoted. Successful samples feed the latency percentiles; abandoned samples remain in rate denominators.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: columns, spacing: 12) {
                        MetricCard(title: "p50", value: milliseconds(model.statistics.p50))
                        MetricCard(title: "p95", value: milliseconds(model.statistics.p95))
                        MetricCard(title: "Hit rate", value: percentage(model.statistics.hitRate))
                        MetricCard(title: "Abandon rate", value: percentage(model.statistics.abandonRate))
                    }

                    GroupBox("Samples") {
                        LabeledContent("Total", value: model.statistics.sampleCount.formatted())
                        LabeledContent("Immediate hits", value: model.statistics.hitCount.formatted())
                        LabeledContent("Abandoned", value: model.statistics.abandonedCount.formatted())
                        LabeledContent("Maximum", value: milliseconds(model.statistics.max))
                    }

                    GroupBox("Try it") {
                        Text("Switch between Preloaded and Current on the Playback tab. Promote after preloading for a hit, or demote before the first frame to record an abandonment.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("Metrics")
        }
    }

    private func milliseconds(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0))) + " ms"
    }

    private func percentage(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(1)))
    }
}

private struct MetricCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
    }
}
