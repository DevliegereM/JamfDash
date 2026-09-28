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

// MARK: - Dashie

#if canImport(FoundationModels)
import FoundationModels

private struct NoCLI: SimulatedCLI {
    func run(_ command: CLICommand) async throws -> Data { Data() }
    func run(_ command: CLICommand, outputFormat: ReportOutputFormat) async throws -> Data { Data() }
}

@available(macOS 26, *)
final class DashieToolTests: XCTestCase {

    @MainActor
    func testToolNamesAreUniqueAndMatchSystemPrompt() {
        let names = AIAssistantViewModel.tools(cli: NoCLI(), actionsEnabled: true).map(\.name)
        let prompt = AIAssistantViewModel.prompt(actionsEnabled: true)
        XCTAssertEqual(Set(names).count, names.count, "tool names must be unique")
        for name in names {
            XCTAssertTrue(prompt.contains(name), "system prompt doesn't mention \(name)")
        }
    }

    private let computers = Data("""
        {"totalCount": 3, "results": [
          {"general": {"name": "Finance-MBP-01", "lastContactTime": "2026-09-26T10:00:00Z"},
           "hardware": {"serialNumber": "AAA111"}, "operatingSystem": {"version": "15.6"}},
          {"general": {"name": "Design-iMac", "lastContactTime": "2026-08-01T10:00:00Z"},
           "hardware": {"serialNumber": "BBB222"}, "operatingSystem": {"version": "14.7.1"}},
          {"general": {"name": "finance-mini"},
           "hardware": {"serialNumber": "CCC333"}, "operatingSystem": {"version": "150.1"}}
        ]}
        """.utf8)

    private let now = ISO8601DateFormatter().date(from: "2026-09-27T12:00:00Z")!

    func testListComputersFilters() {
        let byName = ListComputersTool.summarize(computers, filter: .init(nameContains: "finance"), now: now)
        XCTAssertTrue(byName.contains("AAA111") && byName.contains("CCC333"))
        XCTAssertFalse(byName.contains("BBB222"))

        // "15" matches 15.6 but not 150.1.
        let byOS = ListComputersTool.summarize(computers, filter: .init(osVersion: "15"), now: now)
        XCTAssertTrue(byOS.contains("AAA111"))
        XCTAssertFalse(byOS.contains("CCC333"))

        // Stale: last seen 57 days ago, or never seen.
        let stale = ListComputersTool.summarize(computers, filter: .init(notSeenForDays: 30), now: now)
        XCTAssertTrue(stale.contains("BBB222") && stale.contains("CCC333"))
        XCTAssertFalse(stale.contains("AAA111"))
        XCTAssertTrue(stale.contains("Matching not seen for 30+ days: 2."))
    }

    func testListComputersUnfilteredListsAll() {
        let all = ListComputersTool.summarize(computers, now: now)
        XCTAssertTrue(all.hasPrefix("Total: 3 managed Macs."))
        XCTAssertFalse(all.contains("Matching"))
    }

    func testBulkDisableRejectsMatchAllPatterns() {
        for p in ["", "  ", "*", "**", "?*", "* "] {
            XCTAssertTrue(BulkSetPoliciesTool.matchesEverything(p), "\(p) should be refused")
        }
        for p in ["Test*", "*Legacy*", "?"] {
            XCTAssertFalse(BulkSetPoliciesTool.matchesEverything(p), "\(p) should be allowed")
        }
    }

    func testBulkDisableMatchesGlob() {
        let names = ["Test Install", "Test Remove", "Prod Install", "Contest"]
        XCTAssertEqual(BulkSetPoliciesTool.matchingNames("Test*", in: names), ["Test Install", "Test Remove"])
        XCTAssertEqual(BulkSetPoliciesTool.matchingNames("*Install", in: names), ["Test Install", "Prod Install"])
    }

    func testBulkDisableUsesNamePatternFlag() {
        XCTAssertEqual(CLICommand.bulkDisablePolicies(pattern: "Test*").baseArguments,
                       ["pro", "bulk", "disable-policies", "--name-pattern=Test*", "--yes"])
    }
}
#endif

final class DigestTests: XCTestCase {
    func testStripBullet() {
        XCTAssertEqual(DigestEntry.stripBullet("• 12 Macs lack FileVault"), "12 Macs lack FileVault")
        XCTAssertEqual(DigestEntry.stripBullet("- * point"), "point")
        XCTAssertEqual(DigestEntry.stripBullet("plain"), "plain")
    }

    @MainActor
    func testContextIsReadableTextNotTruncatedJSON() {
        let overview = Data(#"[{"section":"Devices","resource":"Computers","value":"42"}]"#.utf8)
        let context = DigestService.buildContext(overview: overview, security: nil, patch: nil)
        XCTAssertTrue(context.contains("Computers: 42"))
        XCTAssertTrue(DigestService.buildContext(overview: nil, security: nil, patch: nil).isEmpty)
    }
}

#if canImport(FoundationModels)
/// Returns small canned JSON for any command so tool calls succeed.
private struct CannedCLI: SimulatedCLI {
    func run(_ command: CLICommand) async throws -> Data {
        Data("""
            {"totalCount": 2, "results": [
              {"id": "1", "general": {"name": "BE-ONE", "lastContactTime": "2026-09-26T10:00:00Z"},
               "hardware": {"serialNumber": "AAA111"}, "operatingSystem": {"version": "26.0"}},
              {"id": "2", "general": {"name": "BE-TWO", "lastContactTime": "2026-08-01T10:00:00Z"},
               "hardware": {"serialNumber": "BBB222"}, "operatingSystem": {"version": "15.6"}}
            ]}
            """.utf8)
    }
    func run(_ command: CLICommand, outputFormat: ReportOutputFormat) async throws -> Data { try await run(command) }
}

/// Sends real questions through Dashie with the on-device model; skipped without Apple Intelligence.
@available(macOS 26, *)
final class DashieLiveTests: XCTestCase {
    @MainActor
    func testAskQuestionWithToolCall() async throws {
        guard case .available = SystemLanguageModel.default.availability else { throw XCTSkip("model unavailable") }
        let vm = AIAssistantViewModel(cli: CannedCLI())
        vm.inputText = "Which Macs haven't checked in for 30 days?"
        await vm.send()
        for m in vm.messages { print("DASHIE \(m.role): \(m.content)") }
        XCTAssertEqual(vm.messages.first?.role, .user)
        XCTAssertGreaterThan(vm.messages.count, 1)
        // Give FoundationModels' background session cleanup time to run (the app crashed there).
        try await Task.sleep(for: .seconds(8))
    }

    @MainActor
    func testHelpQuestionIsAnsweredFromHelp() async throws {
        guard case .available = SystemLanguageModel.default.availability else { throw XCTSkip("model unavailable") }
        let vm = AIAssistantViewModel(cli: CannedCLI())
        vm.inputText = "How do I turn on automatic updates for Jamf Dash?"
        await vm.send()
        let reply = vm.messages.last(where: { $0.role == .assistant })?.content ?? ""
        print("DASHIE help: \(reply.prefix(300))")
        XCTAssertTrue(reply.localizedCaseInsensitiveContains("Updates"), reply)
    }

    @MainActor
    func testFollowUpQuestion() async throws {
        guard case .available = SystemLanguageModel.default.availability else { throw XCTSkip("model unavailable") }
        let vm = AIAssistantViewModel(cli: CannedCLI())
        vm.inputText = "How many Macs do I have?"
        await vm.send()
        vm.inputText = "And which one is on macOS 15?"
        await vm.send()
        for m in vm.messages { print("DASHIE \(m.role): \(m.content)") }
        try await Task.sleep(for: .seconds(5))
    }

    @MainActor
    func testDigest() async throws {
        guard case .available = SystemLanguageModel.default.availability else { throw XCTSkip("model unavailable") }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("digest-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let service = DigestService(cli: CannedCLI(), storageURL: file, notifies: false)
        let before = service.entries.count
        await service.run()
        print("DIGEST entries \(before) → \(service.entries.count): \(service.entries.last?.bullets ?? [])")
        try await Task.sleep(for: .seconds(5))
    }
}
#endif

#if canImport(FoundationModels)
/// Tool-routing evaluation: real questions through Dashie with the on-device model, checking
/// which tools it calls. Actions are auto-cancelled, so nothing runs. Skipped without Apple
/// Intelligence. The pass rate is printed per case and must stay above a threshold, because a
/// small model is never 100% consistent.
@available(macOS 26, *)
final class DashieToolRoutingEvals: XCTestCase {
    private struct Case {
        let question: String
        /// Any of these tools counts as correct.
        let expected: Set<String>
    }

    private let cases: [Case] = [
        Case(question: "How many Macs do we manage?", expected: ["getOverview", "listComputers", "getInventorySummary"]),
        Case(question: "Which Macs haven't checked in for 30 days?", expected: ["listComputers"]),
        Case(question: "List the Macs still on macOS 14", expected: ["listComputers"]),
        Case(question: "Show me the hardware of the Mac with serial AAA111", expected: ["getComputerDetail"]),
        Case(question: "How much RAM does AAA111 have?", expected: ["getComputerDetail"]),
        Case(question: "What apps are installed on BBB222?", expected: ["getInstalledApps"]),
        Case(question: "Which Mac models do we have in the fleet?", expected: ["getInventorySummary"]),
        Case(question: "How many Macs don't have FileVault enabled?", expected: ["getSecurityReport"]),
        Case(question: "Is the firewall on across the fleet?", expected: ["getSecurityReport"]),
        Case(question: "Which devices are non-compliant?", expected: ["getCompliance"]),
        Case(question: "Which software titles are out of date?", expected: ["getPatchStatus"]),
        Case(question: "List our policies", expected: ["getPolicies"]),
        Case(question: "Which policies are disabled?", expected: ["getPolicies"]),
        Case(question: "What smart groups exist?", expected: ["getSmartGroups"]),
        Case(question: "Restart the Mac with serial AAA111", expected: ["restartDevice"]),
        Case(question: "Send a blank push to BBB222", expected: ["blankPush"]),
        Case(question: "Renew the MDM profile on AAA111", expected: ["renewMDMProfile"]),
        Case(question: "Flush the failed MDM commands on BBB222", expected: ["flushFailedCommands"]),
        Case(question: "Disable all policies named Test*", expected: ["bulkSetPolicies"]),
        Case(question: "Enable all policies in the Maintenance category", expected: ["bulkSetPolicies"]),
        Case(question: "What happened when AAA111 enrolled?", expected: ["explainEnrollment"]),
        Case(question: "Why didn't the Wi-Fi profile install on the new Mac BBB222?", expected: ["explainEnrollment"]),
        Case(question: "Give me a health overview of the Jamf Pro instance", expected: ["getOverview"]),
        Case(question: "What do we have for FileVault?", expected: ["searchFleetKnowledge"]),
        Case(question: "What did the daily digest say about patches?", expected: ["searchFleetKnowledge"]),
        Case(question: "How do I add a Platform API connection in Jamf Dash?", expected: ["searchHelp"]),
        Case(question: "Why are Blueprints greyed out in the sidebar?", expected: ["searchHelp"]),
        Case(question: "Where can I turn on automatic app updates?", expected: ["searchHelp"]),
    ]

    /// Minimum share of cases where the model picks an expected tool.
    private let requiredPassRate = 0.85

    @MainActor
    func testToolRouting() async throws {
        guard case .available = SystemLanguageModel.default.availability else { throw XCTSkip("model unavailable") }
        var confirmations: [String] = []
        DashieToolConfirmation.testOverride = { title in confirmations.append(title); return false }
        defer { DashieToolConfirmation.testOverride = nil }
        let actionsWereEnabled = UserDefaults.standard.bool(forKey: DashieActions.enabledKey)
        UserDefaults.standard.set(true, forKey: DashieActions.enabledKey)
        defer { UserDefaults.standard.set(actionsWereEnabled, forKey: DashieActions.enabledKey) }

        var passed = 0
        var report: [String] = []
        for c in cases {
            let vm = AIAssistantViewModel(cli: CannedCLI())
            vm.inputText = c.question
            await vm.send()
            let called = Self.toolNames(in: vm)
            let ok = !called.isDisjoint(with: c.expected)
            if ok { passed += 1 }
            report.append("\(ok ? "PASS" : "FAIL")  \(c.question)  → \(called.isEmpty ? "(no tool)" : called.sorted().joined(separator: ", "))  expected \(c.expected.sorted().joined(separator: "|"))")
            if !ok, let reply = vm.messages.last(where: { $0.role == .assistant })?.content {
                report.append("      reply: \(reply.replacingOccurrences(of: "\n", with: " ").prefix(160))")
            }
        }
        let rate = Double(passed) / Double(cases.count)
        print("DASHIE-EVAL tool routing \(passed)/\(cases.count) (\(Int(rate * 100))%)")
        report.forEach { print("DASHIE-EVAL \($0)") }
        print("DASHIE-EVAL confirmations shown (all cancelled): \(confirmations)")
        XCTAssertGreaterThanOrEqual(rate, requiredPassRate, "Tool routing dropped below \(Int(requiredPassRate * 100))%")
    }

    @MainActor
    private static func toolNames(in vm: AIAssistantViewModel) -> Set<String> {
        guard let session = vm._session as? LanguageModelSession else { return [] }
        var names: Set<String> = []
        for entry in session.transcript {
            if case .toolCalls(let calls) = entry {
                for call in calls { names.insert(call.toolName) }
            }
        }
        return names
    }
}
#endif

#if canImport(FoundationModels)
/// Prints what this Mac's on-device model offers on macOS 27 (variant, context, capabilities).
@available(macOS 27, *)
final class OnDeviceModelProbe: XCTestCase {
    func testProbe() async throws {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { throw XCTSkip("model unavailable") }
        let caps = model.capabilities
        print("PROBE variant=\(model.variant.displayName) core3=\(model.variant == .core3) advanced=\(model.variant == .coreAdvanced3)")
        print("PROBE contextSize=\(model.contextSize)")
        print("PROBE reasoning=\(caps.contains(.reasoning)) vision=\(caps.contains(.vision)) tools=\(caps.contains(.toolCalling)) guided=\(caps.contains(.guidedGeneration))")
        let session = LanguageModelSession(model: model)
        let start = Date()
        do {
            let r = try await session.respond(to: "A fleet has 13 Macs; 11 never reported compliance results and 2 score 90%. What is the average score over all 13? Answer with the number.",
                                              contextOptions: ContextOptions(reasoningLevel: .moderate))
            print("PROBE reasoning answer (\(String(format: "%.1f", Date().timeIntervalSince(start)))s): \(r.content.prefix(200))")
        } catch {
            print("PROBE reasoning error: \(error)")
        }
    }

    /// A fake screenshot with an error message, rendered in memory.
    private func errorScreenshot() -> CGImage {
        let size = NSSize(width: 640, height: 200)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.white.setFill(); rect.fill()
            let title = "Jamf Pro — Computer inventory" as NSString
            title.draw(at: NSPoint(x: 20, y: 150), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 22)])
            let msg = "Error: MDM profile expired on BE-ZJ4J3D7CPL. Last check-in 41 days ago." as NSString
            msg.draw(at: NSPoint(x: 20, y: 90), withAttributes: [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.systemRed])
            return true
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    }

    func testHistoryTrimShortensOnlyOlderToolOutput() {
        func output(_ id: String, _ text: String) -> Transcript.Entry {
            .toolOutput(Transcript.ToolOutput(id: id, toolName: "listComputers",
                                              segments: [.text(Transcript.TextSegment(content: text))]))
        }
        let long = String(repeating: "x", count: 1_000)
        let entries = [output("1", long), output("2", long), output("3", long), output("4", "short")]
        let trimmed = DashieHistory.trim(entries)
        func text(_ e: Transcript.Entry) -> String {
            guard case .toolOutput(let o) = e, case .text(let t) = o.segments.first else { return "" }
            return t.content
        }
        XCTAssertTrue(text(trimmed[0]).hasSuffix("call the tool again for details)"))
        XCTAssertLessThan(text(trimmed[0]).count, 400)
        XCTAssertTrue(text(trimmed[1]).count < 400)          // 3rd-newest output: shortened
        XCTAssertEqual(text(trimmed[2]).count, 1_000)          // 2 newest kept in full
        XCTAssertEqual(text(trimmed[3]), "short")
    }

    @MainActor
    func testDashieReadsAttachedImage() async throws {
        guard AIAssistantViewModel.supportsImages else { throw XCTSkip("no vision") }
        let vm = AIAssistantViewModel(cli: CannedCLI())
        let rep = NSBitmapImageRep(cgImage: errorScreenshot())
        vm.pendingImage = ImageAttachmentLoader.png(from: rep.representation(using: .png, properties: [:])!)
        vm.inputText = "What's wrong here?"
        await vm.send()
        let reply = vm.messages.last(where: { $0.role == .assistant })?.content ?? ""
        print("PROBE dashie-vision: \(reply.prefix(300))")
        XCTAssertNotNil(vm.messages.first?.imageData)
        XCTAssertNil(vm.pendingImage)
        XCTAssertTrue(reply.localizedCaseInsensitiveContains("MDM") || reply.localizedCaseInsensitiveContains("expired"))
    }

    func testVision() async throws {
        let model = SystemLanguageModel.default
        guard case .available = model.availability, model.capabilities.contains(.vision) else { throw XCTSkip("no vision") }
        let session = LanguageModelSession(model: model)
        let image = errorScreenshot()
        let r = try await session.respond(to: Prompt {
            "What problem does this screenshot show, and which device?"
            Attachment(image)
        })
        print("PROBE vision: \(r.content.prefix(300))")
    }

    func testProfileSessionWithHooks() async throws {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { throw XCTSkip("model unavailable") }
        final class Recorder: @unchecked Sendable {
            private let lock = NSLock()
            private var _calls: [String] = []
            private var _transforms = 0
            func call(_ n: String) { lock.withLock { _calls.append(n) } }
            func transform() { lock.withLock { _transforms += 1 } }
            var calls: [String] { lock.withLock { _calls } }
            var transforms: Int { lock.withLock { _transforms } }
        }
        let rec = Recorder()
        let tools = await AIAssistantViewModel.tools(cli: CannedCLI(), actionsEnabled: true)
        let session = LanguageModelSession(profile: LanguageModelSession.Profile {
            Instructions("You are Dashie. Use tools to answer questions about Macs.")
            tools
        }
        .temperature(0.2)
        .historyTransform { entries in rec.transform(); return entries }
        .onToolCall { call in rec.call(call.toolName) })
        let r = try await session.respond(to: "How many Macs haven't checked in for 30 days?")
        let toolCalls = rec.calls, transformed = rec.transforms
        print("PROBE profile: tools=\(toolCalls) historyTransforms=\(transformed) answer=\(r.content.prefix(160))")
    }
}
#endif
