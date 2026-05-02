import SwiftUI
import Charts
import UniformTypeIdentifiers

struct MobileDevicesView: View {
    @Bindable var vm: MobileDevicesViewModel
    @State private var selectedTab = 0
    @State private var selectedOSVersion: String? = nil
    @State private var selectedDeviceID: String? = nil
    @State private var selectedDevice: MobileDevice? = nil
    @State private var sortOrder: [KeyPathComparator<MobileDevice>] = []

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
                TextField("Search by name, serial, or model…", text: $vm.searchText)
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
                Text("OS Versions").tag(2)
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
        .navigationTitle("Mobile Devices")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { exportCSV() } label: {
                    Label("Export CSV", systemImage: "arrow.down.doc")
                }
                .disabled(vm.state.isPending || selectedTab == 2)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await vm.load(force: true) } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(vm.state.isLoading)
            }
        }
        .sheet(item: $selectedDevice) { device in
            MobileDeviceDetailSheet(device: device, vm: vm)
                .onDisappear { vm.actionResult = nil }
        }
        .task { await vm.load() }
    }

    // MARK: - All Devices Tab

    private var allDevicesFiltered: [MobileDevice] {
        sortOrder.isEmpty ? vm.filtered : vm.filtered.sorted(using: sortOrder)
    }

    private var allDevicesTab: some View {
        VStack(spacing: 0) {
            HStack(spacing: 24) {
                statPill(label: "Total",   value: "\(vm.totalCount)",   color: .blue)
                statPill(label: "Managed", value: "\(vm.managedCount)", color: .green)
                statPill(label: "Stale (>\(vm.staleThresholdDays)d)", value: "\(vm.staleDevices.count)", color: .orange)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.03))

            Divider()

            if allDevicesFiltered.isEmpty {
                mdEmptyState(icon: "iphone", label: vm.searchText.isEmpty ? "No mobile devices enrolled" : "No results")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(allDevicesFiltered, selection: $selectedDeviceID, sortOrder: $sortOrder) {
                    TableColumn("Name", value: \.name) { Text($0.name).lineLimit(1) }
                    TableColumn("Serial", value: \.sortableSerial) {
                        Text($0.serialNumber ?? "—").font(.caption).foregroundStyle(.secondary)
                    }
                    TableColumn("Model", value: \.sortableModel) {
                        Text($0.model ?? "—").font(.caption).foregroundStyle(.secondary)
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
                .onChange(of: selectedDeviceID) { _, id in
                    selectedDevice = id.flatMap { id in allDevicesFiltered.first { $0.id == id } }
                }
            }
        }
    }

    // MARK: - Stale Check-in Tab

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
                mdEmptyState(icon: "checkmark.seal", label: "No stale devices — all checked in within \(vm.staleThresholdDays) days")
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
                                Text(device.serialNumber ?? "—")
                                    .font(.caption).foregroundStyle(.secondary).frame(width: 130, alignment: .leading)
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

    // MARK: - OS Distribution Tab

    private var osDistributionTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if vm.osDistribution.isEmpty {
                    mdEmptyState(icon: "iphone", label: "No mobile devices enrolled")
                } else {
                    HStack(alignment: .top, spacing: 24) {
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

                        VStack(spacing: 0) {
                            ForEach(vm.osDistribution, id: \.version) { row in
                                Button {
                                    selectedOSVersion = selectedOSVersion == row.version ? nil : row.version
                                } label: {
                                    HStack(spacing: 10) {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(colorForVersion(row.version))
                                            .frame(width: 12, height: 12)
                                        Text(row.version).font(.callout)
                                            .foregroundStyle(selectedOSVersion == nil || selectedOSVersion == row.version ? Color.primary : Color.secondary)
                                        Spacer()
                                        Text("\(row.count)")
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 8).padding(.vertical, 2)
                                            .background(.quaternary, in: Capsule())
                                        Text(String(format: "%.0f%%",
                                             vm.totalCount > 0 ? Double(row.count) / Double(vm.totalCount) * 100 : 0))
                                            .font(.caption).foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                                    }
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(selectedOSVersion == row.version ? colorForVersion(row.version).opacity(0.12) : Color.clear,
                                                in: RoundedRectangle(cornerRadius: 6))
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

                    if let version = selectedOSVersion {
                        let devices = vm.devicesForOS(version)
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Text("Devices on \(version)").font(.subheadline.weight(.semibold))
                                Spacer()
                                Button { selectedOSVersion = nil } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                }.buttonStyle(.plain)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(Color.primary.opacity(0.04))

                            Divider()

                            ForEach(Array(devices.enumerated()), id: \.element.id) { idx, device in
                                HStack {
                                    Text(device.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                    Text(device.serialNumber ?? "—").font(.caption).foregroundStyle(.secondary)
                                        .frame(width: 130, alignment: .leading)
                                    staleLabel(for: device).frame(width: 120, alignment: .trailing)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                .background(idx.isMultiple(of: 2) ? Color.primary.opacity(0.02) : Color.clear)
                                if idx < devices.count - 1 { Divider().padding(.horizontal, 16) }
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

    private func staleLabel(for device: MobileDevice) -> some View {
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

    private func mdEmptyState(icon: String, label: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 36)).foregroundStyle(.secondary)
            Text(label).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity).padding(40)
    }

    // MARK: - CSV Export

    private func exportCSV() {
        let devices = selectedTab == 1 ? vm.staleDevices : vm.filtered
        let filename = selectedTab == 1 ? "stale-mobile-devices.csv" : "mobile-devices.csv"
        var lines = ["Name,Serial,Model,OS Version,Last Contact,Managed"]
        for d in devices {
            let fields = [d.name, d.serialNumber ?? "", d.model ?? "", d.osVersion ?? "", d.lastContactTime ?? "", d.managed == true ? "Yes" : "No"]
            lines.append(fields.map { s -> String in
                guard s.contains(",") || s.contains("\"") || s.contains("\n") else { return s }
                return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }.joined(separator: ","))
        }
        let csv = lines.joined(separator: "\n")
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename
        panel.allowedContentTypes = [UTType.commaSeparatedText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? csv.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Device Detail Sheet

struct MobileDeviceDetailSheet: View {
    let device: MobileDevice
    @Bindable var vm: MobileDevicesViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmAction: ConfirmableAction? = nil
    @State private var showConfirm = false

    struct ConfirmableAction: Identifiable {
        let id = UUID()
        let label: String
        let command: CLICommand
        let isDestructive: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name).font(.title2).bold()
                    Text(device.serialNumber ?? device.id).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Hardware
                    detailSection("Hardware") {
                        if let v = device.model        { detailRow("Model", value: v) }
                        if let v = device.serialNumber { detailRow("Serial", value: v) }
                    }

                    // OS & Management
                    detailSection("OS & Management") {
                        if let v = device.osVersion  { detailRow("OS Version", value: v) }
                        if let v = device.managed    { detailRow("Managed", value: v ? "Yes" : "No") }
                        if let v = device.supervised { detailRow("Supervised", value: v ? "Yes" : "No") }
                        if let v = device.enrolled   { detailRow("MDM Enrolled", value: v ? "Yes" : "No") }
                        if let v = device.lastContactTime { detailRow("Last Contact", value: v) }
                    }

                    // Actions
                    detailSection("Actions") {
                        if let s = device.serialNumber {
                            actionGrid(serial: s)
                        } else {
                            Text("Serial number required for device actions.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    // Result banner
                    if let result = vm.actionResult {
                        HStack(spacing: 8) {
                            Image(systemName: result.contains("failed") ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(result.contains("failed") ? Color.orange : Color.green)
                            Text(result).font(.callout)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 480, minHeight: 360)
        .overlay(alignment: .center) {
            if vm.isActionRunning {
                Color.black.opacity(0.2)
                    .overlay(alignment: .center) { ProgressView().controlSize(.large) }
                    .ignoresSafeArea()
            }
        }
        .alert(
            confirmAction?.isDestructive == true ? "Confirm Destructive Action" : "Confirm Action",
            isPresented: $showConfirm,
            presenting: confirmAction
        ) { action in
            Button(action.label, role: .destructive) {
                Task { await vm.runAction(action.command, label: action.label) }
            }
            Button("Cancel", role: .cancel) { }
        } message: { action in
            Text("Send \"\(action.label)\" to \(device.name)?")
        }
    }

    @ViewBuilder
    private func actionGrid(serial: String) -> some View {
        let safeActions: [(String, CLICommand)] = [
            ("Update Inventory", .mobileDeviceUpdateInventory(serial: serial))
        ]
        let moderateActions: [(String, CLICommand)] = [
            ("Restart", .mobileDeviceRestart(serial: serial)),
            ("Shutdown", .mobileDeviceShutdown(serial: serial)),
            ("Clear Passcode", .mobileDeviceClearPasscode(serial: serial)),
            ("Enable Lost Mode", .mobileDeviceEnableLostMode(serial: serial)),
            ("Disable Lost Mode", .mobileDeviceDisableLostMode(serial: serial))
        ]
        let destructiveActions: [(String, CLICommand)] = [
            ("Erase Device", .mobileDeviceErase(serial: serial)),
            ("Unmanage", .mobileDeviceUnmanage(serial: serial)),
            ("Lock Device", .mobileDeviceLock(serial: serial))
        ]

        VStack(alignment: .leading, spacing: 8) {
            Text("Safe").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(safeActions, id: \.0) { label, cmd in
                    actionButton(label: label, cmd: cmd, tint: .accentColor, isDestructive: false)
                }
            }

            Text("Moderate").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 4)
            FlowLayout(spacing: 8) {
                ForEach(moderateActions, id: \.0) { label, cmd in
                    actionButton(label: label, cmd: cmd, tint: .orange, isDestructive: false)
                }
            }

            Text("Destructive").font(.caption.weight(.semibold)).foregroundStyle(.red).padding(.top, 4)
            HStack(spacing: 8) {
                ForEach(destructiveActions, id: \.0) { label, cmd in
                    actionButton(label: label, cmd: cmd, tint: .red, isDestructive: true)
                }
            }
        }
    }

    private func actionButton(label: String, cmd: CLICommand, tint: Color, isDestructive: Bool) -> some View {
        Button(label) {
            confirmAction = ConfirmableAction(label: label, command: cmd, isDestructive: isDestructive)
            showConfirm = true
        }
        .buttonStyle(.bordered)
        .tint(tint)
        .controlSize(.small)
        .disabled(vm.isActionRunning)
    }

    @ViewBuilder
    private func detailSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08)))
    }

    @ViewBuilder
    private func detailRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(width: 120, alignment: .leading)
            Text(value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Simple flow layout for action buttons

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0; var y: CGFloat = 0; var rowHeight: CGFloat = 0; var maxY: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { y += rowHeight + spacing; x = 0; rowHeight = 0 }
            rowHeight = max(rowHeight, size.height); x += size.width + spacing
            maxY = max(maxY, y + rowHeight)
        }
        return CGSize(width: width, height: maxY)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX; var y = bounds.minY; var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { y += rowHeight + spacing; x = bounds.minX; rowHeight = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            rowHeight = max(rowHeight, size.height); x += size.width + spacing
        }
    }
}

// MARK: - Sortable helpers

fileprivate extension MobileDevice {
    var sortableSerial:  String { serialNumber ?? "" }
    var sortableModel:   String { model ?? "" }
    var sortableOS:      String { osVersion ?? "" }
    var sortableContact: Int    { daysSinceContact ?? Int.max }
}
