import SwiftUI

// MARK: - Public API
//
// JamfDash inline sync indicator. Drop into any content panel.
// Pass the active step index as steps complete.
//
//   SyncBar(
//       title: "Syncing Jamf Pro",
//       steps: ["Computers", "Policies", ...],
//       activeIndex: viewModel.completedStepCount
//   )
//
// On macOS 26 (Tahoe), the card uses Liquid Glass automatically.
// On macOS 14 / 15, it falls back to a solid material card.

struct SyncBar: View {
    let title: String
    let steps: [String]
    let activeIndex: Int   // 0...steps.count

    init(title: String = "Syncing Jamf Pro", steps: [String], activeIndex: Int) {
        self.title = title
        self.steps = steps
        self.activeIndex = activeIndex
    }

    var body: some View {
        SyncBarContent(title: title, steps: steps, activeIndex: activeIndex)
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .frame(width: 320, alignment: .leading)
            .modifier(SyncBarBackground())
    }
}

// MARK: - Background — branches on OS

private struct SyncBarBackground: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            // Liquid Glass — floating panel that lenses what's behind it
            content
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            // macOS 14 / 15 — solid material card with a hairline border
            content
                .background(.background, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.06), radius: 12, y: 6)
        }
    }
}

// MARK: - Inner content (shared)

private struct SyncBarContent: View {
    let title: String
    let steps: [String]
    let activeIndex: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(percent)%")
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 12)

            IndeterminateBar()
                .frame(height: 5)

            Text("Fetching \(currentLabel.lowercased())…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.top, 14)
                .padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, label in
                    StepRow(
                        label: label,
                        state: state(for: i)
                    )
                }
            }
        }
    }

    private var currentLabel: String {
        activeIndex < steps.count ? steps[activeIndex] : "finishing up"
    }
    private var percent: Int {
        guard !steps.isEmpty else { return 0 }
        return Int((Double(min(activeIndex, steps.count)) / Double(steps.count)) * 100)
    }
    private func state(for i: Int) -> StepState {
        if i < activeIndex { return .done }
        if i == activeIndex { return .active }
        return .pending
    }
}

// MARK: - Indeterminate sweeping bar

private struct IndeterminateBar: View {
    @State private var phase: CGFloat = -0.4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))

                Capsule()
                    .fill(barFill)
                    .frame(width: geo.size.width * 0.45)
                    .offset(x: phase * geo.size.width)
                    .modifier(GlowIfTahoe())
            }
            .clipShape(Capsule())
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1.0
                }
            }
        }
    }

    private var barFill: LinearGradient {
        if #available(macOS 26.0, *) {
            return LinearGradient(
                colors: [.clear, .accentColor, .accentColor.opacity(1.0), .accentColor, .clear],
                startPoint: .leading, endPoint: .trailing
            )
        } else {
            return LinearGradient(
                colors: [.clear, .accentColor, .accentColor, .clear],
                startPoint: .leading, endPoint: .trailing
            )
        }
    }
}

// Soft glow under the bar on Tahoe; no-op on older macOS.
private struct GlowIfTahoe: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.shadow(color: .accentColor.opacity(0.5), radius: 4)
        } else {
            content
        }
    }
}

// MARK: - Step row

private struct StepRow: View {
    let label: String
    let state: StepState

    var body: some View {
        HStack(spacing: 9) {
            StepDot(state: state)
            Text(label)
                .font(.system(size: 12.5, weight: state == .active ? .medium : .regular))
                .foregroundStyle(state == .done ? .secondary : .primary)
            Spacer()
            if state == .active {
                Text("loading")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .modifier(LoadingPulse())
            }
        }
        .opacity(state == .pending ? 0.4 : 1.0)
        .animation(.easeInOut(duration: 0.25), value: state)
    }
}

private struct StepDot: View {
    let state: StepState
    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.primary.opacity(0.2), lineWidth: state == .done ? 0 : 1)
                .background(Circle().fill(state == .done ? Color.accentColor : .clear))
                .frame(width: 12, height: 12)
            if state == .done {
                Image(systemName: "checkmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }
}

private struct LoadingPulse: ViewModifier {
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .opacity(on ? 1.0 : 0.5)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    on = true
                }
            }
    }
}

private enum StepState { case pending, active, done }

// MARK: - Inline indicator (sweeping bar only, no card — for individual content panels)

struct SyncingIndicator: View {
    var body: some View {
        VStack(spacing: 10) {
            IndeterminateBar()
                .frame(width: 200, height: 5)
            Text("Loading…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview

#Preview("macOS — current OS") {
    SyncBar(
        title: "Syncing Jamf Pro",
        steps: ["Computers", "Policies", "Smart Groups", "Scripts", "Packages", "Configuration Profiles"],
        activeIndex: 2
    )
    .padding(40)
    .frame(width: 400, height: 320)
}
