import XCTest
@testable import JamfDash

/// Runs `jamf-cli <command path> --help` for every command Jamf Dash can send and checks
/// that the command exists and knows every flag passed to it. Needs the jamf-cli that
/// Jamf Dash installs; skipped when it isn't there. Help output is offline.
final class CLIHelpContractTests: XCTestCase {

    /// One example of every command. `coverage(_:)` has no `default`, so adding a
    /// command without adding it here fails to compile.
    static let samples: [CLICommand] = [
        .overview,
        .securityReport,
        .securityInventory,
        .policies,
        .smartComputerGroups,
        .categories,
        .scripts,
        .packages,
        .configProfiles,
        .policyDetail(id: 1),
        .configProfileDetail(id: 1),
        .computers,
        .computerDetail(serial: "X1"),
        .computerDetailById(id: "X1"),
        .installedApps(serial: "X1"),
        .deviceIdentity(serial: "X1"),
        .smartGroupDetail(id: "X1"),
        .ddmStatusItems(managementId: "X1"),
        .ddmComputers,
        .reportDDMStatus,
        .proNotifications,
        .blueprints,
        .blueprintDetail(name: "X1"),
        .blueprintStatus,
        .complianceBenchmarks,
        .complianceBenchmarkDetail(name: "X1"),
        .benchmarkCompliancePercentage(id: "X1"),
        .benchmarkRuleStats(id: "X1"),
        .benchmarkRuleDevices(id: "X1", ruleID: "X1"),
        .benchmarkFailingDevices(title: "X1"),
        .protectOverview,
        .protectEvents,
        .protectComputers,
        .protectComputerDetail(name: "X1"),
        .protectPlans,
        .protectAlerts,
        .protectInsights,
        .protectAuditLogs,
        .protectExceptionSets,
        .protectAnalyticSets,
        .protectExceptionSetDetail(name: "X1"),
        .schoolOverview,
        .schoolDevices,
        .schoolDeviceGroups,
        .schoolUsers,
        .schoolUserGroups,
        .schoolClasses,
        .schoolApps,
        .schoolProfiles,
        .schoolDepDevices,
        .blankPush(serial: "X1"),
        .renewMDM(serial: "X1"),
        .ddmSync(serial: "X1"),
        .flushFailedCommands(serial: "X1"),
        .flushAllCommands(serial: "X1"),
        .redeployFramework(serial: "X1"),
        .enableRemoteDesktop(serial: "X1"),
        .disableRemoteDesktop(serial: "X1"),
        .restart(serial: "X1"),
        .shutdown(serial: "X1"),
        .removeMDM(serial: "X1"),
        .clearRecoveryLock(serial: "X1"),
        .lock(serial: "X1", pin: "X1"),
        .erase(serial: "X1"),
        .mobileDeviceList,
        .mobileDeviceErase(serial: "X1"),
        .mobileDeviceLock(serial: "X1"),
        .mobileDeviceRestart(serial: "X1"),
        .mobileDeviceShutdown(serial: "X1"),
        .mobileDeviceUnmanage(serial: "X1"),
        .mobileDeviceEnableLostMode(serial: "X1", message: "X1", phone: "X1", footnote: "X1"),
        .mobileDeviceDisableLostMode(serial: "X1"),
        .mobileDeviceUpdateInventory(serial: "X1"),
        .reportPatchStatus,
        .reportPolicyStatus,
        .reportProfileStatus,
        .reportAppStatus,
        .reportUpdateStatus(includeFailures: true),
        .reportDeviceCompliance,
        .reportInventorySummary,
        .reportSoftwareInstalls,
        .proAudit(category: "X1"),
        .bulkEnablePolicies(category: "X1"),
        .bulkDisablePolicies(pattern: "X1"),
        .buildings,
        .departments,
        .networkSegments,
        .computerExtensionAttributes,
        .patchTitles,
        .patchPolicies,
        .patchSoftwareTitleConfigurations,
        .appInstallerTitles,
        .appInstallerDeployments,
        .restrictedSoftware,
        .restrictedSoftwareDetail(id: "X1"),
        .depTokens,
        .computerPrestages,
        .mobileDevicePrestages,
        .webhooks,
        .selfServiceSettings,
        .clientCheckInSettings,
        .protectRemovableStorage,
        .protectUnifiedLogging,
        .protectUnifiedLoggingDetail(name: "X1"),
        .protectActionConfigs,
        .protectTelemetryConfigs,
        .protectCustomPreventLists,
        .protectRoles,
        .protectUsers,
        .protectGroups,
        .protectAPIClients,
        .protectDataForwarding,
        .protectDataRetention,
        .protectConfigFreeze,
        .protectDownloadsSummary,
        .protectAnalyticDetail(name: "X1"),
        .patchTitleDetail(id: "X1"),
        .patchPolicyDetail(id: "X1"),
        .scriptDetail(id: "X1"),
        .packageDetail(id: 1),
        .softwareUpdatePlans,
        .softwareUpdatePlansForComputer(computerId: "X1"),
        .softwareUpdateStatuses,
        .computersUpdateReadiness,
        .recentEnrollments,
        .enrollmentInventory(serial: "X1"),
        .mdmCommandsForDevice(managementId: "X1"),
        .computerHistory(serial: "X1", subset: .commands),
        .computerPrestageDetail(id: "X1"),
        .logFlushingSettings,
    ]

    private static func coverage(_ command: CLICommand) {
        switch command {
        case .overview,
             .securityReport,
             .securityInventory,
             .policies,
             .smartComputerGroups,
             .categories,
             .scripts,
             .packages,
             .configProfiles,
             .policyDetail,
             .configProfileDetail,
             .computers,
             .computerDetail,
             .computerDetailById,
             .installedApps,
             .deviceIdentity,
             .smartGroupDetail,
             .ddmStatusItems,
             .ddmComputers,
             .reportDDMStatus,
             .proNotifications,
             .blueprints,
             .blueprintDetail,
             .blueprintStatus,
             .complianceBenchmarks,
             .complianceBenchmarkDetail,
             .benchmarkCompliancePercentage,
             .benchmarkRuleStats,
             .benchmarkRuleDevices,
             .benchmarkFailingDevices,
             .protectOverview,
             .protectEvents,
             .protectComputers,
             .protectComputerDetail,
             .protectPlans,
             .protectAlerts,
             .protectInsights,
             .protectAuditLogs,
             .protectExceptionSets,
             .protectAnalyticSets,
             .protectExceptionSetDetail,
             .schoolOverview,
             .schoolDevices,
             .schoolDeviceGroups,
             .schoolUsers,
             .schoolUserGroups,
             .schoolClasses,
             .schoolApps,
             .schoolProfiles,
             .schoolDepDevices,
             .blankPush,
             .renewMDM,
             .ddmSync,
             .flushFailedCommands,
             .flushAllCommands,
             .redeployFramework,
             .enableRemoteDesktop,
             .disableRemoteDesktop,
             .restart,
             .shutdown,
             .removeMDM,
             .clearRecoveryLock,
             .lock,
             .erase,
             .mobileDeviceList,
             .mobileDeviceErase,
             .mobileDeviceLock,
             .mobileDeviceRestart,
             .mobileDeviceShutdown,
             .mobileDeviceUnmanage,
             .mobileDeviceEnableLostMode,
             .mobileDeviceDisableLostMode,
             .mobileDeviceUpdateInventory,
             .reportPatchStatus,
             .reportPolicyStatus,
             .reportProfileStatus,
             .reportAppStatus,
             .reportUpdateStatus,
             .reportDeviceCompliance,
             .reportInventorySummary,
             .reportSoftwareInstalls,
             .proAudit,
             .bulkEnablePolicies,
             .bulkDisablePolicies,
             .buildings,
             .departments,
             .networkSegments,
             .computerExtensionAttributes,
             .patchTitles,
             .patchPolicies,
             .patchSoftwareTitleConfigurations,
             .appInstallerTitles,
             .appInstallerDeployments,
             .restrictedSoftware,
             .restrictedSoftwareDetail,
             .depTokens,
             .computerPrestages,
             .mobileDevicePrestages,
             .webhooks,
             .selfServiceSettings,
             .clientCheckInSettings,
             .protectRemovableStorage,
             .protectUnifiedLogging,
             .protectUnifiedLoggingDetail,
             .protectActionConfigs,
             .protectTelemetryConfigs,
             .protectCustomPreventLists,
             .protectRoles,
             .protectUsers,
             .protectGroups,
             .protectAPIClients,
             .protectDataForwarding,
             .protectDataRetention,
             .protectConfigFreeze,
             .protectDownloadsSummary,
             .protectAnalyticDetail,
             .patchTitleDetail,
             .patchPolicyDetail,
             .scriptDetail,
             .packageDetail,
             .softwareUpdatePlans,
             .softwareUpdatePlansForComputer,
             .softwareUpdateStatuses,
             .computersUpdateReadiness,
             .recentEnrollments,
             .enrollmentInventory,
             .mdmCommandsForDevice,
             .computerHistory,
             .computerPrestageDetail,
             .logFlushingSettings:
            break
        }
    }

    private var binary: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/JamfDash/bin/jamf-cli")
    }

    func testEveryCommandAndFlagExists() throws {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: binary.path),
                          "jamf-cli isn't installed at \(binary.path)")
        var helpCache: [String: String] = [:]
        for command in Self.samples {
            Self.coverage(command)
            let args = command.baseArguments
            let end = args.firstIndex(of: "--") ?? args.endIndex
            let path = Array(args[..<end].prefix { !$0.hasPrefix("-") })
            let key = path.joined(separator: " ")
            let help: String
            if let cached = helpCache[key] {
                help = cached
            } else {
                let (status, output) = try run(path + ["--help"])
                XCTAssertEqual(status, 0, "`jamf-cli \(key)` doesn't exist: \(output.prefix(200))")
                // An unknown subcommand prints its parent's help, whose usage line is shorter.
                // Aliases (bld → buildings) print the full name, so compare the word count.
                XCTAssertEqual(Self.usageDepth(output), path.count, "`jamf-cli \(key)` isn't a command")
                help = output
                helpCache[key] = output
            }
            for flag in args[..<end] where flag.hasPrefix("-") {
                let name = String(flag.split(separator: "=", maxSplits: 1)[0])
                XCTAssertTrue(help.contains(name + " ") || help.contains(name + "\n") || help.contains(name + ","),
                              "`jamf-cli \(key)` has no \(name) flag")
            }
        }
    }

    /// Number of command words in the first usage line, e.g. 3 for
    /// "jamf-cli pro buildings list [flags]".
    static func usageDepth(_ help: String) -> Int {
        let lines = help.components(separatedBy: "\n")
        guard let i = lines.firstIndex(where: { $0.hasPrefix("Usage:") }), i + 1 < lines.count else { return -1 }
        let words = lines[i + 1].split(separator: " ").map(String.init)
        return words.dropFirst().prefix { !$0.hasPrefix("[") && !$0.hasPrefix("<") && !$0.hasPrefix("-") }.count
    }

    private func run(_ args: [String]) throws -> (Int32, String) {
        let process = Process()
        process.executableURL = binary
        process.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["JAMF_CLI_NO_UPDATE_CHECK"] = "1"
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
