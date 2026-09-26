import SwiftUI

private enum DDMViewMode: String, CaseIterable {
    case perDevice = "Per Device"
    case statusItems = "Status Items"
    case fleetOverview = "Fleet Overview"
    case updateReadiness = "Update Readiness"
}

struct DDMMonitorView: View {
    @Bindable var vm: DDMMonitorViewModel
    @State private var searchText = ""
    @State private var viewMode: DDMViewMode = .perDevice

    var body: some View {
        Group {
            if viewMode == .fleetOverview {
                DDMFleetStatusView(vm: vm)
                    .task {
                        await vm.loadFleetStatus()
                        await vm.load()
                    }
            } else if viewMode == .statusItems {
                DDMDeviceStatusTableView(vm: vm)
            } else if viewMode == .updateReadiness {
                UpdateReadinessView(vm: vm.readiness)
                    .task { await vm.readiness.load() }
            } else {
                Group {
                    switch vm.devicesState {
                    case .idle, .loading:
                        VStack(spacing: 12) {
                            SyncingIndicator()
                            Text("Loading DDM devices…")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    case .failed(let error):
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 36))
                                .foregroundStyle(.orange)
                            Text("Failed to load DDM devices")
                                .font(.headline)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 300)
                            Button("Retry") {
                                Task { await vm.load(force: true) }
                            }
                            .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    case .loaded:
                        HSplitView {
                            deviceList
                                .frame(minWidth: 220, idealWidth: 260, maxWidth: 360)

                            DDMDeclarationDetailView(
                                state: vm.statusItemsState,
                                hasSelection: vm.selectedDeviceId != nil,
                                endpointUnsupported: vm.statusItemsEndpointUnsupported,
                                onRetry: {
                                    if let id = vm.selectedDeviceId {
                                        Task { await vm.loadStatusItems(for: id) }
                                    }
                                }
                            )
                            .frame(minWidth: 300, maxWidth: .infinity)
                        }
                        .onChange(of: vm.selectedDeviceId) { _, deviceId in
                            guard let deviceId else { return }
                            Task { await vm.loadStatusItems(for: deviceId) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task { await vm.load() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("DDM Monitor")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("View", selection: $viewMode) {
                    ForEach(DDMViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 440)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    switch viewMode {
                    case .fleetOverview:   Task { await vm.loadFleetStatus(force: true) }
                    case .statusItems:     Task { await vm.loadAllDeviceStatusItems(force: true) }
                    case .updateReadiness: Task { await vm.readiness.load(force: true) }
                    case .perDevice:       Task { await vm.load(force: true) }
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isRefreshing)
                .help("Refresh DDM declaration status")
                .accessibilityLabel("Refresh")
            }
        }
    }

    // MARK: - Device list pane

    private var deviceList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("Search devices", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.callout)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            List(filteredDevices, selection: $vm.selectedDeviceId) { device in
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(device.serialNumber ?? device.managementId)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .tag(device.id)
            }
            .listStyle(.plain)
        }
    }

    // MARK: - Helpers

    private var isRefreshing: Bool {
        switch viewMode {
        case .fleetOverview:   return vm.fleetStatusState.isLoading
        case .statusItems:     return vm.deviceStatusState.isLoading
        case .updateReadiness: return vm.readiness.rowsState.isLoading
        case .perDevice:       return vm.devicesState.isLoading
        }
    }

    private var filteredDevices: [DDMDevice] {
        guard case .loaded(let devices) = vm.devicesState else { return [] }
        guard !searchText.isEmpty else { return devices }
        let q = searchText.lowercased()
        return devices.filter {
            $0.name.lowercased().contains(q) ||
            ($0.serialNumber?.lowercased().contains(q) ?? false)
        }
    }
}

// MARK: - Fleet Overview

private struct DDMFleetStatusView: View {
    @Bindable var vm: DDMMonitorViewModel

    var body: some View {
        AsyncContentView(state: vm.fleetStatusState, retry: { await vm.loadFleetStatus(force: true) }) { stats in
            VStack(spacing: 0) {
                if let coverage = vm.coverage {
                    DDMCoverageBar(coverage: coverage)
                    Divider()
                }
                fleetTable(stats)
            }
        }
    }

    @ViewBuilder
    private func fleetTable(_ stats: [DDMDeclarationStat]) -> some View {
            if stats.isEmpty && vm.fleetStatusEndpointUnsupported {
                DDMEndpointUnsupportedView(what: "DDM declaration report")
            } else if stats.isEmpty {
                ContentUnavailableView(
                    "No Declaration Data",
                    systemImage: "arrow.triangle.2.circlepath.circle",
                    description: Text("No fleet-wide DDM declaration data available.")
                )
            } else {
                Table(stats) {
                    TableColumn("Declaration") { stat in
                        Text(stat.declaration)
                            .lineLimit(1)
                    }
                    TableColumn("✓ Succeeded") { stat in
                        Text("\(stat.succeededCount)")
                            .foregroundStyle(stat.succeededCount > 0 ? .green : .secondary)
                            .monospacedDigit()
                    }
                    .width(100)
                    TableColumn("✗ Failed") { stat in
                        Text("\(stat.failedCount)")
                            .foregroundStyle(stat.failedCount > 0 ? .red : .secondary)
                            .monospacedDigit()
                    }
                    .width(80)
                    TableColumn("⏳ Pending") { stat in
                        Text("\(stat.pendingCount)")
                            .foregroundStyle(stat.pendingCount > 0 ? .orange : .secondary)
                            .monospacedDigit()
                    }
                    .width(90)
                    TableColumn("Total") { stat in
                        Text("\(stat.totalCount)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .width(70)
                }
            }
    }
}

// MARK: - Declaration coverage

private struct DDMCoverageBar: View {
    let coverage: DDMCoverageSummary

    var body: some View {
        HStack(spacing: 24) {
            metric("DDM Devices",
                   value: "\(coverage.ddmEnabledDevices) / \(coverage.inventoryDevices)",
                   detail: coverage.deviceCoverage.map { $0.formatted(.percent.precision(.fractionLength(0))) + " coverage" })
            metric("Declarations", value: "\(coverage.declarationCount)", detail: nil)
            metric("Succeeded",
                   value: coverage.successRate.map { $0.formatted(.percent.precision(.fractionLength(1))) } ?? "—",
                   detail: "\(coverage.succeeded) statuses")
            metric("Failed", value: "\(coverage.failed)", detail: coverage.failed > 0 ? "needs review" : nil,
                   tint: coverage.failed > 0 ? .red : nil)
            metric("Pending", value: "\(coverage.pending)", detail: nil,
                   tint: coverage.pending > 0 ? .orange : nil)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    private func metric(_ title: String, value: String, detail: String?, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
                .foregroundStyle(tint ?? .primary)
            if let detail {
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Status items across devices

private struct DDMDeviceStatusTableView: View {
    @Bindable var vm: DDMMonitorViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("Filter", selection: $vm.statusFilter) {
                    ForEach(DDMStatusFilter.allCases) { f in Text(f.rawValue).tag(f) }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 240)
                if vm.deviceStatusState.isLoading {
                    ProgressView(value: Double(vm.deviceStatusProgress.done),
                                 total: Double(max(vm.deviceStatusProgress.total, 1)))
                        .frame(maxWidth: 200)
                    Text("\(vm.deviceStatusProgress.done) of \(vm.deviceStatusProgress.total) devices")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.regularMaterial)
            Divider()
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.deviceStatusState {
        case .idle:
            ContentUnavailableView {
                Label("Status Items Across Devices", systemImage: "list.bullet.rectangle")
            } description: {
                Text("Fetches the latest DDM status report of every DDM-enabled Mac (one jamf-cli call per device) and shows enrollment type, awaiting configuration, Lockdown Mode, hardware health and software update state as columns.")
            } actions: {
                Button("Load Status Items") { Task { await vm.loadAllDeviceStatusItems() } }
                    .buttonStyle(.borderedProminent)
            }
        case .loading:
            SyncingIndicator().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ErrorStateView(message: message) { await vm.loadAllDeviceStatusItems(force: true) }
        case .loaded(let rows) where rows.isEmpty:
            ContentUnavailableView("No DDM Devices", systemImage: "desktopcomputer",
                                   description: Text("No devices with a DDM management ID were found."))
        case .loaded:
            if vm.statusItemsEndpointUnsupported {
                DDMEndpointUnsupportedView(what: "DDM status items")
            } else {
                table
            }
        }
    }

    private var table: some View {
        Table(vm.filteredDeviceStatusRows) {
            TableColumn("Device") { row in
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.device.name).lineLimit(1)
                    if let error = row.error {
                        Text(error).font(.caption2).foregroundStyle(.red).lineLimit(1)
                    } else if let serial = row.device.serialNumber {
                        Text(serial).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            TableColumn("OS") { row in Text(row.summary?.osVersion ?? "—").monospacedDigit() }
                .width(60)
            TableColumn("Enrollment") { row in cell(row.summary?.enrollmentTypeLabel) }
                .width(85)
            TableColumn("Awaiting Config") { row in boolCell(row.summary?.isAwaitingConfiguration, trueTint: .orange) }
                .width(100)
            TableColumn("Lockdown") { row in boolCell(row.summary?.lockdownModeEnabled, trueTint: .blue) }
                .width(70)
            TableColumn("Hardware") { row in
                if let s = row.summary, s.systemHealth != nil {
                    let bad = s.unhealthyComponents
                    Text(bad.isEmpty ? "OK" : bad.joined(separator: ", "))
                        .foregroundStyle(bad.isEmpty ? Color.green : Color.red)
                        .lineLimit(1)
                } else {
                    cell(nil)
                }
            }
            .width(90)
            TableColumn("Update State") { row in
                let su = row.summary?.softwareUpdate
                Text(su?.installState?.capitalized ?? "—")
                    .foregroundStyle(su?.isFailed == true ? .red : .primary)
            }
            .width(95)
            TableColumn("Pending") { row in
                cell(row.summary?.softwareUpdate.hasPendingUpdate == true ? row.summary?.softwareUpdate.pendingOSVersion : nil)
            }
            .width(70)
            TableColumn("Failures") { row in
                let count = row.summary?.softwareUpdate.failureCount
                Text(count.map(String.init) ?? "—")
                    .foregroundStyle((count ?? 0) > 0 ? .red : .secondary)
                    .monospacedDigit()
                    .help(row.summary?.softwareUpdate.failureReason ?? "")
            }
            .width(60)
        }
    }

    private func cell(_ value: String?) -> some View {
        Text(value ?? "—").foregroundStyle(value == nil ? .tertiary : .primary)
    }

    private func boolCell(_ value: Bool?, trueTint: Color) -> some View {
        Text(value.map { $0 ? "Yes" : "No" } ?? "—")
            .foregroundStyle(value == true ? trueTint : (value == nil ? Color.secondary : Color.primary))
    }
}

#Preview {
    DDMMonitorView(vm: DDMMonitorViewModel(cli: DemoCLIManager()))
}
