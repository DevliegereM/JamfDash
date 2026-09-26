import SwiftUI

struct CorrelationView: View {
    @Bindable var vm: CorrelationViewModel
    @Environment(AppEnvironment.self) private var env
    @State private var selectedID: CorrelatedDevice.ID?
    @State private var selectedDevice: CorrelatedDevice?

    var body: some View {
        VStack(spacing: 0) {
            searchFilterBar
            Divider()

            if vm.devices.isEmpty {
                ContentUnavailableView(
                    "No Devices to Correlate",
                    systemImage: "link.badge.plus",
                    description: Text(
                        "Make sure both Jamf Pro and Jamf Protect data are loaded. " +
                        "Switch to Jamf Pro to load devices, then return here."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                deviceSplitView
            }
        }
        .navigationTitle("Device Correlation")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                summaryChips
            }
            ToolbarItem(placement: .primaryAction) {
                refreshButton
            }
        }
        .liquidGlassToolbar()
        .task {
            if vm.devices.isEmpty {
                vm.correlate(
                    pro: env.devicesVM.allComputers,
                    protect: env.protectVM.computersState.value ?? []
                )
            }
        }
    }

    // MARK: - Search & Filter Bar

    private var searchFilterBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search devices…", text: $vm.searchText)
                .textFieldStyle(.plain)
            Spacer()
            Picker("Filter", selection: $vm.filter) {
                ForEach(CorrelationFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 320)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    // MARK: - Split View

    private var deviceSplitView: some View {
        VSplitView {
            deviceTable
                .frame(minHeight: 200)

            if let device = selectedDevice {
                CorrelationDetailPanel(device: device, env: env)
                    .frame(minHeight: 180)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Text("Select a device to view details")
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Device Table

    private var deviceTable: some View {
        Table(vm.filtered, selection: $selectedID) {
            TableColumn("") { (device: CorrelatedDevice) in
                Image(systemName: device.matchState.icon)
                    .foregroundStyle(device.matchState.color)
                    .help(device.matchState.rawValue)
            }
            .width(24)

            TableColumn("Device") { (device: CorrelatedDevice) in
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.displayName).lineLimit(1)
                    Text(device.displaySerial)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            TableColumn("Protect Plan") { (device: CorrelatedDevice) in
                Text(device.protectComputer?.planName ?? "—")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            TableColumn("Last Protect Check-in") { (device: CorrelatedDevice) in
                Text(device.protectComputer?.formattedCheckinTime ?? "—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            TableColumn("OS") { (device: CorrelatedDevice) in
                Text(device.displayOS ?? "—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TableColumn("Last Pro Contact") { (device: CorrelatedDevice) in
                if let days = device.proComputer?.daysSinceContact {
                    Text("\(days)d ago")
                        .font(.caption)
                        .foregroundStyle(days >= 30 ? .orange : .secondary)
                } else {
                    Text("—")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: selectedID) { _, newID in
            selectedDevice = vm.filtered.first { $0.id == newID }
        }
    }

    // MARK: - Toolbar Items

    private var summaryChips: some View {
        HStack(spacing: 8) {
            CorrelationCountChip(count: vm.matchedCount, label: "Matched", color: .green)
            CorrelationCountChip(count: vm.proOnlyCount, label: "Pro Only", color: .blue)
            CorrelationCountChip(count: vm.protectOnlyCount, label: "Protect Only", color: .orange)
        }
    }

    private var refreshButton: some View {
        Button {
            vm.correlate(
                pro: env.devicesVM.allComputers,
                protect: env.protectVM.computersState.value ?? []
            )
        } label: {
            Label("Refresh Correlation", systemImage: "arrow.triangle.2.circlepath")
        }
        .help("Re-run correlation with current data")
    }
}

// MARK: - Detail Panel

private struct CorrelationDetailPanel: View {
    let device: CorrelatedDevice
    let env: AppEnvironment

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            protectSide
            Divider()
            proSide
        }
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: Protect side

    private var protectSide: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Jamf Protect", systemImage: "shield.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)

            if let pc = device.protectComputer {
                detailGrid([
                    ("Plan", pc.planName ?? "—"),
                    ("Status", pc.connectionStatus ?? "—"),
                    ("Full Disk Access", pc.fullDiskAccess ?? "—"),
                    ("Web Protection", pc.webProtectionActive.map { $0 ? "Active" : "Inactive" } ?? "—"),
                    ("Agent Version", pc.agentVersion ?? "—"),
                    ("Last Check-in", pc.formattedCheckinTime ?? "—"),
                ])
            } else {
                Text("Not enrolled in Jamf Protect")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    // MARK: Pro side

    private var proSide: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Jamf Pro", systemImage: "laptopcomputer")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.blue)

            if let pc = device.proComputer {
                detailGrid([
                    ("Managed", pc.managed.map { $0 ? "Yes" : "No" } ?? "—"),
                    ("OS Version", pc.osVersion ?? "—"),
                    ("Serial", pc.serialNumber ?? "—"),
                    ("Last Contact", pc.daysSinceContact.map { "\($0) days ago" } ?? "—"),
                ])

                Spacer()

                if let serial = pc.serialNumber {
                    HStack(spacing: 8) {
                        QuickActionButton(
                            title: "Blank Push",
                            icon: "bell.fill",
                            cliCommand: .blankPush(serial: serial),
                            env: env
                        )
                        QuickActionButton(
                            title: "Restart",
                            icon: "arrow.clockwise",
                            cliCommand: .restart(serial: serial),
                            env: env
                        )
                    }
                }
            } else {
                Text("Not enrolled in Jamf Pro")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    // MARK: Helpers

    private func detailGrid(_ rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(rows, id: \.0) { label, value in
                HStack(alignment: .top) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 120, alignment: .leading)
                    Text(value)
                        .font(.caption)
                        .lineLimit(2)
                }
            }
        }
    }
}

// MARK: - Quick Action Button

private struct QuickActionButton: View {
    let title: String
    let icon: String
    let cliCommand: CLICommand
    let env: AppEnvironment
    @State private var isRunning = false

    var body: some View {
        Button {
            isRunning = true
            Task {
                _ = try? await env.cliManager.run(cliCommand)
                isRunning = false
            }
        } label: {
            HStack(spacing: 4) {
                if isRunning {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: icon).imageScale(.small)
                }
                Text(title).font(.caption)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(isRunning)
    }
}

// MARK: - Count Chip

private struct CorrelationCountChip: View {
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.1), in: Capsule())
    }
}
