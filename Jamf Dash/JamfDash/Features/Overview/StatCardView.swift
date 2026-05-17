import SwiftUI

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    var color: Color = .accentColor
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(color.opacity(0.14))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .foregroundStyle(color)
                        .font(.system(size: 17, weight: .semibold))
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let sub = subtitle {
                    Text(sub)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(14)
        .glassCard()
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(color.opacity(0.18), lineWidth: 1)
        )
    }
}

struct StatusBadge: View {
    let text: String
    var isOK: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isOK ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
                .shadow(color: (isOK ? Color.green : Color.orange).opacity(0.6), radius: 3)
            Text(text)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            (isOK ? Color.green : Color.orange).opacity(0.10),
            in: Capsule()
        )
        .overlay(
            Capsule()
                .stroke((isOK ? Color.green : Color.orange).opacity(0.25), lineWidth: 1)
        )
    }
}
