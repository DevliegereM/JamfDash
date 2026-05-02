import SwiftUI

struct DeviceSearchView: View {
    @Bindable var vm: DeviceSearchViewModel
    @Environment(AppEnvironment.self) private var env

    private var isDestructiveAllowed: Bool {
        env.currentScope == .fullAdmin
    }

    var body: some View {
        HSplitView {
            searchPanel
                .frame(minWidth: 260, maxWidth: 340)

            detailPanel
                .frame(minWidth: 480)
        }
        .navigationTitle("Device Lookup")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { vm.clearSearch() } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }
                .disabled(vm.searchText.isEmpty && vm.selectedDevice == nil)
            }
        }
    }

    // MARK: - Left: Search + results

    private var searchPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .imageScale(.small)
                TextField("Serial number or device name…", text: $vm.searchText)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        if let first = vm.localResults.first {
                            vm.selectDevice(first)
                        } else if !vm.searchText.isEmpty {
                            Task { await vm.fetchDetail(serial: vm.searchText.trimmingCharacters(in: .whitespaces)) }
                        }
                    }
                if !vm.searchText.isEmpty {
                    Button { vm.clearSearch() } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial)

            Divider()

            if vm.searchText.isEmpty {
                emptySearchPrompt
            } else if vm.localResults.isEmpty {
                noLocalResultsView
            } else {
                resultsList
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var emptySearchPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Search by serial number or device name")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var noLocalResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No local match")
                .font(.callout.bold())
                .foregroundStyle(.secondary)
            Text("Press Return to look up directly from Jamf Pro.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 200)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(vm.localResults) { device in
                    DeviceRow(device: device, isSelected: vm.selectedDevice?.id == device.id)
                        .onTapGesture { vm.selectDevice(device) }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Right: Detail panel

    @ViewBuilder
    private var detailPanel: some View {
        switch vm.detailState {
        case .idle:
            if let device = vm.selectedDevice {
                basicDeviceDetail(device)
            } else {
                emptyDetailPrompt
            }
        case .loading:
            VStack(spacing: 16) {
                ProgressView().scaleEffect(1.4).tint(Color.accentColor)
                Text("Fetching device details…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loaded(let detail):
            DeviceDetailView(detail: detail, vm: vm, isDestructiveAllowed: isDestructiveAllowed)

        case .failed:
            if let device = vm.selectedDevice {
                basicDeviceDetail(device)
            } else {
                emptyDetailPrompt
            }
        }
    }

    private var emptyDetailPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "laptopcomputer.and.iphone")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Select a Device")
                .font(.title3.bold())
                .foregroundStyle(.secondary)
            Text("Search for a device and select it to see full inventory details.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func basicDeviceDetail(_ device: Computer) -> some View {
        let consoleURL: URL? = {
            guard let base = env.currentServerURL else { return nil }
            let root = base.hasSuffix("/") ? String(base.dropLast()) : base
            return URL(string: "\(root)/computers.html?id=\(device.id)&o=r")
        }()
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DeviceHeroHeader(
                    name: device.name,
                    serial: device.serialNumber ?? "—",
                    model: nil,
                    isManaged: device.managed ?? false,
                    consoleURL: consoleURL
                )

                if let serial = device.serialNumber, !serial.isEmpty {
                    DeviceActionsPanel(serial: serial, vm: vm, isDestructiveAllowed: isDestructiveAllowed)
                }

                DetailSection("General") {
                    if let serial = device.serialNumber { DetailRow("Serial Number", value: serial) }
                    if let os = device.osVersion       { DetailRow("macOS Version", value: os) }
                    if let days = device.daysSinceContact {
                        DetailRow("Last Contact", value: "\(days) days ago")
                    } else if let t = device.lastContactTime {
                        DetailRow("Last Contact", value: t)
                    }
                    DetailRow("Managed", value: (device.managed ?? false) ? "Yes" : "No")
                }
            }
            .padding(24)
        }
    }
}

// MARK: - Device row in search results

private struct DeviceRow: View {
    let device: Computer
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.accentColor.opacity(0.14))
                    .frame(width: 34, height: 34)
                Image(systemName: "laptopcomputer")
                    .foregroundStyle(Color.accentColor)
                    .imageScale(.small)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(device.serialNumber ?? "No serial")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())

        Divider().padding(.horizontal, 12)
    }
}

// MARK: - Rich device detail view

struct DeviceDetailView: View {
    let detail: ComputerDetail
    @Bindable var vm: DeviceSearchViewModel
    let isDestructiveAllowed: Bool
    @Environment(AppEnvironment.self) private var env

    private var consoleURL: URL? {
        guard let base = env.currentServerURL else { return nil }
        let root = base.hasSuffix("/") ? String(base.dropLast()) : base
        return URL(string: "\(root)/computers.html?id=\(detail.id)&o=r")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                DeviceHeroHeader(
                    name: detail.name,
                    serial: detail.effectiveSerial,
                    model: detail.effectiveModel,
                    isManaged: detail.isManaged,
                    consoleURL: consoleURL
                )

                // Action result banner
                if let result = vm.lastActionResult {
                    ActionResultBanner(result: result) { vm.dismissActionResult() }
                }

                // Actions
                DeviceActionsPanel(serial: detail.effectiveSerial, vm: vm, isDestructiveAllowed: isDestructiveAllowed)

                // General
                DetailSection("General") {
                    CopyableDetailRow("Serial Number", value: detail.effectiveSerial)
                    if let udid = detail.udid                          { CopyableDetailRow("UDID", value: udid) }
                    if let ip   = detail.effectiveIP                   { DetailRow("IP Address", value: ip) }
                    if let tag  = detail.general?.assetTag, !tag.isEmpty { DetailRow("Asset Tag", value: tag) }
                    if let b1   = detail.general?.barcode1, !b1.isEmpty  { DetailRow("Barcode 1", value: b1) }
                    if let b2   = detail.general?.barcode2, !b2.isEmpty  { DetailRow("Barcode 2", value: b2) }
                    if let jv   = detail.general?.jamfBinaryVersion    { DetailRow("Jamf Agent", value: jv) }
                    if let ct   = detail.general?.lastContactTime      { DetailRow("Last Contact", value: ct) }
                    if let ed   = detail.general?.lastEnrolledDate     { DetailRow("Last Enrolled", value: ed) }
                    if let ie   = detail.general?.initialEntryDate     { DetailRow("Initial Entry", value: ie) }
                    if let em   = detail.general?.enrollmentMethod     { DetailRow("Enrolled via", value: em) }
                    DetailRow("Managed", value: detail.isManaged ? "Yes" : "No")
                    if let sup  = detail.general?.supervised           { DetailRow("Supervised", value: sup ? "Yes" : "No") }
                    if let uam  = detail.general?.userApprovedMdm     { DetailRow("User-approved MDM", value: uam ? "Yes" : "No") }
                    if let ddm  = detail.general?.declarativeDeviceManagementEnabled { DetailRow("DDM Enabled", value: ddm ? "Yes" : "No") }
                    if let mc   = detail.general?.mdmCapable           { DetailRow("MDM Capable", value: mc ? "Yes" : "No") }
                }

                // Hardware
                DetailSection("Hardware") {
                    if let model = detail.effectiveModel               { DetailRow("Model", value: model) }
                    if let mid   = detail.hardware?.modelId            { DetailRow("Model ID", value: mid) }
                    if let cpu   = detail.hardware?.cpuType            { DetailRow("CPU", value: cpu) }
                    if let cores = detail.hardware?.coreCount          { DetailRow("Cores", value: "\(cores)") }
                    if let ram   = detail.effectiveRAM                 { DetailRow("RAM", value: ram) }
                    if let bat   = detail.effectiveBattery             { DetailRow("Battery", value: bat) }
                    if let free  = detail.effectiveDiskFree            { DetailRow("Boot Drive Free", value: free) }
                    if let apple = detail.hardware?.isAppleSilicon     { DetailRow("Apple Silicon", value: apple ? "Yes" : "No") }
                    if let mac   = detail.hardware?.macAddress         { DetailRow("MAC Address", value: mac) }
                    if let mac2  = detail.hardware?.altMacAddress      { DetailRow("Alt MAC", value: mac2) }
                    if let bt    = detail.hardware?.bluetoothMacAddress { DetailRow("Bluetooth MAC", value: bt) }
                    if let smc   = detail.hardware?.smcVersion         { DetailRow("SMC Version", value: smc) }
                }

                // Operating System
                if let os = detail.operatingSystem {
                    DetailSection("Operating System") {
                        if let ver  = os.version                       { DetailRow("Version", value: "macOS \(ver)") }
                        if let bld  = os.build                         { DetailRow("Build", value: bld) }
                        if let rsr  = os.rapidSecurityResponse, !rsr.isEmpty { DetailRow("Rapid Security Response", value: rsr) }
                        if let ads  = os.activeDirectoryStatus         { DetailRow("Active Directory", value: ads) }
                        if let fv   = os.fileVault2Status              { DetailRow("FileVault Status", value: fv) }
                    }
                }

                // Security
                DetailSection("Security") {
                    if let sip = detail.isSIPEnabled        { BoolDetailRow("System Integrity Protection", value: sip) }
                    if let gk  = detail.isGatekeeperEnabled { BoolDetailRow("Gatekeeper", value: gk) }
                    if let fv  = detail.isFileVaultEnabled  { BoolDetailRow("FileVault", value: fv) }
                    if let fw  = detail.security?.firewallEnabled      { BoolDetailRow("Firewall", value: fw) }
                    if let al  = detail.security?.activationLockEnabled { BoolDetailRow("Activation Lock", value: al, invertColor: true) }
                    if let alm = detail.security?.isActivationLockManageable { DetailRow("Activation Lock Manageable", value: alm ? "Yes" : "No") }
                    if let rl  = detail.security?.recoveryLockEnabled  { BoolDetailRow("Recovery Lock", value: rl) }
                    if let xp  = detail.security?.xprotectVersion, !xp.isEmpty { DetailRow("XProtect", value: xp) }
                    if let sb  = detail.security?.secureBootLevel      { DetailRow("Secure Boot", value: sb) }
                    if let eb  = detail.security?.externalBootLevel    { DetailRow("External Boot", value: eb) }
                    if let bt  = detail.security?.bootstrapTokenAllowed { BoolDetailRow("Bootstrap Token", value: bt) }
                    if let bte = detail.security?.bootstrapTokenEscrowedStatus { DetailRow("Bootstrap Token Status", value: bte) }
                    if let ald = detail.security?.autoLoginDisabled    { BoolDetailRow("Auto-Login Disabled", value: ald) }
                    if let rd  = detail.security?.remoteDesktopEnabled { BoolDetailRow("Remote Desktop", value: rd) }
                }

                // Disk Encryption
                if let de = detail.diskEncryption {
                    DetailSection("Disk Encryption") {
                        if let bp = de.bootPartitionEncryptionDetails {
                            if let state = bp.partitionFileVault2State   { DetailRow("FileVault State", value: state) }
                            if let pct   = bp.partitionFileVault2Percent { DetailRow("Encryption Progress", value: "\(pct)%") }
                        }
                        if let irk = de.individualRecoveryKeyValidityStatus { DetailRow("Recovery Key Status", value: irk) }
                        if let irp = de.institutionalRecoveryKeyPresent { BoolDetailRow("Institutional Recovery Key", value: irp) }
                        if let cfg = de.diskEncryptionConfigurationName { DetailRow("Configuration", value: cfg) }
                    }
                }

                // Storage
                if let disks = detail.storage?.disks, !disks.isEmpty {
                    DetailSection("Storage") {
                        ForEach(disks) { disk in
                            if let model = disk.model { DetailRow("Drive", value: model) }
                            if let size  = disk.sizeMegabytes {
                                let gb = size >= 1024 ? "\(size / 1024) GB" : "\(size) MB"
                                DetailRow("Capacity", value: gb)
                            }
                            if let smart = disk.smartStatus { DetailRow("SMART Status", value: smart) }
                        }
                    }
                }

                // Purchasing
                if let p = detail.purchasing,
                   [p.vendor, p.poNumber, p.warrantyDate, p.appleCareId].contains(where: { $0 != nil && !($0!.isEmpty) }) {
                    DetailSection("Purchasing") {
                        if let v  = p.vendor,        !v.isEmpty  { DetailRow("Vendor", value: v) }
                        if let po = p.poNumber,      !po.isEmpty { DetailRow("PO Number", value: po) }
                        if let dt = p.poDate,        !dt.isEmpty { DetailRow("PO Date", value: dt) }
                        if let wd = p.warrantyDate,  !wd.isEmpty { DetailRow("Warranty Expires", value: wd) }
                        if let ac = p.appleCareId,   !ac.isEmpty { DetailRow("AppleCare ID", value: ac) }
                        if let pp = p.purchasePrice, !pp.isEmpty { DetailRow("Purchase Price", value: pp) }
                        if let le = p.leased                     { DetailRow("Leased", value: le ? "Yes" : "No") }
                        if let li = p.lifeExpectancy             { DetailRow("Life Expectancy", value: "\(li) years") }
                    }
                }

                // User & Location
                if let loc = detail.location {
                    let hasAny = [loc.username, loc.realName, loc.email, loc.position,
                                  loc.phone, loc.departmentName, loc.buildingName, loc.room]
                        .contains(where: { $0 != nil && !($0!.isEmpty) })
                    if hasAny {
                        DetailSection("User & Location") {
                            if let rn   = loc.realName,       !rn.isEmpty   { DetailRow("Full Name", value: rn) }
                            if let un   = loc.username,       !un.isEmpty   { DetailRow("Username", value: un) }
                            if let em   = loc.email,          !em.isEmpty   { DetailRow("Email", value: em) }
                            if let pos  = loc.position,       !pos.isEmpty  { DetailRow("Position", value: pos) }
                            if let ph   = loc.phone,          !ph.isEmpty   { DetailRow("Phone", value: ph) }
                            if let dept = loc.departmentName, !dept.isEmpty { DetailRow("Department", value: dept) }
                            if let bld  = loc.buildingName,   !bld.isEmpty  { DetailRow("Building", value: bld) }
                            if let rm   = loc.room,           !rm.isEmpty   { DetailRow("Room", value: rm) }
                        }
                    }
                }

                // Network
                if let adapters = detail.network?.networkAdapters, !adapters.isEmpty {
                    DetailSection("Network Adapters") {
                        ForEach(adapters) { adapter in
                            if let name = adapter.displayName { DetailRow("Interface", value: name) }
                            if let mac  = adapter.macAddress  { DetailRow("MAC", value: mac) }
                            if let ip   = adapter.ipAddress, !ip.isEmpty { DetailRow("IP", value: ip) }
                        }
                    }
                }

                // Group Memberships
                if let groups = detail.groupMemberships, !groups.isEmpty {
                    let smart   = detail.smartGroupNames
                    let static_ = detail.staticGroupNames
                    if !smart.isEmpty {
                        CollapsibleDetailSection("Smart Groups (\(smart.count))") {
                            ForEach(smart, id: \.self) { groupName in
                                HStack {
                                    Text(groupName).font(.callout)
                                    Spacer()
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 12)
                                Divider().padding(.horizontal, 12)
                            }
                        }
                    }
                    if !static_.isEmpty {
                        CollapsibleDetailSection("Static Groups (\(static_.count))") {
                            ForEach(static_, id: \.self) { groupName in
                                HStack {
                                    Text(groupName).font(.callout)
                                    Spacer()
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 12)
                                Divider().padding(.horizontal, 12)
                            }
                        }
                    }
                }

                // Local User Accounts
                if let users = detail.localUserAccounts, !users.isEmpty {
                    CollapsibleDetailSection("Local Users (\(users.count))") {
                        ForEach(users) { user in
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(user.username ?? "—").font(.callout.weight(.medium))
                                    if let fn = user.fullName, !fn.isEmpty {
                                        Text(fn).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if user.admin == true {
                                    Text("Admin")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange, in: Capsule())
                                }
                                if user.fileVault2Enabled == true {
                                    Image(systemName: "lock.fill")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            Divider().padding(.horizontal, 12)
                        }
                    }
                }

                // Pending Software Updates
                if let updates = detail.softwareUpdates, !updates.isEmpty {
                    DetailSection("Pending Updates (\(updates.count))") {
                        ForEach(updates) { update in
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(update.name ?? "—").font(.callout)
                                    if let v = update.version {
                                        Text(v).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            Divider().padding(.horizontal, 12)
                        }
                    }
                }

                // Configuration Profiles
                if let profiles = detail.configurationProfiles, !profiles.isEmpty {
                    CollapsibleDetailSection("Configuration Profiles (\(profiles.count))") {
                        ForEach(profiles) { profile in
                            HStack {
                                Text(profile.displayName ?? "—").font(.callout)
                                Spacer()
                                if let state = profile.state {
                                    Text(state)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            Divider().padding(.horizontal, 12)
                        }
                    }
                }

                // Extension Attributes
                let attrs = (detail.extensionAttributes ?? []).filter { ea in
                    guard let vals = ea.values else { return false }
                    return !vals.isEmpty && vals.first?.isEmpty == false
                }
                if !attrs.isEmpty {
                    CollapsibleDetailSection("Extension Attributes") {
                        ForEach(attrs) { ea in
                            if let name = ea.name {
                                DetailRow(name, value: ea.values?.joined(separator: ", ") ?? "—")
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}

// MARK: - Actions Panel

struct DeviceActionsPanel: View {
    let serial: String
    @Bindable var vm: DeviceSearchViewModel
    let isDestructiveAllowed: Bool

    @State private var destructiveUnlocked = false
    @State private var confirmAction: ConfirmableAction? = nil
    @State private var showLockSheet = false
    @State private var lockPIN = ""

    enum ConfirmableAction: Identifiable {
        case removeMDM, setRecoveryLock, erase
        case restart, shutdown, redeployFramework, flushAllCommands

        var id: String {
            switch self {
            case .removeMDM:           return "removeMDM"
            case .setRecoveryLock:     return "setRecoveryLock"
            case .erase:               return "erase"
            case .restart:             return "restart"
            case .shutdown:            return "shutdown"
            case .redeployFramework:   return "redeployFramework"
            case .flushAllCommands:    return "flushAllCommands"
            }
        }

        var title: String {
            switch self {
            case .removeMDM:         return "Remove MDM Profile"
            case .setRecoveryLock:   return "Set Recovery Lock"
            case .erase:             return "Erase Computer"
            case .restart:           return "Restart"
            case .shutdown:          return "Shut Down"
            case .redeployFramework: return "Redeploy Management Framework"
            case .flushAllCommands:  return "Flush All MDM Commands"
            }
        }

        var message: String {
            switch self {
            case .removeMDM:         return "This will unenroll the device from MDM. The device will need to be re-enrolled manually."
            case .setRecoveryLock:   return "This will set or clear the Recovery Lock password on Apple Silicon / T2 Macs."
            case .erase:             return "This will permanently erase all data on the computer. This cannot be undone."
            case .restart:           return "This will restart the computer remotely."
            case .shutdown:          return "This will shut down the computer remotely."
            case .redeployFramework: return "This will redeploy the Jamf management framework to the device."
            case .flushAllCommands:  return "This will flush both pending and failed MDM commands from the queue."
            }
        }

        var isDestructive: Bool {
            switch self {
            case .removeMDM, .erase: return true
            default: return false
            }
        }

        func makeCommand(serial: String) -> CLICommand {
            switch self {
            case .removeMDM:         return .removeMDM(serial: serial)
            case .setRecoveryLock:   return .setRecoveryLock(serial: serial)
            case .erase:             return .erase(serial: serial)
            case .restart:           return .restart(serial: serial)
            case .shutdown:          return .shutdown(serial: serial)
            case .redeployFramework: return .redeployFramework(serial: serial)
            case .flushAllCommands:  return .flushAllCommands(serial: serial)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ACTIONS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)
                .padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 12) {

                if vm.isRunningAction {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(vm.runningActionName ?? "Running…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                }

                // Safe actions
                actionGroupLabel("Safe")
                actionRow {
                    actionButton("Blank Push", icon: "antenna.radiowaves.left.and.right") {
                        Task { await vm.runAction(.blankPush(serial: serial), name: "Blank Push") }
                    }
                    actionButton("Renew MDM", icon: "arrow.triangle.2.circlepath") {
                        Task { await vm.runAction(.renewMDM(serial: serial), name: "Renew MDM Profile") }
                    }
                    actionButton("DDM Sync", icon: "arrow.down.doc") {
                        Task { await vm.runAction(.ddmSync(serial: serial), name: "DDM Sync") }
                    }
                    actionButton("Flush Failed", icon: "trash.slash") {
                        Task { await vm.runAction(.flushFailedCommands(serial: serial), name: "Flush Failed Commands") }
                    }
                }

                // Moderate actions
                actionGroupLabel("Moderate")
                actionRow {
                    actionButton("Redeploy Framework", icon: "gearshape.arrow.triangle.2.circlepath") {
                        confirmAction = .redeployFramework
                    }
                    actionButton("Enable Remote Desktop", icon: "desktopcomputer") {
                        Task { await vm.runAction(.enableRemoteDesktop(serial: serial), name: "Enable Remote Desktop") }
                    }
                    actionButton("Disable Remote Desktop", icon: "rectangle.slash") {
                        Task { await vm.runAction(.disableRemoteDesktop(serial: serial), name: "Disable Remote Desktop") }
                    }
                    actionButton("Restart", icon: "restart") {
                        confirmAction = .restart
                    }
                    actionButton("Shut Down", icon: "power") {
                        confirmAction = .shutdown
                    }
                    actionButton("Flush All Commands", icon: "trash") {
                        confirmAction = .flushAllCommands
                    }
                }

                // Destructive actions — Full Admin only, locked behind explicit unlock
                if isDestructiveAllowed {
                    if destructiveUnlocked {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.open.fill")
                                .foregroundStyle(.red)
                                .imageScale(.small)
                            Text("Destructive actions unlocked")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.red)
                            Spacer()
                            Button("Lock") { destructiveUnlocked = false }
                                .font(.caption)
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.red.opacity(0.2)))

                        actionGroupLabel("Destructive", color: .red)
                        actionRow {
                            actionButton("Remove MDM", icon: "wifi.slash", tint: .orange) {
                                confirmAction = .removeMDM
                            }
                            actionButton("Set Recovery Lock", icon: "lock.rotation", tint: .orange) {
                                confirmAction = .setRecoveryLock
                            }
                            actionButton("Lock", icon: "lock.fill", tint: .red) {
                                lockPIN = ""
                                showLockSheet = true
                            }
                            actionButton("Erase", icon: "exclamationmark.triangle.fill", tint: .red) {
                                confirmAction = .erase
                            }
                        }
                    } else {
                        Button { destructiveUnlocked = true } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "lock.fill")
                                    .imageScale(.small)
                                Text("Unlock Destructive Actions")
                                    .font(.caption.weight(.medium))
                            }
                            .foregroundStyle(.orange)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.orange)
                    }
                }
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.06)))
            .disabled(vm.isRunningAction)
            .opacity(vm.isRunningAction ? 0.7 : 1)
        }
        .onChange(of: isDestructiveAllowed) { _, _ in destructiveUnlocked = false }
        .confirmationDialog(
            confirmAction?.title ?? "",
            isPresented: Binding(
                get: { confirmAction != nil },
                set: { if !$0 { confirmAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let action = confirmAction {
                Button(action.title, role: action.isDestructive ? .destructive : nil) {
                    let cmd = action.makeCommand(serial: serial)
                    let name = action.title
                    Task { await vm.runAction(cmd, name: name) }
                    confirmAction = nil
                }
                Button("Cancel", role: .cancel) { confirmAction = nil }
            }
        } message: {
            if let action = confirmAction {
                Text(action.message)
            }
        }
        .sheet(isPresented: $showLockSheet) {
            LockDeviceSheet(serial: serial, pin: $lockPIN, vm: vm, isPresented: $showLockSheet)
        }
    }

    private func actionGroupLabel(_ label: String, color: Color = .secondary) -> some View {
        Text(label.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 2)
    }

    private func actionRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 118, maximum: 210), spacing: 6)],
            alignment: .leading,
            spacing: 6
        ) {
            content()
        }
    }

    private func actionButton(
        _ title: String,
        icon: String,
        tint: Color = .accentColor,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.medium))
                .foregroundStyle(tint)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(tint)
    }
}

// MARK: - Lock Device Sheet

private struct LockDeviceSheet: View {
    let serial: String
    @Binding var pin: String
    @Bindable var vm: DeviceSearchViewModel
    @Binding var isPresented: Bool

    private var pinIsValid: Bool {
        pin.count == 6 && pin.allSatisfy(\.isNumber)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Lock Computer", systemImage: "lock.fill")
                    .font(.headline)
                    .foregroundStyle(.red)
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            VStack(alignment: .leading, spacing: 20) {
                // Warning
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("This will immediately lock the computer.")
                            .font(.callout.weight(.semibold))
                        Text("The user will be logged out and a 6-digit PIN will be required to unlock the device. Store the PIN before proceeding.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.25)))

                // Device info
                HStack {
                    Text("Device").foregroundStyle(.secondary)
                    Spacer()
                    Text(serial).font(.body.monospaced())
                }
                .font(.callout)
                .padding(.horizontal, 2)

                Divider()

                // PIN input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Lock PIN")
                        .font(.callout.weight(.semibold))

                    HStack(spacing: 8) {
                        TextField("6-digit PIN", text: $pin)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.title3, design: .monospaced))
                            .frame(maxWidth: 160)
                            .onChange(of: pin) { _, newVal in
                                // Strip non-digits, limit to 6
                                let digits = newVal.filter(\.isNumber)
                                if digits.count > 6 {
                                    pin = String(digits.prefix(6))
                                } else if digits != newVal {
                                    pin = digits
                                }
                            }

                        // Visual digit indicators
                        HStack(spacing: 6) {
                            ForEach(0..<6, id: \.self) { i in
                                Circle()
                                    .fill(i < pin.count ? Color.accentColor : Color.secondary.opacity(0.3))
                                    .frame(width: 10, height: 10)
                                    .animation(.easeInOut(duration: 0.15), value: pin.count)
                            }
                        }

                        Spacer()
                    }

                    if !pin.isEmpty && !pinIsValid {
                        Label("PIN must be exactly 6 digits.", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    Text("Record this PIN now. It cannot be retrieved from Jamf Pro after the lock command is sent.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                Button("Lock Computer") {
                    isPresented = false
                    Task { await vm.runAction(.lock(serial: serial, pin: pin), name: "Lock Computer") }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!pinIsValid || vm.isRunningAction)
            }
            .padding()
        }
        .frame(minWidth: 440, minHeight: 380)
    }
}

// MARK: - Action result banner

private struct ActionResultBanner: View {
    let result: DeviceActionResult
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isSuccess ? .green : .orange)
            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            (isSuccess ? Color.green : Color.orange).opacity(0.12),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke((isSuccess ? Color.green : Color.orange).opacity(0.25))
        )
    }

    private var isSuccess: Bool {
        if case .success = result { return true }
        return false
    }

    private var message: String {
        switch result {
        case .success(let msg): return msg
        case .failure(let msg): return msg
        }
    }
}

// MARK: - Supporting views

struct DeviceHeroHeader: View {
    let name: String
    let serial: String
    let model: String?
    let isManaged: Bool
    var consoleURL: URL? = nil

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.accentColor.opacity(0.14))
                    .frame(width: 64, height: 64)
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.title2.bold())
                if let model { Text(model).font(.callout).foregroundStyle(.secondary) }
                HStack(spacing: 6) {
                    Text(serial).font(.caption.monospaced()).foregroundStyle(.secondary)
                    CopyButton(value: serial)
                    StatusBadge(text: isManaged ? "Managed" : "Unmanaged", isOK: isManaged)
                }
            }
            Spacer()
            if let url = consoleURL {
                Link(destination: url) {
                    Label("Open in Jamf Pro", systemImage: "arrow.up.right.square")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Open this computer in the Jamf Pro web console")
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.06)))
    }
}

// MARK: - Copy button

struct CopyButton: View {
    let value: String
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            withAnimation(.easeInOut(duration: 0.15)) { copied = true }
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                withAnimation(.easeInOut(duration: 0.15)) { copied = false }
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .imageScale(.small)
                .foregroundStyle(copied ? .green : .secondary)
        }
        .buttonStyle(.plain)
        .help("Copy to clipboard")
    }
}

private struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)
                .padding(.horizontal, 12)

            VStack(spacing: 0) {
                content()
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.06)))
        }
    }
}

private struct CollapsibleDetailSection<Content: View>: View {
    let title: String
    @State private var isExpanded: Bool = true
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Text(title.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.bottom, 6)
                .padding(.horizontal, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 0) {
                    content()
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.06)))
            }
        }
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    init(_ label: String, value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.callout)
        .padding(.vertical, 7)
        .padding(.horizontal, 12)

        Divider().padding(.horizontal, 12)
    }
}

private struct CopyableDetailRow: View {
    let label: String
    let value: String

    init(_ label: String, value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
            CopyButton(value: value)
        }
        .font(.callout)
        .padding(.vertical, 7)
        .padding(.horizontal, 12)
        Divider().padding(.horizontal, 12)
    }
}

private struct BoolDetailRow: View {
    let label: String
    let value: Bool
    var invertColor: Bool = false

    init(_ label: String, value: Bool, invertColor: Bool = false) {
        self.label = label
        self.value = value
        self.invertColor = invertColor
    }

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 4) {
                let isGood = invertColor ? !value : value
                Circle()
                    .fill(isGood ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Text(value ? "Enabled" : "Disabled")
                    .foregroundStyle(isGood ? .green : .orange)
            }
            .font(.callout)
        }
        .font(.callout)
        .padding(.vertical, 7)
        .padding(.horizontal, 12)

        Divider().padding(.horizontal, 12)
    }
}
