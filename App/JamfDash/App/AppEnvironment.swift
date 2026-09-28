import AppKit
import Foundation
import OSLog
import Observation
import SwiftUI
import UserNotifications

// MARK: - Pro Notification

struct ProNotification: Decodable, Identifiable, Sendable {
    let id: String
    let type: String
    let message: String
    let severity: String?
    let expirationDate: String?
    /// What the alert is about, when Jamf Pro names it in `params` (e.g. a patch title).
    let subject: String?

    private enum CodingKeys: String, CodingKey {
        case id, type, message, severity, params
        case expirationDate, expiration_date, expiresAt, expires_at, expirationUtcDateTime
    }

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    private static func subject(in params: KeyedDecodingContainer<AnyKey>) -> String? {
        for key in ["name", "title", "softwareTitleName", "displayName", "objectName"] {
            if let k = AnyKey(stringValue: key), let v = try? params.decode(String.self, forKey: k), !v.isEmpty {
                return v
            }
        }
        return nil
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else if let n = try? c.decode(Int.self, forKey: .id) { id = String(n) }
        else { id = UUID().uuidString }
        type       = (try? c.decode(String.self, forKey: .type)) ?? "UNKNOWN"
        message    = (try? c.decode(String.self, forKey: .message)) ?? ""
        severity   = try? c.decode(String.self, forKey: .severity)
        expirationDate = (try? c.decode(String.self, forKey: .expirationDate))
                      ?? (try? c.decode(String.self, forKey: .expiration_date))
                      ?? (try? c.decode(String.self, forKey: .expiresAt))
                      ?? (try? c.decode(String.self, forKey: .expires_at))
                      ?? (try? c.decode(String.self, forKey: .expirationUtcDateTime))
        subject = (try? c.nestedContainer(keyedBy: AnyKey.self, forKey: .params)).flatMap(Self.subject)
    }

    var severityColor: Color {
        switch severity?.uppercased() {
        case "CRITICAL": return .red
        case "WARNING":  return .orange
        default:         return .blue
        }
    }

    var severityIcon: String {
        switch severity?.uppercased() {
        case "CRITICAL": return "exclamationmark.triangle.fill"
        case "WARNING":  return "exclamationmark.circle.fill"
        default:         return "info.circle.fill"
        }
    }
}

@MainActor
@Observable
final class AppEnvironment {
    private static let logger = Logger(subsystem: "com.jamfdash", category: "AppEnvironment")
    private static let signposter = OSSignposter(subsystem: "com.jamfdash", category: "Sync")

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

    let ddmMonitorVM: DDMMonitorViewModel
    let platformVM: PlatformViewModel
    let aiAssistantVM: AIAssistantViewModel
    let settingsInspectorVM: SettingsInspectorViewModel
    let enrollmentVM: EnrollmentFlowViewModel

    /// Set by a view to switch the sidebar to another section; MainView applies and clears it.
    var requestedSection: SidebarItem?

    /// Opens Device Lookup and searches for a device name or serial number.
    func showInDeviceLookup(_ query: String) {
        deviceSearchVM.lookUp(query)
        requestedSection = .deviceSearch
    }

    /// Opens Enrollment → Recent Enrollments with this Mac's timeline.
    func showEnrollmentTimeline(serial: String) {
        enrollmentVM.showTimeline(serial: serial)
        requestedSection = .enrollment
    }
    let digestService: DigestService
    let driftVM: DriftViewModel
    let correlationVM: CorrelationViewModel
    let auditVM: AuditViewModel

    /// Non-nil when Jamf Security Cloud credentials are configured.
    private(set) var jscVM: JamfSecurityViewModel?

    // MARK: - Health score tracking

    private var previousHealthScore: Int? = nil
    /// The profile each product's data in memory was loaded from, so views that combine
    /// products (Device Correlation) can say which instances they're pairing.
    private(set) var loadedProfiles: [JamfProduct: String] = [:]

    /// Profiles discovered from the system keychain.
    private(set) var availableProfiles: [String] = []

    // MARK: - Sync progress (drives SyncBar)

    private(set) var syncStepLabels: [String] = []
    private(set) var syncCompletedSteps: Int = 0
    private(set) var isSyncing: Bool = false
    private(set) var notificationsState: LoadState<[ProNotification]> = .idle
    var notificationCount: Int {
        (notificationsState.value ?? []).count
    }
    private var currentLoadTask: Task<Void, Never>?

    // MARK: - Profile switching state

    private(set) var isSwitchingProfile = false
    private(set) var switchError: String?
    /// Incremented each time a profile switch succeeds; lets MainView reset navigation.
    private(set) var profileSwitchCount = 0

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
        let deprecationScanner = ProfileDeprecationScanner(cli: cliManager)
        self.overviewVM       = OverviewViewModel(repository: overviewRepo)
        self.securityVM       = SecurityViewModel(repository: securityRepo, cli: cliManager)
        self.fleetVM          = FleetViewModel(repository: fleetRepo)
        self.devicesVM        = devicesVM
        self.deviceSearchVM   = DeviceSearchViewModel(cli: cliManager, devicesVM: devicesVM, deprecationScanner: deprecationScanner)
        self.mobileDevicesVM  = MobileDevicesViewModel(cli: cliManager)
        self.protectVM        = ProtectViewModel(cli: cliManager)
        self.ddmMonitorVM           = DDMMonitorViewModel(cli: cliManager, deprecationScanner: deprecationScanner)
        self.platformVM             = PlatformViewModel(cli: cliManager)
        self.aiAssistantVM          = AIAssistantViewModel(cli: cliManager)
        self.schoolVM               = SchoolViewModel(cli: cliManager)
        self.settingsInspectorVM    = SettingsInspectorViewModel(cli: cliManager)
        self.enrollmentVM           = EnrollmentFlowViewModel(cli: cliManager)
        let instanceDir = InstanceStorage.directory(forProfile: profileService.selectedProfile.name)
        self.digestService          = DigestService(cli: cliManager, storageURL: instanceDir.appendingPathComponent("digests.json"))
        self.driftVM                = DriftViewModel(cli: cliManager, store: .forProfile(profileService.selectedProfile.name))
        self.correlationVM          = CorrelationViewModel()
        self.auditVM                = AuditViewModel(cli: cliManager, deprecationScanner: deprecationScanner)

        self.currentProduct = profileService.currentProduct
        IntentCLIProvider.current = cliManager
        refreshActiveProfileAuth()
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
        let deprecationScanner = ProfileDeprecationScanner(cli: demoCLI)
        self.overviewVM       = OverviewViewModel(repository: overviewRepo)
        self.securityVM       = SecurityViewModel(repository: securityRepo, cli: demoCLI)
        self.fleetVM          = FleetViewModel(repository: fleetRepo)
        self.devicesVM        = devicesVM
        self.deviceSearchVM   = DeviceSearchViewModel(cli: demoCLI, devicesVM: devicesVM, deprecationScanner: deprecationScanner)
        self.mobileDevicesVM  = MobileDevicesViewModel(cli: demoCLI)
        self.protectVM        = ProtectViewModel(cli: demoCLI)
        self.schoolVM               = SchoolViewModel(cli: demoCLI)
        self.ddmMonitorVM           = DDMMonitorViewModel(cli: demoCLI, deprecationScanner: deprecationScanner)
        self.platformVM             = PlatformViewModel(cli: demoCLI)
        self.aiAssistantVM          = AIAssistantViewModel(cli: demoCLI)
        self.settingsInspectorVM    = SettingsInspectorViewModel(cli: demoCLI)
        self.enrollmentVM           = EnrollmentFlowViewModel(cli: demoCLI)
        self.digestService          = DigestService(cli: demoCLI,
                                                    storageURL: InstanceStorage.demoDirectory.appendingPathComponent("digests.json"),
                                                    notifies: false)
        self.driftVM                = DriftViewModel(cli: demoCLI, store: .demo())
        self.correlationVM          = CorrelationViewModel()
        self.auditVM                = AuditViewModel(cli: demoCLI, deprecationScanner: deprecationScanner)

        self.currentProduct = .pro  // demo always starts with Jamf Pro
        IntentCLIProvider.current = demoCLI
    }

    // MARK: - Load / Refresh

    /// Rebuilds Dashie's local search index from data already in memory (no extra CLI calls).
    func rebuildFleetIndex() {
        var s = FleetKnowledgeIndex.Sources()
        s.computers = devicesVM.allComputers
        s.policies = fleetVM.policiesState.value ?? []
        s.policyCategories = fleetVM.policyCategoryMap
        s.configProfiles = fleetVM.configProfilesState.value ?? []
        s.profileCategories = fleetVM.configProfileCategoryMap
        s.scripts = fleetVM.scriptsState.value ?? []
        s.packages = fleetVM.packagesState.value ?? []
        s.smartGroups = fleetVM.groupsState.value ?? []
        s.blueprints = Array(platformVM.blueprintStatuses.values)
        s.complianceRules = platformVM.benchmarkResultsState.value?.rules ?? []
        s.digests = digestService.entries
        let index = FleetKnowledgeIndex.build(profile: profileService.selectedProfile.name, from: s)
        FleetKnowledgeStore.shared.replace(with: index, persist: !isDemoMode)
    }

    func loadMainData() {
        // Cancel any in-flight load so stale results from a previous profile don't land.
        currentLoadTask?.cancel()
        if isSyncing {
            isSyncing = false
            syncCompletedSteps = 0
        }

        // Sync current product from profile service on every data load.
        // In demo mode the product is driven by switchDemoProduct(), not the profile service.
        if !isDemoMode {
            currentProduct = profileService.currentProduct
        }
        let product = currentProduct
        loadedProfiles[product] = currentProfileName
        Self.logger.info("Starting main data sync — product: \(product.rawValue, privacy: .public), profile: \(self.currentProfileName, privacy: .private)")

        switch product {
        case .pro:
            syncStepLabels = ["Overview", "Security", "Mobile Devices", "Computers",
                              "Policies", "Smart Groups", "Scripts", "Packages", "Configuration Profiles", "Notifications"]
            syncCompletedSteps = 0
            isSyncing = true
            let startTime = Date()
            currentLoadTask = Task {
                let spID = Self.signposter.makeSignpostID()
                let spState = Self.signposter.beginInterval("MainSync", id: spID, "Jamf Pro")
                await withTaskGroup(of: Void.self) { group in
                    group.addTask { await self.overviewVM.load(force: true) }
                    group.addTask { await self.securityVM.load(force: true) }
                    group.addTask { await self.mobileDevicesVM.load(force: true) }
                    group.addTask { await self.devicesVM.load(force: true) }
                    group.addTask { await self.fleetVM.loadPolicies(force: true, suppressEnrichment: true) }
                    group.addTask { await self.fleetVM.loadGroups(force: true) }
                    group.addTask { await self.fleetVM.loadScripts(force: true) }
                    group.addTask { await self.fleetVM.loadPackages(force: true) }
                    group.addTask { await self.fleetVM.loadConfigProfiles(force: true, suppressEnrichment: true) }
                    group.addTask { await self.loadNotifications() }
                    for await _ in group { self.syncCompletedSteps += 1 }
                }
                Self.signposter.endInterval("MainSync", spState)
                guard !Task.isCancelled else {
                    Self.logger.info("Main data sync cancelled (Jamf Pro)")
                    return
                }
                let elapsed = String(format: "%.1f", Date().timeIntervalSince(startTime))
                Self.logger.info("Main data sync complete in \(elapsed, privacy: .public)s (Jamf Pro)")
                // Keep the stored server URL in sync with whatever Jamf Pro reports in the
                // overview. This corrects platform-API profiles, which store the gateway URL
                // (e.g. eu.apigw.jamf.com) at setup time instead of the actual instance URL
                // needed for console deep links (e.g. kbcgroup.jamfcloud.com).
                if !self.isDemoMode,
                   let reportedURL = self.overviewVM.value(for: "Server URL"),
                   !reportedURL.isEmpty {
                    let profile = self.profileService.selectedProfile.name
                    self.profileService.setServerURL(reportedURL, for: profile)
                }
                self.isSyncing = false
                self.updateDockBadge()
                // Start enrichment and digest only after the main sync completes so they
                // don't add concurrent CLI processes on top of the 10 sync tasks.
                self.fleetVM.startPostSyncEnrichment()
                self.rebuildFleetIndex()
                Task {
                    await self.digestService.runIfNeeded()
                    self.rebuildFleetIndex()   // include today's digest
                }
            }
        case .protect:
            syncStepLabels = ["Overview", "Computers", "Plans", "Analytics", "Analytic Sets", "Exception Sets"]
            syncCompletedSteps = 0
            isSyncing = true
            let startTime = Date()
            currentLoadTask = Task {
                let spID = Self.signposter.makeSignpostID()
                let spState = Self.signposter.beginInterval("MainSync", id: spID, "Jamf Protect")
                await withTaskGroup(of: Void.self) { group in
                    group.addTask { await self.protectVM.loadOverview(force: true) }
                    group.addTask { await self.protectVM.loadComputers(force: true) }
                    group.addTask { await self.protectVM.loadPlans(force: true) }
                    group.addTask { await self.protectVM.loadAnalytics(force: true) }
                    group.addTask { await self.protectVM.loadAnalyticSets(force: true) }
                    group.addTask { await self.protectVM.loadExceptionSets(force: true) }
                    for await _ in group { self.syncCompletedSteps += 1 }
                }
                Self.signposter.endInterval("MainSync", spState)
                guard !Task.isCancelled else {
                    Self.logger.info("Main data sync cancelled (Jamf Protect)")
                    return
                }
                let elapsed = String(format: "%.1f", Date().timeIntervalSince(startTime))
                Self.logger.info("Main data sync complete in \(elapsed, privacy: .public)s (Jamf Protect)")
                self.isSyncing = false
            }
        case .school:
            syncStepLabels = ["Overview", "Devices", "Device Groups", "Users", "User Groups", "Classes", "Apps"]
            syncCompletedSteps = 0
            isSyncing = true
            let startTime = Date()
            currentLoadTask = Task {
                let spID = Self.signposter.makeSignpostID()
                let spState = Self.signposter.beginInterval("MainSync", id: spID, "Jamf School")
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
                Self.signposter.endInterval("MainSync", spState)
                guard !Task.isCancelled else {
                    Self.logger.info("Main data sync cancelled (Jamf School)")
                    return
                }
                let elapsed = String(format: "%.1f", Date().timeIntervalSince(startTime))
                Self.logger.info("Main data sync complete in \(elapsed, privacy: .public)s (Jamf School)")
                self.isSyncing = false
            }
        }
    }

    // MARK: - Demo product switching

    /// Switches the active product in demo mode and reloads the relevant data.
    func switchDemoProduct(_ product: JamfProduct) {
        guard isDemoMode else { return }
        currentProduct = product
        NSApp.dockTile.badgeLabel = nil
        loadMainData()
    }

    // MARK: - System Notifications

    func loadNotifications() async {
        guard !isDemoMode else {
            notificationsState = .loaded([])
            return
        }
        notificationsState = .loading
        do {
            let data = try await cliManager.run(.proNotifications)
            let decoder = JSONDecoder()
            if let notifs = try? decoder.decode([ProNotification].self, from: data) {
                Self.logger.info("Loaded \(notifs.count) system notification(s)")
                notificationsState = .loaded(notifs)
            } else if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for key in ["notifications", "results", "items", "data"] {
                    if let arr = obj[key],
                       let arrData = try? JSONSerialization.data(withJSONObject: arr),
                       let notifs = try? decoder.decode([ProNotification].self, from: arrData) {
                        Self.logger.info("Loaded \(notifs.count) system notification(s) (key: \(key, privacy: .public))")
                        notificationsState = .loaded(notifs)
                        return
                    }
                }
                notificationsState = .loaded([])
            } else {
                notificationsState = .loaded([])
            }
        } catch {
            // Non-fatal — notifications failing should not block the UI
            Self.logger.error("Failed to load system notifications: \(error)")
            notificationsState = .loaded([])
        }
    }

    // MARK: - Profile discovery

    func loadProfiles() async {
        availableProfiles = await keychain.jamfCLIProfiles()
        refreshActiveProfileAuth()
    }

    // MARK: - Active profile auth

    /// True when the active jamf-cli profile authenticates through the Jamf Platform API
    /// gateway (`auth-method: platform`). Features the gateway doesn't offer check this.
    private(set) var activeProfileUsesPlatformAPI = false

    /// Whether the current connection allows destructive device actions.
    private(set) var allowsDestructiveActions = false

    func refreshActionPermission() {
        allowsDestructiveActions = isDemoMode
            || profileService.allowsDestructiveActions(for: profileService.selectedProfile.name)
    }

    func refreshActiveProfileAuth() {
        refreshActionPermission()
        guard !isDemoMode else {
            activeProfileUsesPlatformAPI = false
            blueprintsAccess = .available
            benchmarksAccess = .available
            return
        }
        let config = JamfCLIConfigFile(url: JamfCLIConfigFile.standardURL)
        let selected = profileService.selectedProfile.name
        let name = selected.isEmpty ? ((try? config.defaultProfile()) ?? "") : selected
        let method = name.isEmpty ? nil : (try? config.authMethod(ofProfile: name)) ?? nil
        activeProfileUsesPlatformAPI = method == "platform"
        probePlatformFeatures(profile: selected)
    }

    // MARK: - Platform-only features

    /// Whether Blueprints / Compliance Benchmarks can be loaded with the active profile.
    /// jamf-cli only serves them through the Platform API, and only integrations with the
    /// right Jamf Account permissions (in practice: created at platform-environment level)
    /// can read them — so each Platform profile is checked with one list call.
    enum PlatformFeatureAccess: Equatable {
        case checking
        case available
        case requiresPlatformAPI
        case noPermission
    }

    private(set) var blueprintsAccess: PlatformFeatureAccess = .checking
    private(set) var benchmarksAccess: PlatformFeatureAccess = .checking
    private var probedProfile: String?
    private var probeTask: Task<Void, Never>?

    func access(for item: SidebarItem) -> PlatformFeatureAccess {
        switch item {
        case .blueprints:           return blueprintsAccess
        case .complianceBenchmarks: return benchmarksAccess
        default:                    return .available
        }
    }

    private func probePlatformFeatures(profile: String) {
        guard activeProfileUsesPlatformAPI else {
            probeTask?.cancel()
            probedProfile = nil
            blueprintsAccess = .requiresPlatformAPI
            benchmarksAccess = .requiresPlatformAPI
            return
        }
        guard probedProfile != profile else { return }   // already checked (or checking)
        probeTask?.cancel()
        probedProfile = profile
        blueprintsAccess = .checking
        benchmarksAccess = .checking
        let cli = cliManager
        probeTask = Task { [weak self] in
            async let bp = Self.probe(cli, .blueprints)
            async let cb = Self.probe(cli, .complianceBenchmarks)
            let (bpAccess, cbAccess) = await (bp, cb)
            guard let self, !Task.isCancelled, self.probedProfile == profile else { return }
            self.blueprintsAccess = bpAccess
            self.benchmarksAccess = cbAccess
        }
    }

    /// Only a permission refusal disables a feature; any other failure (network, timeout)
    /// leaves it enabled so the view shows the real error when it loads.
    private nonisolated static func probe(_ cli: CLIManager, _ command: CLICommand) async -> PlatformFeatureAccess {
        do {
            _ = try await cli.run(command)
            return .available
        } catch CLIError.nonZeroExit(_, let stderr) {
            guard let payload = JamfCLIErrorPayload(output: stderr) else { return .available }
            if payload.isPermissionDenied { return .noPermission }
            if payload.exitCodeName == "unsupported" || payload.error == "unsupported" { return .requiresPlatformAPI }
            return .available
        } catch {
            return .available
        }
    }

    // MARK: - Instance switching

    /// Switch to a different jamf-cli profile, verify credentials, then reload all data.
    /// Sets `isSwitchingProfile` while verifying, `switchError` on failure.
    func switchInstance(to profileName: String) {
        guard !isSwitchingProfile else { return }
        guard profileName != profileService.selectedProfile.name else { return }

        Self.logger.info("Switching instance to profile: \(profileName, privacy: .private)")
        let previousProfile = profileService.selectedProfile
        let previousProduct = currentProduct

        profileService.selectedProfile = JamfProfile(name: profileName)
        currentProduct = profileService.currentProduct
        refreshActiveProfileAuth()
        isSwitchingProfile = true
        switchError = nil

        Task {
            do {
                try await cliManager.verifyConnection()
                Self.logger.info("Instance switch verified — loading data for \(profileName, privacy: .private)")
                // Another Jamf instance: don't let Dashie search the previous one's data.
                FleetKnowledgeStore.shared.clear()
                enrollmentVM.reset()
                // Scores from another instance aren't comparable.
                previousHealthScore = nil
                NSApp.dockTile.badgeLabel = nil
                useInstanceStorage(for: profileName)
                // Dashie's conversation is about the previous instance.
                aiAssistantVM.clearHistory()
                loadMainData()
                profileSwitchCount += 1
            } catch {
                Self.logger.error("Instance switch failed for \(profileName, privacy: .private): \(error)")
                profileService.selectedProfile = previousProfile
                currentProduct = previousProduct
                refreshActiveProfileAuth()
                switchError = Self.connectionErrorMessage(for: error, profile: profileName)
            }
            isSwitchingProfile = false
        }
    }

    func clearSwitchError() { switchError = nil }

    /// Points drift history, digests and correlation at the given profile's own data.
    private func useInstanceStorage(for profileName: String) {
        let dir = InstanceStorage.directory(forProfile: profileName)
        digestService.use(storageURL: dir.appendingPathComponent("digests.json"))
        driftVM.use(store: .forProfile(profileName))
        correlationVM.reset()
    }

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

    // MARK: - Fleet Health Score

    var fleetHealthScore: FleetHealthScore {
        FleetHealthScore(
            summary: securityVM.summary,
            staleCount: devicesVM.staleDevices.count,
            totalCount: devicesVM.totalCount,
            patchCompliancePct: securityVM.patchCompliancePct
        )
    }

    func updateDockBadge() {
        let score = fleetHealthScore
        // No score without security data, and none outside Jamf Pro: clear the badge and
        // keep the previous score, so a failed load can't trigger a "dropped" alert.
        guard currentProduct == .pro, score.isAvailable else {
            NSApp.dockTile.badgeLabel = nil
            return
        }
        let rawThreshold = UserDefaults.standard.integer(forKey: "healthScoreThreshold")
        let threshold = rawThreshold == 0 ? 70 : rawThreshold
        NSApp.dockTile.badgeLabel = score.score < threshold ? "\(score.score)" : nil

        if let prev = previousHealthScore, prev >= threshold, score.score < threshold {
            sendHealthScoreNotification(score: score.score)
        }
        previousHealthScore = score.score
    }

    private func sendHealthScoreNotification(score: Int) {
        Self.logger.notice("Fleet health score dropped to \(score) — posting alert notification")
        let content = UNMutableNotificationContent()
        content.title = "Fleet Health Alert"
        content.body = "Fleet health score dropped to \(score). Review your Security Posture."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "health-score-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                // Logger calls from completion handler closures need a nonisolated context;
                // use a detached task to stay off the main actor.
                Task.detached {
                    Logger(subsystem: "com.jamfdash", category: "AppEnvironment")
                        .error("Failed to post health score notification: \(error)")
                }
            }
        }
    }

    // MARK: - Jamf Security Cloud

    /// Reads JSC credentials from the keychain and (re-)creates jscVM if found.
    /// Call at bootstrap and after the user saves/removes credentials in Settings.
    func setupJSC() async {
        do {
            let creds = try await keychain.loadJSC()
            let client = JamfSecurityClient(credentials: creds)
            let repo   = JamfSecurityRepository(client: client)
            jscVM = JamfSecurityViewModel(repository: repo)
            Self.logger.info("Jamf Security Cloud configured — VM ready")
        } catch KeychainError.notFound {
            jscVM = nil
            Self.logger.info("No Jamf Security Cloud credentials found")
        } catch {
            jscVM = nil
            Self.logger.error("Failed to load JSC credentials: \(error)")
        }
    }

    // MARK: - Settings / Onboarding factories

    func makeSettingsVM() -> SettingsViewModel {
        let vm = SettingsViewModel(keychain: keychain, profileService: profileService, cliManager: cliManager)
        vm.onProfilesChanged = { [weak self] in
            Task { await self?.loadProfiles() }
        }
        vm.onActionPermissionChanged = { [weak self] in
            self?.refreshActionPermission()
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
    func makeReportSecurityVM() -> SecurityViewModel { SecurityViewModel(repository: securityRepo, cli: cliManager) }
}
