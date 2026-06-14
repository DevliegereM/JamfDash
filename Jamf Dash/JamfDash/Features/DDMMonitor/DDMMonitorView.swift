import SwiftUI

private enum DDMViewMode: String, CaseIterable {
    case perDevice = "Per Device"
    case fleetOverview = "Fleet Overview"
}

struct DDMMonitorView: View {
    @Bindable var vm: DDMMonitorViewModel
    @State private var searchText = ""
    @State private var viewMode: DDMViewMode = .perDevice

    var body: some View {
        Group {
            if viewMode == .fleetOverview {
                DDMFleetStatusView(vm: vm)
                    .task { await vm.loadFleetStatus() }
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
                .frame(width: 200)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if viewMode == .fleetOverview {
                        Task { await vm.loadFleetStatus(force: true) }
                    } else {
                        Task { await vm.load(force: true) }
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewMode == .fleetOverview ? vm.fleetStatusState.isLoading : vm.devicesState.isLoading)
                .help("Refresh DDM declaration status")
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
            if stats.isEmpty {
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
}

#Preview {
    DDMMonitorView(vm: DDMMonitorViewModel(cli: DemoCLIManager()))
}
