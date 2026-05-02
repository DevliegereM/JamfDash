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
        XCTAssertTrue(policies.allSatisfy { !$0.id.isEmpty && !$0.name.isEmpty })
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
      {"id": "1",  "name": "CORP - Enable FileVault",   "category": {"id": "5", "name": "Security"}},
      {"id": "2",  "name": "CORP - Enable Firewall",    "category": {"id": "5", "name": "Security"}},
      {"id": "7",  "name": "CORP - Google Chrome",      "category": {"id": "8", "name": "Software"}},
      {"id": "15", "name": "CORP - SwiftDialog Install","category": {"id": "1", "name": "Deployment Tools"}}
    ]
    """
}
