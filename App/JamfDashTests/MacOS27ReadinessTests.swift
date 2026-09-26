import XCTest
@testable import JamfDash

final class MacOS27ReadinessTests: XCTestCase {

    // MARK: - DDM status value parsing

    func testParseJavaMapValue() {
        let v = DDMStatusValue.parse("{os-version=27.0.1, build-version=27A5340, target-local-date-time=2026-10-03T18:00:00}")
        XCTAssertEqual(v["os-version"]?.stringValue, "27.0.1")
        XCTAssertEqual(v["build-version"]?.stringValue, "27A5340")
        XCTAssertEqual(v["target-local-date-time"]?.stringValue, "2026-10-03T18:00:00")
    }

    func testParseNestedJavaMapAndList() {
        let v = DDMStatusValue.parse("{active=true, reasons=[a, b], inner={count=2}}")
        XCTAssertEqual(v["active"]?.boolValue, true)
        XCTAssertEqual(v["inner"]?["count"]?.intValue, 2)
        if case .array(let items)? = v["reasons"] {
            XCTAssertEqual(items.count, 2)
        } else {
            XCTFail("reasons should parse as an array")
        }
    }

    func testParseJSONAndScalars() {
        XCTAssertEqual(DDMStatusValue.parse(#"{"count":0}"#)["count"]?.intValue, 0)
        XCTAssertEqual(DDMStatusValue.parse("true").boolValue, true)
        XCTAssertEqual(DDMStatusValue.parse("supervised").stringValue, "supervised")
        // Unbalanced text falls back to a plain string instead of failing.
        XCTAssertEqual(DDMStatusValue.parse("{broken").stringValue, "{broken")
    }

    func testStatusItemDecodesNonStringValues() throws {
        let json = #"""
        {"statusItems":[
          {"key":"security.lockdown-mode","value":true,"lastUpdateTime":"t"},
          {"key":"device.system.health","value":{"Display":"ok","Camera":"non-genuine"}},
          {"key":"com.example.future-item","value":"x"}
        ]}
        """#
        let r = try JSONDecoder().decode(DDMStatusItemResponse.self, from: Data(json.utf8))
        XCTAssertEqual(r.statusItems.count, 3)
        XCTAssertEqual(r.statusItems[0].value, "true")
        XCTAssertEqual(r.statusItems[0].knownKey, .lockdownMode)
        XCTAssertNil(r.statusItems[2].knownKey, "Unknown keys must be kept as raw items")

        let summary = DDMDeviceStatusSummary(items: r.statusItems)
        XCTAssertEqual(summary.lockdownModeEnabled, true)
        XCTAssertEqual(summary.unhealthyComponents, ["Camera"])
        XCTAssertEqual(summary.unknownKeys, ["com.example.future-item"])
        XCTAssertTrue(summary.reportsOS27Items)
    }

    func testDeviceStatusSummaryFromJamfStrings() {
        let items = [
            DDMStatusItem(key: "mdm.enrollment-type", value: "supervised", lastUpdateTime: nil),
            DDMStatusItem(key: "mdm.is-awaiting-configuration", value: "false", lastUpdateTime: nil),
            DDMStatusItem(key: "device.operating-system.version", value: "27.0", lastUpdateTime: nil),
            DDMStatusItem(key: "softwareupdate.install-state", value: "failed", lastUpdateTime: nil),
            DDMStatusItem(key: "softwareupdate.pending-version", value: "{os-version=27.0.1, build-version=27A5340}", lastUpdateTime: nil),
            DDMStatusItem(key: "softwareupdate.failure-reason", value: "{count=2, reason=Insufficient disk space}", lastUpdateTime: nil),
        ]
        let s = DDMDeviceStatusSummary(items: items)
        XCTAssertEqual(s.enrollmentTypeLabel, "Supervised")
        XCTAssertEqual(s.isAwaitingConfiguration, false)
        XCTAssertEqual(s.osVersion, "27.0")
        XCTAssertTrue(s.softwareUpdate.isFailed)
        XCTAssertTrue(s.softwareUpdate.hasPendingUpdate)
        XCTAssertEqual(s.softwareUpdate.pendingOSVersion, "27.0.1")
        XCTAssertEqual(s.softwareUpdate.failureCount, 2)
        XCTAssertEqual(s.softwareUpdate.failureReason, "Insufficient disk space")
        XCTAssertNil(s.lockdownModeEnabled)
    }

    func testDecodeDevicesReportsTotalCount() throws {
        let json = #"""
        {"totalCount":3,"results":[
          {"id":"1","general":{"name":"A","managementId":"m1","declarativeDeviceManagementEnabled":true}},
          {"id":2,"general":{"name":"B","managementId":"m2","declarativeDeviceManagementEnabled":false}},
          {"id":"3","general":{"name":"C"}}
        ]}
        """#
        let (devices, total) = try DDMMonitorViewModel.decodeDevices(from: Data(json.utf8))
        XCTAssertEqual(total, 3)
        XCTAssertEqual(devices.map(\.id), ["1", "2"])
        XCTAssertEqual(devices[1].ddmEnabled, false)
    }

    func testCoverageSummary() {
        let c = DDMCoverageSummary(inventoryDevices: 10, ddmEnabledDevices: 8, declarationCount: 3,
                                   succeeded: 18, failed: 1, pending: 1)
        XCTAssertEqual(c.deviceCoverage ?? 0, 0.8, accuracy: 0.0001)
        XCTAssertEqual(c.successRate ?? 0, 0.9, accuracy: 0.0001)
    }

    // MARK: - Profile payload parsing + deprecation rules

    private func profileJSON(id: Int, name: String, payloads: String) -> Data {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>PayloadContent</key><array>\(payloads)</array><key>PayloadType</key><string>Configuration</string></dict></plist>
        """
        let obj: [String: Any] = ["general": ["id": id, "name": name, "payloads": plist]]
        return try! JSONSerialization.data(withJSONObject: obj)
    }

    func testPayloadParserExtractsTypesAndKeys() throws {
        let data = profileJSON(id: 11, name: "SU Deferrals", payloads:
            "<dict><key>PayloadType</key><string>com.apple.applicationaccess</string><key>enforcedSoftwareUpdateDelay</key><integer>30</integer></dict>")
        let p = try XCTUnwrap(ProfilePayloadParser.parse(detailJSON: data))
        XCTAssertEqual(p.id, 11)
        XCTAssertEqual(p.name, "SU Deferrals")
        XCTAssertEqual(p.payloads["com.apple.applicationaccess"], ["enforcedSoftwareUpdateDelay"])
    }

    func testPayloadParserRegexFallback() {
        let text = "<dict><key>PayloadType</key><string>com.apple.AssetCache.managed</string><key>AllowSharedCaching</key>"
        let payloads = ProfilePayloadParser.payloads(fromPlist: text)
        XCTAssertNotNil(payloads["com.apple.AssetCache.managed"])
    }

    func testDeprecationRulesFlagExpectedProfiles() throws {
        let profiles = [
            ScannedProfile(id: 1, name: "Deferrals", payloads: ["com.apple.applicationaccess": ["forceDelayedSoftwareUpdates"]]),
            ScannedProfile(id: 2, name: "Restrictions", payloads: ["com.apple.applicationaccess": ["allowCamera"]]),
            ScannedProfile(id: 3, name: "Parental", payloads: ["com.apple.applicationaccess.new": []]),
            ScannedProfile(id: 4, name: "Caching", payloads: ["com.apple.AssetCache.managed": []]),
            ScannedProfile(id: 5, name: "PPPC", payloads: ["com.apple.TCC.configuration-profile-policy": ["Services"]]),
            ScannedProfile(id: 6, name: "DNS", payloads: ["com.apple.dnsSettings.managed": []]),
            ScannedProfile(id: 7, name: "SU", payloads: ["com.apple.SoftwareUpdate": []]),
            ScannedProfile(id: 8, name: "Firewall", payloads: ["com.apple.security.firewall": []]),
        ]
        let findings = DeprecationAuditRules.findings(for: profiles)
        let byID = Dictionary(uniqueKeysWithValues: findings.map { ($0.id, $0) })

        XCTAssertEqual(byID["os27-softwareupdate-deferrals"]?.affectedDeviceNames, ["Deferrals"],
                       "Plain restrictions without deferral keys must not be flagged")
        XCTAssertEqual(byID["os27-softwareupdate-deferrals"]?.severity, .critical)
        XCTAssertEqual(byID["os27-softwareupdate-payload"]?.affectedDeviceNames, ["SU"])
        XCTAssertEqual(byID["os27-applicationaccess-new"]?.affectedCount, 1)
        XCTAssertEqual(byID["os27-assetcache-managed"]?.remediation?.contains("content-cache.settings"), true)
        XCTAssertEqual(byID["os27-network-dns-relay"]?.affectedDeviceNames, ["DNS"])
        XCTAssertEqual(byID["os27-pppc-tcc"]?.severity, .info)
        XCTAssertNil(byID["os27-network-vpn"], "Rules with no matches produce no finding")
        XCTAssertTrue(findings.allSatisfy { $0.category == DeprecationAuditRules.category })
        XCTAssertFalse(findings.contains { $0.affectedDeviceNames?.contains("Firewall") == true })

        let legacy = DeprecationAuditRules.legacySoftwareUpdateProfiles(in: profiles).map(\.name)
        XCTAssertEqual(Set(legacy), ["Deferrals", "SU"])
    }

    // MARK: - Update readiness

    private func computer(_ id: String, os: String, ddm: Bool?, profiles: [String] = []) -> ReadinessComputer {
        ReadinessComputer(id: id, name: "Mac \(id)", serialNumber: "S\(id)", managementId: "m\(id)",
                          osVersion: os, ddmEnabled: ddm,
                          profiles: profiles.map { .init(id: nil, name: $0) })
    }

    func testReadinessEvaluator() throws {
        let plansJSON = #"""
        {"results":[
          {"planUuid":"p1","device":{"deviceId":"1","objectType":"COMPUTER"},"versionType":"LATEST_MINOR","status":{"state":"PlanAccepted","errorReasons":[]}},
          {"planUuid":"p3","device":{"deviceId":"3","objectType":"COMPUTER"},"specificVersion":"27.0.1","status":{"state":"PlanFailed","errorReasons":["SPECIFIED_VERSION_NOT_AVAILABLE"]}}
        ]}
        """#
        let plans = try XCTUnwrap(JamfListDecoder.decode(ManagedUpdatePlan.self, from: Data(plansJSON.utf8)))
        XCTAssertEqual(plans.count, 2)
        XCTAssertTrue(plans[1].isFailed)

        let legacy = [ScannedProfile(id: 11, name: "SU Deferrals", payloads: ["com.apple.SoftwareUpdate": []])]
        let rows = UpdateReadinessEvaluator.evaluate(
            computers: [
                computer("1", os: "27.0", ddm: true),                             // ready
                computer("2", os: "27.0.1", ddm: true, profiles: ["SU Deferrals"]), // legacy + no plan
                computer("3", os: "27.0", ddm: true),                             // failed plan
                computer("4", os: "27.0", ddm: false),                            // blocked
                computer("5", os: "15.4", ddm: true, profiles: ["su deferrals"]), // heads-up
                computer("6", os: "14.7", ddm: true),                             // ready (pre-27)
            ],
            plans: plans, statuses: [], legacyProfiles: legacy)
        let level = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.level) })
        XCTAssertEqual(level["1"], .ready)
        XCTAssertEqual(level["2"], .attention)
        XCTAssertEqual(rows.first { $0.id == "2" }?.legacyProfileNames, ["SU Deferrals"])
        XCTAssertEqual(level["3"], .attention)
        XCTAssertEqual(level["4"], .blocked)
        XCTAssertEqual(level["5"], .info)
        XCTAssertEqual(level["6"], .ready)
    }

    func testOSVersionMajor() {
        XCTAssertEqual(OSVersionParser.major("27.0.1"), 27)
        XCTAssertEqual(OSVersionParser.major("macOS 26.4"), 26)
        XCTAssertNil(OSVersionParser.major(""))
        XCTAssertNil(OSVersionParser.major(nil))
    }

    func testReadinessComputerDecoding() throws {
        let json = #"""
        [{"id":7,"general":{"name":"X","managementId":"m","declarativeDeviceManagementEnabled":true},
          "hardware":{"serialNumber":"SER"},"operatingSystem":{"version":"27.0"},
          "configurationProfiles":[{"id":11,"displayName":"SU Deferrals"}]}]
        """#
        let list = try XCTUnwrap(JamfListDecoder.decode(ReadinessComputer.self, from: Data(json.utf8)))
        XCTAssertEqual(list.first?.id, "7")
        XCTAssertEqual(list.first?.serialNumber, "SER")
        XCTAssertEqual(list.first?.osMajor, 27)
        XCTAssertEqual(list.first?.profiles.first?.id, "11")
    }

    // MARK: - CLI commands

    func testNewCommandArguments() {
        XCTAssertEqual(CLICommand.softwareUpdatePlans.baseArguments,
                       ["pro", "managed-software-updates-plans", "list", "-o", "json"])
        XCTAssertEqual(CLICommand.softwareUpdateStatuses.baseArguments,
                       ["pro", "managed-software-updates", "update-statuses", "-o", "json"])
        // Non-digits are stripped so the RSQL filter can't be injected into.
        let args = CLICommand.softwareUpdatePlansForComputer(computerId: "12\";x==\"1").baseArguments
        XCTAssertTrue(args.contains("device.deviceId==121;device.objectType==COMPUTER"))
        XCTAssertTrue(CLICommand.computersUpdateReadiness.baseArguments.contains("CONFIGURATION_PROFILES"))
    }

    // MARK: - App Intent summaries

    func testIntentComplianceSummary() throws {
        let json = #"[{"compliance_status":"Compliant"},{"compliance_status":"Non-Compliant"},{"compliance_status":"Compliant"},{"compliant":true}]"#
        let c = try XCTUnwrap(IntentSummaries.compliance(from: Data(json.utf8)))
        XCTAssertEqual(c.total, 4)
        XCTAssertEqual(c.compliant, 3)
        XCTAssertEqual(c.percent, 75)
    }

    func testIntentDevicesNeedingUpdates() {
        let perDevice = #"[{"status":"Pending"},{"status":"Current"},{"status":"Failed"}]"#
        XCTAssertEqual(IntentSummaries.devicesNeedingUpdates(from: Data(perDevice.utf8)), 2)
        let aggregated = #"{"results":[{"status":"IDLE","count":40},{"status":"DOWNLOADING","count":5},{"status":"INSTALL_FAILED","count":2}]}"#
        XCTAssertEqual(IntentSummaries.devicesNeedingUpdates(from: Data(aggregated.utf8)), 7)
    }

    func testIntentDDMFailures() throws {
        let json = #"[{"declaration":"A","succeededCount":3,"failedCount":2,"pendingCount":0},{"declaration":"B","succeededCount":1,"failedCount":0,"pendingCount":0},{"declaration":"C","failed":5}]"#
        let f = try XCTUnwrap(IntentSummaries.ddmFailures(from: Data(json.utf8)))
        XCTAssertEqual(f.failedStatuses, 7)
        XCTAssertEqual(f.failingDeclarations, ["C", "A"])
    }

    // MARK: - Demo Mode

    func testDemoModeDataFeedsNewFeatures() async throws {
        let demo = DemoCLIManager()
        let profile = try await demo.run(.configProfileDetail(id: 11))
        let scanned = try XCTUnwrap(ProfilePayloadParser.parse(detailJSON: profile))
        XCTAssertEqual(scanned.name, "Software Update Deferrals")
        XCTAssertFalse(DeprecationAuditRules.legacySoftwareUpdateProfiles(in: [scanned]).isEmpty)

        let computers = try await demo.run(.computersUpdateReadiness)
        XCTAssertEqual(JamfListDecoder.decode(ReadinessComputer.self, from: computers)?.count, 8)
        let plans = try await demo.run(.softwareUpdatePlans)
        XCTAssertEqual(JamfListDecoder.decode(ManagedUpdatePlan.self, from: plans)?.count, 3)
        let ddm = try await demo.run(.reportDDMStatus)
        XCTAssertEqual(IntentSummaries.ddmFailures(from: ddm)?.failedStatuses, 3)
        let items = try await demo.run(.ddmStatusItems(managementId: "dddddddd-4444-5555-6666-eeeeeeeeeeee"))
        let summary = DDMDeviceStatusSummary(items: try DDMMonitorViewModel.decodeStatusItems(from: items))
        XCTAssertEqual(summary.lockdownModeEnabled, true)
        XCTAssertEqual(summary.softwareUpdate.failureCount, 2)
    }
}
