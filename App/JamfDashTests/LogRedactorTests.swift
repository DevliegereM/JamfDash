import XCTest
@testable import JamfDash

final class LogRedactorTests: XCTestCase {

    private let redactor = LogRedactor(hosts: ["https://acme.jamfcloud.com"], names: ["Acme-Prod"],
                                       serials: [], userNames: ["jdoe"])

    func testKnownValuesAndPatterns() {
        let line = """
        2026-09-28 10:41:02 JamfDash[123] CLIManager: Updated profile Acme-Prod from https://eu.apigw.jamf.com/api to https://acme.jamfcloud.com
        Device C02XG2JCJG5J (mgmt 3F2504E0-4F89-11D3-9A0C-0305E82C3301) at 192.168.1.42 / a4:83:e7:12:34:56 by jane.doe@acme.com
        client_secret=Zm9vYmFyYmF6cXV4cXV1eHF1dXg and Authorization: Bearer abcdef1234567890
        /Users/jdoe/Library/Application Support/JamfDash/bin/jamf-cli
        """
        let (out, counts) = redactor.redact(line)
        for leaked in ["acme.jamfcloud.com", "Acme-Prod", "eu.apigw.jamf.com", "C02XG2JCJG5J",
                       "3F2504E0-4F89-11D3-9A0C-0305E82C3301", "192.168.1.42", "a4:83:e7:12:34:56",
                       "jane.doe@acme.com", "Zm9vYmFyYmF6cXV4cXV1eHF1dXg", "abcdef1234567890", "jdoe"] {
            XCTAssertFalse(out.contains(leaked), "\(leaked) leaked:\n\(out)")
        }
        XCTAssertTrue(out.contains("https://‹host-"), out)
        XCTAssertTrue(out.contains("JamfDash[123] CLIManager"), "ordinary text stays")
        XCTAssertGreaterThanOrEqual(counts.total, 10)
    }

    func testSameValueGetsSameNumber() {
        let (out, _) = redactor.redact("a https://acme.jamfcloud.com b acme.jamfcloud.com c https://other.example.com")
        XCTAssertEqual(out.components(separatedBy: "‹host-1›").count - 1, 2, out)
        XCTAssertTrue(out.contains("‹host-2›"), out)
    }

    func testCodeIdentifiersSurvive() {
        let text = "com.jamfdash be.devliegere.JamfDash.CLIWorker JamfDash.app Sparkle.framework Info.plist " +
                   "$s8JamfDash10CLIManagerC3runy10Foundation4DataVAA10CLICommandOYaKF jamf-cli 1.31.1"
        let (out, counts) = redactor.redact(text)
        XCTAssertEqual(out, text)
        XCTAssertEqual(counts.total, 0)
    }

    func testCommandNamesKeepNoValues() {
        XCTAssertEqual(DiagnosticsJournal.commandName(["--profile", "Acme-Prod", "pro", "scripts", "get", "-o", "json", "--", "7"]),
                       "pro scripts get")
        XCTAssertEqual(DiagnosticsJournal.commandName(["pro", "computers", "blank-push", "--serial=C02"]),
                       "pro computers blank-push")
        XCTAssertEqual(DiagnosticsJournal.commandName(["--profile", "x", "Secret Name"]), "(unknown)")
    }

    func testCrashReportIdentifiersRemoved() {
        let ips = #"{"crashReporterKey" : "ABCDEF-1234", "sleepWakeUUID" : "1111", "procName" : "JamfDash"}"#
        let out = CrashReports.stripIdentifiers(ips)
        XCTAssertFalse(out.contains("ABCDEF-1234"))
        XCTAssertTrue(out.contains("JamfDash"))
    }
}
