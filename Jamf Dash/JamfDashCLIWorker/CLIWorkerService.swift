import Foundation

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
        // Allowlist: only execute binaries from the JamfDash bin directory
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
        let binary = URL(fileURLWithPath: binaryPath)
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
