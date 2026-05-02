import SwiftUI
import Charts
import UniformTypeIdentifiers

struct DevicesView: View {
    @Bindable var vm: DevicesViewModel
    @State private var selectedTab = 0
    @State private var selectedOSVersion: String? = nil
    @State private var selectedDeviceIDs: Set<Computer.ID> = []
    @State private var sortOrder: [KeyPathComparator<Computer>] = []
    @State private var filterManaged: Bool? = nil

    private let versionColors: [Color] = [
        .blue, .green, .orange, .purple, .pink, .teal, .indigo, .yellow, .mint, .cyan
    ]

    private func colorForVersion(_ version: String) -> Color {
        let idx = vm.osDistribution.firstIndex(where: { $0.version == version }) ?? 0
        return versionColors[idx % versionColors.count]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search by name or serial…", text: $vm.searchText)
                    .textFieldStyle(.plain)
                if !vm.searchText.isEmpty {
                    Button { vm.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.regularMaterial)

            Picker("View", selection: $selectedTab) {
                Text("All Devices").tag(0)
                Text("Stale Check-in").tag(1)
                Text("macOS Versions").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(.regularMaterial)

            Divider()

            Group {
                if vm.state.isPending {
                    SyncingIndicator().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = vm.state.errorMessage {
                    ErrorStateView(message: error) { await vm.load(force: true) }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    switch selectedTab {
                    case 0: allDevicesTab
                    case 1: staleTab
                    case 2: osDistributionTab
                    default: EmptyView()
                    }
                }
            }
        }
        .navigationTitle("Devices")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { exportCSV() } label: {
                    Label("Export CSV", systemImage: "arrow.down.doc")
                }
                .disabled(vm.state.isPending || selectedTab == 2)
                .help("Export device list as CSV")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await vm.load(force: true) } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(vm.state.isLoading)
            }
        }
    }

    // MARK: - All Devices

    private var allDevicesFiltered: [Computer] {
        let base = filterManaged == nil ? vm.filtered : vm.filtered.filter { $0.managed == filterManaged }
        return sortOrder.isEmpty ? base : base.sorted(using: sortOrder)
    }

    private var allDevicesTab: some View {
        VStack(spacing: 0) {
            HStack(spacing: 24) {
                statPill(label: "Total", value: "\(vm.totalCount)", color: .blue)
                statPill(label: "Managed", value: "\(vm.managedCount)", color: .green)
                statPill(label: "Stale (>\(vm.staleThresholdDays)d)", value: "\(vm.staleDevices.count)", color: .orange)
                Spacer()
                Menu {
                    Button {
                        filterManaged = nil
                    } label: {
                        Label("All Devices", systemImage: filterManaged == nil ? "checkmark" : "")
                    }
                    Button {
                        filterManaged = true
                    } label: {
                        Label("Managed Only", systemImage: filterManaged == true ? "checkmark" : "")
                    }
                    Button {
                        filterManaged = false
                    } label: {
                        Label("Unmanaged Only", systemImage: filterManaged == false ? "checkmark" : "")
                    }
                } label: {
                    Label(filterManaged == nil ? "Filter" : filterManaged == true ? "Managed" : "Unmanaged",
                          systemImage: "line.3.horizontal.decrease.circle\(filterManaged != nil ? ".fill" : "")")
                        .font(.callout)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.03))

            Divider()

            if allDevicesFiltered.isEmpty {
                emptyState(icon: "desktopcomputer", label: vm.searchText.isEmpty && filterManaged == nil ? "No devices enrolled" : "No results")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(allDevicesFiltered, selection: $selectedDeviceIDs, sortOrder: $sortOrder) {
                    TableColumn("Name", value: \.name) { Text($0.name).lineLimit(1) }
                    TableColumn("Serial", value: \.sortableSerial) {
                        Text($0.serialNumber ?? "—").font(.caption).foregroundStyle(.secondary)
                    }
                    TableColumn("OS", value: \.sortableOS) {
                        Text($0.osVersion ?? "—").font(.caption).foregroundStyle(.secondary)
                    }
                    TableColumn("Last Contact", value: \.sortableContact) { device in
                        staleLabel(for: device)
                    }
                    TableColumn("Managed") { device in
                        if let m = device.managed {
                            Image(systemName: m ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundStyle(m ? .green : .secondary)
                        } else {
                            Text("—").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !selectedDeviceIDs.isEmpty {
                bulkActionBar
            }
        }
        .sheet(item: $vm.bulkActionSummary) { summary in
            BulkActionResultSheet(summary: summary)
                .onDisappear { vm.clearBulkActionSummary() }
        }
    }

    // MARK: - Bulk action bar

    private var bulkActionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                Text("\(selectedDeviceIDs.count) selected")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                if vm.isBulkRunning {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Running…").foregroundStyle(.secondary).font(.callout)
                    }
                } else {
                    Menu("Actions") {
                        Button("Blank Push")           { runBulk(CLICommand.blankPush,          name: "Blank Push") }
                        Button("Renew MDM")             { runBulk(CLICommand.renewMDM,            name: "Renew MDM") }
                        Button("Redeploy Framework")    { runBulk(CLICommand.redeployFramework,   name: "Redeploy Framework") }
                        Divider()
                        Button("Flush Failed Commands") { runBulk(CLICommand.flushFailedCommands, name: "Flush Failed Commands") }
                    }
                    .menuStyle(.borderedButton)

                    Button("Clear") { selectedDeviceIDs = [] }
                        .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial)
        }
    }

    private func runBulk(_ makeCmd: @escaping @Sendable (String) -> CLICommand, name: String) {
        let devices = vm.filtered
            .filter { selectedDeviceIDs.contains($0.id) }
            .compactMap { d -> (name: String, serial: String)? in
                guard let s = d.serialNumber, !s.isEmpty else { return nil }
                return (name: d.name, serial: s)
            }
        Task {
            await vm.runBulkAction(makeCmd, actionName: name, devices: devices)
            selectedDeviceIDs = []
        }
    }

    // MARK: - Stale Check-in

    private var staleTab: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Flag devices with no check-in for more than:")
                    .font(.callout).foregroundStyle(.secondary)
                Stepper("\(vm.staleThresholdDays) days", value: $vm.staleThresholdDays, in: 1...365)
                    .fixedSize()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.03))

            Divider()

            if vm.staleDevices.isEmpty {
                emptyState(icon: "checkmark.seal", label: "No stale devices — all checked in within \(vm.staleThresholdDays) days")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        HStack {
                            Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                            Text("Serial").frame(width: 130, alignment: .leading)
                            Text("Last Contact").frame(width: 150, alignment: .trailing)
                        }
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 20).padding(.vertical, 6)
                        .background(Color.primary.opacity(0.04))

                        Divider()

                        ForEach(Array(vm.staleDevices.enumerated()), id: \.element.id) { idx, device in
                            HStack {
                                Text(device.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                                Text(device.serialNumber ?? "—")
                                    .font(.caption).foregroundStyle(.secondary).frame(width: 130, alignment: .leading)
                                    .textSelection(.enabled)
                                staleLabel(for: device).frame(width: 150, alignment: .trailing)
                            }
                            .padding(.horizontal, 20).padding(.vertical, 8)
                            .background(idx.isMultiple(of: 2) ? Color.primary.opacity(0.02) : Color.clear)
                            if idx < vm.staleDevices.count - 1 { Divider().padding(.horizontal, 20) }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    // MARK: - macOS Version Distribution

    private var osDistributionTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if vm.osDistribution.isEmpty {
                    emptyState(icon: "applelogo", label: "No devices enrolled")
                } else {
                    // Chart + legend side by side
                    HStack(alignment: .top, spacing: 24) {
                        // Donut chart
                        Chart(vm.osDistribution, id: \.version) { row in
                            SectorMark(
                                angle: .value("Devices", row.count),
                                innerRadius: .ratio(0.48),
                                angularInset: 2
                            )
                            .foregroundStyle(colorForVersion(row.version))
                            .opacity(selectedOSVersion == nil || selectedOSVersion == row.version ? 1.0 : 0.22)
                            .cornerRadius(4)
                        }
                        .chartLegend(.hidden)
                        .frame(width: 200, height: 200)

                        // Legend — tap to filter
                        VStack(spacing: 0) {
                            ForEach(vm.osDistribution, id: \.version) { row in
                                Button {
                                    selectedOSVersion = selectedOSVersion == row.version ? nil : row.version
                                } label: {
                                    HStack(spacing: 10) {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(colorForVersion(row.version))
                                            .frame(width: 12, height: 12)
                                        Text(row.version)
                                            .font(.callout)
                                            .foregroundStyle(
                                                selectedOSVersion == nil || selectedOSVersion == row.version
                                                    ? Color.primary : Color.secondary
                                            )
                                        Spacer()
                                        Text("\(row.count)")
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 8).padding(.vertical, 2)
                                            .background(.quaternary, in: Capsule())
                                        Text(String(format: "%.0f%%",
                                                    vm.totalCount > 0
                                                        ? Double(row.count) / Double(vm.totalCount) * 100
                                                        : 0))
                                            .font(.caption).foregroundStyle(.secondary)
                                            .frame(width: 40, alignment: .trailing)
                                    }
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(
                                        selectedOSVersion == row.version
                                            ? colorForVersion(row.version).opacity(0.12)
                                            : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 6)
                                    )
                                }
                                .buttonStyle(.plain)

                                if row.version != vm.osDistribution.last?.version {
                                    Divider().padding(.horizontal, 12)
                                }
                            }
                        }
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08)))
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 20)

                    // Filtered device list (shown when a version is selected)
                    if let version = selectedOSVersion {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Text("Devices on \(version)")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Button {
                                    selectedOSVersion = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(Color.primary.opacity(0.04))

                            Divider()

                            let devices = vm.devicesForOS(version)
                            if devices.isEmpty {
                                Text("No devices")
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(20)
                            } else {
                                HStack {
                                    Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                                    Text("Serial").frame(width: 130, alignment: .leading)
                                    Text("Last Contact").frame(width: 120, alignment: .trailing)
                                }
                                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                .padding(.horizontal, 16).padding(.vertical, 6)
                                .background(Color.primary.opacity(0.04))

                                Divider()

                                ForEach(Array(devices.enumerated()), id: \.element.id) { idx, device in
                                    HStack {
                                        Text(device.name).lineLimit(1)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text(device.serialNumber ?? "—")
                                            .font(.caption).foregroundStyle(.secondary)
                                            .frame(width: 130, alignment: .leading)
                                            .textSelection(.enabled)
                                        staleLabel(for: device).frame(width: 120, alignment: .trailing)
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 8)
                                    .background(idx.isMultiple(of: 2) ? Color.primary.opacity(0.02) : Color.clear)
                                    if idx < devices.count - 1 { Divider().padding(.horizontal, 16) }
                                }
                            }
                        }
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08)))
                        .padding(.horizontal, 20)
                    }
                }
            }
            .padding(.vertical, 20)
        }
    }

    // MARK: - Helpers

    private func staleLabel(for device: Computer) -> some View {
        Group {
            if let days = device.daysSinceContact {
                Text("\(days)d ago")
                    .font(.caption)
                    .foregroundStyle(days >= vm.staleThresholdDays ? .orange : .secondary)
            } else if let str = device.lastContactTime {
                Text(str).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text("—").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func statPill(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.bold()).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func emptyState(icon: String, label: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 36)).foregroundStyle(.secondary)
            Text(label).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity).padding(40)
    }

    // MARK: - CSV Export

    private func exportCSV() {
        let devices: [Computer]
        let filename: String
        switch selectedTab {
        case 1:
            devices = vm.staleDevices
            filename = "stale-devices.csv"
        default:
            devices = vm.filtered
            filename = "devices.csv"
        }

        let csv = csvString(from: devices)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename
        panel.allowedContentTypes = [UTType.commaSeparatedText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? csv.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func csvString(from devices: [Computer]) -> String {
        var lines = ["Name,Serial Number,OS Version,Last Contact,Managed"]
        for d in devices {
            let fields = [
                d.name,
                d.serialNumber ?? "",
                d.osVersion ?? "",
                d.lastContactTime ?? "",
                d.managed == true ? "Yes" : "No"
            ]
            lines.append(fields.map(csvEscape).joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private func csvEscape(_ s: String) -> String {
        guard s.contains(",") || s.contains("\"") || s.contains("\n") else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

// MARK: - Bulk action result sheet

private struct BulkActionResultSheet: View {
    let summary: BulkActionSummary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.actionName).font(.title2).bold()
                    Text("\(summary.successCount) succeeded · \(summary.failureCount) failed")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            Table(summary.results) {
                TableColumn("Device") { Text($0.deviceName) }
                TableColumn("Serial") {
                    Text($0.serial).font(.caption).foregroundStyle(.secondary)
                }
                TableColumn("Result") { result in
                    HStack(spacing: 6) {
                        Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(result.success ? .green : .red)
                        Text(result.success ? "Success" : "Failed").font(.caption)
                    }
                }
                TableColumn("Message") {
                    Text($0.message).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 320)
    }
}

// MARK: - Sortable Computer helpers (used only by DevicesView Table columns)

fileprivate extension Computer {
    var sortableSerial:  String { serialNumber ?? "" }
    var sortableOS:      String { osVersion ?? "" }
    var sortableContact: Int    { daysSinceContact ?? Int.max }
}
