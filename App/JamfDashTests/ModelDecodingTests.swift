import XCTest
@testable import JamfDash

final class ModelDecodingTests: XCTestCase {

    // MARK: - Overview

    func testDecodeOverviewJSON() throws {
        let data = try XCTUnwrap(Fixtures.overview.data(using: .utf8))
        let items = try JSONDecoder().decode([OverviewItem].self, from: data)
        XCTAssertFalse(items.isEmpty)
        XCTAssertTrue(items.contains(where: { $0.resource == "Health Status" }))
        XCTAssertTrue(items.contains(where: { $0.resource == "Managed Computers" }))
    }

    func testOverviewSectionGrouping() throws {
        let data = try XCTUnwrap(Fixtures.overview.data(using: .utf8))
        let items = try JSONDecoder().decode([OverviewItem].self, from: data)
        let sections = Set(items.map(\.section))
        XCTAssertTrue(sections.contains("Fleet"))
        XCTAssertTrue(sections.contains("Configuration"))
        XCTAssertTrue(sections.contains("Health & Alerts"))
    }

    func testOverviewIDs() throws {
        let data = try XCTUnwrap(Fixtures.overview.data(using: .utf8))
        let items = try JSONDecoder().decode([OverviewItem].self, from: data)
        let ids = items.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "All OverviewItem IDs should be unique")
    }

    // MARK: - Security

    func testDecodeSecurityJSON() throws {
        let data = try XCTUnwrap(Fixtures.security.data(using: .utf8))
        let envelopes = try JSONDecoder().decode([SecurityEnvelope].self, from: data)
        let report = SecurityReport(from: envelopes)
        XCTAssertNotNil(report.summary)
        XCTAssertFalse(report.osVersions.isEmpty)
        XCTAssertFalse(report.devices.isEmpty)
    }

    func testSecuritySummaryFields() throws {
        let data = try XCTUnwrap(Fixtures.security.data(using: .utf8))
        let envelopes = try JSONDecoder().decode([SecurityEnvelope].self, from: data)
        let report = SecurityReport(from: envelopes)
        let summary = try XCTUnwrap(report.summary)
        XCTAssertGreaterThan(summary.totalDevices, 0)
        XCTAssertLessThanOrEqual(summary.filevaultEncrypted, summary.totalDevices)
        XCTAssertLessThanOrEqual(summary.gatekeeperEnabled, summary.totalDevices)
        XCTAssertLessThanOrEqual(summary.sipEnabled, summary.totalDevices)
        XCTAssertLessThanOrEqual(summary.firewallEnabled, summary.totalDevices)
    }

    func testOSVersionRows() throws {
        let data = try XCTUnwrap(Fixtures.security.data(using: .utf8))
        let envelopes = try JSONDecoder().decode([SecurityEnvelope].self, from: data)
        let report = SecurityReport(from: envelopes)
        XCTAssertTrue(report.osVersions.allSatisfy { !$0.osVersion.isEmpty })
        XCTAssertTrue(report.osVersions.allSatisfy { $0.count > 0 })
    }

    func testDeviceSecurityFields() throws {
        let data = try XCTUnwrap(Fixtures.security.data(using: .utf8))
        let envelopes = try JSONDecoder().decode([SecurityEnvelope].self, from: data)
        let report = SecurityReport(from: envelopes)
        for device in report.devices {
            XCTAssertFalse(device.name.isEmpty)
            XCTAssertFalse(device.serial.isEmpty)
            XCTAssertFalse(device.osVersion.isEmpty)
        }
    }

    func testDeviceSecurityHelpers() throws {
        let data = try XCTUnwrap(Fixtures.security.data(using: .utf8))
        let envelopes = try JSONDecoder().decode([SecurityEnvelope].self, from: data)
        let report = SecurityReport(from: envelopes)
        // First demo device has filevault NOT_ENCRYPTED
        let first = try XCTUnwrap(report.devices.first)
        XCTAssertFalse(first.isFilevaultEncrypted)
    }

    // MARK: - Policies

    func testDecodePoliciesJSON() throws {
        let data = try XCTUnwrap(Fixtures.policies.data(using: .utf8))
        let policies = try JSONDecoder().decode([Policy].self, from: data)
        XCTAssertFalse(policies.isEmpty)
        XCTAssertTrue(policies.allSatisfy { $0.id > 0 && !$0.name.isEmpty })
    }

    func testPolicyCategoryDecoding() throws {
        let data = try XCTUnwrap(Fixtures.policies.data(using: .utf8))
        let policies = try JSONDecoder().decode([Policy].self, from: data)
        let withCategory = policies.filter { $0.category != nil }
        XCTAssertFalse(withCategory.isEmpty, "At least some policies should have a category")
    }

    // MARK: - CLIVersion

    func testCLIVersionOlderThan() {
        let v1 = CLIVersion(semver: "1.2.0", architecture: .arm64)
        XCTAssertTrue(v1.isOlderThan("1.3.0"))
        XCTAssertFalse(v1.isOlderThan("1.2.0"))
        XCTAssertFalse(v1.isOlderThan("1.1.0"))
    }

    func testCLIVersionArchitecture() {
        let arm = CLIVersion(semver: "1.0.0", architecture: .arm64)
        XCTAssertEqual(arm.architecture.rawValue, "arm64")
        let intel = CLIVersion(semver: "1.0.0", architecture: .x86_64)
        XCTAssertEqual(intel.architecture.rawValue, "x86_64")
    }
}

// MARK: - Inline fixtures (mirrors demo/ JSON files)

private enum Fixtures {
    static let overview = """
    [
      {"section": "Health & Alerts", "resource": "Health Status",      "value": "online",  "status": ""},
      {"section": "Health & Alerts", "resource": "Active Alerts",      "value": "None",    "status": ""},
      {"section": "Instance",        "resource": "Server URL",         "value": "https://demo.jamfcloud.com", "status": ""},
      {"section": "Instance",        "resource": "Jamf Pro Version",   "value": "11.26.0", "status": ""},
      {"section": "Fleet",           "resource": "Managed Computers",  "value": "1,247",   "status": ""},
      {"section": "Fleet",           "resource": "Unmanaged Computers","value": "9",       "status": ""},
      {"section": "Fleet",           "resource": "Managed Devices",    "value": "532",     "status": ""},
      {"section": "Configuration",   "resource": "Policies",           "value": "298",     "status": ""},
      {"section": "Configuration",   "resource": "macOS Config Profiles","value": "174",   "status": ""}
    ]
    """

    static let security = """
    [
      {
        "section": "summary",
        "data": {
          "total_devices": 1247,
          "filevault_encrypted": 1228,
          "filevault_encrypted_pct": "98.5%",
          "gatekeeper_enabled": 1247,
          "gatekeeper_enabled_pct": "100.0%",
          "sip_enabled": 1241,
          "sip_enabled_pct": "99.5%",
          "firewall_enabled": 1209,
          "firewall_enabled_pct": "97.0%"
        }
      },
      {"section": "os_version", "os_version": "15.4.1", "count": 412, "pct": "33.0%"},
      {"section": "os_version", "os_version": "14.7.5", "count": 176, "pct": "14.1%"},
      {"section": "device", "name": "Demo-MacBook-001", "serial": "C02X1AABCDEF", "os_version": "14.6.1", "filevault": "NOT_ENCRYPTED", "gatekeeper": "APP_STORE_AND_IDENTIFIED_DEVELOPERS", "sip": "ENABLED",  "firewall": false},
      {"section": "device", "name": "Demo-MacBook-002", "serial": "C02X2AABCDEF", "os_version": "13.6.0", "filevault": "ENCRYPTED",    "gatekeeper": "DISABLED",                              "sip": "ENABLED",  "firewall": true}
    ]
    """

    static let policies = """
    [
      {"id": 1,  "name": "CORP - Enable FileVault",   "category": {"id": 5, "name": "Security"}},
      {"id": 2,  "name": "CORP - Enable Firewall",    "category": {"id": 5, "name": "Security"}},
      {"id": 7,  "name": "CORP - Google Chrome",      "category": {"id": 8, "name": "Software"}},
      {"id": 15, "name": "CORP - SwiftDialog Install","category": {"id": 1, "name": "Deployment Tools"}}
    ]
    """
}

// MARK: - Platform reports (shapes from jamf-cli 1.31.1 output)

final class PlatformReportDecodingTests: XCTestCase {

    func testBlueprintStatusDecodesDeployedAndUndeployedRows() {
        let json = Data("""
            [
              {"failed": 1, "name": "ALL - Siri", "pending": 10, "scope": 1, "state": "DEPLOYED", "steps": 1, "succeeded": 4},
              {"name": "ALL - Passcode", "scope": 1, "state": "OUT_OF_DATE", "steps": 1},
              {"name": "SD Card", "scope": 0, "state": "NOT_DEPLOYED", "steps": 1}
            ]
            """.utf8)
        let statuses = BlueprintStatus.byName(json)
        XCTAssertEqual(statuses.count, 3)
        let siri = statuses["ALL - Siri"]
        XCTAssertEqual(siri?.succeeded, 4)
        XCTAssertEqual(siri?.failed, 1)
        XCTAssertEqual(siri?.pending, 10)
        XCTAssertEqual(siri?.total, 15)
        XCTAssertEqual(siri?.hasCounts, true)
        XCTAssertEqual(statuses["ALL - Passcode"]?.hasCounts, false)
        XCTAssertEqual(statuses["SD Card"]?.state, "NOT_DEPLOYED")
    }

    func testBlueprintStatusIgnoresNonArrayOutput() {
        XCTAssertTrue(BlueprintStatus.byName(Data("No data".utf8)).isEmpty)
    }

    func testAppInstallerDeploymentDecodesIconGroupAndStatuses() throws {
        let json = Data("""
            [{
              "id": "2", "name": "Microsoft Teams (work or school)", "enabled": true,
              "deploymentType": "SELF_SERVICE", "updateBehavior": "AUTOMATIC",
              "site": {"id": "-1", "name": null},
              "smartGroup": {"id": "78", "name": "ALL - All Managed Clients"},
              "category": {"id": "2", "name": "Software"},
              "computerStatuses": {"installed": 3, "available": 9, "inProgress": 3, "failed": 0, "unqualified": 0},
              "app": {"id": "5E3", "latestVersion": "26246.1709.5146.8945", "selectedVersion": "",
                      "bundleId": "com.microsoft.teams2", "deployedVersion": "26246.1709.5146.8945",
                      "iconUrl": "https://appinstallers-packages.services.jamfcloud.com/icons/5E3.png"}
            }]
            """.utf8)
        let d = try XCTUnwrap(try JSONDecoder().decode([AppInstallerDeployment].self, from: json).first)
        XCTAssertEqual(d.iconURL?.absoluteString, "https://appinstallers-packages.services.jamfcloud.com/icons/5E3.png")
        XCTAssertEqual(d.smartGroupName, "ALL - All Managed Clients")
        XCTAssertEqual(d.inProgressCount, 3)
        XCTAssertEqual(d.installedCount, 3)
        XCTAssertEqual(d.displayVersion, "26246.1709.5146.8945")
    }

    func testIconURLMustBeHTTPSOnJamfCloud() {
        XCTAssertNotNil(AppInstallerDeployment.trustedIconURL("https://appinstallers-packages.services.jamfcloud.com/icons/0BC.png"))
        XCTAssertNil(AppInstallerDeployment.trustedIconURL("http://appinstallers-packages.services.jamfcloud.com/icons/0BC.png"))
        XCTAssertNil(AppInstallerDeployment.trustedIconURL("https://evil.example.com/icon.png"))
        XCTAssertNil(AppInstallerDeployment.trustedIconURL("https://jamfcloud.com.evil.example/icon.png"))
        XCTAssertNil(AppInstallerDeployment.trustedIconURL("file:///etc/passwd"))
    }
}

final class BenchmarkReportTests: XCTestCase {

    func testRuleStatsDecode() throws {
        let json = Data("""
            [{"ruleId": "os_world_writable_library_folder_configure",
              "ruleTitle": "Ensure No World Writable Files Exist in the Library Folder",
              "ruleNumber": "5.1.7", "discussion": "Folders _MUST_ not be world-writable.\\n",
              "passed": 0, "failed": 2, "unknown": 11, "passPercentage": 0.0, "numberOfDevices": 13},
             {"ruleId": "system_settings_media_sharing_disabled", "ruleTitle": "Disable Media Sharing",
              "ruleNumber": "2.3.3.9", "passed": 1, "failed": 1, "unknown": 11, "passPercentage": 7.7, "numberOfDevices": 13}]
            """.utf8)
        let rules = try XCTUnwrap(BenchmarkRuleStat.decodeList(json))
        XCTAssertEqual(rules.count, 2)
        XCTAssertEqual(rules[0].failedCount, 2)
        XCTAssertEqual(rules[1].passPercentage, 7.7)
        XCTAssertEqual(rules[0].id, "os_world_writable_library_folder_configure")
    }

    func testCompliancePercentage() {
        XCTAssertEqual(PlatformViewModel.compliancePercentage(Data(#"{"compliancePercentage": 12.7}"#.utf8)), 12.7)
        XCTAssertEqual(PlatformViewModel.compliancePercentage(Data(#"{"compliancePercentage": 100}"#.utf8)), 100)
        XCTAssertNil(PlatformViewModel.compliancePercentage(Data("[]".utf8)))
    }

    func testFailingDevicesDecode() throws {
        let json = Data("""
            [{"compliance": "0.0%", "device": "BE-ZJ4J3D7CPL", "deviceId": "598516d7-79d8-4161-8418-e597a7c11257",
              "rulesFailed": 6, "rulesPassed": 0}]
            """.utf8)
        let devices = try JSONDecoder().decode([BenchmarkDeviceCompliance].self, from: json)
        XCTAssertEqual(devices.first?.device, "BE-ZJ4J3D7CPL")
        XCTAssertEqual(devices.first?.rulesFailed, 6)
    }

    func testRuleDevicesDecodeLooselyAndKeepFailuresOnly() throws {
        let json = Data("""
            {"results": [
              {"deviceId": "a", "deviceName": "BE-ONE", "ruleResult": "FAILED"},
              {"deviceId": "b", "deviceName": "BE-TWO", "ruleResult": "PASSED"},
              {"id": "c", "device": "BE-THREE"}
            ]}
            """.utf8)
        let devices = try XCTUnwrap(BenchmarkRuleDevice.decodeList(json))
        XCTAssertEqual(devices.map(\.name), ["BE-ONE", "BE-THREE"])
        XCTAssertNil(BenchmarkRuleDevice.decodeList(Data("oops".utf8)))
    }

    func testBenchmarkArgumentsKeepValuesAfterSeparator() {
        XCTAssertEqual(CLICommand.benchmarkFailingDevices(title: "-x Title").baseArguments,
                       ["pro", "report", "compliance-devices", "-o", "json", "--", "-x Title"])
        XCTAssertEqual(CLICommand.benchmarkRuleStats(id: "abc").arguments(outputFormat: .csv),
                       ["pro", "benchmark-reports", "rules", "--sort", "failed:desc", "-o", "csv", "--", "abc"])
    }
}

final class BenchmarkRuleDevicesRealShapeTests: XCTestCase {
    // Shape from `pro benchmark-reports devices <id> --rule-id … --rule-result FAILED` (jamf-cli 1.31.1).
    func testRealShape() throws {
        let json = Data("""
            [{"deviceId": "598516d7-79d8-4161-8418-e597a7c11257", "state": "FAILED", "deviceName": "BE-ZJ4J3D7CPL"},
             {"deviceId": "ff36b2da-0352-448c-8a07-c4d491304a68", "state": "FAILED", "deviceName": "BE-ZCDH7FG3L7"}]
            """.utf8)
        let devices = try XCTUnwrap(BenchmarkRuleDevice.decodeList(json))
        XCTAssertEqual(devices.map(\.name), ["BE-ZJ4J3D7CPL", "BE-ZCDH7FG3L7"])
        XCTAssertEqual(devices.first?.id, "598516d7-79d8-4161-8418-e597a7c11257")
    }

    func testBenchmarkDetailUsesTitleAndTarget() throws {
        let json = Data("""
            {"id": "6a7453c53a35016b9cfa78c3", "title": "CIS Level 2 V2", "syncState": "SYNCED",
             "updateAvailable": true, "target": {"deviceGroups": ["0600227e-4fb8-48ca-ac43-cb811ead8a7d"]}}
            """.utf8)
        let d = try JSONDecoder().decode(BenchmarkDetail.self, from: json)
        XCTAssertEqual(d.displayName, "CIS Level 2 V2")
        XCTAssertEqual(d.resolvedScope?.deviceGroups?.count, 1)
        XCTAssertEqual(d.displayStatus, "SYNCED")
    }
}

final class FleetQueryTests: XCTestCase {
    func testVersionFilters() {
        let q15 = FleetQuery(osVersionPrefix: "15")
        XCTAssertTrue(q15.matches(name: "a", osVersion: "15.6", days: 1, managed: true))
        XCTAssertFalse(q15.matches(name: "a", osVersion: "150.1", days: 1, managed: true))
        let older = FleetQuery(osOlderThan: "15")
        XCTAssertTrue(older.matches(name: "a", osVersion: "14.7.1", days: 1, managed: true))
        XCTAssertFalse(older.matches(name: "a", osVersion: "15.0", days: 1, managed: true))
        XCTAssertFalse(older.matches(name: "a", osVersion: nil, days: 1, managed: true))
        let atLeast = FleetQuery(osAtLeast: "14.7")
        XCTAssertTrue(atLeast.matches(name: "a", osVersion: "14.10", days: 1, managed: true))
        XCTAssertFalse(atLeast.matches(name: "a", osVersion: "14.6.1", days: 1, managed: true))
    }

    func testCheckInAndManagedFilters() {
        let stale = FleetQuery(notSeenForDays: 14)
        XCTAssertTrue(stale.matches(name: "a", osVersion: "15", days: 20, managed: true))
        XCTAssertTrue(stale.matches(name: "a", osVersion: "15", days: nil, managed: true))
        XCTAssertFalse(stale.matches(name: "a", osVersion: "15", days: 3, managed: true))
        let recent = FleetQuery(seenWithinDays: 7)
        XCTAssertFalse(recent.matches(name: "a", osVersion: "15", days: nil, managed: true))
        let unmanaged = FleetQuery(managed: false)
        XCTAssertTrue(unmanaged.matches(name: "a", osVersion: nil, days: nil, managed: false))
        XCTAssertFalse(unmanaged.matches(name: "a", osVersion: nil, days: nil, managed: true))
    }

    func testGroundingDropsFiltersTheQuestionDoesNotSupport() {
        // What the small model actually returned for this question: every slot filled with 14.
        let q = FleetQuery.grounded([
            (.osVersionIs, "14"), (.osOlderThan, "14"), (.osAtLeast, "14"),
            (.notSeenForDays, "14"), (.seenWithinDays, "14"), (.unmanagedOnly, ""),
        ], question: "Macs on macOS 14 that haven't checked in for two weeks")
        XCTAssertEqual(q.osVersionPrefix, "14")
        XCTAssertNil(q.osOlderThan)
        XCTAssertNil(q.osAtLeast)
        XCTAssertEqual(q.notSeenForDays, 14)
        XCTAssertNil(q.seenWithinDays)
        XCTAssertNil(q.managed)
    }

    func testGroundingVersionMustAppearInQuestion() {
        XCTAssertEqual(FleetQuery.grounded([(.osOlderThan, "15")], question: "devices older than macOS 15").osOlderThan, "15")
        XCTAssertEqual(FleetQuery.grounded([(.osVersionIs, "15")], question: "Macs still on Sequoia").osVersionPrefix, "15")
        XCTAssertNil(FleetQuery.grounded([(.osVersionIs, "13")], question: "Macs on macOS 14").osVersionPrefix)
        XCTAssertNil(FleetQuery.grounded([(.osVersionIs, "1")], question: "Macs on macOS 14").osVersionPrefix)
    }

    func testGroundingNameAndManaged() {
        let q = FleetQuery.grounded([(.nameContains, "BE-"), (.unmanagedOnly, ""), (.nameContains, "Macs")],
                                    question: "unmanaged macs with BE- in the name")
        XCTAssertEqual(q.nameContains, "BE-")
        XCTAssertEqual(q.managed, false)
        XCTAssertNil(FleetQuery.grounded([(.managedOnly, "")], question: "unmanaged macs").managed == true ? 1 : nil)
    }

    func testRemovingLastFilterEmptiesQuery() {
        var q = FleetQuery(notSeenForDays: 30)
        q.remove(.notSeen)
        XCTAssertTrue(q.isEmpty)
    }
}

#if canImport(FoundationModels)
import FoundationModels

/// Runs the real on-device model; skipped when Apple Intelligence isn't available.
@available(macOS 26, *)
final class FleetQueryModelTests: XCTestCase {
    private func parse(_ q: String) async throws -> FleetQuery {
        guard case .available = SystemLanguageModel.default.availability else {
            throw XCTSkip("On-device model unavailable")
        }
        let result = try await FleetQueryParser.parse(q)
        print("FLEETQUERY «\(q)» → \(result)")
        return result
    }

    func testStaleOnOldOS() async throws {
        let q = try await parse("Macs on macOS 14 that haven't checked in for two weeks")
        XCTAssertEqual(q.osVersionPrefix ?? q.osOlderThan.map { _ in "14" }, "14")
        XCTAssertEqual(q.notSeenForDays, 14)
    }

    func testOlderThan() async throws {
        let q = try await parse("which devices are older than macOS 15")
        XCTAssertEqual(q.osOlderThan, "15")
    }

    func testUnsupportedDepartment() async throws {
        let q = try await parse("Finance department laptops")
        XCTAssertFalse(q.unsupported.isEmpty)
    }

    func testNameAndUnmanaged() async throws {
        let q = try await parse("unmanaged macs with BE- in the name")
        XCTAssertEqual(q.managed, false)
        XCTAssertEqual(q.nameContains?.uppercased(), "BE-")
    }
}
#endif

final class FleetKnowledgeIndexTests: XCTestCase {
    private func sampleIndex() throws -> FleetKnowledgeIndex {
        let computers = try JSONDecoder().decode([Computer].self, from: Data("""
            [{"id": "1", "name": "BE-ZJ4J3D7CPL", "serialNumber": "ZJ4J3D7CPL", "osVersion": "26.0"}]
            """.utf8))
        let policies = try JSONDecoder().decode([Policy].self, from: Data("""
            [{"id": 1, "name": "Enable FileVault", "category": {"id": 3, "name": "Security"}},
             {"id": 2, "name": "Install Chrome"}]
            """.utf8))
        let groups = try JSONDecoder().decode([SmartComputerGroup].self, from: Data("""
            [{"id": "5", "name": "FileVault not enabled"}]
            """.utf8))
        var s = FleetKnowledgeIndex.Sources()
        s.computers = computers
        s.policies = policies
        s.smartGroups = groups
        s.blueprints = [BlueprintStatus(name: "ALL - SCB - Apple - Siri", state: "DEPLOYED", scope: 1, steps: 1,
                                        succeeded: 4, failed: 1, pending: 10)]
        s.digests = [DigestEntry(id: UUID(), date: Date(timeIntervalSince1970: 1_790_000_000),
                                 bullets: ["3 Macs lack FileVault"], rawSummary: "")]
        return FleetKnowledgeIndex.build(profile: "test", from: s)
    }

    func testFindsAcrossKinds() throws {
        let hits = try sampleIndex().search("what do we have for FileVault?")
        XCTAssertEqual(Set(hits.map(\.kind)), [.policy, .smartGroup, .digest])
        XCTAssertEqual(hits.first?.kind, .policy)   // title match beats body match
    }

    func testKindWordsNarrowResults() throws {
        let hits = try sampleIndex().search("FileVault policies")
        XCTAssertEqual(hits.first?.title, "Enable FileVault")
        XCTAssertEqual(try sampleIndex().search("list the blueprints").map(\.kind), [.blueprint])
    }

    func testSerialAndPrefixMatch() throws {
        XCTAssertEqual(try sampleIndex().search("ZJ4J3D7CPL").first?.kind, .computer)
        XCTAssertEqual(try sampleIndex().search("chro").first?.title, "Install Chrome")
    }

    func testNoMatchExplainsWhatIsIndexed() throws {
        XCTAssertTrue(try sampleIndex().answer("zebra").contains("No indexed Jamf data"))
        XCTAssertTrue(try sampleIndex().search("the and of").isEmpty)
    }

    @MainActor
    func testStoreRoundTripsAndClears() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("fleet-index-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = FleetKnowledgeStore(fileURL: file)
        XCTAssertTrue(store.answer("x").contains("isn't ready"))
        store.replace(with: try sampleIndex())
        let perms = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o600)
        XCTAssertEqual(FleetKnowledgeStore(fileURL: file).index?.documents.count, try sampleIndex().documents.count)
        store.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
}

final class OverviewAlertTests: XCTestCase {
    private func item(_ resource: String, _ value: String) -> OverviewItem {
        OverviewItem(section: "Health & Alerts", resource: resource, value: value)
    }

    func testIdenticalAlertsAreCounted() {
        let items = [item("Health Status", "ok"), item("Active Alerts", "6 active"),
                     item("Alert Types", "Patch extension attribute issue"),
                     item("", "Patch extension attribute issue"),
                     item("", "Push certificate expiring"),
                     item("", "Patch extension attribute issue")]
        let grouped = OverviewViewModel.groupingAlerts(items)
        XCTAssertEqual(grouped.map(\.resource), ["Health Status", "Active Alerts", "Alert Types", ""])
        XCTAssertEqual(grouped[2].value, "Patch extension attribute issue ×3")
        XCTAssertEqual(grouped[3].value, "Push certificate expiring")
        XCTAssertEqual(Set(grouped.map(\.id)).count, grouped.count, "ids must be unique for ForEach")
    }

    func testNotificationSubjectFromParams() throws {
        let json = Data("""
            [{"id": 1, "type": "PATCH_EXTENSION_ATTRIBUTE", "message": "", "params": {"id": "12", "name": "Google Chrome"}},
             {"id": 2, "type": "PATCH_EXTENSION_ATTRIBUTE"}]
            """.utf8)
        let n = try JSONDecoder().decode([ProNotification].self, from: json)
        XCTAssertEqual(n.map(\.subject), ["Google Chrome", nil])
        XCTAssertEqual(AlertHints.readable("PATCH_EXTENSION_ATTRIBUTE"), "Patch extension attribute")
        XCTAssertNotNil(AlertHints.fix(for: "PATCH_EXTENSION_ATTRIBUTE", message: ""))
        XCTAssertNil(AlertHints.fix(for: "SOMETHING_ELSE", message: "Other"))
    }
}
