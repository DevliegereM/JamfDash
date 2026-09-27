import Foundation
import OSLog
import UniformTypeIdentifiers

// MARK: - CLI Commands

enum CLICommand: Sendable {
    // MARK: Jamf Pro — data fetching
    case overview
    case securityReport
    /// Inventory with the sections needed to build a security report locally —
    /// the fallback when `pro report security` hits the gateway's missing /v4 endpoint.
    case securityInventory
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
    case computerDetailById(id: String)
    /// One Mac's installed applications (inventory APPLICATIONS section).
    case installedApps(serial: String)
    case smartGroupDetail(id: String)

    // MARK: DDM Monitor
    case ddmStatusItems(managementId: String)
    case ddmComputers
    case reportDDMStatus
    case proNotifications

    // MARK: Blueprints
    case blueprints
    case blueprintDetail(name: String)
    case blueprintStatus                    // Platform report: deployment state + device counts

    // MARK: Compliance Benchmarks
    case complianceBenchmarks
    case complianceBenchmarkDetail(name: String)
    case benchmarkCompliancePercentage(id: String)
    case benchmarkRuleStats(id: String)
    case benchmarkRuleDevices(id: String, ruleID: String)
    case benchmarkFailingDevices(title: String)

    // MARK: Jamf Protect — data fetching
    case protectOverview
    case protectEvents
    case protectComputers
    case protectComputerDetail(name: String)
    case protectPlans
    case protectAlerts
    case protectInsights
    case protectAuditLogs
    case protectExceptionSets
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
    case schoolProfiles
    case schoolDepDevices

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
    /// Clears the Recovery Lock password (jamf-cli clears it when no new password is given).
    case clearRecoveryLock(serial: String)
    case lock(serial: String, pin: String)
    case erase(serial: String)

    // MARK: Mobile Device actions
    case mobileDeviceList
    case mobileDeviceErase(serial: String)
    case mobileDeviceLock(serial: String)
    case mobileDeviceRestart(serial: String)
    case mobileDeviceShutdown(serial: String)
    case mobileDeviceUnmanage(serial: String)
    case mobileDeviceEnableLostMode(serial: String, message: String, phone: String, footnote: String)
    case mobileDeviceDisableLostMode(serial: String)
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

    // MARK: Audit
    case proAudit(category: String)

    // MARK: Bulk Operations
    case bulkEnablePolicies(category: String)
    case bulkDisablePolicies(pattern: String)

    // MARK: Org Objects
    case buildings
    case departments
    case networkSegments

    // MARK: Extension Attributes
    case computerExtensionAttributes

    // MARK: Patch Management
    case patchTitles
    case patchPolicies                      // Classic API list (id+name only)
    case patchSoftwareTitleConfigurations   // modern patch titles (UAPI v2)
    case appInstallerTitles                 // App Installer catalogue
    case appInstallerDeployments            // App Installer deployments
    case restrictedSoftware                 // restricted software list (id+name only)
    case restrictedSoftwareDetail(id: String) // full detail with "general" sub-object

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
    case protectUnifiedLogging
    case protectUnifiedLoggingDetail(name: String)
    case protectActionConfigs
    case protectTelemetryConfigs
    case protectCustomPreventLists
    case protectRoles
    case protectUsers
    case protectGroups
    case protectAPIClients
    case protectDataForwarding
    case protectDataRetention
    case protectConfigFreeze
    case protectDownloadsSummary
    case protectAnalyticDetail(name: String)

    // MARK: Patch Management detail
    case patchTitleDetail(id: String)
    case patchPolicyDetail(id: String)

    // MARK: Script & Package detail
    case scriptDetail(id: String)
    case packageDetail(id: Int)

    // MARK: macOS 27 readiness (appended)
    /// DDM-based managed software update plans (Jamf Pro API `/v1/managed-software-updates/plans`).
    case softwareUpdatePlans
    /// Plans for a single computer — `computerId` must be the numeric Jamf Pro ID.
    case softwareUpdatePlansForComputer(computerId: String)
    /// Managed software update statuses (`/v1/managed-software-updates/update-statuses`).
    case softwareUpdateStatuses
    /// Computers with OS version, DDM flag and installed configuration profiles.
    case computersUpdateReadiness

    // MARK: Enrollment flow & timeline (appended)
    /// Inventory with enrollment dates, method and serials for the Recent Enrollments list.
    case recentEnrollments
    /// One Mac's inventory with the sections the timeline needs.
    case enrollmentInventory(serial: String)
    /// MDM commands for one Mac (`clientManagementId` must be a UUID).
    case mdmCommandsForDevice(managementId: String)
    /// One section of a Mac's Classic computer history.
    case computerHistory(serial: String, subset: ComputerHistorySubset)
    case computerPrestageDetail(id: String)
    case logFlushingSettings

    enum ComputerHistorySubset: String, Sendable {
        case commands = "Commands"
        case policyLogs = "PolicyLogs"
    }

    /// Letters and digits only; serial numbers never contain anything else.
    static func sanitizedSerial(_ serial: String) -> String {
        serial.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    /// `--serial=<value>`. The `=` form keeps a value that starts with "-" from being read
    /// as a flag. Control characters are dropped; spaces, dots and dashes stay because
    /// virtual machine serials use them.
    static func serialFlag(_ serial: String) -> String {
        "--serial=" + cleanValue(serial)
    }

    /// Trims whitespace and removes control characters from a value passed to jamf-cli.
    static func cleanValue(_ value: String) -> String {
        String(String.UnicodeScalarView(value.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }))
            .trimmingCharacters(in: .whitespaces)
    }

    private static func protectList(_ sub: String) -> [String] {
        ["protect", sub, "list", "-o", "json"]
    }
    private static func protectGet(_ sub: String, _ name: String) -> [String] {
        ["protect", sub, "get", "-o", "json", "--", name]
    }

    var baseArguments: [String] {
        switch self {
        // Jamf Pro — data
        case .overview:             return ["pro", "overview", "-o", "json"]
        case .securityReport:       return ["pro", "report", "security", "-o", "json"]
        case .securityInventory:    return ["pro", "computers-inventory", "list", "--all", "--section", "GENERAL", "--section", "HARDWARE", "--section", "OPERATING_SYSTEM", "--section", "SECURITY", "--section", "DISK_ENCRYPTION", "-o", "json"]
        case .policies:             return ["pro", "classic-policies", "list", "-o", "json"]
        case .smartComputerGroups:  return ["pro", "smart-computer-groups", "list", "-o", "json"]
        case .categories:           return ["pro", "categories", "list", "-o", "json"]
        case .scripts:              return ["pro", "scripts", "list", "-o", "json"]
        case .packages:             return ["pro", "classic-packages", "list", "-o", "json"]
        case .configProfiles:                     return ["pro", "classic-macos-config-profiles", "list", "-o", "json"]
        case .policyDetail(let id):               return ["pro", "classic-policies", "get", "\(id)", "-o", "json"]
        case .configProfileDetail(let id):        return ["pro", "classic-macos-config-profiles", "get", "\(id)", "-o", "json"]
        case .computers:                          return ["pro", "computers-inventory", "list", "--all", "--section", "GENERAL", "--section", "HARDWARE", "--section", "OPERATING_SYSTEM", "-o", "json"]
        case .computerDetail(let s):              return ["pro", "computers-inventory", "list", "--filter", CLICommand.serialFilter(s), "--section", "GENERAL", "--section", "HARDWARE", "--section", "OPERATING_SYSTEM", "--section", "STORAGE", "--section", "DISK_ENCRYPTION", "--section", "SECURITY", "--section", "USER_AND_LOCATION", "--section", "PURCHASING", "--section", "GROUP_MEMBERSHIPS", "--section", "LOCAL_USER_ACCOUNTS", "--section", "SOFTWARE_UPDATES", "--section", "CONFIGURATION_PROFILES", "--section", "EXTENSION_ATTRIBUTES", "-o", "json"]
        case .computerDetailById(let id):         return ["pro", "computers-inventory", "get", "-o", "json", "--", id]
        case .installedApps(let s):               return ["pro", "computers-inventory", "list", "--filter", CLICommand.serialFilter(s), "--section", "GENERAL", "--section", "APPLICATIONS", "-o", "json"]
        case .smartGroupDetail(let id):           return ["pro", "smart-computer-groups", "get", "-o", "json", "--", id]

        // DDM Monitor
        case .ddmStatusItems(let managementId): return ["pro", "ddm-status", "status-items", "-o", "json", "--", managementId]
        case .ddmComputers: return ["pro", "computers-inventory", "list", "--all", "--section", "GENERAL", "-o", "json"]

        // Blueprints
        case .blueprints:                          return ["pro", "bp", "list", "-o", "json"]
        case .blueprintDetail(let n):              return ["pro", "bp", "get", "-o", "json", "--", n]
        case .blueprintStatus:                     return ["pro", "report", "blueprint-status", "-o", "json"]

        // Compliance Benchmarks
        case .complianceBenchmarks:                return ["pro", "cb", "list", "-o", "json"]
        case .complianceBenchmarkDetail(let n):    return ["pro", "cb", "get", "-o", "json", "--", n]
        // IDs and titles go after `--` so a value starting with "-" can't be read as a flag.
        case .benchmarkCompliancePercentage(let id):
            return ["pro", "benchmark-reports", "compliance-percentage", "-o", "json", "--", id]
        case .benchmarkRuleStats(let id):
            return ["pro", "benchmark-reports", "rules", "--sort", "failed:desc", "-o", "json", "--", id]
        case .benchmarkRuleDevices(let id, let ruleID):
            return ["pro", "benchmark-reports", "devices", "--rule-id=" + Self.cleanValue(ruleID), "--rule-result", "FAILED",
                    "--sort", "deviceName", "-o", "json", "--", id]
        case .benchmarkFailingDevices(let title):
            return ["pro", "report", "compliance-devices", "-o", "json", "--", title]

        // Jamf Protect — data
        case .protectEvents:        return ["protect", "alerts", "list", "-o", "json"]
        case .protectOverview:      return ["protect", "overview", "-o", "json"]
        case .protectComputers:             return ["protect", "comp", "list", "-o", "json"]
        case .protectComputerDetail(let n): return Self.protectGet("comp", n)
        case .protectPlans:         return ["protect", "plans", "list", "-o", "json"]
        case .protectAlerts:        return ["protect", "analytics", "list", "-o", "json"]
        case .protectInsights:      return ["protect", "analytic-sets", "list", "-o", "json"]
        case .protectAuditLogs:     return ["protect", "audit-logs", "list", "-o", "json"]
        case .protectExceptionSets: return Self.protectList("exception-sets")
        case .protectAnalyticSets:              return ["protect", "analytic-sets", "list", "-o", "json"]
        case .protectExceptionSetDetail(let n): return Self.protectGet("exception-sets", n)

        // Jamf School — data
        case .schoolOverview:       return ["school", "overview", "-o", "json"]
        case .schoolDevices:        return ["school", "dev", "list", "-o", "json"]
        case .schoolDeviceGroups:   return ["school", "dg", "list", "-o", "json"]
        case .schoolUsers:          return ["school", "users", "list", "-o", "json"]
        case .schoolUserGroups:     return ["school", "groups", "list", "-o", "json"]
        case .schoolClasses:        return ["school", "cls", "list", "-o", "json"]
        case .schoolApps:           return ["school", "apps", "list", "-o", "json"]
        case .schoolProfiles:       return ["school", "profiles", "list", "-o", "json"]
        case .schoolDepDevices:     return ["school", "dep-devices", "list", "-o", "json"]

        // Safe actions
        case .blankPush(let s):           return ["pro", "computers", "blank-push", Self.serialFlag(s), "--yes"]
        case .renewMDM(let s):            return ["pro", "computers", "renew-mdm", Self.serialFlag(s), "--yes"]
        case .ddmSync(let s):             return ["pro", "computers", "ddm-sync", Self.serialFlag(s), "--yes"]
        case .flushFailedCommands(let s): return ["pro", "computers", "flush-commands", Self.serialFlag(s), "--yes"]
        case .flushAllCommands(let s):    return ["pro", "computers", "flush-commands", Self.serialFlag(s), "--status", "both", "--yes"]

        // Moderate actions
        case .redeployFramework(let s):    return ["pro", "computers", "redeploy-framework", Self.serialFlag(s), "--yes"]
        case .enableRemoteDesktop(let s):  return ["pro", "computers", "enable-remote-desktop", Self.serialFlag(s), "--yes"]
        case .disableRemoteDesktop(let s): return ["pro", "computers", "disable-remote-desktop", Self.serialFlag(s), "--yes"]
        case .restart(let s):              return ["pro", "computers", "restart", Self.serialFlag(s), "--yes"]
        case .shutdown(let s):             return ["pro", "computers", "shutdown", Self.serialFlag(s), "--yes"]

        // Destructive actions
        case .removeMDM(let s):       return ["pro", "computers", "remove-mdm", Self.serialFlag(s), "--yes"]
        case .clearRecoveryLock(let s): return ["pro", "computers", "set-recovery-lock", Self.serialFlag(s), "--yes"]
        // jamf-cli's `computers lock` has no PIN flag, so the lock is sent as a raw
        // DEVICE_LOCK MDM command (body on stdin, see CLIManager.lockComputer).
        case .lock:                   return ["pro", "mdm-commands", "commands", "-o", "json"]
        case .erase(let s):           return ["pro", "computers", "erase", Self.serialFlag(s), "--yes"]

        // Mobile Devices
        case .mobileDeviceList:                    return ["pro", "md", "list", "--all", "-o", "json"]
        case .mobileDeviceErase(let s):            return ["pro", "md", "erase", Self.serialFlag(s), "--yes"]
        case .mobileDeviceLock(let s):             return ["pro", "md", "lock", Self.serialFlag(s), "--yes", "--confirm-destructive"]
        case .mobileDeviceRestart(let s):          return ["pro", "md", "restart", Self.serialFlag(s), "--yes"]
        case .mobileDeviceShutdown(let s):         return ["pro", "md", "shutdown", Self.serialFlag(s), "--yes"]
        case .mobileDeviceUnmanage(let s):         return ["pro", "md", "unmanage", Self.serialFlag(s), "--yes"]
        case .mobileDeviceEnableLostMode(let s, let message, let phone, let footnote):
            var args = ["pro", "md", "enable-lost-mode", Self.serialFlag(s), "--message=" + Self.cleanValue(message)]
            if !Self.cleanValue(phone).isEmpty { args.append("--phone=" + Self.cleanValue(phone)) }
            if !Self.cleanValue(footnote).isEmpty { args.append("--footnote=" + Self.cleanValue(footnote)) }
            return args + ["--yes"]
        case .mobileDeviceDisableLostMode(let s):  return ["pro", "md", "disable-lost-mode", Self.serialFlag(s), "--yes"]
        case .mobileDeviceUpdateInventory(let s):  return ["pro", "md", "update-inventory", Self.serialFlag(s), "--yes"]

        // Reports
        case .reportPatchStatus:              return ["pro", "report", "patch-status", "-o", "json"]
        case .reportPolicyStatus:             return ["pro", "report", "policy-status", "-o", "json"]
        case .reportProfileStatus:            return ["pro", "report", "profile-status", "-o", "json"]
        case .reportAppStatus:                return ["pro", "report", "app-status", "-o", "json"]
        case .reportUpdateStatus(let f):      return f ? ["pro", "report", "update-status", "--scan-failures", "-o", "json"] : ["pro", "report", "update-status", "-o", "json"]
        case .reportDeviceCompliance:         return ["pro", "report", "device-compliance", "-o", "json"]
        case .reportInventorySummary:         return ["pro", "report", "inventory-summary", "-o", "json"]
        case .reportSoftwareInstalls:         return ["pro", "report", "software-installs", "-o", "json"]
        case .reportDDMStatus:                return ["pro", "report", "ddm-status", "-o", "json"]
        case .proNotifications:               return ["pro", "notifications", "list", "-o", "json"]
        case .proAudit(let cat):              return ["pro", "audit", "--checks=" + Self.cleanValue(cat), "-o", "json"]

        // Bulk Operations
        case .bulkEnablePolicies(let c):          return ["pro", "bulk", "enable-policies", "--category=" + Self.cleanValue(c), "--yes"]
        case .bulkDisablePolicies(let p):         return ["pro", "bulk", "disable-policies", "--name-pattern=" + Self.cleanValue(p), "--yes"]


        // Org Objects
        case .buildings:       return ["pro", "bld", "list", "-o", "json"]
        case .departments:     return ["pro", "dept", "list", "-o", "json"]
        case .networkSegments: return ["pro", "classic-network-segments", "list", "-o", "json"]

        // Extension Attributes
        case .computerExtensionAttributes: return ["pro", "computer-extension-attributes", "list", "-o", "json"]

        // Patch Management
        case .patchTitles:       return ["pro", "classic-patch-titles",  "list", "-o", "json"]
        case .patchPolicies:     return ["pro", "classic-patch-policies", "list", "-o", "json"]
        case .patchSoftwareTitleConfigurations: return ["pro", "patch-software-title-configurations", "list", "-o", "json"]
        case .appInstallerTitles:               return ["pro", "app-installer-titles", "list", "-o", "json"]
        case .appInstallerDeployments:          return ["pro", "app-installer-deployments", "list", "-o", "json"]
        case .restrictedSoftware:               return ["pro", "classic-restricted-software", "list", "-o", "json"]

        // Enrollment
        case .depTokens:             return ["pro", "device-enrollment-instances", "list", "-o", "json"]
        case .computerPrestages:     return ["pro", "computer-prestages", "list", "-o", "json"]
        case .mobileDevicePrestages: return ["pro", "mobile-device-prestages", "list", "-o", "json"]

        // Webhooks
        case .webhooks: return ["pro", "classic-webhooks", "list", "-o", "json"]

        // Self Service & Check-In
        case .selfServiceSettings:   return ["pro", "self-service-settings", "get", "-o", "json"]
        case .clientCheckInSettings: return ["pro", "client-check-in", "get", "-o", "json"]

        // Protect extended
        case .protectRemovableStorage:               return Self.protectList("rscs")
        case .protectUnifiedLogging:                 return Self.protectList("ulf")
        case .protectUnifiedLoggingDetail(let n):    return Self.protectGet("ulf", n)
        case .protectActionConfigs:                  return Self.protectList("ac")
        case .protectTelemetryConfigs:               return Self.protectList("telemetry")
        case .protectCustomPreventLists:             return Self.protectList("cpl")
        case .protectRoles:                          return Self.protectList("roles")
        case .protectUsers:                          return Self.protectList("users")
        case .protectGroups:                         return Self.protectList("groups")
        case .protectAPIClients:                     return Self.protectList("apic")
        case .protectDataForwarding:                 return ["protect", "df", "get", "-o", "json"]
        case .protectDataRetention:                  return ["protect", "dr", "get", "-o", "json"]
        case .protectConfigFreeze:                   return ["protect", "cf", "get", "-o", "json"]
        case .protectDownloadsSummary:               return ["protect", "downloads", "summary", "-o", "json"]
        case .protectAnalyticDetail(let n):          return Self.protectGet("analytics", n)

        // Patch Management detail
        case .patchTitleDetail(let id):          return ["pro", "classic-patch-titles", "get", "-o", "json", "--", id]
        case .patchPolicyDetail(let id):         return ["pro", "classic-patch-policies", "get", "-o", "json", "--", id]
        case .restrictedSoftwareDetail(let id):  return ["pro", "classic-restricted-software", "get", "-o", "json", "--", id]
        case .scriptDetail(let id):      return ["pro", "scripts", "get", "-o", "json", "--", id]
        case .packageDetail(let id):     return ["pro", "classic-packages", "get", "\(id)", "-o", "json"]

        // macOS 27 readiness (appended)
        case .softwareUpdatePlans:               return ["pro", "managed-software-updates-plans", "list", "-o", "json"]
        case .softwareUpdatePlansForComputer(let id):
            let digits = id.filter { $0.isASCII && $0.isNumber }
            return ["pro", "managed-software-updates-plans", "list", "--filter", "device.deviceId==\(digits);device.objectType==COMPUTER", "-o", "json"]
        case .softwareUpdateStatuses:            return ["pro", "managed-software-updates", "update-statuses", "-o", "json"]
        case .computersUpdateReadiness:          return ["pro", "computers-inventory", "list", "--all", "--section", "GENERAL", "--section", "HARDWARE", "--section", "OPERATING_SYSTEM", "--section", "CONFIGURATION_PROFILES", "-o", "json"]

        // Enrollment flow & timeline (appended)
        case .recentEnrollments:
            return ["pro", "computers-inventory", "list", "--all", "--section", "GENERAL", "--section", "HARDWARE", "-o", "json"]
        case .enrollmentInventory(let s):
            return ["pro", "computers-inventory", "list", "--filter", CLICommand.serialFilter(s),
                    "--section", "GENERAL", "--section", "HARDWARE", "--section", "USER_AND_LOCATION",
                    "--section", "GROUP_MEMBERSHIPS", "--section", "CONFIGURATION_PROFILES", "-o", "json"]
        case .mdmCommandsForDevice(let id):
            let uuid = id.filter { $0.isHexDigit || $0 == "-" }
            return ["pro", "mdm", "list", "--filter", "clientManagementId==\(uuid)", "--sort", "dateSent:asc", "-o", "json"]
        case .computerHistory(let s, let subset):
            return ["pro", "classic-computer-history", "get", CLICommand.serialFlag(s),
                    "--subset", subset.rawValue, "-o", "json"]
        case .computerPrestageDetail(let id):
            return ["pro", "computer-prestages", "get", id.filter { $0.isASCII && $0.isNumber }, "-o", "json"]
        case .logFlushingSettings:
            return ["pro", "log-flushing", "list", "-o", "json"]
        }
    }

    var timeout: TimeInterval {
        switch self {
        case .securityReport, .securityInventory, .computers, .erase, .lock(_, _),
             .mobileDeviceList, .mobileDeviceErase, .mobileDeviceLock,
             .bulkEnablePolicies, .bulkDisablePolicies,
             .reportPatchStatus, .reportPolicyStatus, .reportUpdateStatus,
             .reportDeviceCompliance, .reportSoftwareInstalls,
             .ddmStatusItems(_), .ddmComputers, .reportDDMStatus, .blueprintStatus,
             .benchmarkFailingDevices:
            return 120
        case .computersUpdateReadiness, .softwareUpdatePlans, .softwareUpdateStatuses:
            return 120
        case .recentEnrollments, .mdmCommandsForDevice, .computerHistory:
            return 120
        default: return 60
        }
    }

    /// RSQL filter matching one serial number. The value is quoted and `\` / `"` are
    /// escaped so a crafted serial cannot close the string and append clauses.
    static func serialFilter(_ serial: String) -> String {
        let escaped = cleanValue(serial)
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "hardware.serialNumber==\"\(escaped)\""
    }

    /// What a command can do to a device or the Jamf instance.
    var risk: CLIRisk {
        switch self {
        case .blankPush, .renewMDM, .ddmSync, .flushFailedCommands, .flushAllCommands,
             .mobileDeviceUpdateInventory:
            return .safe
        case .redeployFramework, .enableRemoteDesktop, .disableRemoteDesktop, .restart, .shutdown,
             .mobileDeviceRestart, .mobileDeviceShutdown, .mobileDeviceDisableLostMode,
             .bulkEnablePolicies, .bulkDisablePolicies:
            return .moderate
        case .removeMDM, .clearRecoveryLock, .lock, .erase,
             .mobileDeviceErase, .mobileDeviceLock, .mobileDeviceUnmanage, .mobileDeviceEnableLostMode:
            return .destructive
        default:
            return .read
        }
    }

    /// True for commands that permanently alter or destroy device state.
    var isDestructive: Bool { risk == .destructive }
}

/// How much a command changes. Anything other than `.read` sends something to devices
/// or changes Jamf Pro.
enum CLIRisk: Int, Sendable, Comparable {
    case read, safe, moderate, destructive
    static func < (a: CLIRisk, b: CLIRisk) -> Bool { a.rawValue < b.rawValue }
}

// MARK: - Report Output Format
enum ReportOutputFormat: String, CaseIterable, Identifiable {
    case json = "json", table = "table", csv = "csv", yaml = "yaml", plain = "plain"
    var id: String { rawValue }
    var fileExtension: String {
        switch self {
        case .json: return "json"
        case .table: return "txt"
        case .csv: return "csv"
        case .yaml: return "yaml"
        case .plain: return "txt"
        }
    }
    var contentType: UTType {
        switch self {
        case .json: return .json
        case .csv: return .commaSeparatedText
        case .yaml, .plain, .table: return .plainText
        }
    }
}

// MARK: - CLICommand Output Format Helper

extension CLICommand {
    func arguments(outputFormat: ReportOutputFormat) -> [String] {
        guard outputFormat != .json else { return baseArguments }
        var args = baseArguments
        // Flags must stay before a `--` separator; everything after it is positional.
        let end = args.firstIndex(of: "--") ?? args.endIndex
        if let oIdx = args[..<end].lastIndex(of: "-o") {
            args.removeSubrange(oIdx...(oIdx + 1))
        }
        let insertAt = args.firstIndex(of: "--") ?? args.endIndex
        args.insert(contentsOf: ["-o", outputFormat.rawValue], at: insertAt)
        return args
    }
}

// MARK: - CLIRunning Protocol


protocol CLIRunning: Sendable {
    func run(_ command: CLICommand) async throws -> Data
    func run(_ command: CLICommand, outputFormat: ReportOutputFormat) async throws -> Data
}

// MARK: - CLIManager Actor

actor CLIManager: CLIRunning {
    private let downloader: CLIDownloader
    private let profileService: ProfileService
    private let keychain: KeychainService
    private let executor: any CLIExecuting
    private let versionStore: CLIVersionStore
    private let logger = Logger(subsystem: "com.jamfdash", category: "CLIManager")
    private let supportDirectory: URL
    private let binDirectory: URL

    private(set) var installedVersion: CLIVersion?

    init(
        downloader: CLIDownloader,
        profileService: ProfileService,
        keychain: KeychainService,
        executor: any CLIExecuting = CLIManager.defaultExecutor()
    ) {
        self.downloader = downloader
        self.profileService = profileService
        self.keychain = keychain
        // Every launch of jamf-cli goes through the signature check.
        self.executor = VerifyingCLIExecutor(wrapping: executor)
        let supportDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Self.appSupportName, isDirectory: true)
        self.supportDirectory = supportDir
        self.binDirectory = supportDir.appendingPathComponent("bin", isDirectory: true)
        self.versionStore = CLIVersionStore(supportDirectory: supportDir)
    }

    /// Runs jamf-cli in the embedded `JamfDashCLIWorker` XPC service when it is bundled,
    /// otherwise in-process. `defaults write be.devliegere.JamfDash UseInProcessCLI -bool YES`
    /// forces in-process execution for troubleshooting.
    static func defaultExecutor() -> any CLIExecuting {
        if XPCCLIExecutor.isWorkerEmbedded && !UserDefaults.standard.bool(forKey: "UseInProcessCLI") {
            Logger(subsystem: "com.jamfdash", category: "CLIManager").info("Using CLI worker XPC service")
            return XPCCLIExecutor(fallback: CLIExecutor())
        }
        return CLIExecutor()
    }

    // MARK: - Minimum jamf-cli version

    /// Oldest jamf-cli whose setup prompts and gateway handling Jamf Dash supports.
    static let minimumCLIVersion = "1.31.1"

    static func meetsMinimum(_ version: String) -> Bool {
        !CLIVersion(semver: version, architecture: currentArchitecture).isOlderThan(minimumCLIVersion)
    }

    /// True when the installed jamf-cli is at least `minimumCLIVersion`.
    var meetsMinimumVersion: Bool {
        guard let v = installedVersion?.semver else { return false }
        return Self.meetsMinimum(v)
    }

    private func requireMinimumVersion() throws {
        guard let v = installedVersion?.semver else { return }   // unknown: let jamf-cli decide
        guard Self.meetsMinimum(v) else {
            throw CLIError.cliTooOld(installed: v, minimum: Self.minimumCLIVersion)
        }
    }

    /// Updates jamf-cli when it is older than `minimumCLIVersion`. A pin to an older
    /// version is removed, since that version can no longer be used.
    func ensureMinimumVersion() async throws {
        await refreshVersion()
        guard isBinaryInstalled, !meetsMinimumVersion else { return }
        let old = installedVersion?.semver ?? "unknown"
        logger.notice("jamf-cli \(old, privacy: .public) is older than \(Self.minimumCLIVersion, privacy: .public) — updating")
        if let pinned = await versionStore.pinnedVersion, !Self.meetsMinimum(pinned) {
            await versionStore.unpin()
        }
        try await performUpdate()
        try requireMinimumVersion()
    }

    // MARK: - Paths

    static let appSupportName = "JamfDash"

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

        // Migrate a pre-versioning binary into the version store.
        let hasStored = await versionStore.hasStoredVersions
        if isBinaryInstalled && !hasStored {
            await refreshVersion()
            await versionStore.migrateIfNeeded(currentVersion: installedVersion?.semver)
        }

        if !isBinaryInstalled {
            logger.info("jamf-cli not found, downloading")
            let tag = try await downloader.download(to: binaryURL, arch: Self.currentArchitecture)
            try setExecutable(binaryURL)
            try await versionStore.install(version: tag)
        }

        try await ensureMinimumVersion()
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
                environment: Self.minimalEnvironment(),
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
        // Never offer an update when the user has pinned a specific version.
        guard await versionStore.pinnedVersion == nil else { return nil }
        let latest = try await downloader.latestVersion()
        guard let current = installedVersion else { return latest }
        return current.isOlderThan(latest) ? latest : nil
    }

    func performUpdate() async throws {
        let tag = try await downloader.download(to: binaryURL, arch: Self.currentArchitecture)
        try setExecutable(binaryURL)
        try await versionStore.install(version: tag)
        await versionStore.prune(keepLatest: 3)
        await refreshVersion()
        logger.info("jamf-cli updated to \(self.installedVersion?.semver ?? "unknown")")
    }

    // MARK: - Version management

    /// Lists all versions stored locally in the version archive.
    var localVersions: [String] {
        get async { await versionStore.installedVersions }
    }

    /// The version tag that the user has pinned, or nil when tracking latest.
    var pinnedVersion: String? {
        get async { await versionStore.pinnedVersion }
    }

    /// Pins the active binary to a specific locally-installed version.
    func pin(version: String) async throws {
        guard Self.meetsMinimum(version) else {
            throw CLIError.cliTooOld(installed: version, minimum: Self.minimumCLIVersion)
        }
        try await versionStore.pin(version)
        await refreshVersion()
    }

    /// Removes the version pin so the app will track the latest release again.
    func unpin() async {
        await versionStore.unpin()
    }

    /// Activates the previous version and pins to it.
    func rollback() async throws {
        if let target = await versionStore.rollbackVersion, !Self.meetsMinimum(target) {
            throw CLIError.cliTooOld(installed: target, minimum: Self.minimumCLIVersion)
        }
        try await versionStore.rollback()
        await refreshVersion()
    }

    /// Downloads and installs a specific version without making it active.
    func downloadVersion(_ version: String) async throws {
        guard Self.meetsMinimum(version) else {
            throw CLIError.cliTooOld(installed: version, minimum: Self.minimumCLIVersion)
        }
        let tag = try await downloader.download(version: version, to: binaryURL, arch: Self.currentArchitecture)
        try setExecutable(binaryURL)
        try await versionStore.install(version: tag)
        // Re-activate whatever was active before so the downloaded version is archived but not yet live.
        if let pin = await versionStore.pinnedVersion {
            try await versionStore.activate(version: pin)
        } else if let active = installedVersion?.semver {
            try? await versionStore.activate(version: active)
        }
    }

    /// Lists the version tags available on the remote repository.
    func remoteVersions(limit: Int = 10) async throws -> [String] {
        try await downloader.availableVersions(limit: limit)
    }

    // MARK: - Setup

    // Setup commands are interactive: jamf-cli only accepts credentials at a prompt.
    // Everything that has a flag is passed as a flag; the remaining questions are answered
    // by prompt text (see `CLIExecutor.executeScripted`), never by position.

    /// Platform API gateway profile (`config add-profile --auth-method platform`).
    /// The API client must have been created at account.jamf.com beforehand.
    func setupPlatform(
        region: PlatformRegion,
        level: PlatformScopeLevel,
        scopeID: String,
        profileName: String,
        clientID: String,
        clientSecret: String
    ) async throws -> String {
        let output = try await runSetup(
            ["config", "add-profile", profileName,
             "--url", region.gatewayURL,
             "--auth-method", "platform",
             level.flag, scopeID],
            rules: Self.clientCredentialRules(clientID: clientID, clientSecret: clientSecret)
        )
        profileService.selectedProfile = JamfProfile(name: profileName)
        return output
    }

    /// Jamf Pro profile for an existing API client (`config add-profile --auth-method oauth2`).
    func setupOAuth(
        serverURL: String,
        profileName: String,
        clientID: String,
        clientSecret: String
    ) async throws -> String {
        let output = try await runSetup(
            ["config", "add-profile", profileName, "--url", serverURL, "--auth-method", "oauth2"],
            rules: Self.clientCredentialRules(clientID: clientID, clientSecret: clientSecret)
        )
        profileService.selectedProfile = JamfProfile(name: profileName)
        return output
    }

    /// Jamf Protect profile (`protect setup`).
    func setupProtect(
        serverURL: String,
        profileName: String,
        clientID: String,
        clientSecret: String
    ) async throws -> String {
        let output = try await preservingDefaultProfile {
            try await runSetup(
                ["protect", "setup", "--url", serverURL, "--profile-name", profileName],
                rules: Self.clientCredentialRules(clientID: clientID, clientSecret: clientSecret)
            )
        }
        profileService.selectedProfile = JamfProfile(name: profileName)
        return output
    }

    /// Jamf School profile (`school setup`). Network ID from Devices → Enroll Device(s),
    /// API key from Organisation → Settings → API.
    func setupSchool(
        serverURL: String,
        profileName: String,
        networkID: String,
        apiKey: String
    ) async throws -> String {
        let output = try await preservingDefaultProfile {
            try await runSetup(
                ["school", "setup", "--url", serverURL, "--profile-name", profileName],
                rules: [
                    PromptRule("Network ID:", answer: networkID),
                    PromptRule("API Key:", answer: apiKey, isSecret: true),
                    // Optional Platform API access for School blueprints — not set up here.
                    PromptRule("Configure Platform API access", answer: "n"),
                ]
            )
        }
        profileService.selectedProfile = JamfProfile(name: profileName)
        return output
    }

    /// Jamf Pro local account: jamf-cli signs in, creates an API role and client with
    /// `scope`, and saves the client — the username and password are not stored.
    func setup(
        serverURL: String,
        username: String,
        password: String,
        scope: Int,
        profileName: String
    ) async throws -> String {
        let scopeName: String
        switch scope {
        case 1:  scopeName = "read-only"
        case 3:  scopeName = "full-admin"
        default: scopeName = "standard"
        }
        return try await runSetup(
            ["pro", "setup",
             "--url", serverURL,
             "--credentials", "create",
             "--scope", scopeName,
             "--profile-name", profileName],
            rules: [
                PromptRule("Username:", answer: username),
                PromptRule("Password:", answer: password, isSecret: true),
                // Global MCP report folder: leave whatever the user has configured.
                PromptRule("HTML report directory", answer: ""),
            ]
        )
    }

    private static func clientCredentialRules(clientID: String, clientSecret: String) -> [PromptRule] {
        [
            PromptRule("Client ID:", answer: clientID),
            PromptRule("Client Secret:", answer: clientSecret, isSecret: true),
        ]
    }

    private func runSetup(_ arguments: [String], rules: [PromptRule]) async throws -> String {
        guard isBinaryInstalled else { throw CLIError.binaryMissing }
        try requireMinimumVersion()
        let data = try await executor.executeScripted(
            binary: binaryURL,
            arguments: arguments,
            environment: Self.minimalEnvironment(),
            rules: rules,
            timeout: 90
        )
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// `protect setup` and `school setup` make the new profile jamf-cli's default. Jamf Dash
    /// always passes `--profile`, so put the user's previous default back afterwards.
    private func preservingDefaultProfile<T>(_ body: () async throws -> T) async throws -> T {
        let config = JamfCLIConfigFile(url: JamfCLIConfigFile.standardURL)
        let previous = try? config.defaultProfile()
        let result = try await body()
        if let previous {
            do { try config.setDefaultProfile(previous) }
            catch { logger.error("Could not restore jamf-cli default profile: \(error.localizedDescription, privacy: .public)") }
        }
        return result
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
            environment: Self.minimalEnvironment(),
            timeout: command.timeout
        )
    }

    // MARK: - Execution

    func run(_ command: CLICommand) async throws -> Data {
        guard isBinaryInstalled else { throw CLIError.binaryMissing }
        if case .lock(let serial, let pin) = command {
            return try await lockComputer(serial: serial, pin: pin)
        }
        return try await runJamfCLI(command.baseArguments, timeout: command.timeout)
    }

    func run(_ command: CLICommand, outputFormat: ReportOutputFormat) async throws -> Data {
        guard isBinaryInstalled else { throw CLIError.binaryMissing }
        return try await runJamfCLI(command.arguments(outputFormat: outputFormat), timeout: command.timeout)
    }

    /// Runs jamf-cli with the selected profile. If the profile still points at the retired
    /// Platform gateway, its URL is updated to the one jamf-cli names and the call is retried once.
    private func runJamfCLI(
        _ commandArgs: [String],
        timeout: TimeInterval,
        allowGatewayFix: Bool = true,
        allowTokenRefresh: Bool = true
    ) async throws -> Data {
        let profile = profileService.selectedProfile
        let args = profile.isDefault ? commandArgs : ["--profile", profile.name] + commandArgs
        logger.debug("Running: jamf-cli \(args.joined(separator: " "), privacy: .private)")
        do {
            let start = Date()
            let data = try await executor.execute(
                binary: binaryURL,
                arguments: args,
                environment: Self.minimalEnvironment(),
                timeout: timeout
            )
            let elapsed = String(format: "%.2f", Date().timeIntervalSince(start))
            logger.debug("jamf-cli finished in \(elapsed, privacy: .public)s — \(data.count, privacy: .public) bytes")
            return data
        } catch CLIError.nonZeroExit(let code, let message)
            where allowGatewayFix && JamfCLIConfigFile.retiredGatewayReplacement(in: message) != nil {
            let newURL = JamfCLIConfigFile.retiredGatewayReplacement(in: message)!
            guard (try? migrateRetiredGateway(profile: profile, to: newURL)) == true else {
                throw CLIError.nonZeroExit(code: code, stderr: message)
            }
            return try await runJamfCLI(commandArgs, timeout: timeout, allowGatewayFix: false,
                                        allowTokenRefresh: allowTokenRefresh)
        } catch CLIError.nonZeroExit(let code, let message)
            where allowTokenRefresh && JamfCLIErrorPayload(output: message)?.isPermissionDenied == true {
            // jamf-cli caches Platform gateway tokens, and a token keeps the permissions it was
            // issued with. After permissions are granted in Jamf Account, get a fresh token once.
            guard await refreshPlatformToken(profile: profile) else {
                throw CLIError.nonZeroExit(code: code, stderr: message)
            }
            return try await runJamfCLI(commandArgs, timeout: timeout, allowGatewayFix: false,
                                        allowTokenRefresh: false)
        } catch {
            logger.error("jamf-cli failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Forces a new Platform gateway token exchange. Returns false for non-platform profiles
    /// (jamf-cli refuses the command) or when the exchange fails. The token is discarded.
    private func refreshPlatformToken(profile: JamfProfile) async -> Bool {
        let args = (profile.isDefault ? [] : ["--profile", profile.name]) + ["platform", "auth", "token", "--refresh"]
        do {
            _ = try await executor.execute(binary: binaryURL, arguments: args,
                                           environment: Self.minimalEnvironment(), timeout: 30)
            logger.notice("Refreshed the Platform token after a permission error; retrying once")
            return true
        } catch {
            return false
        }
    }

    /// Points a profile at the current Platform API gateway (`https://<region>.api.jamfcloud.com`),
    /// as jamf-cli instructs for profiles created against the retired `*.apigw.jamf.com`.
    /// Returns true when the config file was changed (or another call already changed it).
    private func migrateRetiredGateway(profile: JamfProfile, to newURL: String) throws -> Bool {
        let config = JamfCLIConfigFile(url: JamfCLIConfigFile.standardURL)
        let name = profile.isDefault ? try config.defaultProfile() : profile.name
        guard !name.isEmpty else { return false }
        let current = try config.profileURL(name)
        if current == newURL { return true }        // a concurrent call already migrated it
        guard let current, current.contains("apigw.jamf.com") else { return false }
        try config.setURL(newURL, forProfile: name)
        profileService.setServerURL(newURL, for: name)
        logger.notice("Updated profile \(name, privacy: .private) from the retired gateway \(current, privacy: .public) to \(newURL, privacy: .public)")
        return true
    }

    /// Locks a Mac with the user's PIN. Resolves the device's management ID from its
    /// serial, then queues a DEVICE_LOCK command with the PIN in the request body.
    private func lockComputer(serial: String, pin: String) async throws -> Data {
        guard pin.count == 6, pin.allSatisfy(\.isASCII), pin.allSatisfy(\.isNumber) else {
            throw CLIError.nonZeroExit(code: -1, stderr: "The lock PIN must be exactly 6 digits.")
        }
        let profile = profileService.selectedProfile
        let profileArgs = profile.isDefault ? [] : ["--profile", profile.name]

        let lookup = try await executor.execute(
            binary: binaryURL,
            arguments: profileArgs + [
                "pro", "computers-inventory", "list",
                "--filter", CLICommand.serialFilter(serial),
                "--section", "GENERAL", "-o", "json"
            ],
            environment: Self.minimalEnvironment(),
            timeout: 60
        )
        guard let managementId = Self.managementId(in: lookup) else {
            throw CLIError.nonZeroExit(code: -1, stderr: "No computer with serial \(serial) was found, or it has no management ID.")
        }

        let body: [String: Any] = [
            "clientData": [["managementId": managementId]],
            "commandData": ["commandType": "DEVICE_LOCK", "pin": pin]
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        logger.debug("Sending DEVICE_LOCK for \(serial, privacy: .private)")
        return try await executor.execute(
            binary: binaryURL,
            arguments: profileArgs + CLICommand.lock(serial: serial, pin: pin).baseArguments,
            environment: Self.minimalEnvironment(),
            stdinData: bodyData,
            timeout: CLICommand.lock(serial: serial, pin: pin).timeout
        )
    }

    /// Extracts `general.managementId` from a `computers-inventory list` response,
    /// which is either a bare array or wrapped in `results`.
    static func managementId(in data: Data) -> String? {
        let json = try? JSONSerialization.jsonObject(with: data)
        let rows = (json as? [[String: Any]])
            ?? ((json as? [String: Any])?["results"] as? [[String: Any]])
            ?? []
        guard rows.count == 1,
              let general = rows[0]["general"] as? [String: Any],
              let id = general["managementId"] as? String, !id.isEmpty
        else { return nil }
        return id
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
            environment: Self.minimalEnvironment(),
            timeout: 10
        )
    }

    // MARK: - Private helpers

    /// Returns a minimal environment containing only the keys the jamf-cli Go binary
    /// needs to run. Stripping the full process environment prevents accidental
    /// credential or secret leakage into child processes via inherited variables.
    private static func minimalEnvironment() -> [String: String] {
        let env = ProcessInfo.processInfo.environment
        let keepKeys: Set<String> = [
            "HOME", "PATH", "TMPDIR", "USER", "LOGNAME",
            "TERM", "LANG", "LC_ALL", "LC_CTYPE",
            "XPC_SERVICE_NAME", "__CF_USER_TEXT_ENCODING"
        ]
        var result = keepKeys.reduce(into: [String: String]()) { dict, key in
            if let val = env[key] { dict[key] = val }
        }
        // Jamf Dash manages jamf-cli updates itself.
        result["JAMF_CLI_NO_UPDATE_CHECK"] = "1"
        return result
    }

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

extension CLIRunning {
    func run(_ command: CLICommand, outputFormat: ReportOutputFormat) async throws -> Data {
        // Default implementation: ignore format, return same as JSON
        return try await run(command)
    }
}
