import XCTest
@testable import JamfDash

final class CLISecurityTests: XCTestCase {

    private static let jamfCLI = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("JamfDash/bin/jamf-cli")

    // MARK: - Exit status mapping

    func testSuccessReturnsStdout() throws {
        let result = CLIExecutor.completion(reason: .exit, status: 0, timedOut: false,
                                            stdout: Data("ok".utf8), stderr: Data())
        XCTAssertEqual(try result.get(), Data("ok".utf8))
    }

    func testDeprecatedEndpointExitReturnsStdout() throws {
        let result = CLIExecutor.completion(reason: .exit, status: 15, timedOut: false,
                                            stdout: Data("[]".utf8), stderr: Data("Deprecation".utf8))
        XCTAssertEqual(try result.get(), Data("[]".utf8))
    }

    func testTimeoutIsNotMistakenForDeprecatedEndpoint() {
        // Our timeout sends SIGTERM (15); partial stdout must not be returned as success.
        let result = CLIExecutor.completion(reason: .uncaughtSignal, status: 15, timedOut: true,
                                            stdout: Data("{\"partial\":".utf8), stderr: Data())
        guard case .failure(CLIError.timeout) = result else {
            return XCTFail("Expected CLIError.timeout, got \(result)")
        }
    }

    func testExternalSIGTERMIsFailure() {
        let result = CLIExecutor.completion(reason: .uncaughtSignal, status: 15, timedOut: false,
                                            stdout: Data("partial".utf8), stderr: Data())
        XCTAssertThrowsError(try result.get())
    }

    func testRealTimeoutThrows() async throws {
        let executor = CLIExecutor()
        do {
            _ = try await executor.execute(binary: URL(fileURLWithPath: "/bin/sleep"), arguments: ["5"],
                                           environment: [:], stdinData: nil, timeout: 0.3)
            XCTFail("Expected a timeout")
        } catch CLIError.timeout {
            // expected
        }
    }

    // MARK: - RSQL serial filter

    func testSerialFilterPlain() {
        XCTAssertEqual(CLICommand.serialFilter("C02XG2JCJG5J"), #"hardware.serialNumber=="C02XG2JCJG5J""#)
    }

    func testSerialFilterEscapesQuotes() {
        let filter = CLICommand.serialFilter(#"X" or general.name=="*"#)
        XCTAssertEqual(filter, #"hardware.serialNumber=="X\" or general.name==\"*""#)
    }

    func testSerialFilterEscapesBackslash() {
        XCTAssertEqual(CLICommand.serialFilter(#"A\"#), #"hardware.serialNumber=="A\\""#)
    }

    // MARK: - Lock

    func testLockUsesMDMCommandEndpoint() {
        XCTAssertEqual(CLICommand.lock(serial: "S", pin: "123456").baseArguments,
                       ["pro", "mdm-commands", "commands", "-o", "json"])
    }

    func testManagementIdParsing() {
        let wrapped = Data(#"{"totalCount":1,"results":[{"id":"7","general":{"managementId":"abc-123"}}]}"#.utf8)
        XCTAssertEqual(CLIManager.managementId(in: wrapped), "abc-123")
        let bare = Data(#"[{"general":{"managementId":"def"}}]"#.utf8)
        XCTAssertEqual(CLIManager.managementId(in: bare), "def")
        let ambiguous = Data(#"[{"general":{"managementId":"a"}},{"general":{"managementId":"b"}}]"#.utf8)
        XCTAssertNil(CLIManager.managementId(in: ambiguous))
        XCTAssertNil(CLIManager.managementId(in: Data("[]".utf8)))
    }

    // MARK: - Code signature

    func testSystemBinaryIsRejected() {
        XCTAssertThrowsError(try CodeSignatureVerifier.verifyJamfCLI(at: URL(fileURLWithPath: "/bin/ls"))) { error in
            guard case CLIError.untrustedBinary = error else { return XCTFail("Unexpected error \(error)") }
        }
    }

    func testInstalledJamfCLIIsAccepted() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: Self.jamfCLI.path), "jamf-cli not installed")
        XCTAssertNoThrow(try CodeSignatureVerifier.verifyJamfCLI(at: Self.jamfCLI))
    }

    func testVerifyingExecutorRefusesUntrustedBinary() async {
        let executor = VerifyingCLIExecutor(wrapping: CLIExecutor())
        do {
            _ = try await executor.execute(binary: URL(fileURLWithPath: "/bin/echo"), arguments: ["hi"],
                                           environment: [:], stdinData: nil, timeout: 5)
            XCTFail("Unsigned-by-Jamf binary should not run")
        } catch CLIError.untrustedBinary {
            // expected
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testVerifyingExecutorCachesUntilFileChanges() async throws {
        let counter = Counter()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("jd-verify-\(UUID().uuidString).sh")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: tmp)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let executor = VerifyingCLIExecutor(wrapping: CLIExecutor(), verify: { _ in counter.increment() })
        _ = try await executor.execute(binary: tmp, arguments: [], environment: [:], stdinData: nil, timeout: 5)
        _ = try await executor.execute(binary: tmp, arguments: [], environment: [:], stdinData: nil, timeout: 5)
        XCTAssertEqual(counter.value, 1)

        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: tmp.path)
        _ = try await executor.execute(binary: tmp, arguments: [], environment: [:], stdinData: nil, timeout: 5)
        XCTAssertEqual(counter.value, 2)
    }

    // MARK: - XPC worker (runs `jamf-cli --version` only; no server contact)
    //
    // Under `xcodebuild test` the host app is launched via debugserver, and launchd does not
    // register the app's embedded XPC services for it — these tests then skip. They run when
    // the host is launched normally (e.g. from Xcode with "Debug executable" off).

    private func requireReachableWorker() async throws -> XPCCLIExecutor {
        try XCTSkipUnless(XPCCLIExecutor.isWorkerEmbedded, "CLI worker not embedded in host app")
        try XCTSkipIf(CodeSignatureVerifier.peerRequirement(identifier: "x") == nil, "Unsigned build")
        let executor = XPCCLIExecutor()
        let reachable = await executor.isWorkerReachable()
        try XCTSkipUnless(reachable, "launchd did not register the worker for this test host")
        return executor
    }

    func testXPCFallbackRunsInProcessWhenWorkerUnreachable() async throws {
        let executor = XPCCLIExecutor(fallback: CLIExecutor())
        let reachable = await executor.isWorkerReachable()
        try XCTSkipIf(reachable, "Worker reachable; fallback path not exercised")
        let data = try await executor.execute(binary: URL(fileURLWithPath: "/bin/echo"), arguments: ["fallback"],
                                              environment: [:], stdinData: nil, timeout: 5)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "fallback\n")
    }

    func testXPCWorkerRunsJamfCLI() async throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: Self.jamfCLI.path), "jamf-cli not installed")
        let data = try await requireReachableWorker().execute(binary: Self.jamfCLI, arguments: ["--version"],
                                                      environment: [:], stdinData: nil, timeout: 20)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("jamf-cli"))
    }

    func testXPCWorkerRejectsBinaryOutsideAllowlist() async throws {
        let executor = try await requireReachableWorker()
        do {
            _ = try await executor.execute(binary: URL(fileURLWithPath: "/bin/echo"), arguments: ["hi"],
                                                   environment: [:], stdinData: nil, timeout: 5)
            XCTFail("Worker must not run binaries outside its allowlist")
        } catch CLIError.launchFailed(let message) {
            XCTAssertTrue(message.contains("outside the allowed directory"), message)
        }
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}
