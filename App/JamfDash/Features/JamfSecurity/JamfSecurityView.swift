import SwiftUI

// MARK: - Main View

struct JamfSecurityView: View {
    @Bindable var vm: JamfSecurityViewModel
    @State private var selectedID: JSCDevice.ID?
    @State private var sortOrder = [KeyPathComparator(\JSCDevice.riskLevel, order: .reverse)]
    @State private var showInspector = false

    private var selectedDevice: JSCDevice? {
        guard let id = selectedID else { return nil }
        return vm.filteredDevices.first { $0.id == id }
    }

    private var sortedDevices: [JSCDevice] {
        vm.filteredDevices.sorted(using: sortOrder)
    }

    var body: some View {
        Group {
            switch vm.state {
            case .idle, .loading:
                loadingView
            case .failed(let msg):
                ContentUnavailableView(
                    "Unable to Load",
                    systemImage: "shield.slash",
                    description: Text(msg)
                )
                .toolbar { refreshToolbarItem }
            case .loaded:
                loadedContent
            }
        }
        .navigationTitle("Security Cloud")
        .task { await vm.load() }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading Jamf Security Cloud…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Loaded content

    private var loadedContent: some View {
        VStack(spacing: 0) {
            riskSummaryBanner
            Divider()
            deviceTable
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    withAnimation { showInspector.toggle() }
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help(showInspector ? "Hide inspector" : "Show device detail")
                .accessibilityLabel(showInspector ? "Hide inspector" : "Show device detail")
                .disabled(selectedDevice == nil)

                refreshToolbarItem
            }

            ToolbarItem(placement: .automatic) {
                filterToolbar
            }
        }
        .inspector(isPresented: Binding(
            get: { showInspector && selectedDevice != nil },
            set: { showInspector = $0 }
        )) {
            JSCDeviceInspector(device: selectedDevice)
        }
        .onChange(of: selectedID) { _, newID in
            if newID != nil { showInspector = true }
        }
    }

    // MARK: - Risk summary banner

    private var riskSummaryBanner: some View {
        HStack(spacing: 12) {
            ForEach([JSCRiskLevel.high, .medium, .low, .secure, .unknown], id: \.self) { level in
                let count = vm.riskSummary[level] ?? 0
                JSCRiskChip(level: level, count: count, isSelected: vm.filterRisk == level) {
                    vm.filterRisk = vm.filterRisk == level ? nil : level
                }
            }
            Spacer()
            Text("\(vm.filteredCount) of \(vm.totalCount) devices")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Filter toolbar

    private var filterToolbar: some View {
        HStack(spacing: 8) {
            if !vm.availableOSTypes.isEmpty {
                Picker("OS", selection: $vm.filterOS) {
                    Text("All OS").tag(String?.none)
                    ForEach(vm.availableOSTypes, id: \.self) { os in
                        Text(os).tag(Optional(os))
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
            }

            TextField("Search", text: $vm.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
        }
    }

    // MARK: - Device table

    private var deviceTable: some View {
        Table(sortedDevices, selection: $selectedID, sortOrder: $sortOrder) {
            TableColumn("Device", value: \.deviceNameForSort) { device in
                JSCDeviceNameCell(device: device)
            }
            .width(min: 140, ideal: 180)

            TableColumn("User", value: \.userForSort) { device in
                VStack(alignment: .leading, spacing: 1) {
                    if let name = device.userDisplayName {
                        Text(name).lineLimit(1)
                    }
                    if let email = device.userEmail, email != device.userDisplayName {
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .width(min: 130, ideal: 160)

            TableColumn("Risk", value: \.riskLevel) { device in
                JSCRiskBadge(level: device.riskLevel)
            }
            .width(min: 80, ideal: 90)

            TableColumn("OS", value: \.osTypeForSort) { device in
                Text(device.osType ?? "—")
                    .foregroundStyle(device.osType == nil ? .secondary : .primary)
            }
            .width(min: 60, ideal: 80)

            TableColumn("Connector") { device in
                JSCConnectorBadge(state: device.connectorState)
            }
            .width(min: 80, ideal: 100)

            TableColumn("Deployment") { device in
                Text(device.deploymentState?.capitalized.replacingOccurrences(of: "_", with: " ") ?? "—")
                    .foregroundStyle(device.deploymentState == nil ? .secondary : .primary)
                    .font(.caption)
            }
            .width(min: 90, ideal: 110)

            TableColumn("Last Seen", value: \.lastSeenForSort) { device in
                JSCLastSeenCell(device: device)
            }
            .width(min: 90, ideal: 110)
        }
        .tableStyle(.inset)
    }

    private var refreshToolbarItem: some View {
        Button {
            Task { await vm.load(force: true) }
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .help("Refresh Security Cloud data")
        .accessibilityLabel("Refresh")
    }
}

// MARK: - Risk chip (banner)

private struct JSCRiskChip: View {
    let level: JSCRiskLevel
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: level.icon)
                    .imageScale(.small)
                Text(level.displayName)
                    .fontWeight(.medium)
                Text("\(count)")
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(isSelected ? Color.white.opacity(0.3) : level.color.opacity(0.2),
                                in: Capsule())
            }
            .font(.caption)
            .foregroundStyle(isSelected ? .white : level.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? level.color : level.color.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(count == 0 ? "No \(level.displayName.lowercased()) risk devices" :
                           "Filter: \(level.displayName) (\(count))")
    }
}

// MARK: - Risk badge (table cell)

struct JSCRiskBadge: View {
    let level: JSCRiskLevel

    var body: some View {
        Label(level.displayName, systemImage: level.icon)
            .font(.caption.weight(.medium))
            .foregroundStyle(level.color)
            .labelStyle(.titleAndIcon)
    }
}

// MARK: - Connector badge

private struct JSCConnectorBadge: View {
    let state: String?

    var body: some View {
        let (icon, color, label) = appearance(for: state)
        Label(label, systemImage: icon)
            .font(.caption)
            .foregroundStyle(color)
    }

    private func appearance(for state: String?) -> (String, Color, String) {
        switch state?.uppercased() {
        case "ACTIVE":       return ("checkmark.circle.fill", .green, "Active")
        case "INACTIVE":     return ("minus.circle.fill", .secondary, "Inactive")
        case "DISCONNECTED": return ("xmark.circle.fill", .red, "Disconnected")
        default:             return ("questionmark.circle", .secondary, state?.capitalized ?? "Unknown")
        }
    }
}

// MARK: - Device name cell

private struct JSCDeviceNameCell: View {
    let device: JSCDevice

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: osIcon)
                .foregroundStyle(.secondary)
                .imageScale(.medium)
                .frame(width: 18)
            Text(device.deviceName ?? device.guid)
                .lineLimit(1)
        }
    }

    private var osIcon: String {
        switch device.osType?.uppercased() {
        case "IOS":     return "iphone"
        case "ANDROID": return "phone"
        case "MACOS":   return "laptopcomputer"
        case "WINDOWS": return "pc"
        case "CHROME":  return "display"
        default:        return "questionmark.circle"
        }
    }
}

// MARK: - Last seen cell

private struct JSCLastSeenCell: View {
    let device: JSCDevice

    var body: some View {
        if let date = device.lastSeenDate {
            Text(date, format: .relative(presentation: .named))
                .font(.caption)
                .foregroundStyle(staleness(of: date))
        } else {
            Text("Never")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func staleness(of date: Date) -> Color {
        let days = Date().timeIntervalSince(date) / 86400
        if days < 1 { return .primary }
        if days < 7 { return .secondary }
        return .orange
    }
}

// MARK: - Device inspector panel

private struct JSCDeviceInspector: View {
    let device: JSCDevice?

    var body: some View {
        Group {
            if let device {
                inspectorContent(device)
            } else {
                ContentUnavailableView("No Device Selected", systemImage: "iphone")
            }
        }
        .inspectorColumnWidth(min: 260, ideal: 300, max: 400)
    }

    @ViewBuilder
    private func inspectorContent(_ device: JSCDevice) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(device.deviceName ?? "Unknown Device")
                            .font(.title3.weight(.semibold))
                        Spacer()
                        JSCRiskBadge(level: device.riskLevel)
                    }
                    if let user = device.userDisplayName {
                        Label(user, systemImage: "person.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 4)

                Divider()

                // Identity
                inspectorSection("Identity") {
                    row("GUID", device.guid)
                    if let ext = device.externalId { row("External ID", ext) }
                    if let phone = device.phoneNumber { row("Phone", phone) }
                    if let email = device.userEmail { row("User Email", email) }
                }

                Divider()

                // Device
                inspectorSection("Device") {
                    if let os = device.osType { row("OS Type", os) }
                    if let app = device.appVersion { row("App Version", app) }
                    row("Enrolled", device.isEnrolled ? "Yes" : "No")
                    if let state = device.deploymentState {
                        row("Deployment", state.replacingOccurrences(of: "_", with: " ").capitalized)
                    }
                }

                Divider()

                // Connectivity
                inspectorSection("Connectivity") {
                    if let conn = device.connectorState {
                        row("Connector", conn.capitalized)
                    }
                    if let status = device.status {
                        row("Status", status.capitalized)
                    }
                    if let date = device.lastSeenDate {
                        row("Last Seen", date.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let date = device.joinedDate {
                        row("Joined", date.formatted(date: .abbreviated, time: .omitted))
                    }
                }
            }
            .padding(16)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private func inspectorSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
        }
    }
}
