import XCTest
@testable import JamfDash

/// Checks that `CLIManager` sends actions only with a matching, unused confirmation, to the
/// connection it was confirmed on, and destructive ones only when the connection allows them.
/// Uses the installed jamf-cli path (never runs it: the executor is a recorder).
final class ActionConfirmationTests: XCTestCase {

    private final class Recorder: CLIExecuting, @unchecked Sendable {
        private let lock = NSLock()
        private var _calls: [[String]] = []
        var lookupResult = Data(#"{"totalCount":1,"results":[{"id":"1"}]}"#.utf8)
        var mobileList = Data(#"[{"id":"1","serialNumber":"F9A"},{"id":"2","serialNumber":"F9B"}]"#.utf8)
        var calls: [[String]] { lock.withLock { _calls } }

        func execute(binary: URL, arguments: [String], environment: [String: String],
                     stdinData: Data?, timeout: TimeInterval) async throws -> Data {
            lock.withLock { _calls.append(arguments) }
            if arguments.contains("computer-inventory") { return lookupResult }
            if arguments.contains("md") && arguments.contains("list") { return mobileList }
            return Data("{}".utf8)
        }

        func executeScripted(binary: URL, arguments: [String], environment: [String: String],
                             rules: [PromptRule], timeout: TimeInterval) async throws -> Data {
            Data()
        }
    }

    private var defaults: UserDefaults!
    private var profiles: ProfileService!
    private var recorder: Recorder!
    private var cli: CLIManager!

    override func setUp() async throws {
        let binary = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/JamfDash/bin/jamf-cli")
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: binary.path), "jamf-cli isn't installed")
        let suite = "ActionConfirmationTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        profiles = ProfileService(defaults: defaults)
        profiles.selectedProfile = JamfProfile(name: "Test-A")
        recorder = Recorder()
        cli = CLIManager(downloader: CLIDownloader(), profileService: profiles,
                         keychain: KeychainService(), executor: recorder)
    }

    func testActionWithoutConfirmationIsRefused() async {
        do {
            _ = try await cli.run(.blankPush(serial: "C02"))
            XCTFail("expected actionNotConfirmed")
        } catch CLIError.actionNotConfirmed {
        } catch { XCTFail("\(error)") }
        XCTAssertTrue(recorder.calls.isEmpty)
    }

    func testConfirmationWorksOnceForTheSameCommand() async throws {
        let token = try await cli.confirm(.blankPush(serial: "C02"))
        _ = try await cli.run(.blankPush(serial: "C02"), confirmation: token)
        XCTAssertEqual(recorder.calls.count, 1)
        XCTAssertTrue(recorder.calls[0].contains("--serial=C02"))
        XCTAssertEqual(Array(recorder.calls[0].prefix(2)), ["--profile", "Test-A"])

        do {
            _ = try await cli.run(.blankPush(serial: "C02"), confirmation: token)
            XCTFail("a confirmation must not work twice")
        } catch CLIError.actionNotConfirmed {}
    }

    func testConfirmationForAnotherCommandIsRefused() async throws {
        let token = try await cli.confirm(.blankPush(serial: "C02"))
        do {
            _ = try await cli.run(.restart(serial: "C02"), confirmation: token)
            XCTFail("expected actionNotConfirmed")
        } catch CLIError.actionNotConfirmed {}
        do {
            _ = try await cli.run(.blankPush(serial: "OTHER"), confirmation: ActionConfirmation(id: UUID()))
            XCTFail("a made-up confirmation must not work")
        } catch CLIError.actionNotConfirmed {}
        XCTAssertTrue(recorder.calls.isEmpty)
    }

    func testInstanceSwitchAfterConfirmingSendsNothing() async throws {
        let token = try await cli.confirm(.restart(serial: "C02"))
        profiles.selectedProfile = JamfProfile(name: "Test-B")
        do {
            _ = try await cli.run(.restart(serial: "C02"), confirmation: token)
            XCTFail("expected instanceChanged")
        } catch CLIError.instanceChanged {}
        XCTAssertTrue(recorder.calls.isEmpty)
    }

    func testDestructiveActionsNeedThePermission() async throws {
        do {
            _ = try await cli.confirm(.erase(serial: "C02"))
            XCTFail("expected actionNotAllowed")
        } catch CLIError.actionNotAllowed {}

        profiles.setAllowsDestructiveActions(true, for: "Test-A")
        let token = try await cli.confirm(.erase(serial: "C02"))
        _ = try await cli.run(.erase(serial: "C02"), confirmation: token)
        XCTAssertEqual(recorder.calls.count, 2, "one lookup, then the erase")
        XCTAssertTrue(recorder.calls[1].contains("erase"))
    }

    func testDestructiveActionRefusedWhenSerialIsAmbiguous() async throws {
        profiles.setAllowsDestructiveActions(true, for: "Test-A")
        recorder.lookupResult = Data(#"{"totalCount":2,"results":[{"id":"1"},{"id":"2"}]}"#.utf8)
        let token = try await cli.confirm(.removeMDM(serial: "C02"))
        do {
            _ = try await cli.run(.removeMDM(serial: "C02"), confirmation: token)
            XCTFail("expected a refusal")
        } catch CLIError.nonZeroExit(_, let message) {
            XCTAssertTrue(message.contains("2 computers"))
        }
        XCTAssertEqual(recorder.calls.count, 1, "only the lookup ran")
    }

    func testMobileDestructiveActionNeedsExactlyOneDevice() async throws {
        profiles.setAllowsDestructiveActions(true, for: "Test-A")
        let token = try await cli.confirm(.mobileDeviceErase(serial: "f9a"))
        _ = try await cli.run(.mobileDeviceErase(serial: "f9a"), confirmation: token)
        XCTAssertTrue(recorder.calls.last?.contains("erase") == true, "one match (case-insensitive): erase sent")

        recorder.mobileList = Data(#"[{"serialNumber":"F9A"},{"serialNumber":"F9A"}]"#.utf8)
        let second = try await cli.confirm(.mobileDeviceUnmanage(serial: "F9A"))
        let before = recorder.calls.count
        do {
            _ = try await cli.run(.mobileDeviceUnmanage(serial: "F9A"), confirmation: second)
            XCTFail("expected a refusal")
        } catch CLIError.nonZeroExit(_, let message) {
            XCTAssertTrue(message.contains("2 mobile devices"), message)
        }
        XCTAssertEqual(recorder.calls.count, before + 1, "only the list ran")
    }

    func testUnknownScopeIsStandard() {
        XCTAssertEqual(profiles.scope(for: "never-seen"), .standard)
        XCTAssertFalse(profiles.allowsDestructiveActions(for: "never-seen"))
    }
}

/// The confirmation text Dashie shows comes from this parser, not from the model.
final class DeviceIdentityTests: XCTestCase {
    func testParsesOneMac() {
        let data = Data(#"{"results":[{"general":{"name":"Finance-MBP","lastContactTime":"2026-09-27T08:00:00Z"},"hardware":{"model":"MacBook Pro","serialNumber":"AAA111"}}]}"#.utf8)
        guard case .found(let d) = DeviceIdentity.parse(data, serial: "AAA111") else { return XCTFail() }
        XCTAssertEqual(d.name, "Finance-MBP")
        XCTAssertEqual(d.model, "MacBook Pro")
        XCTAssertTrue(d.description.contains("serial AAA111"))
    }

    func testNoneOrSeveralMacs() {
        XCTAssertEqual(DeviceIdentity.parse(Data(#"{"results":[]}"#.utf8), serial: "X"), .notFound)
        XCTAssertEqual(DeviceIdentity.parse(Data(#"[{"id":"1"},{"id":"2"}]"#.utf8), serial: "X"), .ambiguous(2))
    }

    func testLongNamesAreCut() {
        let long = String(repeating: "A", count: 500)
        let data = Data(#"{"results":[{"general":{"name":"\#(long)"}}]}"#.utf8)
        guard case .found(let d) = DeviceIdentity.parse(data, serial: "X") else { return XCTFail() }
        XCTAssertEqual(d.name.count, 80)
    }
}

final class ReleaseTagTests: XCTestCase {
    func testTags() {
        for ok in ["v1.31.1", "1.31.1", "v2.0.0-beta.2"] { XCTAssertTrue(CLIVersionStore.isValidTag(ok), ok) }
        for bad in ["../x", "v1.2.3/../../x", "v1.2", "", "v1.2.3;rm", "latest"] {
            XCTAssertFalse(CLIVersionStore.isValidTag(bad), bad)
        }
    }
}
