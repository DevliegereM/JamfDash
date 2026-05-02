import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openWindow) private var openWindow

    /// True until the first data sync after cold launch finishes.
    @State private var showLaunch = true

    var body: some View {
        Group {
            switch appState.phase {
            case .launching:
                LaunchView()

            case .onboarding:
                OnboardingView(vm: env.makeOnboardingVM()) {
                    appState.completeOnboarding()
                }

            case .setup:
                OnboardingView(vm: env.makeSetupVM()) {
                    appState.completeSetup()
                }

            case .main:
                ZStack {
                    MainView()
                    if showLaunch {
                        LaunchView()
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.45), value: showLaunch)
            }
        }
        // Sync finished → dismiss launch overlay.
        .onChange(of: env.isSyncing) { _, syncing in
            if !syncing && showLaunch && appState.phase == .main {
                showLaunch = false
            }
        }
        // Phase changed: skip launch overlay when coming from onboarding/setup,
        // or if we somehow reach .main with sync already done.
        .onChange(of: appState.phase) { old, new in
            guard new == .main else { return }
            if old == .onboarding || old == .setup || !env.isSyncing {
                showLaunch = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openHelpWindow)) { _ in
            openWindow(id: "jamf-help")
        }
    }
}

// MARK: - Launch screen

private struct LaunchView: View {
    @Environment(AppEnvironment.self) private var env

    private var syncTitle: String {
        switch env.currentProduct {
        case .pro:     return "Syncing Jamf Pro"
        case .protect: return "Syncing Jamf Protect"
        case .school:  return "Syncing Jamf School"
        }
    }

    var body: some View {
        ZStack {
            LaunchBackground()

            VStack(spacing: 0) {
                Spacer()

                Mark()
                    .frame(width: 120, height: 120)
                    .padding(.bottom, 24)

                Text("Jamf Dash")
                    .font(.system(size: 38, weight: .bold))
                    .tracking(-1.2)

                Text("Fleet management, decluttered.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                if let url = env.currentServerURL {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                            .shadow(color: .green.opacity(0.6), radius: 3)
                        (Text("Connected to ").foregroundStyle(.secondary) +
                         Text(url).fontWeight(.medium))
                    }
                    .font(.system(size: 12))
                    .padding(.top, 18)
                }

                Spacer()

                if !env.syncStepLabels.isEmpty {
                    SyncBar(title: syncTitle,
                            steps: env.syncStepLabels,
                            activeIndex: env.syncCompletedSteps)
                        .padding(.bottom, 36)
                }
            }
            .padding(.horizontal, 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Background

private struct LaunchBackground: View {
    var body: some View {
        ZStack {
            // Solid base so nothing underneath bleeds through.
            Color(NSColor.windowBackgroundColor)
                .ignoresSafeArea()
            // Subtle accent tint on top (Tahoe and later).
            if #available(macOS 26.0, *) {
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.10), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()
            }
        }
    }
}

// MARK: - Constellation mark

private struct Mark: View {
    private let nodes: [CGPoint] = [
        .init(x: 60, y: 18), .init(x: 96, y: 38), .init(x: 102, y: 80),
        .init(x: 78, y: 102), .init(x: 38, y: 102), .init(x: 18, y: 76),
        .init(x: 22, y: 38), .init(x: 60, y: 60),
    ]
    private let edges: [(Int, Int)] = [
        (0,7),(1,7),(2,7),(3,7),(4,7),(5,7),(6,7),
        (0,1),(1,2),(2,3),(3,4),(4,5),(5,6),(6,0),
    ]

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                let s = size.width / 120
                func P(_ i: Int) -> CGPoint {
                    .init(x: nodes[i].x * s, y: nodes[i].y * s)
                }
                for (idx, e) in edges.enumerated() {
                    let phase = (t * 0.6 + Double(idx) * 0.1)
                        .truncatingRemainder(dividingBy: 3.2) / 3.2
                    let alpha = sin(phase * .pi) * 0.7 + 0.1
                    var path = Path()
                    path.move(to: P(e.0))
                    path.addLine(to: P(e.1))
                    gc.stroke(path, with: .color(.accentColor.opacity(alpha)), lineWidth: 0.8 * s)
                }
                for (i, _) in nodes.enumerated() {
                    let r: CGFloat = (i == 7 ? 3.2 : 2.2) * s
                    let pulse = sin(t * 1.6 + Double(i) * 0.5) * 0.3 + 0.7
                    let rect = CGRect(x: P(i).x - r, y: P(i).y - r, width: r*2, height: r*2)
                    gc.fill(Path(ellipseIn: rect), with: .color(.accentColor.opacity(pulse)))
                }
            }
        }
    }
}
