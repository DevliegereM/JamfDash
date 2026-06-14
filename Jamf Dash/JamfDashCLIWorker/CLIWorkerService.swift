import Foundation
import Security

/// XPC service implementation.  Receives requests from the main app via `CLIWorkerXPCProtocol`
/// and delegates the actual subprocess work to an in-process `CLIExecutor`.
///
/// `@unchecked Sendable`: all mutable state lives inside the `CLIExecutor` actor; the class
/// itself holds no mutable state of its own.
@objc final class CLIWorkerService: NSObject, CLIWorkerXPCProtocol, @unchecked Sendable {

    private let executor = CLIExecutor()

    // NSXPCConnection delivers reply blocks on an arbitrary thread and is internally
    // thread-safe, so lifting them into a Sendable context is safe.
    private struct Reply: @unchecked Sendable {
        let call: (Data?, NSError?) -> Void
    }

    // MARK: - CLIWorkerXPCProtocol

    func execute(
        binaryPath: String,
        arguments: [String],
        environment: [String: String],
        stdinData: Data,
        timeout: Double,
        withReply reply: @escaping (Data?, NSError?) -> Void
    ) {
        let r = Reply(call: reply)
        Task {
            await run(
                binaryPath: binaryPath,
                arguments: arguments,
                environment: environment,
                stdinData: stdinData.isEmpty ? nil : stdinData,
                timeout: timeout,
                interactive: false,
                reply: r.call
            )
        }
    }

    func executeInteractive(
        binaryPath: String,
        arguments: [String],
        environment: [String: String],
        stdinData: Data,
        timeout: Double,
        withReply reply: @escaping (Data?, NSError?) -> Void
    ) {
        let r = Reply(call: reply)
        Task {
            await run(
                binaryPath: binaryPath,
                arguments: arguments,
                environment: environment,
                stdinData: stdinData,
                timeout: timeout,
                interactive: true,
                reply: r.call
            )
        }
    }

    // MARK: - Shared runner

    private func run(
        binaryPath: String,
        arguments: [String],
        environment: [String: String],
        stdinData: Data?,
        timeout: Double,
        interactive: Bool,
        reply: @escaping (Data?, NSError?) -> Void
    ) async {
        // Allowlist: only execute binaries from the JamfDash bin directory.
        let allowedPrefix = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Application Support/JamfDash/bin")
        let resolvedPath = (binaryPath as NSString).standardizingPath
        guard resolvedPath.hasPrefix(allowedPrefix) else {
            reply(nil, CLIWorkerError.nsError(
                code: .launchFailed,
                description: "Security: binary path '\(binaryPath)' is outside the allowed directory"
            ))
            return
        }
        let binary = URL(fileURLWithPath: resolvedPath)

        // Code-signature check: the binary must be signed by JAMF Software.
        // This prevents a trojan in the bin directory from being executed even if
        // the path check passes.
        if let signatureError = verifyJAMFSignature(at: binary) {
            reply(nil, signatureError)
            return
        }
        do {
            let output: Data
            if interactive {
                output = try await executor.executeInteractive(
                    binary: binary,
                    arguments: arguments,
                    environment: environment,
                    stdinData: stdinData ?? Data(),
                    timeout: timeout
                )
            } else {
                output = try await executor.execute(
                    binary: binary,
                    arguments: arguments,
                    environment: environment,
                    stdinData: stdinData,
                    timeout: timeout
                )
            }
            reply(output, nil)
        } catch let cliError as CLIError {
            reply(nil, bridge(cliError))
        } catch {
            reply(nil, CLIWorkerError.nsError(
                code: .unknown,
                description: error.localizedDescription
            ))
        }
    }

    // MARK: - Code signature verification

    /// Returns nil if the binary at `url` is validly signed by JAMF Software (Team ID 483DWKW443),
    /// or an NSError to send as the XPC reply if verification fails.
    private func verifyJAMFSignature(at url: URL) -> NSError? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else {
            return CLIWorkerError.nsError(
                code: .launchFailed,
                description: "Security: could not read code signature of '\(url.lastPathComponent)'"
            )
        }
        let requirementString = "anchor apple generic and certificate leaf[subject.OU] = \"483DWKW443\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(requirementString as CFString, [], &requirement) == errSecSuccess,
              let req = requirement else {
            return CLIWorkerError.nsError(
                code: .launchFailed,
                description: "Security: could not build code-signing requirement"
            )
        }
        let status = SecStaticCodeCheckValidity(code, [], req)
        guard status == errSecSuccess else {
            return CLIWorkerError.nsError(
                code: .launchFailed,
                description: "Security: '\(url.lastPathComponent)' is not signed by JAMF Software (status \(status))"
            )
        }
        return nil
    }

    // MARK: - CLIError → NSError

    private func bridge(_ error: CLIError) -> NSError {
        switch error {
        case .launchFailed(let msg):
            return CLIWorkerError.nsError(code: .launchFailed, description: msg)
        case .nonZeroExit(let code, let stderr):
            return CLIWorkerError.nsError(
                code: .nonZeroExit,
                description: "Process exited with code \(code)",
                stderr: stderr,
                exitCode: code
            )
        case .timeout:
            return CLIWorkerError.nsError(code: .timeout, description: "Process timed out")
        default:
            return CLIWorkerError.nsError(code: .unknown, description: error.localizedDescription)
        }
    }
}
