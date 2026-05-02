import SwiftUI
import Charts

struct OSDistributionChart: View {
    let rows: [OSVersionRow]

    // Group versions by major.minor (drop patch)
    private var grouped: [OSVersionRow] {
        rows.sorted { $0.count > $1.count }
    }

    private var maxCount: Int {
        rows.map(\.count).max() ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DashSectionHeader("OS Version Distribution", systemImage: "chart.bar.fill")

            Chart(grouped) { row in
                BarMark(
                    x: .value("Count", row.count),
                    y: .value("OS Version", row.osVersion)
                )
                .foregroundStyle(barColor(for: row.osVersion))
                .annotation(position: .trailing) {
                    Text("\(row.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) {
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                }
            }
            .frame(height: CGFloat(grouped.count) * 36 + 20)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func barColor(for version: String) -> Color {
        let major = version.split(separator: ".").first.flatMap { Int($0) } ?? 0
        switch major {
        case 15...: return .blue
        case 14:    return .teal
        case 13:    return .cyan
        default:    return .gray
        }
    }
}
