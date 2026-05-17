import Foundation
import OSLog

/// App-side executor that delegates subprocess work to the `JamfDashCLIWorker` XPC service.
///
/// Drop-in replacement for `CLIExecutor` — wire it in by passing it to `CLIManager`'s `executor`
/// parameter.  The service must be configured in Xcode as an XPC Service target with bundle ID
/// `com.jamfdash.CLIWorker`.
actor XPCCLIExecutor: CLIExecuting {
    private let logger = Logger(subsystem: "com.jamfdash", category: "XPCCLIExecutor")
    private var connection: NSXPCConnection?

    // MARK: - CLIExecuting

    func execute(
        binary: URL,
        arguments: [String],
        environment: [String: String],
        stdinData: Data?,
        timeout: TimeInterval
    ) async throws -> Data {
        try await call { proxy, continuation in
            proxy.execute(
                binaryPath: binary.path,
                arguments: arguments,
                environment: environment,
                stdinData: stdinData ?? Data(),
                timeout: timeout
            ) { data, error in
                if let error { continuation.resume(throwing: Self.translate(error)) }
                else         { continuation.resume(returning: data ?? Data()) }
            }
        }
    }

    func executeInteractive(
        binary: URL,
        arguments: [String],
        environment: [String: String],
        stdinData: Data,
        timeout: TimeInterval
    ) async throws -> Data {
        try await call { proxy, continuation in
            proxy.executeInteractive(
                binaryPath: binary.path,
                arguments: arguments,
                environment: environment,
                stdinData: stdinData,
                timeout: timeout
            ) { data, error in
                if let error { continuation.resume(throwing: Self.translate(error)) }
                else         { continuation.resume(returning: data ?? Data()) }
            }
        }
    }

    // MARK: - Connection management

    /// Obtains a proxy whose error handler resumes `continuation` with a failure, then
    /// hands both to `body`.  This ensures the continuation is always resumed even when
    /// the XPC service is unavailable or crashes mid-call.
    private func call(
        body: (any CLIWorkerXPCProtocol, CheckedContinuation<Data, Error>) -> Void
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let conn = validConnection()
            // Use a once flag so we never resume the continuation twice
            // (error handler + reply could theoretically both fire on an interrupted call).
            let once = OnceFlag()
            let proxy = conn.remoteObjectProxyWithErrorHandler { [weak self] error in
                if once.claim() {
                    continuation.resume(throwing: CLIError.launchFailed(
                        "XPC service unavailable: \(error.localizedDescription)"
                    ))
                }
                Task { await self?.invalidate() }
            }
            guard let typed = proxy as? any CLIWorkerXPCProtocol else {
                continuation.resume(throwing: CLIError.launchFailed(
                    "XPC proxy cast failed"
                ))
                return
            }
            body(typed, continuation)
        }
    }

    private func validConnection() -> NSXPCConnection {
        if let existing = connection { return existing }
        let conn = NSXPCConnection(serviceName: "com.jamfdash.CLIWorker")
        conn.remoteObjectInterface = NSXPCInterface(with: CLIWorkerXPCProtocol.self)
        conn.invalidationHandler = { [weak self] in Task { await self?.invalidate() } }
        conn.interruptionHandler = { [weak self] in Task { await self?.invalidate() } }
        conn.resume()
        connection = conn
        logger.info("XPC connection established to com.jamfdash.CLIWorker")
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
        case .nonZeroExit: return .nonZeroExit(code: exitCode, stderr: stderr)
        case .timeout:     return .timeout
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
