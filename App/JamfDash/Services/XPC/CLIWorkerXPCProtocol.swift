import Foundation

// MARK: - XPC Protocol
//
// Compiled into BOTH the main app target (JamfDash) and the XPC service target
// (JamfDashCLIWorker), together with CLIExecutor.swift, CLIError.swift and
// CodeSignatureVerifier.swift.
//
// All parameter types use NSXPCConnection-compatible Foundation types:
//   • String / [String] / [String: String] — plist-safe
//   • Data  — bridged from NSData
//   • Double — bridged from NSNumber (TimeInterval is a Double alias)
// URL and typed Swift enums cannot cross the XPC boundary directly.

/// XPC interface between the main app and the CLI background worker service.
@objc protocol CLIWorkerXPCProtocol {

    /// Runs a binary with the given arguments and environment.
    /// `stdinData` may be empty; the service passes nil to the process when it is.
    func execute(
        binaryPath: String,
        arguments: [String],
        environment: [String: String],
        stdinData: Data,
        timeout: Double,
        withReply reply: @escaping (Data?, NSError?) -> Void
    )

    /// Liveness probe. Has no side effects, so the app can safely fall back to in-process
    /// execution when it fails.
    func ping(withReply reply: @escaping (Bool) -> Void)

    /// Interactive setup commands: answers the process's questions by prompt text.
    /// `prompts`, `answers` and `secret` are parallel arrays describing `PromptRule`s.
    func executeScripted(
        binaryPath: String,
        arguments: [String],
        environment: [String: String],
        prompts: [String],
        answers: [String],
        secret: [Bool],
        timeout: Double,
        withReply reply: @escaping (Data?, NSError?) -> Void
    )
}

// MARK: - Error domain shared by both sides

enum CLIWorkerError {
    static let domain = "be.devliegere.JamfDash.CLIWorker"

    enum Code: Int {
        case launchFailed    = 1
        case nonZeroExit     = 2
        case timeout         = 3
        case untrustedBinary = 4
        case unexpectedPrompt = 5
        case unknown         = 99
    }

    static let stderrKey = "stderr"
    static let exitCodeKey = "exitCode"

    static func nsError(code: Code, description: String, stderr: String = "", exitCode: Int = 0) -> NSError {
        NSError(
            domain: domain,
            code: code.rawValue,
            userInfo: [
                NSLocalizedDescriptionKey: description,
                stderrKey: stderr,
                exitCodeKey: exitCode
            ]
        )
    }
}
