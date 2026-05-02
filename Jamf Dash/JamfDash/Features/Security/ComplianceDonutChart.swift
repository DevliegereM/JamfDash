import SwiftUI
import Charts

struct ComplianceDonutChart: View {
    let title: String
    let compliant: Int
    let total: Int
    let color: Color

    private var nonCompliant: Int { max(0, total - compliant) }
    private var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(compliant) / Double(total) * 100
    }

    private struct Slice: Identifiable {
        let id: String
        let value: Int
        let isCompliant: Bool
    }

    private var slices: [Slice] {
        [
            Slice(id: "compliant", value: compliant, isCompliant: true),
            Slice(id: "other", value: nonCompliant, isCompliant: false)
        ].filter { $0.value > 0 }
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Chart(slices) { slice in
                    SectorMark(
                        angle: .value("Count", slice.value),
                        innerRadius: .ratio(0.6),
                        angularInset: 1.5
                    )
                    .foregroundStyle(slice.isCompliant ? color : Color.gray.opacity(0.3))
                    .cornerRadius(4)
                }
                .frame(width: 110, height: 110)

                VStack(spacing: 2) {
                    Text(String(format: "%.0f%%", percentage))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("\(compliant)/\(total)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
