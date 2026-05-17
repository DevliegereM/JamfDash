import SwiftUI

struct DDMMonitorView: View {
    @Bindable var vm: DDMMonitorViewModel
    @State private var searchText = ""

    var body: some View {
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
        .navigationTitle("DDM Monitor")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await vm.load(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(vm.devicesState.isLoading)
            }
        }
        .task { await vm.load() }
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

#Preview {
    DDMMonitorView(vm: DDMMonitorViewModel(cli: DemoCLIManager()))
}
