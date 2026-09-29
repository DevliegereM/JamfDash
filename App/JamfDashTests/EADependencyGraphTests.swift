import XCTest
@testable import JamfDash

final class EADependencyGraphTests: XCTestCase {

    // MARK: - Helpers

    private func attribute(_ id: String, _ name: String, enabled: Bool? = true, choices: [String] = [],
                           inputType: String = "SCRIPT") throws -> ExtensionAttribute {
        var row: [String: Any] = ["id": id, "name": name, "inputType": inputType, "popupMenuChoices": choices]
        if let enabled { row["enabled"] = enabled }
        return try JSONDecoder().decode(ExtensionAttribute.self, from: JSONSerialization.data(withJSONObject: row))
    }

    private func group(_ id: String, _ name: String, _ criteria: [(String, String, String)]) -> GroupDefinition {
        GroupDefinition(id: id, name: name, isSmart: true,
                        criteria: criteria.map { ClassicCriterion(name: $0.0, searchType: $0.1, value: $0.2, andOr: "and") })
    }

    private func scoped(_ type: DependentObjectType, _ id: String, _ name: String,
                        include: [String] = [], exclude: [String] = [], payload: Set<String> = []) -> ScopedObjectDefinition {
        ScopedObjectDefinition(type: type, id: id, name: name, allDevices: false,
                               includedGroups: include.map { ScopeGroupRef(id: "", name: $0) },
                               excludedGroups: exclude.map { ScopeGroupRef(id: "", name: $0) },
                               payloadAttributeIDs: payload)
    }

    private func names(_ report: EADependencyReport?, _ type: DependentObjectType) -> [String] {
        report?.dependencies(of: type).map(\.object.name) ?? []
    }

    // MARK: - Parsing

    func testParsesWrappedGroupWithSingleCriterion() throws {
        let json = #"{"computer_group": {"id": 7, "name": "FIN", "is_smart": true, "criteria": {"size": 1, "criterion": {"name": "Department Code", "search_type": "is", "value": "FIN", "and_or": "and"}}}}"#
        let group = try XCTUnwrap(ClassicDefinitionParser.group(Data(json.utf8), fallbackID: "0", fallbackName: ""))
        XCTAssertEqual(group.id, "7")
        XCTAssertEqual(group.criteria, [ClassicCriterion(name: "Department Code", searchType: "is", value: "FIN", andOr: "and")])
    }

    func testParsesScopeInClassicAndFlatForms() throws {
        let json = #"""
        {"general": {"id": 3, "name": "Login", "payloads": "<string>Asset $EXTENSIONATTRIBUTE_7 / $EXTENSIONATTRIBUTE_12</string>"},
         "scope": {"all_computers": false,
                   "computer_groups": {"computer_group": {"id": 5, "name": "Baseline"}},
                   "exclusions": {"computer_groups": [{"id": 9, "name": "Stale"}]}}}
        """#
        let object = try XCTUnwrap(ClassicDefinitionParser.scopedObject(Data(json.utf8), type: .macConfigProfile, id: "3", name: "Login"))
        XCTAssertEqual(object.includedGroups, [ScopeGroupRef(id: "5", name: "Baseline")])
        XCTAssertEqual(object.excludedGroups, [ScopeGroupRef(id: "9", name: "Stale")])
        XCTAssertEqual(object.payloadAttributeIDs, ["7", "12"])
    }

    func testListRowsAcceptEveryListForm() {
        let forms = [
            #"[{"id": 1, "name": "A", "is_smart": true}]"#,
            #"{"computer_groups": [{"id": 1, "name": "A", "is_smart": true}]}"#,
            #"{"results": [{"id": "1", "name": "A"}]}"#,
            #"{"computer_groups": {"size": 1, "computer_group": {"id": 1, "name": "A"}}}"#,
        ]
        for json in forms {
            XCTAssertEqual(ClassicDefinitionParser.idsAndNames(Data(json.utf8)).map(\.id), ["1"], json)
        }
    }

    func testMobileScopeUsesMobileGroups() throws {
        let json = #"{"general": {"name": "Wi-Fi"}, "scope": {"mobile_device_groups": [{"id": 2, "name": "Cart A"}], "computer_groups": [{"id": 3, "name": "Macs"}]}}"#
        let object = try XCTUnwrap(ClassicDefinitionParser.scopedObject(Data(json.utf8), type: .mobileConfigProfile, id: "1", name: "Wi-Fi"))
        XCTAssertEqual(object.includedGroups.map(\.name), ["Cart A"])
    }

    // MARK: - Graph

    private func inventory() throws -> DependencyInventory {
        var inv = DependencyInventory()
        inv.computerAttributes = [
            try attribute("9", "Department Code", choices: ["ENG", "FIN"], inputType: "POPUP"),
            try attribute("4", "Local Admin Present", enabled: false),
            try attribute("2", "Battery Cycle Count"),
            try attribute("7", "Asset Tag", inputType: "TEXT"),
        ]
        inv.mobileAttributes = [try attribute("1", "Department Code", enabled: nil, inputType: "TEXT")]
        inv.computerGroups = [
            group("13", "Engineering", [("Department Code", "is", "ENG")]),
            group("21", "Engineering VPN", [("Computer Group", "member of", "Engineering")]),
            group("22", "Not VPN", [("Computer Group", "not member of", "Engineering VPN")]),
            group("14", "Marketing", [("department code", "is", "MKTG")]),
            group("30", "OS 15", [("Operating System Version", "like", "15.")]),
        ]
        inv.computerSearches = [
            SearchDefinition(id: "1", name: "Admins", criteria: [ClassicCriterion(name: "Local Admin Present", searchType: "is", value: "Yes", andOr: "and")],
                             displayFields: ["Computer Name", "Department Code"]),
        ]
        inv.scopedObjects = [
            scoped(.policy, "1", "Install IDE", include: ["Engineering VPN"]),
            scoped(.patchPolicy, "2", "Chrome", include: ["OS 15"], exclude: ["Engineering"]),
            scoped(.macConfigProfile, "3", "Login Window", payload: ["7"]),
            scoped(.mobileConfigProfile, "4", "iPad Wi-Fi", include: ["Engineering"]),
        ]
        return inv
    }

    func testDirectNestedAndScopedDependencies() throws {
        let inv = try inventory()
        let graph = EADependencyGraph(inventory: inv)
        let report = graph.report(for: inv.computerAttributes[0], kind: .computer)

        XCTAssertEqual(names(report, .computerSmartGroup), ["Engineering", "Engineering VPN", "Marketing", "Not VPN"])
        XCTAssertEqual(names(report, .computerAdvancedSearch), ["Admins"])
        XCTAssertEqual(names(report, .policy), ["Install IDE"])
        XCTAssertEqual(names(report, .patchPolicy), ["Chrome"])
        // A computer attribute never affects mobile objects, even when a group name matches.
        XCTAssertEqual(names(report, .mobileConfigProfile), [])

        let notVPN = try XCTUnwrap(report?.dependencies(of: .computerSmartGroup).first { $0.object.name == "Not VPN" })
        XCTAssertEqual(notVPN.reasons, [.memberOf(group: "Engineering VPN", negated: true, chain: ["Engineering", "Engineering VPN"])])
        XCTAssertFalse(notVPN.isDirect)

        let policy = try XCTUnwrap(report?.dependencies(of: .policy).first)
        XCTAssertEqual(policy.reasons, [.scope(group: "Engineering VPN", excluded: false, chain: ["Engineering", "Engineering VPN"])])
        XCTAssertEqual(policy.reasons.first?.summary, "Scoped to Engineering VPN (via Engineering)")

        let patch = try XCTUnwrap(report?.dependencies(of: .patchPolicy).first)
        XCTAssertTrue(patch.isExclusionOnly)
        XCTAssertTrue(report?.findings.contains { $0.title == "Used in exclusions" } ?? false)
    }

    func testSearchDisplayFieldAndPayloadVariable() throws {
        let inv = try inventory()
        let graph = EADependencyGraph(inventory: inv)
        let department = try XCTUnwrap(graph.report(for: inv.computerAttributes[0], kind: .computer))
        XCTAssertEqual(department.dependencies(of: .computerAdvancedSearch).first?.reasons, [.displayField])

        let assetTag = try XCTUnwrap(graph.report(for: inv.computerAttributes[3], kind: .computer))
        XCTAssertEqual(assetTag.dependencies.map(\.object.name), ["Login Window"])
        XCTAssertEqual(assetTag.dependencies.first?.reasons, [.payloadVariable("$EXTENSIONATTRIBUTE_7")])
    }

    func testFindings() throws {
        let inv = try inventory()
        let graph = EADependencyGraph(inventory: inv)

        let department = try XCTUnwrap(graph.report(for: inv.computerAttributes[0], kind: .computer))
        let menu = department.findings.filter { $0.title == "Value isn't a menu choice" }
        XCTAssertEqual(menu.count, 1)
        XCTAssertTrue(menu[0].detail.contains("MKTG"))
        XCTAssertTrue(department.hasWarnings)

        let admin = try XCTUnwrap(graph.report(for: inv.computerAttributes[1], kind: .computer))
        XCTAssertEqual(admin.findings.first?.title, "Disabled, but still in use")

        let battery = try XCTUnwrap(graph.report(for: inv.computerAttributes[2], kind: .computer))
        XCTAssertTrue(battery.isUnused)
        XCTAssertTrue(battery.findings.first?.detail.contains("script still runs") ?? false)
        XCTAssertFalse(battery.hasWarnings)
    }

    func testMobileAttributeOnlyAffectsMobileObjects() throws {
        var inv = try inventory()
        inv.mobileGroups = [group("1", "Engineering", [("Department Code", "is", "ENG")])]
        let graph = EADependencyGraph(inventory: inv)
        let report = try XCTUnwrap(graph.report(for: inv.mobileAttributes[0], kind: .mobileDevice))
        XCTAssertEqual(report.dependencies.map(\.object.name), ["Engineering", "iPad Wi-Fi"])
        XCTAssertEqual(report.dependencies.map(\.object.type), [.mobileSmartGroup, .mobileConfigProfile])
    }

    func testCircularGroupsTerminate() throws {
        var inv = DependencyInventory()
        inv.computerAttributes = [try attribute("1", "Tag")]
        inv.computerGroups = [
            group("1", "A", [("Tag", "is", "x"), ("Computer Group", "member of", "B")]),
            group("2", "B", [("Computer Group", "member of", "A")]),
            group("3", "C", [("Computer Group", "member of", "D")]),
            group("4", "D", [("Computer Group", "member of", "C")]),
        ]
        let report = try XCTUnwrap(EADependencyGraph(inventory: inv).report(for: inv.computerAttributes[0], kind: .computer))
        XCTAssertEqual(report.dependencies.map(\.object.name), ["A", "B"])
    }

    func testStaticGroupsAreIgnored() throws {
        var inv = DependencyInventory()
        inv.computerAttributes = [try attribute("1", "Tag")]
        inv.computerGroups = [GroupDefinition(id: "1", name: "Static", isSmart: false,
                                              criteria: [ClassicCriterion(name: "Tag", searchType: "is", value: "x", andOr: "and")])]
        XCTAssertTrue(EADependencyGraph(inventory: inv).report(for: inv.computerAttributes[0], kind: .computer)?.isUnused ?? false)
    }

    // MARK: - Scan

    /// Demo data, except that patch policies can't be listed and one policy can't be read.
    private struct PartialCLI: SimulatedCLI {
        func run(_ command: CLICommand) async throws -> Data {
            switch command {
            case .patchPolicies:
                throw CLIError.nonZeroExit(code: 1, stderr: #"{"error":"forbidden","exitCode":1,"message":"Privilege required: Read Patch Policies"}"#)
            case .policyDetail(let id) where id == 2:
                throw CLIError.timeout
            case .classicComputerGroupDetail(let id) where id == "30":
                XCTFail("Static groups have no criteria and shouldn't be fetched")
            default: break
            }
            return try await DemoCLIManager().run(command)
        }
    }

    func testScanRecordsFailuresAndContinues() async throws {
        let inventory = await EADependencyRepository(cli: PartialCLI()).scan { _ in }
        XCTAssertTrue(inventory.failures.contains { $0.type == .patchPolicy && $0.isListFailure })
        XCTAssertTrue(inventory.failures.contains { $0.type == .policy && !$0.isListFailure && $0.count == 1 })
        XCTAssertFalse(inventory.computerGroups.isEmpty)
        XCTAssertFalse(inventory.mobileSearches.isEmpty)
        XCTAssertFalse(inventory.scopedObjects.contains { $0.type == .patchPolicy })
    }

    func testDemoMapShowsNestedGroupsAndFindings() async throws {
        let inventory = await EADependencyRepository(cli: DemoCLIManager()).scan { _ in }
        XCTAssertTrue(inventory.failures.isEmpty, "\(inventory.failures)")
        let graph = EADependencyGraph(inventory: inventory)

        let department = try XCTUnwrap(inventory.computerAttributes.first { $0.name == "Department Code" })
        let report = try XCTUnwrap(graph.report(for: department, kind: .computer))
        XCTAssertTrue(names(report, .computerSmartGroup).contains("Engineering VPN Users"))
        XCTAssertTrue(names(report, .computerSmartGroup).contains("Executives"))
        XCTAssertFalse(names(report, .policy).isEmpty)
        XCTAssertFalse(names(report, .patchPolicy).isEmpty)
        XCTAssertTrue(report.findings.contains { $0.title == "Value isn't a menu choice" })

        let admin = try XCTUnwrap(inventory.computerAttributes.first { $0.name == "Local Admin Present" })
        XCTAssertTrue(graph.report(for: admin, kind: .computer)?.findings.contains { $0.title == "Disabled, but still in use" } ?? false)

        let cart = try XCTUnwrap(inventory.mobileAttributes.first { $0.name == "Cart Number" })
        let cartReport = try XCTUnwrap(graph.report(for: cart, kind: .mobileDevice))
        XCTAssertEqual(Set(names(cartReport, .mobileConfigProfile)), ["Lock Screen Message", "Wi-Fi (Classroom)"])

        let unused = try XCTUnwrap(inventory.computerAttributes.first { $0.name == "Battery Cycle Count" })
        XCTAssertTrue(graph.report(for: unused, kind: .computer)?.isUnused ?? false)
    }
}
