import AppKit
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

            UpdatesTab()
                .tabItem { Label("Updates", systemImage: "arrow.down.circle") }

            BrandingTab(vm: vm)
                .tabItem { Label("Branding", systemImage: "photo") }

            BackupTab(vm: vm)
                .tabItem { Label("Backup", systemImage: "arrow.counterclockwise.icloud") }

            AITab(isEnabled: $isAIEnabled)
                .tabItem { Label("AI", systemImage: "brain") }

            EnrollmentSettingsTab()
                .tabItem { Label("Enrollment", systemImage: "person.badge.plus") }

            SecurityCloudTab()
                .tabItem { Label("Security Cloud", systemImage: "shield.checkered") }

            DeveloperTab()
                .tabItem { Label("Developer", systemImage: "ladybug") }
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 520)
        .task { await vm.loadExisting() }
    }
}

// MARK: - Enrollment

/// Which Jamf Setup Manager profile the Enrollment section uses when there are several.
/// Only written when changed; `defaults delete be.devliegere.JamfDash
/// jamfDash.enrollment.setupManagerProfileID` resets it.
private struct EnrollmentSettingsTab: View {
    @Environment(AppEnvironment.self) private var env
    @AppStorage(EnrollmentFlowViewModel.setupManagerProfileKey) private var profileID = 0

    var body: some View {
        let vm = env.enrollmentVM
        Form {
            Section {
                if vm.setupManagerCandidates.isEmpty {
                    switch vm.scanState {
                    case .scanning(let done, let total):
                        HStack {
                            ProgressView(value: Double(done), total: Double(max(total, 1))).frame(maxWidth: 200)
                            Text("Looking for Setup Manager profiles…").foregroundStyle(.secondary)
                        }
                    case .finished:
                        Text("No configuration profile with Setup Manager settings (com.jamf.setupmanager) was found.")
                            .foregroundStyle(.secondary)
                    default:
                        HStack {
                            Text("Jamf Dash finds Setup Manager profiles when it scans policy and profile scopes.")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Find Profiles") { vm.startScan() }
                        }
                    }
                } else {
                    Picker("Setup Manager profile", selection: $profileID) {
                        Text("Automatic").tag(0)
                        Divider()
                        ForEach(vm.setupManagerCandidates) { p in
                            Text("\(p.name) (\(p.setupManager?.steps.count ?? 0) steps)").tag(p.id)
                        }
                    }
                    .onChange(of: profileID) { _, _ in vm.setupManagerPreferenceChanged() }
                }
            } header: {
                Text("Jamf Setup Manager")
            } footer: {
                Text("Setup Manager shows a window with enrollment steps and runs them in order. Its steps appear in Enrollment → Flow and on each Mac's timeline. Automatic uses the profile installed on the Mac, else the one in the PreStage, else one scoped to All Computers.")
                    .foregroundStyle(.secondary)
            }

            Section("Stuck commands") {
                Text("A command counts as stuck when it has been pending for 4 hours or more and the Mac has checked in since it was sent.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Updates

/// Jamf Dash's own updates (Sparkle). jamf-cli updates are under the CLI tab.
private struct UpdatesTab: View {
    @State private var checksAutomatically = AppUpdater.shared.automaticallyChecks
    @State private var installsAutomatically = AppUpdater.shared.automaticallyDownloads
    @State private var lastCheck = AppUpdater.shared.lastCheck

    var body: some View {
        Form {
            Section {
                Toggle("Check for updates automatically", isOn: $checksAutomatically)
                    .onChange(of: checksAutomatically) { _, on in
                        AppUpdater.shared.automaticallyChecks = on
                        if !on {
                            installsAutomatically = false
                            AppUpdater.shared.automaticallyDownloads = false
                        }
                    }
                Toggle("Download and install updates automatically", isOn: $installsAutomatically)
                    .onChange(of: installsAutomatically) { _, on in
                        AppUpdater.shared.automaticallyDownloads = on
                    }
                    .disabled(!checksAutomatically)
            } header: {
                Text("Jamf Dash Updates")
            } footer: {
                Text(checksAutomatically
                     ? "Jamf Dash checks for a new version once a day and asks before installing it. With automatic install on, updates are downloaded in the background and installed when you quit Jamf Dash."
                     : "Jamf Dash only checks when you choose Check for Updates.")
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Check for Updates Now") {
                        AppUpdater.shared.checkForUpdates()
                        lastCheck = AppUpdater.shared.lastCheck
                    }
                    Spacer()
                    Text(lastCheck.map { "Last checked \($0.formatted(.relative(presentation: .named)))" } ?? "Not checked yet")
                        .font(.caption).foregroundStyle(.secondary)
                }
                LabeledContent("Installed version", value: Self.installedVersion)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            checksAutomatically = AppUpdater.shared.automaticallyChecks
            installsAutomatically = AppUpdater.shared.automaticallyDownloads
            lastCheck = AppUpdater.shared.lastCheck
        }
    }

    private static var installedVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
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
                            .accessibilityLabel("Delete \(profile) connection")
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

struct AddConnectionSheet: View {
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
        // A sheet takes its content's ideal size; without a fixed width, long descriptions
        // ask for a single line and the sheet grows wider than the Settings window.
        .frame(width: 560)
        .frame(minHeight: 520, idealHeight: 660, maxHeight: 760)
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
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recommended: the only connection that shows every section, including Blueprints and Compliance Benchmarks. Create the API integration at the **platform environment** level in account.jamf.com, not for a single tenant.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Device actions (lock, restart, recovery lock, …) aren't available through the Platform API yet — Jamf is still expanding it, so more will become available over time. Until then, add a Jamf Pro API client connection for device actions.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
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
                Text("Region").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                Picker("Region", selection: $vm.platformRegion) {
                    ForEach(PlatformRegion.allCases) { Text("\($0.label) — \($0.gatewayURL)").tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            GridRow {
                Text("Created at").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                Picker("Created at", selection: $vm.platformScopeLevel) {
                    ForEach(PlatformScopeLevel.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("The level the API client was created at in Jamf Account. Environment is preferred.")
            }
            GridRow {
                Text(vm.platformScopeLevel.label).gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                TextField(vm.platformScopeLevel.placeholder, text: $vm.platformScopeID)
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
                    Text("Apple Intelligence requires a Mac with Apple silicon (M1 or later) and macOS 26.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        case .appleIntelligenceNotEnabled:
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Apple Intelligence is not enabled")
                    Text("Turn it on in System Settings → Apple Intelligence & Siri. Dashie shows a step-by-step guide until it's ready.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Open Apple Intelligence Settings") { AppleIntelligenceStatus.openSettings() }
                        .controlSize(.small)
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

// MARK: - Security Cloud Tab

private struct SecurityCloudTab: View {
    @Environment(AppEnvironment.self) private var env
    @State private var applicationID     = ""
    @State private var applicationSecret = ""
    @State private var isSaving          = false
    @State private var saveError: String?
    @State private var isLoaded          = false

    var body: some View {
        Form {
            Section {
                connectionStatusRow
            } header: {
                Text("Connection Status")
            }

            Section {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("Application ID")
                            .gridColumnAlignment(.trailing)
                            .foregroundStyle(.secondary)
                        TextField("Application ID from RADAR portal", text: $applicationID)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("Application Secret")
                            .gridColumnAlignment(.trailing)
                            .foregroundStyle(.secondary)
                        SecureField("Application Secret", text: $applicationSecret)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.password)
                    }
                }

                HStack {
                    if env.jscVM != nil {
                        Button("Remove", role: .destructive) {
                            Task { await removeCredentials() }
                        }
                        .disabled(isSaving)
                    }
                    Spacer()
                    Button(isSaving ? "Connecting…" : "Save & Connect") {
                        Task { await saveAndConnect() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(applicationID.trimmingCharacters(in: .whitespaces).isEmpty ||
                              applicationSecret.isEmpty || isSaving)
                }
            } header: {
                Text("Credentials")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let err = saveError {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                    Text("Obtain credentials from the RADAR portal → Security Integrations → API Credentials.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    infoRow(icon: "arrow.clockwise",
                            title: "Token refresh",
                            body: "Tokens expire after 15 minutes. Jamf Dash refreshes them automatically.")
                    Divider()
                    infoRow(icon: "gauge",
                            title: "Rate limits",
                            body: "5 requests/second, 10 000 requests/day per integration.")
                    Divider()
                    infoRow(icon: "iphone.and.arrow.forward",
                            title: "Data fetched",
                            body: "Device inventory with risk categories, connector state, and deployment state via Risk API v2.")
                }
                .padding(.vertical, 4)
            } header: {
                Text("About this Integration")
            }
        }
        .formStyle(.grouped)
        .task { await loadExisting() }
    }

    @ViewBuilder
    private var connectionStatusRow: some View {
        HStack(spacing: 8) {
            if let jscVM = env.jscVM {
                switch jscVM.state {
                case .loaded(let devices):
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Connected — \(devices.count) device(s) loaded")
                case .loading:
                    ProgressView().controlSize(.small)
                    Text("Loading…").foregroundStyle(.secondary)
                case .failed(let msg):
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                    Text(msg).foregroundStyle(.secondary).font(.caption).lineLimit(2)
                case .idle:
                    Image(systemName: "circle.dashed").foregroundStyle(.secondary)
                    Text("Configured — not yet loaded")
                }
            } else {
                Image(systemName: "minus.circle").foregroundStyle(.secondary)
                Text("Not configured")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func loadExisting() async {
        guard !isLoaded else { return }
        isLoaded = true
        if let creds = try? await env.keychain.loadJSC() {
            applicationID     = creds.applicationID
            applicationSecret = creds.applicationSecret
        }
    }

    private func saveAndConnect() async {
        isSaving   = true
        saveError  = nil
        defer { isSaving = false }
        let creds = JSCCredentials(
            applicationID: applicationID.trimmingCharacters(in: .whitespaces),
            applicationSecret: applicationSecret
        )
        do {
            try await env.keychain.saveJSC(creds)
            await env.setupJSC()
            if let vm = env.jscVM {
                await vm.load(force: true)
                if let err = vm.state.errorMessage {
                    saveError = err
                }
            }
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func removeCredentials() async {
        isSaving  = true
        saveError = nil
        defer { isSaving = false }
        try? await env.keychain.deleteJSC()
        await env.setupJSC()
        applicationID     = ""
        applicationSecret = ""
    }

    private func infoRow(icon: String, title: String, body: String) -> some View {
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

// MARK: - Developer Tab

private struct DeveloperTab: View {
    @State private var debugService = DebugLoggingService.shared
    @State private var showExportSuccess = false
    @State private var exportHours = 4
    @State private var showTerminalCommands = false
    @State private var showReadingLogs = false

    var body: some View {
        Form {
            // MARK: Unified Log
            Section {
                Toggle(isOn: $debugService.isEnabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Verbose Unified Logging")
                            .fontWeight(.medium)
                        Text("Captures all log levels (debug, info, notice, error, fault) for the com.jamfdash subsystem in macOS Console and log exports.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if debugService.isEnabled {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .imageScale(.small)
                        Text("Config installed — restart the app once to apply fully.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Config file")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(debugService.configFilePath)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(debugService.configFilePath, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .imageScale(.small)
                        }
                        .buttonStyle(.plain)
                        .help("Copy path to clipboard")
                    }
                }
            } header: {
                Text("Unified Log Verbosity")
            } footer: {
                Text("In Console.app filter by: subsystem == \"com.jamfdash\". Without this toggle only errors and faults are persisted; debug and info messages are discarded.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // MARK: Log Export
            Section {
                Picker("Time window", selection: $exportHours) {
                    Text("Last 1 hour").tag(1)
                    Text("Last 2 hours").tag(2)
                    Text("Last 4 hours (Recommended)").tag(4)
                    Text("Last 8 hours").tag(8)
                }
                .pickerStyle(.menu)

                HStack {
                    Button {
                        Task { await debugService.exportLogs(hours: exportHours) }
                    } label: {
                        if debugService.isExporting {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Exporting…")
                            }
                        } else {
                            Label("Export Logs to Downloads", systemImage: "arrow.down.doc")
                        }
                    }
                    .disabled(debugService.isExporting)
                    .help("Runs 'log show' for the com.jamfdash subsystem and saves the result to ~/Downloads")

                    Spacer()

                    if let url = debugService.lastExportURL {
                        Button {
                            debugService.revealInFinder()
                        } label: {
                            Label("Show in Finder", systemImage: "folder")
                        }
                        .help(url.path)
                    }
                }

                if let err = debugService.exportError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }

                if let url = debugService.lastExportURL {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Saved to \(url.lastPathComponent)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Log Export")
            } footer: {
                Text("Exports recent unified log entries for JamfDash to a .log file. Enable verbose logging first to capture debug-level entries, reproduce the issue, then export.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // MARK: Pre-launch activation
            Section {
                DisclosureGroup(isExpanded: $showTerminalCommands) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Use these to enable logging before Jamf Dash starts, or to watch logs live.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    terminalCommandRow(
                        label: "Install config plist:",
                        command: #"mkdir -p ~/Library/Preferences/Logging/Subsystems && printf '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>DEFAULT-OPTIONS</key><dict><key>level</key><string>debug</string></dict></dict></plist>' > ~/Library/Preferences/Logging/Subsystems/com.jamfdash.plist"#
                    )
                    Divider()
                    terminalCommandRow(
                        label: "Launch with --debug flag:",
                        command: #"open -a "JamfDash" --args --debug"#
                    )
                    Divider()
                    terminalCommandRow(
                        label: "Stream live in Terminal:",
                        command: #"log stream --predicate 'subsystem == "com.jamfdash"' --level debug"#
                    )
                    Divider()
                    terminalCommandRow(
                        label: "Capture stream to file (Ctrl+C to stop):",
                        command: #"log stream --predicate 'subsystem == "com.jamfdash"' --level debug > ~/Desktop/JamfDash.log"#
                    )
                    Divider()
                    terminalCommandRow(
                        label: "Capture to file AND watch in Terminal:",
                        command: #"log stream --predicate 'subsystem == "com.jamfdash"' --level debug | tee ~/Desktop/JamfDash.log"#
                    )
                    Divider()
                    terminalCommandRow(
                        label: "Remove config plist:",
                        command: "rm ~/Library/Preferences/Logging/Subsystems/com.jamfdash.plist"
                    )
                    Text("The config file is read by macOS when Jamf Dash starts, so it also captures startup. Once installed (here or with the toggle above) it stays active for every launch until removed.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 6)
                } label: {
                    Label("Terminal commands", systemImage: "terminal")
                }
            } header: {
                Text("Advanced")
            }

            // MARK: How to read logs
            Section {
                DisclosureGroup(isExpanded: $showReadingLogs) {
                VStack(alignment: .leading, spacing: 10) {
                    instructionRow(
                        step: "1",
                        title: "Open Console.app",
                        detail: "Found in /Applications/Utilities/ or via Spotlight."
                    )
                    Divider()
                    instructionRow(
                        step: "2",
                        title: "Filter by subsystem",
                        detail: "In the search bar, type:  subsystem:com.jamfdash"
                    )
                    Divider()
                    instructionRow(
                        step: "3",
                        title: "Set Action → Include Debug Messages",
                        detail: "In the Console menu bar choose Action → Include Debug Messages (and Info Messages) to see all log levels."
                    )
                    Divider()
                    instructionRow(
                        step: "4",
                        title: "Or use Terminal",
                        detail: "log stream --predicate 'subsystem == \"com.jamfdash\"' --level debug"
                    )
                }
                .padding(.vertical, 6)
                } label: {
                    Label("How to read logs in Console", systemImage: "list.bullet.rectangle")
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func terminalCommandRow(label: String, command: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text(command)
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .imageScale(.small)
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")
            }
            .padding(8)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    @ViewBuilder
    private func instructionRow(step: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(step)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}
