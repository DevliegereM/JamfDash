import Foundation
import OSLog

// MARK: - CLI Commands

enum CLICommand: Sendable {
    // MARK: Jamf Pro — data fetching
    case overview
    case securityReport
    case policies
    case smartComputerGroups
    case categories
    case scripts
    case packages
    case configProfiles
    case policyDetail(id: Int)
    case configProfileDetail(id: Int)
    case computers
    case computerDetail(serial: String)
    case smartGroupDetail(id: String)

    // MARK: Jamf Protect — data fetching
    case protectOverview
    case protectEvents
    case protectComputers
    case protectComputerDetail(name: String)
    case protectPlans
    case protectAlerts
    case protectInsights
    case protectAuditLogs
    case protectAnalyticSets
    case protectExceptionSetDetail(name: String)

    // MARK: Jamf School — data fetching
    case schoolOverview
    case schoolDevices
    case schoolDeviceGroups
    case schoolUsers
    case schoolUserGroups
    case schoolClasses
    case schoolApps

    // MARK: Device actions (safe)
    case blankPush(serial: String)
    case renewMDM(serial: String)
    case ddmSync(serial: String)
    case flushFailedCommands(serial: String)
    case flushAllCommands(serial: String)

    // MARK: Device actions (moderate)
    case redeployFramework(serial: String)
    case enableRemoteDesktop(serial: String)
    case disableRemoteDesktop(serial: String)
    case restart(serial: String)
    case shutdown(serial: String)

    // MARK: Device actions (destructive)
    case removeMDM(serial: String)
    case setRecoveryLock(serial: String)
    case lock(serial: String, pin: String)
    case erase(serial: String)

    // MARK: Mobile Device actions
    case mobileDeviceList
    case mobileDeviceErase(serial: String)
    case mobileDeviceLock(serial: String)
    case mobileDeviceRestart(serial: String)
    case mobileDeviceShutdown(serial: String)
    case mobileDeviceUnmanage(serial: String)
    case mobileDeviceEnableLostMode(serial: String)
    case mobileDeviceDisableLostMode(serial: String)
    case mobileDeviceClearPasscode(serial: String)
    case mobileDeviceUpdateInventory(serial: String)

    // MARK: Reports
    case reportPatchStatus
    case reportPolicyStatus
    case reportProfileStatus
    case reportAppStatus
    case reportUpdateStatus(includeFailures: Bool)
    case reportDeviceCompliance
    case reportInventorySummary
    case reportSoftwareInstalls

    // MARK: Bulk Operations
    case bulkEnablePolicies(category: String)
    case bulkDisablePolicies(pattern: String)
    case bulkAddToGroup(group: String, file: String)
    case bulkRemoveFromGroup(group: String, file: String)
    case bulkSendCommand(command: String, group: String)

    // MARK: Policy Execute
    case policyExecute(name: String, serial: String)

    // MARK: Org Objects
    case buildings
    case departments
    case networkSegments

    // MARK: Extension Attributes
    case computerExtensionAttributes

    // MARK: Patch Management
    case patchTitles
    case patchPolicies

    // MARK: Enrollment
    case depTokens
    case computerPrestages
    case mobileDevicePrestages

    // MARK: Webhooks
    case webhooks

    // MARK: Self Service & Check-In
    case selfServiceSettings
    case clientCheckInSettings

    // MARK: Protect extended - data
    case protectRemovableStorage
    case protectRemovableStorageDetail(name: String)
    case protectRemovableStorageExport(name: String)
    case protectUnifiedLogging
    case protectUnifiedLoggingDetail(name: String)
    case protectUnifiedLoggingExport(name: String)
    case protectActionConfigs
    case protectActionConfigDetail(name: String)
    case protectActionConfigExport(name: String)
    case protectTelemetryConfigs
    case protectTelemetryDetail(name: String)
    case protectTelemetryExport(name: String)
    case protectCustomPreventLists
    case protectCustomPreventListDetail(name: String)
    case protectCustomPreventListExport(name: String)
    case protectRoles
    case protectRoleDetail(name: String)
    case protectRoleExport(name: String)
    case protectUsers
    case protectUserDetail(email: String)
    case protectUserExport(email: String)
    case protectGroups
    case protectGroupDetail(name: String)
    case protectGroupExport(name: String)
    case protectAPIClients
    case protectAPIClientDetail(name: String)
    case protectAPIClientExport(name: String)
    case protectDataForwarding
    case protectDataRetention
    case protectConfigFreeze
    case protectConfigFreezeEnable
    case protectConfigFreezeDisable
    case protectDownloadsSummary
    case protectPlanExport(name: String)
    case protectAnalyticDetail(name: String)
    case protectAnalyticExport(name: String)
    case protectAnalyticSetExport(name: String)

    // MARK: Patch Management detail
    case patchTitleDetail(id: String)
    case patchPolicyDetail(id: String)
    case protectExceptionSetExport(name: String)

    var baseArguments: [String] {
        switch self {
        // Jamf Pro — data
        case .overview:             return ["pro", "overview", "-o", "json"]
        case .securityReport:       return ["pro", "report", "security", "-o", "json"]
        case .policies:             return ["pro", "classic-policies", "list", "-o", "json"]
        case .smartComputerGroups:  return ["pro", "smart-computer-groups", "list", "-o", "json"]
        case .categories:           return ["pro", "categories", "list", "-o", "json"]
        case .scripts:              return ["pro", "scripts", "list", "-o", "json"]
        case .packages:             return ["pro", "classic-packages", "list", "-o", "json"]
        case .configProfiles:                     return ["pro", "classic-macos-config-profiles", "list", "-o", "json"]
        case .policyDetail(let id):               return ["pro", "classic-policies", "get", "\(id)", "-o", "json"]
        case .configProfileDetail(let id):        return ["pro", "classic-macos-config-profiles", "get", "\(id)", "-o", "json"]
        case .computers:                          return ["pro", "comp", "list", "--all", "-o", "json"]
        case .computerDetail(let s):              return ["pro", "comp", "get", "--serial", s, "-o", "json"]
        case .smartGroupDetail(let id):           return ["pro", "smart-computer-groups", "get", id, "-o", "json"]

        // Jamf Protect — data
        case .protectEvents:        return ["protect", "alerts", "list", "-o", "json"]
        case .protectOverview:      return ["protect", "overview", "-o", "json"]
        case .protectComputers:             return ["protect", "comp", "list", "-o", "json"]
        case .protectComputerDetail(let n): return ["protect", "comp", "get", n, "-o", "json"]
        case .protectPlans:         return ["protect", "plans", "list", "-o", "json"]
        case .protectAlerts:        return ["protect", "analytics", "list", "-o", "json"]
        case .protectInsights:      return ["protect", "analytic-sets", "list", "-o", "json"]
        case .protectAuditLogs:     return ["protect", "exception-sets", "list", "-o", "json"]
        case .protectAnalyticSets:              return ["protect", "analytic-sets", "list", "-o", "json"]
        case .protectExceptionSetDetail(let n): return ["protect", "exception-sets", "get", n, "-o", "json"]

        // Jamf School — data
        case .schoolOverview:       return ["school", "overview", "-o", "json"]
        case .schoolDevices:        return ["school", "dev", "list", "-o", "json"]
        case .schoolDeviceGroups:   return ["school", "dg", "list", "-o", "json"]
        case .schoolUsers:          return ["school", "users", "list", "-o", "json"]
        case .schoolUserGroups:     return ["school", "user-groups", "list", "-o", "json"]
        case .schoolClasses:        return ["school", "cls", "list", "-o", "json"]
        case .schoolApps:           return ["school", "apps", "list", "-o", "json"]

        // Safe actions
        case .blankPush(let s):           return ["pro", "comp", "blank-push", "--serial", s, "--yes"]
        case .renewMDM(let s):            return ["pro", "comp", "renew-mdm", "--serial", s, "--yes"]
        case .ddmSync(let s):             return ["pro", "comp", "ddm-sync", "--serial", s, "--yes"]
        case .flushFailedCommands(let s): return ["pro", "comp", "flush-commands", "--serial", s, "--yes"]
        case .flushAllCommands(let s):    return ["pro", "comp", "flush-commands", "--serial", s, "--status", "both", "--yes"]

        // Moderate actions
        case .redeployFramework(let s):    return ["pro", "comp", "redeploy-framework", "--serial", s, "--yes"]
        case .enableRemoteDesktop(let s):  return ["pro", "comp", "enable-remote-desktop", "--serial", s, "--yes"]
        case .disableRemoteDesktop(let s): return ["pro", "comp", "disable-remote-desktop", "--serial", s, "--yes"]
        case .restart(let s):              return ["pro", "comp", "restart", "--serial", s, "--yes"]
        case .shutdown(let s):             return ["pro", "comp", "shutdown", "--serial", s, "--yes"]

        // Destructive actions
        case .removeMDM(let s):       return ["pro", "comp", "remove-mdm", "--serial", s, "--yes"]
        case .setRecoveryLock(let s): return ["pro", "comp", "set-recovery-lock", "--serial", s, "--yes"]
        case .lock(let s, let pin):   return ["pro", "comp", "lock", "--serial", s, "--pin", pin, "--yes", "--confirm-destructive"]
        case .erase(let s):           return ["pro", "comp", "erase", "--serial", s, "--yes"]

        // Mobile Devices
        case .mobileDeviceList:                    return ["pro", "md", "list", "--all", "-o", "json"]
        case .mobileDeviceErase(let s):            return ["pro", "md", "erase", "--serial", s, "--yes"]
        case .mobileDeviceLock(let s):             return ["pro", "md", "lock", "--serial", s, "--yes", "--confirm-destructive"]
        case .mobileDeviceRestart(let s):          return ["pro", "md", "restart", "--serial", s, "--yes"]
        case .mobileDeviceShutdown(let s):         return ["pro", "md", "shutdown", "--serial", s, "--yes"]
        case .mobileDeviceUnmanage(let s):         return ["pro", "md", "unmanage", "--serial", s, "--yes"]
        case .mobileDeviceEnableLostMode(let s):   return ["pro", "md", "enable-lost-mode", "--serial", s, "--yes"]
        case .mobileDeviceDisableLostMode(let s):  return ["pro", "md", "disable-lost-mode", "--serial", s, "--yes"]
        case .mobileDeviceClearPasscode(let s):    return ["pro", "md", "clear-passcode", "--serial", s, "--yes"]
        case .mobileDeviceUpdateInventory(let s):  return ["pro", "md", "update-inventory", "--serial", s, "--yes"]

        // Reports
        case .reportPatchStatus:              return ["pro", "report", "patch-status", "-o", "json"]
        case .reportPolicyStatus:             return ["pro", "report", "policy-status", "-o", "json"]
        case .reportProfileStatus:            return ["pro", "report", "profile-status", "-o", "json"]
        case .reportAppStatus:                return ["pro", "report", "app-status", "-o", "json"]
        case .reportUpdateStatus(let f):      return f ? ["pro", "report", "update-status", "--scan-failures", "-o", "json"] : ["pro", "report", "update-status", "-o", "json"]
        case .reportDeviceCompliance:         return ["pro", "report", "device-compliance", "-o", "json"]
        case .reportInventorySummary:         return ["pro", "report", "inventory-summary", "-o", "json"]
        case .reportSoftwareInstalls:         return ["pro", "report", "software-installs", "-o", "json"]

        // Bulk Operations
        case .bulkEnablePolicies(let c):          return ["pro", "bulk", "enable-policies", "--category", c, "--yes"]
        case .bulkDisablePolicies(let p):         return ["pro", "bulk", "disable-policies", "--name", p, "--yes"]
        case .bulkAddToGroup(let g, let f):       return ["pro", "bulk", "add-to-group", "--group", g, "--from-file", f, "--yes"]
        case .bulkRemoveFromGroup(let g, let f):  return ["pro", "bulk", "remove-from-group", "--group", g, "--from-file", f, "--yes"]
        case .bulkSendCommand(let cmd, let grp):  return ["pro", "bulk", "send-command", "--command", cmd, "--group", grp, "--yes"]

        // Policy Execute
        case .policyExecute(let n, let s): return ["pro", "policy-execute", n, "--target", s, "--yes"]

        // Org Objects
        case .buildings:       return ["pro", "bld", "list", "-o", "json"]
        case .departments:     return ["pro", "dept", "list", "-o", "json"]
        case .networkSegments: return ["pro", "classic-network-segments", "list", "-o", "json"]

        // Extension Attributes
        case .computerExtensionAttributes: return ["pro", "computer-extension-attributes", "list", "-o", "json"]

        // Patch Management
        case .patchTitles:   return ["pro", "classic-patch-titles", "list", "-o", "json"]
        case .patchPolicies: return ["pro", "classic-patch-policies", "list", "-o", "json"]

        // Enrollment
        case .depTokens:             return ["pro", "device-enrollment-instances", "list", "-o", "json"]
        case .computerPrestages:     return ["pro", "computer-prestages", "list", "-o", "json"]
        case .mobileDevicePrestages: return ["pro", "mobile-device-prestages", "list", "-o", "json"]

        // Webhooks
        case .webhooks: return ["pro", "webhooks", "list", "-o", "json"]

        // Self Service & Check-In
        case .selfServiceSettings:   return ["pro", "self-service-settings", "get", "-o", "json"]
        case .clientCheckInSettings: return ["pro", "client-check-in", "get", "-o", "json"]

        // Protect extended
        case .protectRemovableStorage:               return ["protect", "rscs", "list", "-o", "json"]
        case .protectRemovableStorageDetail(let n):  return ["protect", "rscs", "get", n, "-o", "json"]
        case .protectRemovableStorageExport(let n):  return ["protect", "rscs", "export", n]
        case .protectUnifiedLogging:                 return ["protect", "ulf", "list", "-o", "json"]
        case .protectUnifiedLoggingDetail(let n):    return ["protect", "ulf", "get", n, "-o", "json"]
        case .protectUnifiedLoggingExport(let n):    return ["protect", "ulf", "export", n]
        case .protectActionConfigs:                  return ["protect", "ac", "list", "-o", "json"]
        case .protectActionConfigDetail(let n):      return ["protect", "ac", "get", n, "-o", "json"]
        case .protectActionConfigExport(let n):      return ["protect", "ac", "export", n]
        case .protectTelemetryConfigs:               return ["protect", "telemetry", "list", "-o", "json"]
        case .protectTelemetryDetail(let n):         return ["protect", "telemetry", "get", n, "-o", "json"]
        case .protectTelemetryExport(let n):         return ["protect", "telemetry", "export", n]
        case .protectCustomPreventLists:             return ["protect", "cpl", "list", "-o", "json"]
        case .protectCustomPreventListDetail(let n): return ["protect", "cpl", "get", n, "-o", "json"]
        case .protectCustomPreventListExport(let n): return ["protect", "cpl", "export", n]
        case .protectRoles:                          return ["protect", "roles", "list", "-o", "json"]
        case .protectRoleDetail(let n):              return ["protect", "roles", "get", n, "-o", "json"]
        case .protectRoleExport(let n):              return ["protect", "roles", "export", n]
        case .protectUsers:                          return ["protect", "users", "list", "-o", "json"]
        case .protectUserDetail(let e):              return ["protect", "users", "get", e, "-o", "json"]
        case .protectUserExport(let e):              return ["protect", "users", "export", e]
        case .protectGroups:                         return ["protect", "groups", "list", "-o", "json"]
        case .protectGroupDetail(let n):             return ["protect", "groups", "get", n, "-o", "json"]
        case .protectGroupExport(let n):             return ["protect", "groups", "export", n]
        case .protectAPIClients:                     return ["protect", "apic", "list", "-o", "json"]
        case .protectAPIClientDetail(let n):         return ["protect", "apic", "get", n, "-o", "json"]
        case .protectAPIClientExport(let n):         return ["protect", "apic", "export", n]
        case .protectDataForwarding:                 return ["protect", "df", "get", "-o", "json"]
        case .protectDataRetention:                  return ["protect", "dr", "get", "-o", "json"]
        case .protectConfigFreeze:                   return ["protect", "cf", "get", "-o", "json"]
        case .protectConfigFreezeEnable:             return ["protect", "cf", "enable", "--yes"]
        case .protectConfigFreezeDisable:            return ["protect", "cf", "disable", "--yes"]
        case .protectDownloadsSummary:               return ["protect", "downloads", "summary", "-o", "json"]
        case .protectPlanExport(let n):              return ["protect", "plans", "export", n]
        case .protectAnalyticDetail(let n):          return ["protect", "analytics", "get", n, "-o", "json"]
        case .protectAnalyticExport(let n):          return ["protect", "analytics", "export", n]
        case .protectAnalyticSetExport(let n):       return ["protect", "analytic-sets", "export", n]

        // Patch Management detail
        case .patchTitleDetail(let id):  return ["pro", "classic-patch-titles",  "get", id, "-o", "json"]
        case .patchPolicyDetail(let id): return ["pro", "classic-patch-policies", "get", id, "-o", "json"]
        case .protectExceptionSetExport(let n):      return ["protect", "exception-sets", "export", n]
        }
    }

    var timeout: TimeInterval {
        switch self {
        case .securityReport, .computers, .erase, .lock(_, _),
             .mobileDeviceList, .mobileDeviceErase, .mobileDeviceLock,
             .bulkAddToGroup, .bulkRemoveFromGroup, .bulkSendCommand,
             .bulkEnablePolicies, .bulkDisablePolicies,
             .reportPatchStatus, .reportPolicyStatus, .reportUpdateStatus,
             .reportDeviceCompliance, .reportSoftwareInstalls:
            return 120
        default: return 60
        }
    }

    /// True for commands that permanently alter or destroy device state.
    var isDestructive: Bool {
        switch self {
        case .removeMDM, .setRecoveryLock, .lock(_, _), .erase,
             .mobileDeviceErase, .mobileDeviceLock, .mobileDeviceUnmanage,
             .mobileDeviceEnableLostMode,
             .protectConfigFreezeEnable, .protectConfigFreezeDisable:
            return true
        default: return false
        }
    }
}

// MARK: - CLIRunning Protocol

protocol CLIRunning: Sendable {
    func run(_ command: CLICommand) async throws -> Data
}

// MARK: - CLIManager Actor

actor CLIManager: CLIRunning {
    private let downloader: CLIDownloader
    private let profileService: ProfileService
    private let keychain: KeychainService
    private let executor: CLIExecutor
    private let logger = Logger(subsystem: "com.jamfdash", category: "CLIManager")

    private(set) var installedVersion: CLIVersion?

    init(
        downloader: CLIDownloader,
        profileService: ProfileService,
        keychain: KeychainService,
        executor: CLIExecutor = CLIExecutor()
    ) {
        self.downloader = downloader
        self.profileService = profileService
        self.keychain = keychain
        self.executor = executor
    }

    // MARK: - Paths

    static let appSupportName = "JamfDash"

    private var supportDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Self.appSupportName, isDirectory: true)
    }

    private var binDirectory: URL {
        supportDirectory.appendingPathComponent("bin", isDirectory: true)
    }

    var binaryURL: URL {
        binDirectory.appendingPathComponent("jamf-cli")
    }

    var isBinaryInstalled: Bool {
        FileManager.default.fileExists(atPath: binaryURL.path)
    }

    // MARK: - Lifecycle

    /// Downloads the binary if missing. Call only from onboarding (user-triggered).
    func ensureBinary() async throws {
        try createDirectoriesIfNeeded()
        if !isBinaryInstalled {
            logger.info("jamf-cli not found, downloading")
            try await downloader.download(to: binaryURL, arch: Self.currentArchitecture)
            try setExecutable(binaryURL)
        }
        await refreshVersion()
    }

    /// Read and cache the installed version. Safe to call on any launch.
    func refreshVersion() async {
        guard isBinaryInstalled else {
            self.installedVersion = nil
            return
        }
        do {
            let data = try await executor.execute(
                binary: binaryURL,
                arguments: ["--version"],
                environment: ProcessInfo.processInfo.environment,
                timeout: 10
            )
            let text = String(data: data, encoding: .utf8) ?? ""
            // Output format: "jamf-cli 1.6.0\n  commit: ...\n  built: ..."
            // Take only the first line so the build timestamp is not mistaken for the version.
            let firstLine = text.components(separatedBy: "\n").first ?? text
            let semver = firstLine
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: " ")
                .last
                .map(String.init) ?? firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
            self.installedVersion = semver.isEmpty ? nil : CLIVersion(semver: semver, architecture: Self.currentArchitecture)
        } catch {
            self.installedVersion = nil
            logger.error("Failed to read jamf-cli version: \(error.localizedDescription)")
        }
        logger.info("jamf-cli version: \(self.installedVersion?.semver ?? "unknown")")
    }

    func checkForUpdate() async throws -> String? {
        let latest = try await downloader.latestVersion()
        guard let current = installedVersion else { return latest }
        return current.isOlderThan(latest) ? latest : nil
    }

    func performUpdate() async throws {
        try await downloader.download(to: binaryURL, arch: Self.currentArchitecture)
        try setExecutable(binaryURL)
        await refreshVersion()
        logger.info("jamf-cli updated to \(self.installedVersion?.semver ?? "unknown")")
    }

    // MARK: - Setup

    /// Drives `jamf-cli config add-profile` for SSO / no-local-account instances.
    /// The user must have created an API role and client in Jamf Pro beforehand.
    func setupOAuth(
        serverURL: String,
        profileName: String,
        clientID: String,
        clientSecret: String
    ) async throws -> String {
        guard isBinaryInstalled else { throw CLIError.binaryMissing }
        let stdin = "\(clientID)\n\(clientSecret)\n"
        let data = try await executor.executeInteractive(
            binary: binaryURL,
            arguments: ["config", "add-profile", profileName,
                        "--url", serverURL, "--auth-method", "oauth2"],
            environment: ProcessInfo.processInfo.environment,
            stdinData: stdin.data(using: .utf8) ?? Data(),
            timeout: 30
        )
        // Persist the chosen profile so commands use it immediately
        profileService.selectedProfile = JamfProfile(name: profileName)
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Drives `jamf-cli config add-profile` for Jamf School (API key auth).
    /// The user must have obtained their Network ID and API Key from Jamf School → Organisation → API.
    func setupSchool(
        serverURL: String,
        profileName: String,
        networkID: String,
        apiKey: String
    ) async throws -> String {
        guard isBinaryInstalled else { throw CLIError.binaryMissing }
        let stdin = "\(networkID)\n\(apiKey)\n"
        let data = try await executor.executeInteractive(
            binary: binaryURL,
            arguments: ["config", "add-profile", profileName,
                        "--url", serverURL, "--auth-method", "apikey"],
            environment: ProcessInfo.processInfo.environment,
            stdinData: stdin.data(using: .utf8) ?? Data(),
            timeout: 30
        )
        profileService.selectedProfile = JamfProfile(name: profileName)
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Drives `jamf-cli pro setup` non-interactively by piping answers to stdin.
    func setup(
        serverURL: String,
        username: String,
        password: String,
        scope: Int,
        profileName: String
    ) async throws -> String {
        guard isBinaryInstalled else { throw CLIError.binaryMissing }
        // Answers in the order jamf-cli prompts for them
        let stdin = [serverURL, username, password, "\(scope)", profileName]
            .joined(separator: "\n") + "\n"
        let data = try await executor.executeInteractive(
            binary: binaryURL,
            arguments: ["pro", "setup"],
            environment: ProcessInfo.processInfo.environment,
            stdinData: stdin.data(using: .utf8) ?? Data(),
            timeout: 60
        )
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// True when at least one jamf-cli profile is configured.
    /// Uses keychain-based discovery (same source as SettingsViewModel) rather than
    /// running `jamf-cli profiles list` which is not a valid command.
    func hasProfiles() async -> Bool {
        let profiles = await keychain.jamfCLIProfiles()
        return !profiles.isEmpty
    }

    /// Verifies the current profile can authenticate by running a lightweight overview command.
    /// Throws `CLIError.nonZeroExit` (containing the auth error message) on failure.
    func verifyConnection() async throws {
        guard isBinaryInstalled else { throw CLIError.binaryMissing }
        let product = profileService.currentProduct
        let command: CLICommand
        switch product {
        case .pro:      command = .overview
        case .protect:  command = .protectOverview
        case .school:   command = .schoolOverview
        }
        _ = try await run(command)
    }

    /// Verifies a specific profile (by name and product) without changing the active profile.
    func verifyConnection(profileName: String, product: JamfProduct) async throws {
        guard isBinaryInstalled else { throw CLIError.binaryMissing }
        let command: CLICommand
        switch product {
        case .pro:      command = .overview
        case .protect:  command = .protectOverview
        case .school:   command = .schoolOverview
        }
        let args = ["--profile", profileName] + command.baseArguments
        _ = try await executor.execute(
            binary: binaryURL,
            arguments: args,
            environment: ProcessInfo.processInfo.environment,
            timeout: command.timeout
        )
    }

    // MARK: - Execution

    func run(_ command: CLICommand) async throws -> Data {
        guard isBinaryInstalled else { throw CLIError.binaryMissing }

        let profile = profileService.selectedProfile
        let args = profile.isDefault ? command.baseArguments : ["--profile", profile.name] + command.baseArguments

        logger.debug("Running: jamf-cli \(args.joined(separator: " "))")

        do {
            return try await executor.execute(
                binary: binaryURL,
                arguments: args,
                environment: ProcessInfo.processInfo.environment,
                timeout: command.timeout
            )
        } catch {
            logger.error("jamf-cli failed: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Profile helpers

    func availableProfiles() -> [String] {
        profileService.availableProfiles(binaryURL: binaryURL)
    }

    func removeProfile(_ name: String) async throws {
        guard isBinaryInstalled else { throw CLIError.binaryMissing }
        _ = try await executor.execute(
            binary: binaryURL,
            arguments: ["config", "remove-profile", name],
            environment: ProcessInfo.processInfo.environment,
            timeout: 10
        )
    }

    // MARK: - Private helpers

    private func createDirectoriesIfNeeded() throws {
        for dir in [supportDirectory, binDirectory] {
            if !FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }

    private func setExecutable(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    static var currentArchitecture: CLIVersion.Architecture {
        #if arch(arm64)
        return .arm64
        #else
        return .x86_64
        #endif
    }
}
