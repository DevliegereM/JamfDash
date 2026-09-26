import XCTest
@testable import JamfDash

final class SetupFlowTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("jd-setup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// Writes an executable bash script and returns its URL.
    private func script(_ body: String) throws -> URL {
        let url = tempDir.appendingPathComponent("prompt-\(UUID().uuidString).sh")
        try Data("#!/bin/bash\n\(body)\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func runScripted(_ binary: URL, _ rules: [PromptRule], grace: TimeInterval = 1) async throws -> String {
        let data = try await CLIExecutor().executeScripted(
            binary: binary, arguments: [], environment: ["PATH": "/usr/bin:/bin"],
            rules: rules, timeout: 20, unansweredPromptGrace: grace
        )
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Prompt-driven answers

    func testAnswersArriveInTheOrderAsked() async throws {
        let bin = try script("""
        read -r -p "Username: " u
        read -r -s -p "Password: " p; echo
        echo "user=$u pass-length=${#p}"
        """)
        // Rules deliberately listed in the opposite order.
        let out = try await runScripted(bin, [
            PromptRule("Password:", answer: "s3cret!", isSecret: true),
            PromptRule("Username:", answer: "admin"),
        ])
        XCTAssertTrue(out.contains("user=admin pass-length=7"), out)
    }

    func testOptionalRuleThatIsNeverAskedIsFine() async throws {
        let bin = try script(#"read -r -p "Client ID: " c; echo "id=$c""#)
        let out = try await runScripted(bin, [
            PromptRule("Client ID:", answer: "abc"),
            PromptRule("HTML report directory", answer: ""),
        ])
        XCTAssertTrue(out.contains("id=abc"), out)
    }

    func testUnexpectedQuestionStopsBeforeTheSecretIsTyped() async throws {
        // Mimics jamf-cli 1.31: a new question appears before the ones Jamf Dash knows.
        let received = tempDir.appendingPathComponent("received.txt")
        let bin = try script("""
        read -r -p "Jamf Pro server URL: " url; echo "url=$url" >> "\(received.path)"
        read -r -p "Choose [1-2]: " choice; echo "choice=$choice" >> "\(received.path)"
        read -r -s -p "Password: " p; echo "pass=$p" >> "\(received.path)"
        """)
        do {
            _ = try await runScripted(bin, [
                PromptRule("server URL:", answer: "https://x.jamfcloud.com"),
                PromptRule("Password:", answer: "hunter2", isSecret: true),
            ])
            XCTFail("Expected unexpectedPrompt")
        } catch CLIError.unexpectedPrompt(let question) {
            XCTAssertTrue(question.contains("Choose [1-2]"), question)
        }
        let got = (try? String(contentsOf: received, encoding: .utf8)) ?? ""
        XCTAssertFalse(got.contains("hunter2"), "The password must never be sent to another question")
        XCTAssertFalse(got.contains("choice="), "The unknown question must not be answered")
    }

    func testSecretIsRedactedFromErrors() async throws {
        // jamf-cli 1.31 echoed a mis-routed password in a JSON error, with & escaped as &.
        let bin = try script(#"""
        read -r -s -p "Password: " p; echo
        esc=${p//&/\\u0026}
        printf '{"message":"mkdir %s: read-only file system","raw":"%s"}\n' "$esc" "$p" >&2
        exit 1
        """#)
        do {
            _ = try await runScripted(bin, [PromptRule("Password:", answer: "a&b#c!1", isSecret: true)])
            XCTFail("Expected failure")
        } catch CLIError.nonZeroExit(_, let stderr) {
            XCTAssertFalse(stderr.contains("a&b#c!1"), stderr)
            XCTAssertFalse(stderr.contains(#"a&b#c!1"#), stderr)
            XCTAssertTrue(stderr.contains("••••••"), stderr)
        }
    }

    func testRedactHandlesEscapedForms() {
        let text = #"{"message":"bad \"p\\w\" and a&b"}"#
        let redacted = CLIExecutor.redact(text, secrets: [#""p\w""#, "a&b"])
        XCTAssertEqual(redacted, #"{"message":"bad •••••• and ••••••"}"#)
    }

    // MARK: - Minimum jamf-cli version

    func testMinimumVersion() {
        XCTAssertEqual(CLIManager.minimumCLIVersion, "1.31.1")
        XCTAssertTrue(CLIManager.meetsMinimum("1.31.1"))
        XCTAssertTrue(CLIManager.meetsMinimum("v1.31.2"))
        XCTAssertTrue(CLIManager.meetsMinimum("1.40.0"))
        XCTAssertTrue(CLIManager.meetsMinimum("2.0.0"))
        XCTAssertFalse(CLIManager.meetsMinimum("1.31.0"))
        XCTAssertFalse(CLIManager.meetsMinimum("v1.25.1"))
        XCTAssertFalse(CLIManager.meetsMinimum("1.9.0"))
    }

    // MARK: - jamf-cli config file

    private let sampleConfig = """
    default-profile: ""
    profiles:
        Jamf CLI - Read Only:
            url: https://example.jamfcloud.com
            auth-method: oauth2
        "Jamf Platform - PRD":
            url: https://eu.apigw.jamf.com
            auth-method: platform
            tenant-id: abc
        school:
            url: https://example.jamfschool.com
    report-dir: /tmp/reports
    """

    private func configFile() throws -> JamfCLIConfigFile {
        let url = tempDir.appendingPathComponent("config.yaml")
        try Data(sampleConfig.utf8).write(to: url)
        return JamfCLIConfigFile(url: url)
    }

    func testConfigReadsURLs() throws {
        let config = try configFile()
        XCTAssertEqual(try config.profileURL("Jamf Platform - PRD"), "https://eu.apigw.jamf.com")
        XCTAssertEqual(try config.profileURL("Jamf CLI - Read Only"), "https://example.jamfcloud.com")
        XCTAssertThrowsError(try config.profileURL("missing"))
    }

    func testConfigSetURLChangesOnlyThatLine() throws {
        let config = try configFile()
        try config.setURL("https://eu.api.jamfcloud.com", forProfile: "Jamf Platform - PRD")
        let after = try String(contentsOf: config.url, encoding: .utf8)
        let expected = sampleConfig.replacingOccurrences(
            of: "        url: https://eu.apigw.jamf.com",
            with: "        url: https://eu.api.jamfcloud.com")
        XCTAssertEqual(after, expected)
        XCTAssertTrue(FileManager.default.fileExists(atPath: config.url.path + ".jamfdash-backup"))
    }

    func testConfigDefaultProfileRoundTrip() throws {
        let config = try configFile()
        XCTAssertEqual(try config.defaultProfile(), "")
        try config.setDefaultProfile("school")
        XCTAssertEqual(try config.defaultProfile(), "school")
        try config.setDefaultProfile("")
        XCTAssertEqual(try config.defaultProfile(), "")
        XCTAssertEqual(try String(contentsOf: config.url, encoding: .utf8), sampleConfig)
    }

    func testRetiredGatewayReplacement() {
        let message = #"https://eu.apigw.jamf.com is the retired Jamf Platform gateway and does not serve the GA API paths.\nSet url: https://eu.api.jamfcloud.com in this profile (jamf-cli config path prints the file), or re-run `jamf-cli platform setup`."#
        XCTAssertEqual(JamfCLIConfigFile.retiredGatewayReplacement(in: message), "https://eu.api.jamfcloud.com")
        XCTAssertNil(JamfCLIConfigFile.retiredGatewayReplacement(in: "invalid client credentials"))
        XCTAssertNil(JamfCLIConfigFile.retiredGatewayReplacement(
            in: "the retired Jamf Platform gateway. Set url: https://evil.example.com"))
    }

    // MARK: - Real jamf-cli setup flows (fake host; nothing is saved)
    //
    // Only flows that verify credentials before saving are run here, so no profile is
    // written. Each must end in a connection error — not an unexpected question.

    private static let jamfCLI = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("JamfDash/bin/jamf-cli")

    private func runRealSetup(_ args: [String], _ rules: [PromptRule]) async throws -> String {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: Self.jamfCLI.path), "jamf-cli not installed")
        do {
            _ = try await CLIExecutor().executeScripted(
                binary: Self.jamfCLI, arguments: args,
                environment: ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin", "JAMF_CLI_NO_UPDATE_CHECK": "1"],
                rules: rules, timeout: 60, unansweredPromptGrace: 4
            )
            XCTFail("Setup against example.invalid should not succeed")
            return ""
        } catch CLIError.nonZeroExit(_, let stderr) {
            return stderr
        }
    }

    func testRealProLocalAccountSetupAnswersAllQuestions() async throws {
        let err = try await runRealSetup(
            ["pro", "setup", "--url", "https://example.invalid", "--credentials", "create",
             "--scope", "standard", "--profile-name", "jd-test-probe"],
            [PromptRule("Username:", answer: "probe-user"),
             PromptRule("Password:", answer: "probe&pass#1", isSecret: true),
             PromptRule("HTML report directory", answer: "")])
        XCTAssertTrue(err.contains("example.invalid"), err)
        XCTAssertFalse(err.contains("probe&pass#1"), err)
    }

    func testRealOAuthSetupAnswersAllQuestions() async throws {
        let err = try await runRealSetup(
            ["config", "add-profile", "jd-test-probe", "--url", "https://example.invalid", "--auth-method", "oauth2"],
            [PromptRule("Client ID:", answer: "probe-id"),
             PromptRule("Client Secret:", answer: "probe-secret", isSecret: true)])
        XCTAssertTrue(err.contains("did not write"), err)
    }

    func testRealPlatformSetupAnswersAllQuestions() async throws {
        let err = try await runRealSetup(
            ["config", "add-profile", "jd-test-probe", "--url", "https://example.invalid",
             "--auth-method", "platform", "--environment-id", "env-probe"],
            [PromptRule("Client ID:", answer: "probe-id"),
             PromptRule("Client Secret:", answer: "probe-secret", isSecret: true)])
        XCTAssertTrue(err.contains("did not write"), err)
    }
}

// MARK: - jamf-cli error payloads

final class JamfCLIErrorPayloadTests: XCTestCase {
    func testPermissionDeniedShowsHint() {
        let stderr = #"""
        {
          "error": "permission_denied",
          "exitCode": 5,
          "exitCodeName": "permission_denied",
          "hint": "grant the Jamf Platform API integration these permissions in Jamf Account: Deployment > Blueprints: Read (blueprints:read).",
          "message": "list: API request failed with status 403 Forbidden, traceId 2025d7dbb066da562c97bbe44ba845b5 (method=GET, url=https://us.api.jamfcloud.com/blueprints/v1/blueprints?page=0&page-size=100): [BAD_PERMISSIONS] The given token was not authorized to access the requested resource."
        }
        """#
        let text = CLIError.nonZeroExit(code: 5, stderr: stderr).localizedDescription
        XCTAssertEqual(text, """
        The API client doesn't have permission for this.

        Grant the Jamf Platform API integration these permissions in Jamf Account: Deployment > Blueprints: Read (blueprints:read).
        """)
    }

    func testAuthenticationErrorAfterPromptText() {
        let stderr = #"Client ID: Client Secret: Verifying credentials... ✗ {"error": "authentication", "exitCode": 3, "exitCodeName": "authentication", "message": "getting auth token: invalid client credentials"}"#
        XCTAssertEqual(CLIError.nonZeroExit(code: 3, stderr: stderr).localizedDescription,
                       "Authentication failed: getting auth token: invalid client credentials")
    }

    func testPlainOutputFallsBack() {
        XCTAssertEqual(CLIError.nonZeroExit(code: 1, stderr: "boom").localizedDescription,
                       "jamf-cli exited with code 1: boom")
    }
}

// MARK: - Security report fallback and gateway-refused commands

final class GatewayCompatibilityTests: XCTestCase {
    func testSecurityReportFromInventory() throws {
        let json = #"""
        {"totalCount": 3, "results": [
          {"general": {"name": "Mac-1"}, "hardware": {"serialNumber": "S1"},
           "operatingSystem": {"version": "15.6"},
           "security": {"sipStatus": "ENABLED", "gatekeeperStatus": "APP_STORE_AND_IDENTIFIED_DEVELOPERS", "firewallEnabled": true},
           "diskEncryption": {"bootPartitionEncryptionDetails": {"partitionFileVault2State": "ENCRYPTED"}}},
          {"general": {"name": "Mac-2"}, "hardware": {"serialNumber": "S2"},
           "operatingSystem": {"version": "15.6", "fileVault2Status": "NOT_ENCRYPTED"},
           "security": {"sipStatus": "DISABLED", "gatekeeperStatus": "DISABLED", "firewallEnabled": false},
           "diskEncryption": {"bootPartitionEncryptionDetails": {"partitionFileVault2State": "UNENCRYPTED"}}},
          {"general": {"name": "Mac-3"}, "hardware": {"serialNumber": "S3"},
           "operatingSystem": {"version": "26.0", "fileVault2Status": "ALL_ENCRYPTED"},
           "security": {"sipStatus": "ENABLED", "gatekeeperStatus": "APP_STORE", "firewallEnabled": true}}
        ]}
        """#
        let report = try SecurityReport(inventory: Data(json.utf8))
        XCTAssertEqual(report.devices.map(\.serial), ["S1", "S2", "S3"])
        XCTAssertEqual(report.devices.map(\.isFilevaultEncrypted), [true, false, true])
        XCTAssertEqual(report.devices.map(\.hasIssue), [false, true, false])
        let s = try XCTUnwrap(report.summary)
        XCTAssertEqual(s.totalDevices, 3)
        XCTAssertEqual(s.filevaultEncrypted, 2)
        XCTAssertEqual(s.filevaultEncryptedPct, "66.7%")
        XCTAssertEqual(s.sipEnabled, 2)
        XCTAssertEqual(s.gatekeeperEnabled, 2)
        XCTAssertEqual(s.firewallEnabled, 2)
        XCTAssertEqual(report.osVersions.map(\.osVersion), ["15.6", "26.0"])
        XCTAssertEqual(report.osVersions.first?.pct, "66.7%")
    }

    func testSecurityReportFromBareArray() throws {
        let report = try SecurityReport(inventory: Data(#"[{"hardware": {"serialNumber": "S1"}}]"#.utf8))
        XCTAssertEqual(report.devices.count, 1)
        XCTAssertEqual(report.summary?.totalDevices, 1)
    }

    func testDetectsMissingV4InventoryEndpoint() {
        let stderr = #"{"error": "not_found", "exitCode": 4, "exitCodeName": "not_found", "hint": "run the matching 'list' command to see valid IDs/names", "message": "fetching computer inventory: fetching page 0: resource not found (HTTP 404): GET /pro/v4/computers-inventory?section=GENERAL"}"#
        XCTAssertTrue(SecurityRepository.isMissingInventoryEndpoint(stderr))
        XCTAssertFalse(SecurityRepository.isMissingInventoryEndpoint(#"{"error": "not_found", "message": "policy 12 not found"}"#))
        XCTAssertFalse(SecurityRepository.isMissingInventoryEndpoint("plain failure"))
    }

    func testGatewayRefusedCommandMessage() {
        let stderr = #"{"error": "unsupported", "exitCode": 8, "exitCodeName": "unsupported", "hint": "auth-method platform against the gateway, from profile \"Jamf Platform\"", "message": "jamf-cli pro computer-inventory lock is not part of the Jamf Platform gateway's published API"}"#
        XCTAssertEqual(CLIError.nonZeroExit(code: 8, stderr: stderr).localizedDescription,
                       "This isn't available through the Jamf Platform API. Use a Jamf Pro connection (an API client or local admin account for your Jamf Pro instance) for this.")
    }
}
