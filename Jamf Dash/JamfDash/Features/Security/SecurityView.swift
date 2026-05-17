import SwiftUI

struct SecurityView: View {
    @Bindable var vm: SecurityViewModel
    @Environment(AppEnvironment.self) private var env
    @State private var showIssuesOnly = false

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
                    Task { await vm.load(force: true) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(vm.state.isLoading)
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

// MARK: - Security status indicator

private struct SecurityIndicator: View {
    let ok: Bool

    var body: some View {
        Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(ok ? .green : .red)
            .frame(maxWidth: .infinity)
    }
}
