import XCTest
@testable import JamfDash

/// Checks the arguments Jamf Dash passes to jamf-cli: commands that exist, values that
/// can't turn into flags, and the risk level of every action.
final class CLIContractTests: XCTestCase {

    private let hostile = "-x --url https://evil.example --yes"

    func testSerialValuesStayInOneArgument() {
        let commands: [CLICommand] = [
            .blankPush(serial: hostile), .renewMDM(serial: hostile), .ddmSync(serial: hostile),
            .flushFailedCommands(serial: hostile), .flushAllCommands(serial: hostile),
            .redeployFramework(serial: hostile), .restart(serial: hostile), .shutdown(serial: hostile),
            .removeMDM(serial: hostile), .clearRecoveryLock(serial: hostile), .erase(serial: hostile),
            .mobileDeviceErase(serial: hostile), .mobileDeviceLock(serial: hostile),
            .mobileDeviceRestart(serial: hostile), .mobileDeviceUnmanage(serial: hostile),
            .mobileDeviceEnableLostMode(serial: hostile, message: hostile, phone: "", footnote: ""),
        ]
        for command in commands {
            let args = command.baseArguments
            XCTAssertFalse(args.contains("--url"), "\(args)")
            XCTAssertEqual(args.filter { $0 == "--yes" }.count, 1, "\(args)")
            XCTAssertTrue(args.contains("--serial=" + hostile), "\(args)")
        }
    }

    func testControlCharactersAreRemoved() {
        let args = CLICommand.blankPush(serial: " C02\nX\u{0}Y ").baseArguments
        XCTAssertTrue(args.contains("--serial=C02XY"), "\(args)")
    }

    func testPositionalValuesFollowSeparator() {
        let commands: [CLICommand] = [
            .computerDetailById(id: "-v"), .smartGroupDetail(id: "-v"), .ddmStatusItems(managementId: "-v"),
            .blueprintDetail(name: "-v"), .complianceBenchmarkDetail(name: "-v"),
            .protectComputerDetail(name: "-v"), .protectExceptionSetDetail(name: "-v"),
            .protectUnifiedLoggingDetail(name: "-v"), .protectAnalyticDetail(name: "-v"),
            .patchTitleDetail(id: "-v"), .patchPolicyDetail(id: "-v"),
            .restrictedSoftwareDetail(id: "-v"), .scriptDetail(id: "-v"),
        ]
        for command in commands {
            let args = command.baseArguments
            XCTAssertEqual(args.suffix(2), ["--", "-v"], "\(args)")
        }
    }

    func testCorrectedCommandNames() {
        XCTAssertEqual(CLICommand.schoolUserGroups.baseArguments, ["school", "groups", "list", "-o", "json"])
        XCTAssertEqual(CLICommand.webhooks.baseArguments, ["pro", "classic-webhooks", "list", "-o", "json"])
        let apps = CLICommand.installedApps(serial: "C02").baseArguments
        XCTAssertTrue(apps.contains("APPLICATIONS"))
        XCTAssertTrue(apps.contains(#"hardware.serialNumber=="C02""#))
    }

    func testLostModeFlags() {
        let args = CLICommand.mobileDeviceEnableLostMode(serial: "F9", message: "Call IT", phone: " ", footnote: "Thanks").baseArguments
        XCTAssertEqual(args, ["pro", "md", "enable-lost-mode", "--serial=F9", "--message=Call IT", "--footnote=Thanks", "--yes"])
    }

    func testOutputFormatStaysBeforeSeparator() {
        let args = CLICommand.scriptDetail(id: "7").arguments(outputFormat: .csv)
        XCTAssertEqual(args, ["pro", "scripts", "get", "-o", "csv", "--", "7"])
    }

    func testRiskLevels() {
        XCTAssertEqual(CLICommand.computers.risk, .read)
        XCTAssertEqual(CLICommand.webhooks.risk, .read)
        XCTAssertEqual(CLICommand.blankPush(serial: "A").risk, .safe)
        XCTAssertEqual(CLICommand.restart(serial: "A").risk, .moderate)
        XCTAssertEqual(CLICommand.bulkEnablePolicies(category: "A").risk, .moderate)
        for command: CLICommand in [.erase(serial: "A"), .removeMDM(serial: "A"), .clearRecoveryLock(serial: "A"),
                                    .lock(serial: "A", pin: "123456"), .mobileDeviceErase(serial: "A"),
                                    .mobileDeviceUnmanage(serial: "A"),
                                    .mobileDeviceEnableLostMode(serial: "A", message: "m", phone: "", footnote: "")] {
            XCTAssertEqual(command.risk, .destructive, "\(command)")
            XCTAssertTrue(command.isDestructive)
        }
    }

    func testDemoRejectsReadsWithoutSampleData() async {
        do {
            _ = try await DemoCLIManager().run(.protectDataRetention)
            XCTFail("expected notInDemo")
        } catch CLIError.notInDemo {
        } catch {
            XCTFail("unexpected \(error)")
        }
        let action = try? await DemoCLIManager().run(.blankPush(serial: "A"))
        XCTAssertNotNil(action)
    }
}
