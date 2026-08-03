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
                    Text("TTFF uses a timestamp captured before each user action that enters Current. Successful samples feed the latency percentiles; abandoned samples remain in rate denominators. resumedFromTime stays nil because this demo does not perform a restore seek; set it only when a real restore seek is part of the measured work.")
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
                        Text("Preloaded is pinned to conservativePreload while the Current tuning picker controls the landing role. Promote after preloading for a hit, or leave Current before the first frame to record an abandonment.")
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
