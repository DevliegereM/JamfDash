import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

struct SettingsView: View {
    @Bindable var vm: SettingsViewModel
    @AppStorage("jamfDash.aiEnabled") private var isAIEnabled = false

    var body: some View {
        TabView {
            ConnectionTab(vm: vm)
                .tabItem { Label("Connection", systemImage: "key.fill") }

            CLITab(vm: vm)
                .tabItem { Label("CLI", systemImage: "terminal") }

            BrandingTab(vm: vm)
                .tabItem { Label("Branding", systemImage: "photo") }

            BackupTab(vm: vm)
                .tabItem { Label("Backup", systemImage: "arrow.counterclockwise.icloud") }

            AITab(isEnabled: $isAIEnabled)
                .tabItem { Label("AI", systemImage: "brain") }
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 520)
        .task { await vm.loadExisting() }
    }
}

// MARK: - Connection

private struct ConnectionTab: View {
    @Bindable var vm: SettingsViewModel
    @State private var showingAddSheet = false
    @State private var profileToDelete: String? = nil

    var body: some View {
        Form {
            Section {
                if vm.availableProfiles.isEmpty {
                    Text("No profiles configured yet.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    ForEach(vm.availableProfiles, id: \.self) { profile in
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                                .imageScale(.small)
                            Text(profile)
                            Spacer()
                            Button(role: .destructive) {
                                profileToDelete = profile
                            } label: {
                                Image(systemName: "trash")
                                    .imageScale(.small)
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .help("Remove this connection")
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Configured Connections")
                    Spacer()
                    Button {
                        showingAddSheet = true
                    } label: {
                        Label("Add Connection", systemImage: "plus")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }
            } footer: {
                if let err = vm.deleteError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                } else {
                    Text("Connections are stored securely in the system keychain by jamf-cli.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                if vm.availableProfiles.isEmpty {
                    Text("No profiles found. Add a connection first.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Active Profile", selection: $vm.profileName_selected) {
                        Text("Default (active profile)").tag("")
                        ForEach(vm.availableProfiles, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                }
                HStack {
                    Spacer()
                    Button("Save") { vm.saveProfile() }
                        .buttonStyle(.borderedProminent)
                        .disabled(vm.availableProfiles.isEmpty)
                }
            } header: {
                Text("Active Profile")
            } footer: {
                Text("Select which jamf-cli profile Jamf Dash should use for all API calls. \"Default\" uses whichever profile jamf-cli considers active.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingAddSheet) {
            AddConnectionSheet(vm: vm, isPresented: $showingAddSheet)
        }
        .confirmationDialog(
            "Remove \"\(profileToDelete ?? "")\"?",
            isPresented: Binding(get: { profileToDelete != nil }, set: { if !$0 { profileToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let name = profileToDelete {
                    Task { await vm.deleteProfile(name) }
                }
                profileToDelete = nil
            }
            Button("Cancel", role: .cancel) { profileToDelete = nil }
        } message: {
            Text("This will permanently delete the connection from the keychain. This action cannot be undone.")
        }
    }
}

// MARK: - Add Connection Sheet

private struct AddConnectionSheet: View {
    @Bindable var vm: SettingsViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Connection")
                    .font(.headline)
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: 20) {
                    // Product picker
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Jamf Product")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            ForEach(JamfProduct.allCases, id: \.self) { product in
                                ProductPickerButton(
                                    product: product,
                                    isSelected: vm.selectedProduct == product
                                ) {
                                    vm.selectedProduct = product
                                    vm.setupSuccess = false
                                    vm.setupError = nil
                                }
                            }
                        }
                    }

                    Divider()

                    // Product-specific form
                    switch vm.selectedProduct {
                    case .pro:
                        proForm
                    case .protect:
                        protectForm
                    case .school:
                        schoolForm
                    }

                    // Status
                    if vm.isRunningSetup {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Connecting to \(vm.selectedProduct.displayName)…")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let error = vm.setupError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red).font(.caption)
                            .multilineTextAlignment(.leading)
                    }
                    if vm.setupSuccess {
                        Label("Connection configured successfully.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Button("Done") { isPresented = false }
                            .buttonStyle(.borderedProminent)
                    }

                    if !vm.setupSuccess {
                        HStack {
                            Spacer()
                            Button(vm.isRunningSetup ? "Connecting…" : "Connect") {
                                Task { await vm.runSetup() }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(vm.isRunningSetup || !vm.canRunSetup)
                        }
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 540, minHeight: 560)
    }

    // MARK: - Jamf Pro form

    private var proForm: some View {
        VStack(spacing: 16) {
            Picker("Authentication", selection: $vm.setupMethod) {
                Text("Platform API").tag(SettingsViewModel.SetupMethod.platform)
                Text("Local Admin").tag(SettingsViewModel.SetupMethod.localAccount)
                Text("SSO").tag(SettingsViewModel.SetupMethod.sso)
            }
            .pickerStyle(.segmented)

            switch vm.setupMethod {
            case .platform:
                Text("Routes all Pro API traffic through the Jamf Platform Gateway. Requires API client credentials from account.jamf.com.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                platformForm
            case .localAccount:
                Text("Uses your admin credentials to automatically create a dedicated API client in Jamf Pro.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                localAccountForm
            case .sso:
                Text("Requires an API role and client created manually in Jamf Pro → Settings → System → API Roles and Clients.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ssoForm
            }
        }
    }

    private var localAccountForm: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                Text("Server URL").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                TextField("https://yourinstance.jamfcloud.com", text: $vm.serverURLText)
                    .textFieldStyle(.roundedBorder)
            }
            GridRow {
                Text("Username").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                TextField("Admin username", text: $vm.username)
                    .textFieldStyle(.roundedBorder).textContentType(.username)
            }
            GridRow {
                Text("Password").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                SecureField("Password", text: $vm.password)
                    .textFieldStyle(.roundedBorder).textContentType(.password)
            }
            GridRow {
                Text("API Scope").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                Picker("", selection: $vm.setupScope) {
                    ForEach(OnboardingViewModel.APIScope.allCases) { s in
                        Text(s.label).tag(s)
                    }
                }.labelsHidden()
            }
            GridRow {
                Text("Profile Name").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                TextField("Jamf-CLI - Standard", text: $vm.profileName)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var ssoForm: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                Text("Server URL").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                TextField("https://yourinstance.jamfcloud.com", text: $vm.ssoServerURL)
                    .textFieldStyle(.roundedBorder)
            }
            GridRow {
                Text("Profile Name").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                TextField("Jamf-CLI - SSO", text: $vm.ssoProfileName)
                    .textFieldStyle(.roundedBorder)
            }
            GridRow {
                Text("Client ID").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                TextField("xxxxxxxx-xxxx-…", text: $vm.ssoClientID)
                    .textFieldStyle(.roundedBorder).textContentType(.username)
            }
            GridRow {
                Text("Client Secret").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                SecureField("Client Secret", text: $vm.ssoClientSecret)
                    .textFieldStyle(.roundedBorder).textContentType(.password)
            }
        }
    }

    private var platformForm: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                Text("Gateway URL").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                TextField("https://us.apigw.jamf.com", text: $vm.platformGatewayURL)
                    .textFieldStyle(.roundedBorder)
            }
            GridRow {
                Text("Tenant ID").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                TextField("Tenant ID from account.jamf.com", text: $vm.platformTenantID)
                    .textFieldStyle(.roundedBorder)
            }
            GridRow {
                Text("Profile Name").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                TextField("Jamf Platform", text: $vm.platformProfileName)
                    .textFieldStyle(.roundedBorder)
            }
            GridRow {
                Text("Client ID").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                TextField("xxxxxxxx-xxxx-…", text: $vm.platformClientID)
                    .textFieldStyle(.roundedBorder).textContentType(.username)
            }
            GridRow {
                Text("Client Secret").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                SecureField("Client Secret", text: $vm.platformClientSecret)
                    .textFieldStyle(.roundedBorder).textContentType(.password)
            }
        }
    }

    // MARK: - Jamf Protect form

    private var protectForm: some View {
        VStack(spacing: 12) {
            Text(JamfProduct.protect.authDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Server URL").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                    TextField("https://yourinstance.jamfprotect.com", text: $vm.protectServerURL)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Profile Name").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                    TextField("Jamf Protect", text: $vm.protectProfileName)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Client ID").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                    TextField("xxxxxxxx-xxxx-…", text: $vm.protectClientID)
                        .textFieldStyle(.roundedBorder).textContentType(.username)
                }
                GridRow {
                    Text("Client Secret").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                    SecureField("Client Secret", text: $vm.protectClientSecret)
                        .textFieldStyle(.roundedBorder).textContentType(.password)
                }
            }
        }
    }

    // MARK: - Jamf School form

    private var schoolForm: some View {
        VStack(spacing: 12) {
            Text(JamfProduct.school.authDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Server URL").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                    TextField("https://yourschool.jamfcloud.com", text: $vm.schoolServerURL)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Profile Name").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                    TextField("Jamf School", text: $vm.schoolProfileName)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Network ID").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                    TextField("Network ID", text: $vm.schoolNetworkID)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("API Key").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                    SecureField("API Key", text: $vm.schoolAPIKey)
                        .textFieldStyle(.roundedBorder).textContentType(.password)
                }
            }
        }
    }
}

// MARK: - Product picker button

private struct ProductPickerButton: View {
    let product: JamfProduct
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: product.icon)
                    .font(.title2)
                    .foregroundStyle(isSelected ? .white : Color.accentColor)
                Text(product.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(isSelected ? .white : .primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.2))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - CLI

private struct CLITab: View {
    let vm: SettingsViewModel
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            Section("Installed Version") {
                HStack {
                    Text("jamf-cli")
                    Spacer()
                    Text(vm.installedVersion ?? "Not installed")
                        .foregroundStyle(vm.installedVersion == nil ? .red : .secondary)
                }
                if vm.installedVersion == nil {
                    HStack {
                        Button(vm.isInstallingCLI ? "Downloading…" : "Download & Install") {
                            Task { await vm.installCLI() }
                        }
                        .disabled(vm.isInstallingCLI)
                        Link("Jamf Concepts / jamf-cli ↗", destination: URL(string: "https://github.com/Jamf-Concepts/jamf-cli")!)
                            .font(.callout)
                    }
                }
            }

            Section("Updates") {
                if let status = vm.updateStatus {
                    Label(
                        status,
                        systemImage: vm.availableUpdate != nil ? "arrow.down.circle" : "checkmark.circle"
                    )
                    .foregroundStyle(vm.availableUpdate != nil ? .orange : .green)
                    .font(.caption)
                }

                HStack {
                    Button(vm.isCheckingUpdate ? "Checking…" : "Check for Updates") {
                        Task { await vm.checkForUpdate() }
                    }
                    .disabled(vm.isCheckingUpdate || vm.isUpdating)

                    if vm.availableUpdate != nil {
                        Button(vm.isUpdating ? "Updating…" : "Update Now") {
                            Task { await vm.performUpdate() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(vm.isUpdating)
                    }
                }
            }

            Section {
                if appState.isDemoMode {
                    Label("Demo mode is active. Restart the app to return to a real connection.", systemImage: "theatermask.and.paintbrush")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Demo Mode")
                            Text("Explore Jamf Dash with synthetic data — no real Jamf connection required.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Enable Demo Mode") {
                            appState.requestDemoMode()
                        }
                    }
                }
            } header: {
                Text("Demo")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Backup

private struct BackupTab: View {
    let vm: SettingsViewModel
    @State private var backupFolder: URL? = nil
    @State private var selectedFormat = 0
    @State private var isRunning = false
    @State private var logLines: [String] = []
    @State private var backupResources: Set<BackupResource> = Set(BackupResource.allCases)

    enum BackupResource: String, CaseIterable, Identifiable {
        case policies       = "Policies"
        case configProfiles = "Config Profiles"
        case scripts        = "Scripts"
        case packages       = "Packages"
        case smartGroups    = "Smart Groups"
        case extensionAttrs = "Extension Attributes"
        case patchTitles    = "Patch Titles"
        case patchPolicies  = "Patch Policies"
        case webhooks       = "Webhooks"
        var id: String { rawValue }
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(backupFolder?.path ?? "No folder selected")
                        .foregroundStyle(backupFolder == nil ? .secondary : .primary)
                        .lineLimit(1)
                    Spacer()
                    Button("Choose…") { chooseFolder() }
                }
                Picker("Format", selection: $selectedFormat) {
                    Text("JSON (raw CLI output)").tag(0)
                }
                .pickerStyle(.menu)
            } header: {
                Text("Destination")
            }

            Section {
                ForEach(BackupResource.allCases) { res in
                    Toggle(res.rawValue, isOn: Binding(
                        get: { backupResources.contains(res) },
                        set: { if $0 { backupResources.insert(res) } else { backupResources.remove(res) } }
                    ))
                }
            } header: {
                Text("Resources to Back Up")
            }

            Section {
                if !logLines.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(logLines.indices, id: \.self) { i in
                                Text(logLines[i])
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(minHeight: 100, maxHeight: 180)
                }
                HStack {
                    Spacer()
                    Button(isRunning ? "Running…" : "Run Backup") {
                        Task { await runBackup() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRunning || backupFolder == nil || backupResources.isEmpty)
                }
            } header: {
                Text("Backup Log")
            }
        }
        .formStyle(.grouped)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Backup Folder"
        guard panel.runModal() == .OK else { return }
        backupFolder = panel.url
    }

    private func runBackup() async {
        guard let folder = backupFolder else { return }
        isRunning = true
        logLines = []
        defer { isRunning = false }
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let runFolder = folder.appendingPathComponent("jamfdash-backup-\(timestamp)")
        do {
            try FileManager.default.createDirectory(at: runFolder, withIntermediateDirectories: true)
            logLines.append("Created backup folder: \(runFolder.lastPathComponent)")
            for res in BackupResource.allCases where backupResources.contains(res) {
                logLines.append("Backing up \(res.rawValue)…")
                let cmd = backupCommand(for: res)
                if let data = try? await vm.run(cmd) {
                    let file = runFolder.appendingPathComponent("\(res.id.replacingOccurrences(of: " ", with: "_")).json")
                    try data.write(to: file)
                    logLines.append("  ✓ \(res.rawValue) saved (\(data.count) bytes)")
                } else {
                    logLines.append("  ✗ \(res.rawValue) failed")
                }
            }
            logLines.append("Backup complete.")
        } catch {
            logLines.append("Error: \(error.localizedDescription)")
        }
    }

    private func backupCommand(for resource: BackupResource) -> CLICommand {
        switch resource {
        case .policies:       return .policies
        case .configProfiles: return .configProfiles
        case .scripts:        return .scripts
        case .packages:       return .packages
        case .smartGroups:    return .smartComputerGroups
        case .extensionAttrs: return .computerExtensionAttributes
        case .patchTitles:    return .patchTitles
        case .patchPolicies:  return .patchPolicies
        case .webhooks:       return .webhooks
        }
    }
}

// MARK: - Branding

private struct BrandingTab: View {
    let vm: SettingsViewModel

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Group {
                        if let url = vm.logoURL, let img = NSImage(contentsOf: url) {
                            Image(nsImage: img)
                                .resizable()
                                .scaledToFit()
                        } else {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.secondary.opacity(0.15))
                                .overlay {
                                    Text("No Logo")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                        }
                    }
                    .frame(width: 90, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    VStack(alignment: .leading, spacing: 8) {
                        Button("Choose Logo…") { vm.chooseLogo() }
                            .buttonStyle(.bordered)
                        if vm.logoURL != nil {
                            Button("Remove", role: .destructive) { vm.removeLogo() }
                                .buttonStyle(.plain)
                                .foregroundStyle(.red)
                        }
                    }
                }
            } header: {
                Text("Company Logo")
            } footer: {
                Text("The logo appears in the header of exported PDF reports. PNG or JPEG recommended.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - AI Assistant

private struct AITab: View {
    @Binding var isEnabled: Bool

    var body: some View {
        Form {
            Section {
                Toggle("Enable AI Assistant", isOn: $isEnabled)
            } header: {
                Text("AI Assistant")
            } footer: {
                Text("Powered by Apple Intelligence — on-device, private, and requires macOS 26.")
                    .foregroundStyle(.secondary)
            }

            if #available(macOS 26, *) {
                AIStatusSection()
            } else {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                        Text("Requires macOS 26 or later")
                    }
                } header: {
                    Text("System Requirements")
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    tipRow(icon: "text.bubble",
                           title: "Ask one thing at a time",
                           body: "Focus each message on a single task. \"Show me devices running macOS 15\" works better than a multi-part question.")
                    Divider()
                    tipRow(icon: "magnifyingglass",
                           title: "Use plain language",
                           body: "Ask in conversational questions or commands — \"Which devices haven't checked in for 30 days?\" or \"Send a blank push to C02XG2JCJG5J\".")
                    Divider()
                    tipRow(icon: "cpu",
                           title: "Hardware lookups need a serial",
                           body: "For CPU, RAM, disk, or installed apps on a specific Mac, include the serial number. For fleet-wide breakdowns, just ask — Dashie uses the inventory summary.")
                    Divider()
                    tipRow(icon: "arrow.counterclockwise",
                           title: "Start a new chat when things slow down",
                           body: "The on-device model has a 4 096-token context window (~12 000 characters). Long conversations fill it up — tap \"New Chat\" to reset and keep responses fast.")
                    Divider()
                    tipRow(icon: "lock.shield",
                           title: "Everything stays on your Mac",
                           body: "Dashie uses Apple Intelligence, which runs entirely on-device. No data is sent to external servers.")
                }
                .padding(.vertical, 4)
            } header: {
                Text("Prompting Tips")
            }
        }
        .formStyle(.grouped)
    }

    private func tipRow(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(Color.accentColor)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout).fontWeight(.medium)
                Text(body).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - AI Status Section (macOS 26+)

#if canImport(FoundationModels)
@available(macOS 26, *)
private struct AIStatusSection: View {
    private let model = SystemLanguageModel.default

    var body: some View {
        Section {
            switch model.availability {
            case .available:
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Apple Intelligence is ready")
                }
            case .unavailable(let reason):
                unavailableRow(for: reason)
            @unknown default:
                HStack(spacing: 8) {
                    Image(systemName: "questionmark.circle.fill").foregroundStyle(.secondary)
                    Text("Apple Intelligence status unknown")
                }
            }
        } header: {
            Text("Apple Intelligence Status")
        }
    }

    @ViewBuilder
    private func unavailableRow(for reason: SystemLanguageModel.Availability.UnavailableReason) -> some View {
        switch reason {
        case .deviceNotEligible:
            HStack(spacing: 8) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Device not eligible for Apple Intelligence")
                    Text("Apple Intelligence requires a Mac with Apple silicon and macOS 26.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        case .appleIntelligenceNotEnabled:
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Intelligence is not enabled")
                    Text("Go to System Settings → Apple Intelligence & Siri to turn it on.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        case .modelNotReady:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Model is downloading…")
                    Text("Apple Intelligence will be available once the download completes.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        @unknown default:
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                Text("Apple Intelligence is currently unavailable")
            }
        }
    }
}
#endif
