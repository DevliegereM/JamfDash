import Foundation
import Observation

@MainActor
@Observable
final class AppEnvironment {
    let keychain: KeychainService
    let profileService: ProfileService
    let downloader: CLIDownloader
    let cliManager: CLIManager

    let overviewRepo: OverviewRepository
    let securityRepo: SecurityRepository
    let fleetRepo: FleetRepository

    /// Persistent VMs — created once, survive navigation, only refreshed on demand.
    let overviewVM: OverviewViewModel
    let securityVM: SecurityViewModel
    let fleetVM: FleetViewModel
    let devicesVM: DevicesViewModel
    let deviceSearchVM: DeviceSearchViewModel
    let mobileDevicesVM: MobileDevicesViewModel
    let protectVM: ProtectViewModel
    let schoolVM: SchoolViewModel

    /// Profiles discovered from the system keychain.
    private(set) var availableProfiles: [String] = []

    // MARK: - Sync progress (drives SyncBar)

    private(set) var syncStepLabels: [String] = []
    private(set) var syncCompletedSteps: Int = 0
    private(set) var isSyncing: Bool = false

    // MARK: - Profile switching state

    private(set) var isSwitchingProfile = false
    private(set) var switchError: String?

    /// The name of the currently active jamf-cli profile.
    var currentProfileName: String {
        isDemoMode ? "Demo Mode" : profileService.selectedProfile.name
    }

    /// The product type for the currently active profile.
    private(set) var currentProduct: JamfProduct

    /// The API scope for the currently active profile.
    var currentScope: OnboardingViewModel.APIScope { profileService.currentScope }

    /// The server URL for the currently active profile (nil in demo mode or if not set).
    var currentServerURL: String? {
        isDemoMode ? nil : profileService.currentServerURL
    }

    /// True when running with synthetic demo data — no real Jamf connection.
    let isDemoMode: Bool

    // MARK: - Live init

    init() {
        let keychain        = KeychainService()
        let profileService  = ProfileService()
        let downloader      = CLIDownloader()
        let cliManager      = CLIManager(
            downloader: downloader,
            profileService: profileService,
            keychain: keychain
        )

        self.keychain       = keychain
        self.profileService = profileService
        self.downloader     = downloader
        self.cliManager     = cliManager
        self.isDemoMode     = false

        let overviewRepo = OverviewRepository(cli: cliManager)
        let securityRepo = SecurityRepository(cli: cliManager)
        let fleetRepo    = FleetRepository(cli: cliManager)

        self.overviewRepo = overviewRepo
        self.securityRepo = securityRepo
        self.fleetRepo    = fleetRepo

        let devicesVM = DevicesViewModel(cli: cliManager)
        self.overviewVM       = OverviewViewModel(repository: overviewRepo)
        self.securityVM       = SecurityViewModel(repository: securityRepo)
        self.fleetVM          = FleetViewModel(repository: fleetRepo)
        self.devicesVM        = devicesVM
        self.deviceSearchVM   = DeviceSearchViewModel(cli: cliManager, devicesVM: devicesVM)
        self.mobileDevicesVM  = MobileDevicesViewModel(cli: cliManager)
        self.protectVM        = ProtectViewModel(cli: cliManager)
        self.schoolVM         = SchoolViewModel(cli: cliManager)

        self.currentProduct = profileService.currentProduct
    }

    // MARK: - Demo init

    static func demo() -> AppEnvironment {
        AppEnvironment(demoCLI: DemoCLIManager())
    }

    private init(demoCLI: any CLIRunning) {
        // Create real support objects (unused for data in demo mode)
        let keychain       = KeychainService()
        let profileService = ProfileService()
        let downloader     = CLIDownloader()
        let cliManager     = CLIManager(
            downloader: downloader,
            profileService: profileService,
            keychain: keychain
        )

        self.keychain       = keychain
        self.profileService = profileService
        self.downloader     = downloader
        self.cliManager     = cliManager
        self.isDemoMode     = true

        // Wire repositories and VMs to the demo CLI
        let overviewRepo = OverviewRepository(cli: demoCLI)
        let securityRepo = SecurityRepository(cli: demoCLI)
        let fleetRepo    = FleetRepository(cli: demoCLI)

        self.overviewRepo = overviewRepo
        self.securityRepo = securityRepo
        self.fleetRepo    = fleetRepo

        let devicesVM = DevicesViewModel(cli: demoCLI)
        self.overviewVM       = OverviewViewModel(repository: overviewRepo)
        self.securityVM       = SecurityViewModel(repository: securityRepo)
        self.fleetVM          = FleetViewModel(repository: fleetRepo)
        self.devicesVM        = devicesVM
        self.deviceSearchVM   = DeviceSearchViewModel(cli: demoCLI, devicesVM: devicesVM)
        self.mobileDevicesVM  = MobileDevicesViewModel(cli: demoCLI)
        self.protectVM        = ProtectViewModel(cli: demoCLI)
        self.schoolVM         = SchoolViewModel(cli: demoCLI)

        self.currentProduct = .pro  // demo always starts with Jamf Pro
    }

    // MARK: - Load / Refresh

    func loadMainData() {
        // Sync current product from profile service on every data load.
        // In demo mode the product is driven by switchDemoProduct(), not the profile service.
        if !isDemoMode {
            currentProduct = profileService.currentProduct
        }
        switch currentProduct {
        case .pro:
            syncStepLabels = ["Overview", "Security", "Mobile Devices", "Computers",
                              "Policies", "Smart Groups", "Scripts", "Packages", "Configuration Profiles"]
            syncCompletedSteps = 0
            isSyncing = true
            Task {
                await withTaskGroup(of: Void.self) { group in
                    group.addTask { await self.overviewVM.load(force: true) }
                    group.addTask { await self.securityVM.load(force: true) }
                    group.addTask { await self.mobileDevicesVM.load(force: true) }
                    group.addTask { await self.devicesVM.load(force: true) }
                    group.addTask { await self.fleetVM.loadPolicies(force: true) }
                    group.addTask { await self.fleetVM.loadGroups(force: true) }
                    group.addTask { await self.fleetVM.loadScripts(force: true) }
                    group.addTask { await self.fleetVM.loadPackages(force: true) }
                    group.addTask { await self.fleetVM.loadConfigProfiles(force: true) }
                    for await _ in group { self.syncCompletedSteps += 1 }
                }
                self.isSyncing = false
            }
        case .protect:
            syncStepLabels = ["Overview", "Computers", "Plans", "Analytics", "Analytic Sets", "Exception Sets"]
            syncCompletedSteps = 0
            isSyncing = true
            Task {
                await withTaskGroup(of: Void.self) { group in
                    group.addTask { await self.protectVM.loadOverview(force: true) }
                    group.addTask { await self.protectVM.loadComputers(force: true) }
                    group.addTask { await self.protectVM.loadPlans(force: true) }
                    group.addTask { await self.protectVM.loadAnalytics(force: true) }
                    group.addTask { await self.protectVM.loadAnalyticSets(force: true) }
                    group.addTask { await self.protectVM.loadExceptionSets(force: true) }
                    for await _ in group { self.syncCompletedSteps += 1 }
                }
                self.isSyncing = false
            }
        case .school:
            syncStepLabels = ["Overview", "Devices", "Device Groups", "Users", "User Groups", "Classes", "Apps"]
            syncCompletedSteps = 0
            isSyncing = true
            Task {
                await withTaskGroup(of: Void.self) { group in
                    group.addTask { await self.schoolVM.loadOverview(force: true) }
                    group.addTask { await self.schoolVM.loadDevices(force: true) }
                    group.addTask { await self.schoolVM.loadDeviceGroups(force: true) }
                    group.addTask { await self.schoolVM.loadUsers(force: true) }
                    group.addTask { await self.schoolVM.loadUserGroups(force: true) }
                    group.addTask { await self.schoolVM.loadClasses(force: true) }
                    group.addTask { await self.schoolVM.loadApps(force: true) }
                    for await _ in group { self.syncCompletedSteps += 1 }
                }
                self.isSyncing = false
            }
        }
    }

    // MARK: - Demo product switching

    /// Switches the active product in demo mode and reloads the relevant data.
    func switchDemoProduct(_ product: JamfProduct) {
        guard isDemoMode else { return }
        currentProduct = product
        loadMainData()
    }

    // MARK: - Profile discovery

    func loadProfiles() async {
        availableProfiles = await keychain.jamfCLIProfiles()
    }

    // MARK: - Instance switching

    /// Switch to a different jamf-cli profile, verify credentials, then reload all data.
    /// Sets `isSwitchingProfile` while verifying, `switchError` on failure.
    func switchInstance(to profileName: String) {
        guard !isSwitchingProfile else { return }
        guard profileName != profileService.selectedProfile.name else { return }

        let previousProfile = profileService.selectedProfile
        let previousProduct = currentProduct

        profileService.selectedProfile = JamfProfile(name: profileName)
        currentProduct = profileService.currentProduct
        isSwitchingProfile = true
        switchError = nil

        Task {
            do {
                try await cliManager.verifyConnection()
                loadMainData()
            } catch {
                profileService.selectedProfile = previousProfile
                currentProduct = previousProduct
                switchError = Self.connectionErrorMessage(for: error, profile: profileName)
            }
            isSwitchingProfile = false
        }
    }

    func clearSwitchError() { switchError = nil }

    private static func connectionErrorMessage(for error: Error, profile: String) -> String {
        if case CLIError.nonZeroExit(_, let stderr) = error {
            let lower = stderr.lowercased()
            if lower.contains("authentication") || lower.contains("unauthorized") ||
               lower.contains("invalid") || lower.contains("forbidden") || lower.contains("401") {
                return "Authentication failed for \"\(profile)\". Check your credentials in Settings."
            }
            return "Cannot connect to \"\(profile)\": \(stderr)"
        }
        return "Cannot connect to \"\(profile)\": \(error.localizedDescription)"
    }

    // MARK: - Settings / Onboarding factories

    func makeSettingsVM() -> SettingsViewModel {
        let vm = SettingsViewModel(keychain: keychain, profileService: profileService, cliManager: cliManager)
        vm.onProfilesChanged = { [weak self] in
            Task { await self?.loadProfiles() }
        }
        vm.onProfileSwitched = { [weak self] name in
            self?.switchInstance(to: name)
        }
        return vm
    }

    func makeOnboardingVM() -> OnboardingViewModel {
        OnboardingViewModel(cliManager: cliManager, profileService: profileService)
    }

    /// For users who have the binary but no profile yet (skips the download step).
    func makeSetupVM() -> OnboardingViewModel {
        OnboardingViewModel(cliManager: cliManager, profileService: profileService, startAt: .productPicker)
    }

    // MARK: - Report factory (always fresh data for PDF export)

    func makeReportOverviewVM() -> OverviewViewModel { OverviewViewModel(repository: overviewRepo) }
    func makeReportSecurityVM() -> SecurityViewModel { SecurityViewModel(repository: securityRepo) }
}
