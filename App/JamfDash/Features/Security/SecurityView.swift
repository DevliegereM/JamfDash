import SwiftUI

struct SecurityView: View {
    @Bindable var vm: SecurityViewModel
    @Environment(AppEnvironment.self) private var env
    @State private var showIssuesOnly = false
    @AppStorage("healthScoreThreshold") private var scoreThreshold: Int = 70
    @State private var showThresholdPopover = false

    private var serialToComputerID: [String: String] {
        Dictionary(
            uniqueKeysWithValues: env.devicesVM.allComputers.compactMap { c in
                c.serialNumber.map { ($0, c.id) }
            }
        )
    }

    private func consoleURL(for device: DeviceSecurity) -> URL? {
        guard let base = env.currentServerURL,
              let deviceID = serialToComputerID[device.serial] else { return nil }
        let root = base.hasSuffix("/") ? String(base.dropLast()) : base
        return URL(string: "\(root)/computers.html?id=\(deviceID)&o=r")
    }

    private var visibleDevices: [DeviceSecurity] {
        showIssuesOnly ? vm.devices.filter(\.hasIssue) : vm.devices
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if vm.state.isPending {
                    SyncingIndicator()
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if let error = vm.state.errorMessage {
                    ErrorStateView(message: error) { await vm.load(force: true) }
                } else {
                    if env.fleetHealthScore.isAvailable {
                        HealthScoreBanner(score: env.fleetHealthScore)
                    }
                    if let summary = vm.summary {
                        complianceSection(summary: summary)
                    }
                    if !vm.osVersions.isEmpty {
                        OSDistributionChart(rows: vm.osVersions)
                    }
                    if !vm.devices.isEmpty {
                        deviceTable
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Security Posture")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showThresholdPopover.toggle()
                } label: {
                    Label("Score Settings", systemImage: "gear")
                }
                .help("Configure fleet health score alert threshold")
                .popover(isPresented: $showThresholdPopover) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Alert Threshold")
                            .font(.headline)
                        Text("Get notified when the fleet health score drops below:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Stepper("Score: \(scoreThreshold)", value: $scoreThreshold, in: 0...100, step: 5)
                    }
                    .padding()
                    .frame(width: 280)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await vm.load(force: true) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(vm.state.isLoading)
                .help("Refresh security posture report")
            }
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: $showIssuesOnly) {
                    Label("Issues Only", systemImage: "exclamationmark.triangle")
                }
                .toggleStyle(.button)
                .tint(.orange)
                .help("Show only devices with at least one security issue")
                .disabled(vm.devices.isEmpty)
            }
        }
        .liquidGlassToolbar()
        .task { await vm.loadPatchCompliance() }
    }

    // MARK: - Compliance donuts

    private func complianceSection(summary: SecuritySummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            DashSectionHeader("Security Compliance", systemImage: "lock.shield.fill")

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4),
                spacing: 16
            ) {
                ComplianceDonutChart(
                    title: "FileVault Encryption",
                    compliant: summary.filevaultEncrypted,
                    total: summary.totalDevices,
                    color: .blue
                )
                ComplianceDonutChart(
                    title: "Gatekeeper",
                    compliant: summary.gatekeeperEnabled,
                    total: summary.totalDevices,
                    color: .green
                )
                ComplianceDonutChart(
                    title: "System Integrity Protection",
                    compliant: summary.sipEnabled,
                    total: summary.totalDevices,
                    color: .purple
                )
                ComplianceDonutChart(
                    title: "Firewall",
                    compliant: summary.firewallEnabled,
                    total: summary.totalDevices,
                    color: .orange
                )
            }
        }
    }

    // MARK: - Device security table

    private var deviceTable: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                DashSectionHeader("Device Security Detail", systemImage: "list.bullet.clipboard")
                if showIssuesOnly {
                    Text("\(visibleDevices.count) of \(vm.devices.count) with issues")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
                Spacer()
            }

            VStack(spacing: 0) {
                if visibleDevices.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.green)
                        Text("All devices are compliant")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(32)
                } else {
                    // Header row
                    HStack {
                        Text("Device Name").frame(maxWidth: .infinity, alignment: .leading)
                        Text("OS").frame(width: 80, alignment: .leading)
                        Text("FileVault").frame(width: 100, alignment: .center)
                        Text("SIP").frame(width: 70, alignment: .center)
                        Text("Firewall").frame(width: 80, alignment: .center)
                        Text("Gatekeeper").frame(width: 110, alignment: .center)
                        Spacer().frame(width: 28)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.05))

                    Divider()

                    ForEach(Array(visibleDevices.enumerated()), id: \.element.id) { idx, device in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name)
                                    .lineLimit(1)
                                Text(device.serial)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Text(device.osVersion)
                                .font(.caption)
                                .frame(width: 80, alignment: .leading)

                            SecurityIndicator(ok: device.isFilevaultEncrypted)
                                .frame(width: 100)
                            SecurityIndicator(ok: device.isSIPEnabled)
                                .frame(width: 70)
                            SecurityIndicator(ok: device.firewall)
                                .frame(width: 80)
                            SecurityIndicator(ok: device.isGatekeeperEnabled)
                                .frame(width: 110)

                            Group {
                                if let url = consoleURL(for: device) {
                                    Link(destination: url) {
                                        Image(systemName: "arrow.up.right.square")
                                            .imageScale(.small)
                                            .foregroundStyle(Color.accentColor)
                                    }
                                    .help("Open in Jamf Pro console")
                                    .accessibilityLabel("Open \(device.name) in Jamf Pro")
                                } else {
                                    Color.clear
                                }
                            }
                            .frame(width: 28)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(idx.isMultiple(of: 2) ? Color.primary.opacity(0.02) : Color.clear)

                        if idx < visibleDevices.count - 1 {
                            Divider().padding(.horizontal, 12)
                        }
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }
}

// MARK: - Fleet Health Score Banner

struct HealthScoreBanner: View {
    let score: FleetHealthScore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DashSectionHeader("Fleet Health Score", systemImage: "heart.text.square.fill")

            HStack(alignment: .center, spacing: 24) {
                circularGauge
                breakdownGrid
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Fleet health score: \(score.score), grade \(score.grade)")
        }
    }

    private var circularGauge: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 8)
            Circle()
                .trim(from: 0, to: CGFloat(score.score) / 100)
                .stroke(
                    score.gradeColor,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(score.score)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(score.gradeColor)
                Text(score.grade)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(score.gradeColor.opacity(0.8))
            }
        }
        .frame(width: 80, height: 80)
    }

    private var breakdownGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            if score.isPartial {
                Label("Partial score — load patch data for full score", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160), spacing: 6)],
                spacing: 6
            ) {
                ForEach(score.breakdown) { component in
                    ScoreChip(component: component)
                }
            }
        }
    }
}

// MARK: - Score Chip

private struct ScoreChip: View {
    let component: ScoreComponent

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: component.systemImage)
                .foregroundStyle(component.color)
                .imageScale(.small)
            Text(component.name)
                .font(.caption2)
            Text("\(Int(component.earned))/\(Int(component.maxPoints))")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(component.color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(component.color.opacity(0.1), in: Capsule())
    }
}

// MARK: - Security status indicator

private struct SecurityIndicator: View {
    let ok: Bool

    var body: some View {
        Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(ok ? .green : .red)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(ok ? "Enabled" : "Disabled")
    }
}
