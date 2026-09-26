import Foundation
import OSLog

/// App-side executor that delegates subprocess work to the embedded `JamfDashCLIWorker`
/// XPC service (`Contents/XPCServices/be.devliegere.JamfDash.CLIWorker.xpc`).
///
/// `CLIManager.defaultExecutor()` uses it when the service is present in the app bundle.
///
/// Before the first command it pings the worker. If the worker can't be reached (not
/// registered with launchd, signature mismatch, …) and a `fallback` is given, all commands
/// run in-process for the rest of the session. Only the side-effect-free ping triggers the
/// fallback: a command that fails mid-flight is reported, never silently re-run.
actor XPCCLIExecutor: CLIExecuting {
    static let serviceName = CodeSignatureVerifier.workerIdentifier

    private let logger = Logger(subsystem: "com.jamfdash", category: "XPCCLIExecutor")
    private let fallback: (any CLIExecuting)?
    private var connection: NSXPCConnection?
    private var probe: Task<Bool, Never>?

    init(fallback: (any CLIExecuting)? = nil) {
        self.fallback = fallback
    }

    /// True when the worker is bundled with the running app.
    static var isWorkerEmbedded: Bool {
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Contents/XPCServices/\(serviceName).xpc", isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - CLIExecuting

    func execute(
        binary: URL,
        arguments: [String],
        environment: [String: String],
        stdinData: Data?,
        timeout: TimeInterval
    ) async throws -> Data {
        if let fallback, await !isWorkerReachable() {
            return try await fallback.execute(binary: binary, arguments: arguments, environment: environment,
                                              stdinData: stdinData, timeout: timeout)
        }
        return try await call { proxy, reply in
            proxy.execute(
                binaryPath: binary.path,
                arguments: arguments,
                environment: environment,
                stdinData: stdinData ?? Data(),
                timeout: timeout,
                withReply: reply
            )
        }
    }

    func executeInteractive(
        binary: URL,
        arguments: [String],
        environment: [String: String],
        stdinData: Data,
        timeout: TimeInterval
    ) async throws -> Data {
        if let fallback, await !isWorkerReachable() {
            return try await fallback.executeInteractive(binary: binary, arguments: arguments, environment: environment,
                                                         stdinData: stdinData, timeout: timeout)
        }
        return try await call { proxy, reply in
            proxy.executeInteractive(
                binaryPath: binary.path,
                arguments: arguments,
                environment: environment,
                stdinData: stdinData,
                timeout: timeout,
                withReply: reply
            )
        }
    }

    // MARK: - Liveness

    /// Pings the worker once per session; concurrent callers share the same probe.
    func isWorkerReachable() async -> Bool {
        if let probe { return await probe.value }
        let task = Task { await self.ping() }
        probe = task
        let ok = await task.value
        if !ok {
            logger.error("CLI worker unreachable — running jamf-cli in-process for this session")
        }
        return ok
    }

    private func ping() async -> Bool {
        do {
            let data = try await call { proxy, reply in
                proxy.ping { ok in reply(ok ? Data([1]) : nil, nil) }
            }
            return data == Data([1])
        } catch {
            return false
        }
    }

    // MARK: - Connection management

    /// Obtains a proxy whose error handler fails the call, then hands it to `body` with a
    /// reply block. A once-flag guarantees the continuation is resumed exactly once, even
    /// when the service crashes mid-call and both the error handler and reply fire.
    private func call(
        body: (any CLIWorkerXPCProtocol, @escaping @Sendable (Data?, NSError?) -> Void) -> Void
    ) async throws -> Data {
        let conn = try validConnection()
        return try await withCheckedThrowingContinuation { continuation in
            let once = OnceFlag()
            let proxy = conn.remoteObjectProxyWithErrorHandler { [weak self] error in
                if once.claim() {
                    continuation.resume(throwing: CLIError.launchFailed(
                        "CLI worker unavailable: \(error.localizedDescription)"
                    ))
                }
                Task { await self?.invalidate() }
            }
            guard let typed = proxy as? any CLIWorkerXPCProtocol else {
                if once.claim() {
                    continuation.resume(throwing: CLIError.launchFailed("XPC proxy cast failed"))
                }
                return
            }
            body(typed) { data, error in
                guard once.claim() else { return }
                if let error { continuation.resume(throwing: Self.translate(error)) }
                else         { continuation.resume(returning: data ?? Data()) }
            }
        }
    }

    private func validConnection() throws -> NSXPCConnection {
        if let existing = connection { return existing }
        guard let requirement = CodeSignatureVerifier.peerRequirement(identifier: Self.serviceName) else {
            throw CLIError.launchFailed("JamfDash is not signed with a Team ID; refusing to use the CLI worker")
        }
        let conn = NSXPCConnection(serviceName: Self.serviceName)
        conn.remoteObjectInterface = NSXPCInterface(with: CLIWorkerXPCProtocol.self)
        // Only talk to our own worker, signed by the same team as the app.
        conn.setCodeSigningRequirement(requirement)
        conn.invalidationHandler = { [weak self] in Task { await self?.invalidate() } }
        conn.interruptionHandler = { [weak self] in Task { await self?.invalidate() } }
        conn.resume()
        connection = conn
        logger.info("XPC connection established to \(Self.serviceName, privacy: .public)")
        return conn
    }

    private func invalidate() {
        connection?.invalidate()
        connection = nil
        logger.info("XPC connection invalidated — will reconnect on next call")
    }

    // MARK: - Error translation

    private static func translate(_ nsError: NSError) -> CLIError {
        guard nsError.domain == CLIWorkerError.domain else {
            return .launchFailed(nsError.localizedDescription)
        }
        let stderr   = nsError.userInfo[CLIWorkerError.stderrKey]   as? String ?? ""
        let exitCode = nsError.userInfo[CLIWorkerError.exitCodeKey] as? Int    ?? 0
        switch CLIWorkerError.Code(rawValue: nsError.code) {
        case .nonZeroExit:     return .nonZeroExit(code: exitCode, stderr: stderr)
        case .timeout:         return .timeout
        case .untrustedBinary: return .untrustedBinary(nsError.localizedDescription)
        case .launchFailed, .unknown, .none:
            return .launchFailed(nsError.localizedDescription)
        }
    }
}

// MARK: - Helpers

/// Thread-safe single-use flag to guard against double-resuming a continuation.
private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    func claim() -> Bool { lock.withLock { if fired { return false }; fired = true; return true } }
}
