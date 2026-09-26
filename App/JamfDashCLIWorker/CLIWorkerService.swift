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

    func ping(withReply reply: @escaping (Bool) -> Void) {
        reply(true)
    }

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
                mode: .plain(stdinData: stdinData.isEmpty ? nil : stdinData),
                timeout: timeout,
                reply: r.call
            )
        }
    }

    func executeScripted(
        binaryPath: String,
        arguments: [String],
        environment: [String: String],
        prompts: [String],
        answers: [String],
        secret: [Bool],
        timeout: Double,
        withReply reply: @escaping (Data?, NSError?) -> Void
    ) {
        let r = Reply(call: reply)
        guard prompts.count == answers.count, prompts.count == secret.count else {
            r.call(nil, CLIWorkerError.nsError(code: .launchFailed, description: "Malformed prompt rules"))
            return
        }
        let rules = prompts.indices.map { PromptRule(prompts[$0], answer: answers[$0], isSecret: secret[$0]) }
        Task {
            await run(
                binaryPath: binaryPath,
                arguments: arguments,
                environment: environment,
                mode: .scripted(rules),
                timeout: timeout,
                reply: r.call
            )
        }
    }

    // MARK: - Shared runner

    private enum Mode: Sendable {
        case plain(stdinData: Data?)
        case scripted([PromptRule])
    }

    private func run(
        binaryPath: String,
        arguments: [String],
        environment: [String: String],
        mode: Mode,
        timeout: Double,
        reply: @escaping (Data?, NSError?) -> Void
    ) async {
        // Allowlist: only execute binaries from the JamfDash bin directory.
        guard let binary = Self.allowedBinary(atPath: binaryPath) else {
            reply(nil, CLIWorkerError.nsError(
                code: .launchFailed,
                description: "Security: binary path '\(binaryPath)' is outside the allowed directory"
            ))
            return
        }

        // Code-signature check: the binary must be jamf-cli signed by JAMF Software.
        // This prevents a trojan in the bin directory from being executed even if
        // the path check passes.
        do {
            try CodeSignatureVerifier.verifyJamfCLI(at: binary)
        } catch {
            reply(nil, CLIWorkerError.nsError(code: .untrustedBinary, description: error.localizedDescription))
            return
        }
        do {
            let output: Data
            switch mode {
            case .scripted(let rules):
                output = try await executor.executeScripted(
                    binary: binary,
                    arguments: arguments,
                    environment: environment,
                    rules: rules,
                    timeout: timeout
                )
            case .plain(let stdinData):
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

    // MARK: - Path allowlist

    /// `~/Library/Application Support/JamfDash/bin/`, using the account's real home directory
    /// (not `NSHomeDirectory()`, which would point into a container if this service were
    /// ever sandboxed).
    private static let allowedDirectory: URL = {
        let home: String
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            home = String(cString: dir)
        } else {
            home = NSHomeDirectory()
        }
        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Library/Application Support/JamfDash/bin", isDirectory: true)
            .resolvingSymlinksInPath()
    }()

    /// Returns the resolved binary URL if it lives inside `allowedDirectory`, else nil.
    /// Symlinks and `..` are resolved first, and the prefix check includes the trailing `/`
    /// so a sibling like `bin-evil/` does not match.
    static func allowedBinary(atPath path: String) -> URL? {
        let resolved = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        let prefix = allowedDirectory.path.hasSuffix("/") ? allowedDirectory.path : allowedDirectory.path + "/"
        return resolved.path.hasPrefix(prefix) ? resolved : nil
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
        case .unexpectedPrompt(let question):
            return CLIWorkerError.nsError(code: .unexpectedPrompt, description: question)
        case .untrustedBinary:
            return CLIWorkerError.nsError(code: .untrustedBinary, description: error.localizedDescription)
        default:
            return CLIWorkerError.nsError(code: .unknown, description: error.localizedDescription)
        }
    }
}
