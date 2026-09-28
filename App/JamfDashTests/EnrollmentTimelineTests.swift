import XCTest
@testable import JamfDash

final class EnrollmentParsingTests: XCTestCase {

    func testMDMCommandsFromResultsWrapper() {
        let data = Data("""
            {"totalCount": 3, "results": [
              {"uuid": "u1", "commandType": "INSTALL_PROFILE", "commandState": "ACKNOWLEDGED",
               "dateSent": "2026-09-25T09:12:40.123Z", "dateCompleted": "2026-09-25T09:12:44Z",
               "profileIdentifier": "com.acme.wifi"},
              {"uuid": "u2", "commandType": "INSTALL_APPLICATION", "commandState": "PENDING", "dateSent": "2026-09-25T09:19:30Z"},
              {"uuid": "u3", "commandType": "INSTALL_PROFILE", "commandState": "ERROR", "dateSent": "2026-09-25T09:16:15Z"}
            ]}
            """.utf8)
        let records = EnrollmentParsing.mdmCommands(data)
        XCTAssertEqual(records.map(\.status), [.completed, .pending, .failed])
        XCTAssertEqual(records[0].profileIdentifier, "com.acme.wifi")
        XCTAssertNotNil(records[0].dateSent, "fractional-second ISO dates must parse")
        XCTAssertNotNil(records[0].dateCompleted)
    }

    func testMDMCommandsFlatArrayWithOtherSpellings() {
        let data = Data("""
            [{"command": "DeviceConfigured", "status": "Completed", "dateSent": "2026-09-25 09:15:22"}]
            """.utf8)
        let records = EnrollmentParsing.mdmCommands(data)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].status, .completed)
        XCTAssertEqual(EnrollmentParsing.phase(forCommand: records[0].commandType), .setupAssistant)
    }

    func testHistoryCommandsInBothClassicShapes() {
        // Arrays directly under completed/pending/failed.
        let flat = Data("""
            {"computer_history": {"commands": {
              "completed": [{"name": "InstallProfile", "completed_epoch": 1758791560000}],
              "pending": [{"name": "InstallApplication", "status": "Pending", "issued_epoch": 1758791970000}],
              "failed": [{"name": "InstallProfile", "status": "Certificate error", "issued_utc": "2026-09-25T09:16:15.000+0000",
                          "failed_epoch": 1758791780000}]
            }}}
            """.utf8)
        // XML-converted shape: {"command": {...}} for a single item.
        let wrapped = Data("""
            {"computer_history": {"commands": {
              "completed": {"command": [{"name": "InstallProfile", "completed_epoch": "1758791560000"}]},
              "pending": {"command": {"name": "InstallApplication", "issued_epoch": 1758791970000}},
              "failed": ""
            }}}
            """.utf8)
        let a = EnrollmentParsing.historyCommands(flat)
        XCTAssertEqual(a.map(\.status), [.completed, .pending, .failed])
        XCTAssertEqual(a[2].message, "Certificate error")
        XCTAssertEqual(a[0].finished, Date(timeIntervalSince1970: 1_758_791_560))

        let b = EnrollmentParsing.historyCommands(wrapped)
        XCTAssertEqual(b.map(\.status), [.completed, .pending])
        XCTAssertEqual(b[0].finished, Date(timeIntervalSince1970: 1_758_791_560), "epoch as a string")
    }

    func testPolicyLogsInBothShapes() {
        let flat = Data("""
            {"computer_history": {"policy_logs": [
              {"policy_id": 7, "policy_name": "Configure Login Window", "status": "Completed", "date_completed_epoch": 1758791880000},
              {"policy_id": 9, "policy_name": "Install Printer Drivers", "status": "Failed", "date_completed_epoch": 1758791900000}
            ]}}
            """.utf8)
        let wrapped = Data("""
            {"computer_history": {"policy_logs": {"policy_log": {"policy_id": "7", "policy_name": "Configure Login Window",
              "status": "Completed", "date_completed_utc": "2026-09-25T09:18:00.000+0000"}}}}
            """.utf8)
        let a = EnrollmentParsing.policyLogs(flat)
        XCTAssertEqual(a.map(\.policyID), [7, 9])
        XCTAssertEqual(a.map(\.failed), [false, true])
        let b = EnrollmentParsing.policyLogs(wrapped)
        XCTAssertEqual(b.first?.policyID, 7)
        XCTAssertNotNil(b.first?.date)
    }

    func testPrestageDetail() throws {
        let data = Data("""
            {"id": "1", "displayName": "MacBook Pro - Standard", "isMandatory": true, "isMdmRemovable": false,
             "skipSetupItems": {"Siri": true, "Location": false, "iCloudStorage": true},
             "prestageInstalledProfileIds": ["10", 11], "customPackageIds": ["1"],
             "enrollmentCustomizationId": "0", "deviceEnrollmentProgramInstanceId": "A1",
             "accountSettings": {"userAccountType": "STANDARD"}}
            """.utf8)
        let p = try XCTUnwrap(EnrollmentParsing.prestageDetail(data))
        XCTAssertEqual(p.profileIDs, [10, 11])
        XCTAssertEqual(p.packageIDs, [1])
        XCTAssertEqual(p.skippedPanes, ["Siri", "iCloudStorage"])
        XCTAssertEqual(p.shownPanes, ["Location"])
        XCTAssertNil(p.customizationID, "0 means no customization")
        XCTAssertTrue(p.facts.contains(.init(label: "MDM profile removable", value: "No")))
        XCTAssertTrue(p.facts.contains(.init(label: "Local account", value: "Standard")))
    }

    func testEnrollmentMethodObjectAndString() {
        XCTAssertEqual(EnrollmentParsing.enrollmentMethod(["id": "3", "objectName": "Lab"]).name, "Lab")
        XCTAssertEqual(EnrollmentParsing.enrollmentMethod(["id": "3", "objectName": "Lab"]).id, "3")
        XCTAssertEqual(EnrollmentParsing.enrollmentMethod("PreStage").name, "PreStage")
    }

    func testReadableCommandAndPanes() {
        XCTAssertEqual(EnrollmentParsing.readableCommand("INSTALL_PROFILE"), "Install Profile")
        XCTAssertEqual(EnrollmentParsing.readableCommand("InstallEnterpriseApplication"), "Install Enterprise Application")
        XCTAssertEqual(EnrollmentAnalyzer.readablePane("TermsOfAddress"), "Terms Of Address")
        XCTAssertEqual(EnrollmentAnalyzer.readablePane("iCloudStorage"), "iCloud Storage")
        XCTAssertEqual(EnrollmentAnalyzer.readablePane("TOS"), "TOS")
    }

    func testLogFlushingRetention() {
        let data = Data("""
            {"retentionPolicies": [
              {"displayName": "Computer Management History", "retentionPeriod": 3, "retentionPeriodUnit": "MONTH"},
              {"displayName": "Policy Logs", "retentionPeriod": 2, "retentionPeriodUnit": "WEEK"},
              {"displayName": "Mobile Device Usage Logs", "retentionPeriod": 1, "retentionPeriodUnit": "DAY"}
            ]}
            """.utf8)
        let r = EnrollmentParsing.historyRetention(data)
        XCTAssertEqual(r?.name, "Policy Logs")
        XCTAssertEqual(r?.days, 14)
        XCTAssertEqual(r?.label, "2 weeks")
    }
}

/// Shapes seen on a real Jamf Pro instance (values made up).
final class EnrollmentRealShapeTests: XCTestCase {

    func testMDMListAsReturnedByJamfPro() {
        let data = Data("""
            [{"uuid": "1", "commandState": "ACKNOWLEDGED", "commandType": "INSTALL_PROFILE", "profileId": 419,
              "client": {"managementId": "8f406756-bd08-4a0c-bad2-7eb1082b54f5", "clientType": "COMPUTER"},
              "dateSent": "2026-09-09T08:55:59.202Z", "dateCompleted": "2026-09-09T08:55:59.653Z", "commandError": {}},
             {"uuid": "2", "commandState": "PENDING", "commandType": "DEVICE_INFORMATION",
              "dateSent": "2026-09-17T08:39:12.332Z", "dateCompleted": "1970-01-01T00:00:00Z", "commandError": {}}]
            """.utf8)
        let r = EnrollmentParsing.mdmCommands(data)
        XCTAssertEqual(r[0].profileID, 419)
        XCTAssertNil(r[0].errorText, "an empty commandError object is no error")
        XCTAssertNil(r[1].dateCompleted, "1970 means not completed")
        XCTAssertEqual(r[1].status, .pending)
        XCTAssertEqual(EnrollmentParsing.phase(forCommand: "DEVICE_INFORMATION"), .inventory)
        XCTAssertEqual(EnrollmentParsing.phase(forCommand: "MANAGED_APPLICATION_LIST"), .inventory)
        XCTAssertEqual(EnrollmentParsing.phase(forCommand: "INSTALL_APPLICATION"), .apps)
        XCTAssertEqual(EnrollmentParsing.errorText(["code": 12021, "localizedDescription": "Certificate error"]),
                       "Certificate error · 12021")
    }

    func testHistoryWithoutWrapperAndProfileNames() {
        let data = Data("""
            {"commands": {
              "completed": {"command": [
                {"name": "Install Configuration Profile ALL - Wi-Fi", "completed": "2026/09/09 at 8:56 AM",
                 "completed_epoch": 1789030560000, "completed_utc": "2026-09-09T08:56:00.000+0000", "username": ""}]},
              "pending": {"command": {"name": "DeviceInformation", "issued_epoch": 1789634352332, "status": "Pending"}},
              "failed": ""}}
            """.utf8)
        let r = EnrollmentParsing.historyCommands(data)
        XCTAssertEqual(r.first?.name, "InstallProfile")
        XCTAssertEqual(r.first?.subject, "ALL - Wi-Fi")
        XCTAssertEqual(r.count, 2)
    }

    func testHistoryNamesTheMatchingAPICommand() {
        let sent = Date(timeIntervalSince1970: 1_789_030_000)
        var input = EnrollmentAnalyzer.TimelineInput()
        input.mdmCommands = [MDMCommandRecord(uuid: "1", commandType: "INSTALL_PROFILE", status: .completed,
                                              dateSent: sent, dateCompleted: sent.addingTimeInterval(300),
                                              profileIdentifier: nil, profileID: 419, errorText: nil)]
        // History has only the completion time, 5 minutes after the command was sent.
        input.historyCommands = [HistoryCommandRecord(name: "InstallProfile", subject: "ALL - Wi-Fi", status: .completed,
                                                      issued: sent.addingTimeInterval(300), finished: sent.addingTimeInterval(300),
                                                      message: nil)]
        let events = EnrollmentAnalyzer.buildEvents(input, now: sent.addingTimeInterval(3600))
        XCTAssertEqual(events.count, 1, "matched on completion time")
        XCTAssertEqual(events.first?.title, "ALL - Wi-Fi")
    }

    func testUserInitiatedEnrollmentMethod() {
        let m = EnrollmentParsing.enrollmentMethod(["id": "359", "objectName": NSNull(), "objectType": "User-initiated - no invitation"])
        XCTAssertEqual(m.name, "User-initiated - no invitation")
        XCTAssertFalse(EnrollmentParsing.isPrestageMethod(type: m.type, viaADE: false),
                       "the invitation ID must not be taken for a PreStage ID")
        XCTAssertTrue(EnrollmentParsing.isPrestageMethod(type: "Computer PreStage", viaADE: nil))
        XCTAssertEqual(EnrollmentParsing.lastContact(["lastContact": "2026-09-17T10:46:41.489Z"]),
                       try? Date("2026-09-17T10:46:41.489Z", strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
    }
}

final class SetupManagerTests: XCTestCase {
    /// As Jamf Pro stores it: a custom settings payload with the settings under Forced.
    private let payloads = """
        <?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>PayloadContent</key><array>
        <dict><key>PayloadType</key><string>com.apple.ManagedClient.preferences</string><key>PayloadContent</key><dict>
        <key>com.jamf.setupmanager</key><dict><key>Forced</key><array><dict><key>mcx_preference_settings</key><dict>
        <key>runAt</key><string>loginwindow</string><key>finalAction</key><string>restart</string>
        <key>finishedTrigger</key><string>sm_done</string>
        <key>enrollmentActions</key><array>
          <dict><key>label</key><string>Rosetta 2</string><key>policy</key><string>EnrollRosetta2</string></dict>
          <dict><key>label</key><string>Teams</string><key>installomator</key><string>microsoftteams</string></dict>
          <dict><key>label</key><string>Time zone</string><key>shell</key><string>/usr/sbin/systemsetup</string>
                <key>arguments</key><array><string>-setTimeZone</string><string>Europe/Brussels</string></array></dict>
          <dict><key>label</key><string>Protect</string><key>watchPath</key><string>/Applications/JamfProtect.app</string></dict>
          <dict><key>label</key><string>Wait</string><key>wait</key><integer>20</integer></dict>
          <dict><key>label</key><string>Inventory</string><key>recon</key><true/></dict>
          <dict><key>label</key><string>Check-in</string><key>policy</key><string></string></dict>
        </array></dict></dict></array></dict></dict></dict></array></dict></plist>
        """

    func testParsesStepsFromCustomSettingsPayload() throws {
        let config = try XCTUnwrap(EnrollmentParsing.setupManager(payloads: payloads))
        XCTAssertEqual(config.steps.map(\.kind), [.policy, .installomator, .shell, .watchPath, .wait, .recon, .policy])
        XCTAssertEqual(config.steps[0].value, "EnrollRosetta2")
        XCTAssertEqual(config.steps[2].value, "/usr/sbin/systemsetup -setTimeZone Europe/Brussels")
        XCTAssertEqual(config.steps[4].value, "20")
        XCTAssertNil(config.steps[5].value)
        XCTAssertEqual(config.finishedTrigger, "sm_done")
        XCTAssertEqual(config.runAtLabel, "Starts at the login window")
        XCTAssertEqual(config.finalActionLabel, "Restarts the Mac when done")
        XCTAssertNil(EnrollmentParsing.setupManager(payloads: "<plist><dict/></plist>"))
    }

    private func scan(profiles: [ScopedProfile], policies: [ScopedPolicy] = []) -> ScopeScanResult {
        ScopeScanResult(profiles: profiles, policies: policies, failures: 0, scannedAt: Date())
    }

    private func smProfile(_ id: Int, all: Bool = false) -> ScopedProfile {
        var p = ScopedProfile(id: id, name: "SM \(id)", identifier: nil, scope: JamfScope(allComputers: all))
        p.setupManager = EnrollmentParsing.setupManager(payloads: payloads)
        return p
    }

    func testChoosesTheRightProfile() {
        let s = scan(profiles: [smProfile(1), smProfile(2, all: true), smProfile(3),
                                ScopedProfile(id: 4, name: "Other", identifier: nil, scope: JamfScope(allComputers: true))])
        let prestage = PrestageDetail(id: "1", name: "P", profileIDs: [3], packageIDs: [], skipItems: [:],
                                      customizationID: nil, adeInstanceID: nil, facts: [])
        XCTAssertEqual(EnrollmentAnalyzer.setupManagerCandidates(s).map(\.id), [1, 2, 3])
        XCTAssertEqual(EnrollmentAnalyzer.setupManagerSource(scan: s, preferredProfileID: 1, prestage: prestage)?.profileID, 1)
        XCTAssertEqual(EnrollmentAnalyzer.setupManagerSource(scan: s, preferredProfileID: nil, prestage: prestage,
                                                             installedProfileIDs: [2])?.profileID, 2)
        XCTAssertEqual(EnrollmentAnalyzer.setupManagerSource(scan: s, preferredProfileID: nil, prestage: prestage)?.profileID, 3)
        XCTAssertEqual(EnrollmentAnalyzer.setupManagerSource(scan: s, preferredProfileID: 99, prestage: nil)?.reason,
                       "Scoped to All Computers", "an unknown preference falls back to automatic")
        XCTAssertNil(EnrollmentAnalyzer.setupManagerSource(scan: scan(profiles: []), preferredProfileID: nil, prestage: nil))
    }

    func testStepStatusFromPolicyLogs() throws {
        var rosetta = ScopedPolicy(id: 11, name: "Install Rosetta 2", enabled: true, enrollmentTrigger: false,
                                   scope: JamfScope(allComputers: true))
        rosetta.customTrigger = "EnrollRosetta2"
        let s = scan(profiles: [smProfile(1)], policies: [rosetta])
        let source = try XCTUnwrap(EnrollmentAnalyzer.setupManagerSource(scan: s, preferredProfileID: nil, prestage: nil))
        XCTAssertEqual(EnrollmentAnalyzer.setupManagerPolicyIDs(source, scan: s), [11: "Rosetta 2"])

        let log = EnrollmentEvent(id: "p", date: Date(), completedDate: nil, phase: .setupManager, kind: "Setup Manager · Rosetta 2",
                                  title: "Install Rosetta 2", detail: nil, status: .completed, isApproximate: false,
                                  source: .policyLogs, profileIdentifier: nil)
        let rows = EnrollmentAnalyzer.setupManagerRows(source, scan: s, events: [log])
        XCTAssertEqual(rows[0].status, .completed)
        XCTAssertEqual(rows[0].policies, ["Install Rosetta 2"])
        XCTAssertNil(rows[1].status, "Installomator steps aren't logged by Jamf Pro")
        XCTAssertEqual(rows[6].note, "Runs the Recurring Check-in policies")

        let none = EnrollmentAnalyzer.setupManagerRows(source, scan: s, events: [])
        XCTAssertEqual(none[0].status, .notRunYet)
        let flowRows = EnrollmentAnalyzer.setupManagerRows(source, scan: s, events: nil)
        XCTAssertNil(flowRows[0].status, "the flow shows no status")
    }

    func testTimelineMarksSetupManagerPolicies() {
        var input = EnrollmentAnalyzer.TimelineInput()
        input.policyLogs = [PolicyLogRecord(policyID: 11, name: "Install Rosetta 2", status: "Completed", date: Date())]
        input.setupManagerPolicies = [11: "Rosetta 2"]
        let e = EnrollmentAnalyzer.buildEvents(input).first
        XCTAssertEqual(e?.phase, .setupManager)
        XCTAssertEqual(e?.kind, "Setup Manager · Rosetta 2")
    }

    func testDemoHasSetupManager() async throws {
        let repo = EnrollmentRepository(cli: DemoCLIManager())
        let scan = try await repo.scanScopes { _, _ in }
        let prestageDetail = try await repo.prestageDetail(id: "1")
        let source = try XCTUnwrap(EnrollmentAnalyzer.setupManagerSource(scan: scan, preferredProfileID: nil,
                                                                         prestage: prestageDetail))
        XCTAssertEqual(source.profileName, "Jamf Setup Manager")
        let timeline = try await repo.timeline(serial: "C02XA001DEMO",
                                               setupManagerPolicies: EnrollmentAnalyzer.setupManagerPolicyIDs(source, scan: scan))
        let rows = EnrollmentAnalyzer.setupManagerRows(source, scan: scan, events: timeline.events)
        XCTAssertEqual(rows.map(\.status), [.completed, .completed, .completed, .completed, .notRunYet, nil, nil])
        let flow = EnrollmentAnalyzer.buildFlow(.init(prestage: try XCTUnwrap(prestageDetail), scan: scan, setupManager: source))
        XCTAssertEqual(flow.phases.first { $0.phase == .setupManager }?.items.count, 7)
    }
}

/// Device Lookup's detail by serial asked for sections Jamf Pro rejects (HTTP 400).
final class ComputerDetailSectionTests: XCTestCase {
    private let validSections: Set<String> = [
        "GENERAL", "DISK_ENCRYPTION", "PURCHASING", "APPLICATIONS", "STORAGE", "USER_AND_LOCATION",
        "CONFIGURATION_PROFILES", "PRINTERS", "SERVICES", "HARDWARE", "LOCAL_USER_ACCOUNTS", "CERTIFICATES",
        "ATTACHMENTS", "PLUGINS", "PACKAGE_RECEIPTS", "FONTS", "SECURITY", "OPERATING_SYSTEM", "LICENSED_SOFTWARE",
        "IBEACONS", "SOFTWARE_UPDATES", "EXTENSION_ATTRIBUTES", "CONTENT_CACHING", "GROUP_MEMBERSHIPS",
    ]

    func testInventoryCommandsOnlyUseValidSections() {
        let commands: [CLICommand] = [.computerDetail(serial: "A"), .computers, .securityInventory, .ddmComputers,
                                      .computersUpdateReadiness, .recentEnrollments, .enrollmentInventory(serial: "A")]
        for c in commands {
            let args = c.baseArguments
            for (i, a) in args.enumerated() where a == "--section" {
                XCTAssertTrue(validSections.contains(args[i + 1]), "\(args[i + 1]) is not a Jamf Pro inventory section")
            }
        }
    }

    func testUserAndLocationDecodes() throws {
        let data = Data("""
            {"id": "1", "general": {"name": "Mac"}, "userAndLocation": {"username": "ann", "realname": "Ann Peeters",
             "email": "ann@example.com", "departmentId": "4", "buildingId": 2, "room": "3.14"}}
            """.utf8)
        let d = try JSONDecoder().decode(ComputerDetail.self, from: data)
        XCTAssertEqual(d.location?.realName, "Ann Peeters")
        XCTAssertEqual(d.location?.departmentId, "4")
        XCTAssertEqual(d.location?.buildingId, "2")
    }
}

final class EnrollmentCLISafetyTests: XCTestCase {

    func testManagementIDMustBeAUUIDAndIsFiltered() {
        XCTAssertTrue(EnrollmentParsing.isManagementID("aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb"))
        XCTAssertFalse(EnrollmentParsing.isManagementID("x;status==Pending"))
        XCTAssertFalse(EnrollmentParsing.isManagementID(""))
        let args = CLICommand.mdmCommandsForDevice(managementId: "aaaa;command==X,b").baseArguments
        XCTAssertEqual(args[4], "clientManagementId==aaaacadb", "only hex digits and dashes reach the filter")
        XCTAssertFalse(args[4].dropFirst("clientManagementId==".count).contains { $0 == ";" || $0 == "=" || $0 == "," })
    }

    func testSerialAndPrestageIDAreSanitized() {
        let history = CLICommand.computerHistory(serial: "C02 --url x", subset: .commands).baseArguments
        XCTAssertEqual(history, ["pro", "classic-computer-history", "get", "--serial=C02 --url x",
                                 "--subset", "Commands", "-o", "json"], "the serial stays inside one --serial= argument")
        XCTAssertEqual(CLICommand.computerPrestageDetail(id: "1 --yes").baseArguments,
                       ["pro", "computer-prestages", "get", "-o", "json", "--", "1"])
        let inventory = CLICommand.enrollmentInventory(serial: #"A"B"#).baseArguments
        XCTAssertTrue(inventory.contains(#"hardware.serialNumber=="A\"B""#))
    }

    func testEnrollmentCommandsAreReadOnly() {
        let commands: [CLICommand] = [
            .recentEnrollments, .enrollmentInventory(serial: "A"), .mdmCommandsForDevice(managementId: "a"),
            .computerHistory(serial: "A", subset: .policyLogs), .computerPrestageDetail(id: "1"), .logFlushingSettings,
        ]
        for c in commands {
            XCTAssertFalse(c.isDestructive)
            XCTAssertFalse(c.baseArguments.contains("--yes"))
            XCTAssertTrue(c.baseArguments.contains("list") || c.baseArguments.contains("get"), "\(c.baseArguments)")
        }
    }
}

final class EnrollmentAnalyzerTests: XCTestCase {
    private let enrolled = Date(timeIntervalSince1970: 1_758_791_523)   // 25 Sep 2026 09:12:03 UTC
    private var now: Date { enrolled.addingTimeInterval(2 * 86_400) }

    private func input() -> EnrollmentAnalyzer.TimelineInput {
        var i = EnrollmentAnalyzer.TimelineInput()
        i.enrolledAt = enrolled
        i.method = "MacBook Pro - Standard"
        i.lastContact = now.addingTimeInterval(-600)
        i.mdmCommands = [
            MDMCommandRecord(uuid: "1", commandType: "INSTALL_PROFILE", status: .completed,
                             dateSent: enrolled.addingTimeInterval(37), dateCompleted: enrolled.addingTimeInterval(40),
                             profileIdentifier: "ca", errorText: nil),
            MDMCommandRecord(uuid: "2", commandType: "INSTALL_PROFILE", status: .failed,
                             dateSent: enrolled.addingTimeInterval(252), dateCompleted: nil,
                             profileIdentifier: "wifi", errorText: "Certificate error"),
            MDMCommandRecord(uuid: "3", commandType: "INSTALL_APPLICATION", status: .pending,
                             dateSent: enrolled.addingTimeInterval(447), dateCompleted: nil,
                             profileIdentifier: nil, errorText: nil),
        ]
        i.historyCommands = [
            // Same as the first API command, 2 seconds apart: must not appear twice.
            HistoryCommandRecord(name: "InstallProfile", status: .completed, issued: enrolled.addingTimeInterval(39),
                                 finished: enrolled.addingTimeInterval(40), message: nil),
            HistoryCommandRecord(name: "DeviceConfigured", status: .completed, issued: enrolled.addingTimeInterval(199),
                                 finished: enrolled.addingTimeInterval(200), message: nil),
        ]
        i.policyLogs = [PolicyLogRecord(policyID: 7, name: "Configure Login Window", status: "Completed",
                                        date: enrolled.addingTimeInterval(359))]
        i.installedProfiles = [
            .init(name: "Internal CA", identifier: "ca", installedAt: enrolled.addingTimeInterval(40)),
            .init(name: "FileVault", identifier: "fv", installedAt: enrolled.addingTimeInterval(300)),
        ]
        i.enrollmentPolicyIDs = [7]
        return i
    }

    func testTimelineMergesSourcesInOrder() {
        let events = EnrollmentAnalyzer.buildEvents(input(), now: now)
        XCTAssertEqual(events.first?.title, "Enrolled in MDM")
        XCTAssertEqual(events.map(\.date), events.map(\.date).sorted())
        XCTAssertEqual(events.filter { EnrollmentParsing.commandKey($0.kind) == "installprofile" }.count, 2,
                       "the history duplicate of the first InstallProfile is dropped")
        XCTAssertEqual(events.first { $0.profileIdentifier == "ca" && $0.source == .mdmCommands }?.title, "Internal CA",
                       "profile commands are named after the installed profile")
        let setup = events.first { $0.id == "setup-finished" }
        XCTAssertEqual(setup?.isApproximate, true)
        XCTAssertEqual(events.first { $0.source == .policyLogs }?.kind, "Enrollment policy")
        XCTAssertTrue(events.contains { $0.title == "FileVault" && $0.source == .inventory },
                      "installed profiles without a command still appear")
    }

    func testStuckNeedsFourHoursAndALaterCheckIn() {
        let events = EnrollmentAnalyzer.buildEvents(input(), now: now)
        XCTAssertEqual(events.first { $0.kind == "Install Application" }?.status, .stuck)

        // Pending for under 4 hours: still pending.
        let recent = EnrollmentAnalyzer.buildEvents(input(), now: enrolled.addingTimeInterval(447 + 3 * 3600))
        XCTAssertEqual(recent.first { $0.kind == "Install Application" }?.status, .pending)

        // Mac hasn't checked in since the command was sent: pending, not stuck.
        var offline = input()
        offline.lastContact = enrolled.addingTimeInterval(400)
        let events2 = EnrollmentAnalyzer.buildEvents(offline, now: now)
        XCTAssertEqual(events2.first { $0.kind == "Install Application" }?.status, .pending)

        // Exactly the threshold counts as stuck.
        let edge = EnrollmentAnalyzer.markStuck(
            [EnrollmentEvent(id: "x", date: now.addingTimeInterval(-EnrollmentAnalyzer.stuckThreshold), completedDate: nil,
                             phase: .apps, kind: "Install Application", title: "App", detail: nil, status: .pending,
                             isApproximate: false, source: .mdmCommands, profileIdentifier: nil)],
            lastContact: now, now: now)
        XCTAssertEqual(edge.first?.status, .stuck)
    }

    func testAttentionListsFailuresFirst() {
        let events = EnrollmentAnalyzer.buildEvents(input(), now: now)
        XCTAssertEqual(EnrollmentAnalyzer.attention(events).map(\.status), [.failed, .stuck])
    }

    func testWindowKeepsFailuresAndPendingItems() {
        var i = input()
        i.mdmCommands.append(MDMCommandRecord(uuid: "late", commandType: "INSTALL_PROFILE", status: .completed,
                                              dateSent: enrolled.addingTimeInterval(3 * 86_400), dateCompleted: nil,
                                              profileIdentifier: nil, errorText: nil))
        let events = EnrollmentAnalyzer.buildEvents(i, now: now)
        let day = EnrollmentAnalyzer.eventsInWindow(events, enrolledAt: enrolled, window: 86_400)
        XCTAssertFalse(day.contains { $0.id == "mdm-late" })
        XCTAssertTrue(day.contains { $0.status == .stuck })
        XCTAssertTrue(EnrollmentAnalyzer.eventsInWindow(events, enrolledAt: enrolled, window: nil).contains { $0.id == "mdm-late" })
    }

    func testRelativeTimes() {
        XCTAssertEqual(EnrollmentAnalyzer.relative(enrolled.addingTimeInterval(37), to: enrolled), "+0:37")
        XCTAssertEqual(EnrollmentAnalyzer.relative(enrolled.addingTimeInterval(3 * 3600 + 720), to: enrolled), "+3h 12m")
        XCTAssertEqual(EnrollmentAnalyzer.relative(enrolled.addingTimeInterval(2 * 86_400 + 4 * 3600), to: enrolled), "+2d 4h")
    }

    // MARK: Scope

    private func scope(all: Bool = false, groups: [String] = [], excluded: [String] = [],
                       departments: [String] = []) -> JamfScope {
        JamfScope(allComputers: all,
                  computerGroups: groups.enumerated().map { JamfScopeItem(id: $0.offset, name: $0.element) },
                  departments: departments.enumerated().map { JamfScopeItem(id: $0.offset, name: $0.element) },
                  exclusions: JamfScopeExclusions(computerGroups: excluded.enumerated().map { JamfScopeItem(id: $0.offset, name: $0.element) }))
    }

    func testScopeMatchForOneMac() {
        let mac = EnrollmentAnalyzer.DeviceContext(computerID: 1, name: "Alice", groups: ["All Managed Macs"],
                                                   department: "Engineering", building: nil)
        XCTAssertEqual(EnrollmentAnalyzer.match(scope(all: true), device: mac), .applies("All Computers"))
        XCTAssertEqual(EnrollmentAnalyzer.match(scope(groups: ["all managed macs"]), device: mac), .applies("Member of “all managed macs”"))
        XCTAssertEqual(EnrollmentAnalyzer.match(scope(all: true, excluded: ["All Managed Macs"]), device: mac),
                       .excluded("Excluded by “All Managed Macs”"))
        XCTAssertEqual(EnrollmentAnalyzer.match(scope(departments: ["Engineering"]), device: mac), .applies("Department “Engineering”"))
        XCTAssertEqual(EnrollmentAnalyzer.match(scope(groups: ["Beta"]), device: mac), .notScoped("Not in “Beta”"))
    }

    func testFlowCertainty() {
        XCTAssertEqual(EnrollmentAnalyzer.flowCondition(scope(all: true))?.0, .certain)
        XCTAssertEqual(EnrollmentAnalyzer.flowCondition(scope(all: true, excluded: ["Kiosks"]))?.0, .conditional)
        XCTAssertEqual(EnrollmentAnalyzer.flowCondition(scope(groups: ["Engineering"]))?.1, "If in “Engineering”")
        XCTAssertNil(EnrollmentAnalyzer.flowCondition(JamfScope(computers: [JamfScopeItem(id: 1, name: "One")])),
                     "items for named Macs only are left out of the flow")
    }

    // MARK: Expected vs actual

    private func timeline(events: [EnrollmentEvent], installed: [EnrollmentTimeline.InstalledProfile],
                          prestageProfiles: [Int] = []) -> EnrollmentTimeline {
        EnrollmentTimeline(
            device: .init(computerID: "1", name: "Alice", serial: "AAA111", managementId: nil, enrolledAt: enrolled,
                          firstSeenAt: nil, lastContact: now, method: nil, methodID: nil, supervised: true,
                          userApprovedMDM: true, groups: ["All Managed Macs"], department: nil, building: nil),
            events: events, sources: [:], installedProfiles: installed, ddm: nil,
            prestage: PrestageDetail(id: "1", name: "P", profileIDs: prestageProfiles, packageIDs: [], skipItems: [:],
                                     customizationID: nil, adeInstanceID: nil, facts: []),
            historyRetention: nil, loadedAt: now)
    }

    func testProfileRowsCompareExpectedWithInstalled() {
        let events = EnrollmentAnalyzer.buildEvents(input(), now: now)
        let installed: [EnrollmentTimeline.InstalledProfile] = [
            .init(name: "Internal CA", identifier: "ca", installedAt: enrolled),
            .init(name: "Legacy Proxy", identifier: "proxy", installedAt: enrolled),
            .init(name: "MDM Profile", identifier: "mdm", installedAt: enrolled),
        ]
        let scan = ScopeScanResult(profiles: [
            ScopedProfile(id: 10, name: "Internal CA", identifier: "ca", scope: scope(groups: ["Nobody"])),
            ScopedProfile(id: 5, name: "Wi-Fi", identifier: "wifi", scope: scope(all: true)),
            ScopedProfile(id: 4, name: "Energy Saver", identifier: "energy", scope: scope(groups: ["All Managed Macs"])),
            ScopedProfile(id: 6, name: "VPN", identifier: "vpn", scope: scope(groups: ["Engineering VPN"])),
            ScopedProfile(id: 20, name: "Legacy Proxy", identifier: "proxy", scope: scope(groups: ["Old Macs"])),
        ], policies: [], failures: 0, scannedAt: now)

        let rows = EnrollmentAnalyzer.profileRows(timeline: timeline(events: events, installed: installed, prestageProfiles: [10]),
                                                  events: events, scan: scan)
        func status(_ name: String) -> ProfileRowStatus? { rows.first { $0.name == name }?.status }
        XCTAssertEqual(status("Internal CA"), .installed, "PreStage profiles are expected regardless of scope")
        XCTAssertEqual(rows.first { $0.name == "Internal CA" }?.source, "PreStage")
        XCTAssertEqual(status("Wi-Fi"), .failed)
        XCTAssertEqual(status("Energy Saver"), .missing)
        XCTAssertEqual(status("VPN"), .notScoped)
        XCTAssertEqual(status("Legacy Proxy"), .unexpected)
        XCTAssertEqual(status("MDM Profile"), .installed)
        XCTAssertEqual(rows.first?.status, .failed, "problems sort first")
    }

    func testProfileRowsWithoutScanShowInstalledAndFailed() {
        let events = EnrollmentAnalyzer.buildEvents(input(), now: now)
        let rows = EnrollmentAnalyzer.profileRows(
            timeline: timeline(events: events, installed: [.init(name: "Internal CA", identifier: "ca", installedAt: enrolled)]),
            events: events, scan: nil)
        XCTAssertEqual(rows.map(\.status), [.failed, .installed])
        XCTAssertEqual(rows.first?.name, "wifi")
    }

    func testPolicyRowsFlagEnrollmentPoliciesWithoutALog() {
        let events = EnrollmentAnalyzer.buildEvents(input(), now: now)
        let scan = ScopeScanResult(profiles: [], policies: [
            ScopedPolicy(id: 7, name: "Configure Login Window", enabled: true, enrollmentTrigger: true, scope: scope(all: true)),
            ScopedPolicy(id: 11, name: "Install Rosetta 2", enabled: true, enrollmentTrigger: true, scope: scope(all: true)),
            ScopedPolicy(id: 12, name: "Disabled", enabled: false, enrollmentTrigger: true, scope: scope(all: true)),
            ScopedPolicy(id: 13, name: "Other group", enabled: true, enrollmentTrigger: true, scope: scope(groups: ["X"])),
        ], failures: 0, scannedAt: now)
        let rows = EnrollmentAnalyzer.policyRows(timeline: timeline(events: events, installed: []), events: events, scan: scan)
        XCTAssertEqual(rows.map(\.name), ["Install Rosetta 2", "Configure Login Window"])
        XCTAssertEqual(rows.map(\.status), [.notRunYet, .completed])
    }

    func testFlowForPrestage() {
        let prestage = PrestageDetail(id: "1", name: "Std", profileIDs: [10], packageIDs: [1],
                                      skipItems: ["Siri": true, "Location": false], customizationID: "2",
                                      adeInstanceID: "T", facts: [.init(label: "MDM profile removable", value: "No")])
        let scan = ScopeScanResult(profiles: [
            ScopedProfile(id: 10, name: "CA", identifier: nil, scope: scope(all: true)),
            ScopedProfile(id: 2, name: "FileVault", identifier: nil, scope: scope(all: true)),
            ScopedProfile(id: 6, name: "VPN", identifier: nil, scope: scope(groups: ["Eng"])),
            ScopedProfile(id: 7, name: "Kiosk", identifier: nil, scope: JamfScope(computers: [JamfScopeItem(id: 1, name: "K")])),
        ], policies: [
            ScopedPolicy(id: 1, name: "02 Rosetta", enabled: true, enrollmentTrigger: true, scope: scope(all: true)),
            ScopedPolicy(id: 2, name: "01 Name", enabled: true, enrollmentTrigger: true, scope: scope(all: true)),
            ScopedPolicy(id: 3, name: "Check-in", enabled: true, enrollmentTrigger: false, scope: scope(all: true)),
        ], failures: 0, scannedAt: now)
        let flow = EnrollmentAnalyzer.buildFlow(.init(prestage: prestage, adeTokenName: "Acme",
                                                      profileNames: [10: "CA"], packageNames: [1: "Tools.pkg"],
                                                      checkInMinutes: 15, scan: scan))
        func phase(_ p: EnrollmentPhase) -> FlowPhase? { flow.phases.first { $0.phase == p } }
        XCTAssertEqual(phase(.adeAssignment)?.summary, "Token “Acme”")
        XCTAssertEqual(phase(.prestageItems)?.items.map(\.name), ["CA", "Tools.pkg"])
        XCTAssertEqual(phase(.profiles)?.items.map(\.name), ["FileVault", "VPN"], "PreStage profiles aren't listed twice")
        XCTAssertEqual(phase(.policies)?.items.map(\.name), ["01 Name", "02 Rosetta"], "enrollment policies in name order")
        XCTAssertEqual(flow.specificOnlyCount, 1)
        XCTAssertEqual(phase(.inventory)?.summary, "Check-in every 15 min")
        XCTAssertTrue(phase(.setupAssistant)?.lines.contains { $0.contains("Enrollment Customization 2") } == true)
    }
}

/// The demo data must decode through the same code as real data.
final class EnrollmentDemoTests: XCTestCase {

    func testDemoTimelineHasAFailureAndAStuckCommand() async throws {
        let repo = EnrollmentRepository(cli: DemoCLIManager())
        let recent = try await repo.recentEnrollments(withinDays: 7)
        XCTAssertEqual(recent.first?.serial, "C02XA001DEMO", "newest enrollment first")
        XCTAssertFalse(recent.contains { $0.serial == "C02XA008DEMO" }, "a 45-day-old enrollment is outside 7 days")

        let timeline = try await repo.timeline(serial: "C02XA001DEMO")
        XCTAssertEqual(timeline.device.name, "Alice's MacBook Pro")
        XCTAssertEqual(timeline.prestage?.name, "MacBook Pro - Standard")
        XCTAssertTrue(timeline.sources.values.allSatisfy(\.isOK), "\(timeline.sources)")
        let attention = EnrollmentAnalyzer.attention(timeline.events)
        XCTAssertEqual(attention.map(\.status), [.failed, .stuck])
        XCTAssertEqual(attention.first?.title, "Wi-Fi (Corporate)")
        XCTAssertTrue(timeline.events.contains { $0.id == "setup-finished" })
        XCTAssertEqual(timeline.historyRetention?.label, "3 months")
    }

    func testDemoScanAndFlow() async throws {
        let repo = EnrollmentRepository(cli: DemoCLIManager())
        let scan = try await repo.scanScopes { _, _ in }
        XCTAssertEqual(scan.failures, 0)
        XCTAssertTrue(scan.policies.contains { $0.enrollmentTrigger })
        let detail = try await repo.prestageDetail(id: "1")
        let prestage = try XCTUnwrap(detail)
        let flow = EnrollmentAnalyzer.buildFlow(.init(prestage: prestage, scan: scan))
        XCTAssertFalse(flow.phases.first { $0.phase == .profiles }?.items.isEmpty ?? true)

        let timeline = try await repo.timeline(serial: "C02XA001DEMO")
        let rows = EnrollmentAnalyzer.profileRows(timeline: timeline, events: timeline.events, scan: scan)
        XCTAssertEqual(rows.first { $0.name == "Wi-Fi (Corporate)" }?.status, .failed)
        XCTAssertEqual(rows.first { $0.name == "VPN Settings" }?.status, .notScoped)
        XCTAssertEqual(rows.first { $0.name == "Certificates - Internal CA" }?.source, "PreStage")
    }
}

/// Runs the timeline against a real Jamf Pro instance through jamf-cli (read-only commands).
/// Skipped unless `TEST_RUNNER_JAMFDASH_LIVE_SERIAL` (and optionally `…_LIVE_PROFILE`) are set.
final class EnrollmentLiveProbeTests: XCTestCase {
    private struct ShellCLI: SimulatedCLI {
        let profile: String?
        func run(_ command: CLICommand) async throws -> Data {
            let binary = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("JamfDash/bin/jamf-cli")
            let args = (profile.map { ["--profile", $0] } ?? []) + command.baseArguments
            var env = ProcessInfo.processInfo.environment
            env["JAMF_CLI_NO_UPDATE_CHECK"] = "1"
            return try await CLIExecutor().execute(binary: binary, arguments: args, environment: env,
                                                   stdinData: nil, timeout: command.timeout)
        }
        func run(_ command: CLICommand, outputFormat: ReportOutputFormat) async throws -> Data { try await run(command) }
    }

    func testLiveTimeline() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let serial = env["JAMFDASH_LIVE_SERIAL"], !serial.isEmpty else { throw XCTSkip("no live serial") }
        let repo = EnrollmentRepository(cli: ShellCLI(profile: env["JAMFDASH_LIVE_PROFILE"]))
        let t = try await repo.timeline(serial: serial)
        let events = t.events
        print("LIVE sources: \(t.sources.map { "\($0.key.rawValue)=\($0.value)" }.sorted())")
        print("LIVE method=\(t.device.method ?? "-") prestage=\(t.prestage?.name ?? "-") lastContact=\(t.device.lastContact != nil) dept=\(t.device.department != nil) groups=\(t.device.groups.count)")
        print("LIVE events=\(events.count) byPhase=\(Dictionary(grouping: events, by: \.phase.title).mapValues(\.count).sorted { $0.key < $1.key })")
        print("LIVE status=\(Dictionary(grouping: events, by: \.status.rawValue).mapValues(\.count))")
        print("LIVE profile commands named=\(events.filter { $0.phase == .profiles && $0.title != $0.kind }.count)/\(events.filter { $0.phase == .profiles }.count)")
        print("LIVE retention=\(t.historyRetention?.label ?? "-") installed=\(t.installedProfiles.count) ddm=\(t.ddm?.itemCount ?? 0)")
        print("LIVE summary:\n" + EnrollmentAnalyzer.summary(t).split(separator: "\n").dropFirst().joined(separator: "\n"))
        XCTAssertFalse(events.isEmpty)

        guard env["JAMFDASH_LIVE_SCAN"] == "1" else { return }
        let start = Date()
        let scan = try await repo.scanScopes { _, _ in }
        print("LIVE scan \(Int(Date().timeIntervalSince(start)))s: \(scan.profiles.count) profiles, \(scan.policies.count) policies, \(scan.failures) failed, enrollment policies \(scan.policies.filter { $0.enrollmentTrigger && $0.enabled }.count)")
        let rows = EnrollmentAnalyzer.profileRows(timeline: t, events: t.events, scan: scan)
        print("LIVE profile rows: \(Dictionary(grouping: rows, by: \.status.label).mapValues(\.count))")
        let policies = EnrollmentAnalyzer.policyRows(timeline: t, events: t.events, scan: scan)
        print("LIVE policy rows: \(Dictionary(grouping: policies, by: \.status.label).mapValues(\.count))")
        let installed = Set(t.installedProfiles.compactMap(\.jamfID))
        print("LIVE setup manager candidates: \(EnrollmentAnalyzer.setupManagerCandidates(scan).map { "\($0.id) \($0.name) (\($0.setupManager!.steps.count))" })")
        if let sm = EnrollmentAnalyzer.setupManagerSource(scan: scan, preferredProfileID: nil, prestage: t.prestage,
                                                          installedProfileIDs: installed) {
            print("LIVE setup manager: \(sm.profileName) — \(sm.reason)")
            let t2 = try await repo.timeline(serial: serial, setupManagerPolicies: EnrollmentAnalyzer.setupManagerPolicyIDs(sm, scan: scan))
            for row in EnrollmentAnalyzer.setupManagerRows(sm, scan: scan, events: t2.events) {
                print("LIVE   \(row.step.id + 1). \(row.step.label) [\(row.step.kind.title)] → \(row.status?.label ?? "—") \(row.policies.count) policies \(row.note)")
            }
        }
        if let p = t.prestage {
            let flow = EnrollmentAnalyzer.buildFlow(.init(prestage: p, scan: scan))
            print("LIVE flow: " + flow.phases.map { "\($0.phase.title)=\($0.summary) [\($0.items.count)]" }.joined(separator: " | "))
        }
    }
}
