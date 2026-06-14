import Foundation
import Darwin
import OSLog

/// Wraps Foundation.Process; the single place in the app that spawns subprocesses.
actor CLIExecutor {
    private let logger = Logger(subsystem: "com.jamfdash", category: "CLIExecutor")

    func execute(
        binary: URL,
        arguments: [String],
        environment: [String: String],
        stdinData: Data? = nil,
        timeout: TimeInterval = 60
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            let stdinPipe  = Pipe()

            process.executableURL = binary
            process.arguments = arguments
            process.environment = environment
            process.standardOutput = stdoutPipe
            process.standardError  = stderrPipe
            process.standardInput  = stdinPipe

            // Collect data via readabilityHandler to avoid deadlock on large output.
            let stdoutBuffer = LockedBuffer()
            let stderrBuffer = LockedBuffer()

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if !chunk.isEmpty {
                    stdoutBuffer.append(chunk)
                }
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if !chunk.isEmpty {
                    stderrBuffer.append(chunk)
                }
            }

            // Defined before the handler so it can be captured and cancelled on exit.
            let timeout0 = CancellableWorkItem(DispatchWorkItem { if process.isRunning { process.terminate() } })

            process.terminationHandler = { proc in
                timeout0.cancel()
                // Drain any remaining data
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                let remainingOut = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
                stdoutBuffer.append(remainingOut)
                let remainingErr = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
                stderrBuffer.append(remainingErr)

                let outData = stdoutBuffer.drain()
                let errData = stderrBuffer.drain()
                let status  = Int(proc.terminationStatus)

                if status == 0 {
                    continuation.resume(returning: outData)
                } else if status == 15, !outData.isEmpty {
                    // Exit code 15 is jamf-cli's convention for "API call succeeded but
                    // the endpoint has returned a Deprecation header — migrate callers."
                    // The response data is still valid; log the warning and return stdout.
                    let warning = String(data: errData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    Logger(subsystem: "com.jamfdash", category: "CLIExecutor")
                        .warning("Deprecated endpoint (exit 15) — data returned normally. \(warning)")
                    continuation.resume(returning: outData)
                } else {
                    // jamf-cli writes JSON errors to stdout (not stderr) when using -o json.
                    // Prefer stderr; fall back to stdout so the message is never lost.
                    let errOutput = errData.isEmpty ? outData : errData
                    let errMsg = String(data: errOutput, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    continuation.resume(throwing: CLIError.nonZeroExit(
                        code: status,
                        stderr: errMsg.isEmpty ? "exit \(status)" : errMsg
                    ))
                }
            }

            do {
                try process.run()
                // Write stdin after launch so the process is ready to read
                if let data = stdinData {
                    stdinPipe.fileHandleForWriting.write(data)
                }
                try? stdinPipe.fileHandleForWriting.close()
            } catch {
                continuation.resume(throwing: CLIError.launchFailed(error.localizedDescription))
                return
            }

            timeout0.schedule(after: timeout)
        }
    }

    /// Like `execute()` but uses a PTY as stdin so that tools that call
    /// `tcgetattr()` (e.g. Go's `term.ReadPassword`) don't get ENOTTY.
    func executeInteractive(
        binary: URL,
        arguments: [String],
        environment: [String: String],
        stdinData: Data,
        timeout: TimeInterval = 60
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            // Open a PTY master
            let masterFD = posix_openpt(O_RDWR | O_NOCTTY)
            guard masterFD >= 0 else {
                continuation.resume(throwing: CLIError.launchFailed("posix_openpt failed: \(String(cString: strerror(errno)))"))
                return
            }
            guard grantpt(masterFD) == 0, unlockpt(masterFD) == 0 else {
                close(masterFD)
                continuation.resume(throwing: CLIError.launchFailed("PTY grant/unlock failed"))
                return
            }
            guard let slavePathCStr = ptsname(masterFD) else {
                close(masterFD)
                continuation.resume(throwing: CLIError.launchFailed("ptsname failed"))
                return
            }
            let slaveFD = open(slavePathCStr, O_RDWR)
            guard slaveFD >= 0 else {
                close(masterFD)
                continuation.resume(throwing: CLIError.launchFailed("open slave PTY failed"))
                return
            }

            // Disable echo on the slave so echoed input doesn't fill the PTY buffer
            var tio = termios()
            tcgetattr(slaveFD, &tio)
            tio.c_lflag &= ~tcflag_t(ECHO | ECHOE | ECHOK | ECHONL)
            tcsetattr(slaveFD, TCSANOW, &tio)

            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL  = binary
            process.arguments      = arguments
            process.environment    = environment
            process.standardInput  = FileHandle(fileDescriptor: slaveFD, closeOnDealloc: true)
            process.standardOutput = stdoutPipe
            process.standardError  = stderrPipe

            let stdoutBuffer = LockedBuffer()
            let stderrBuffer = LockedBuffer()

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if !chunk.isEmpty { stdoutBuffer.append(chunk) }
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if !chunk.isEmpty { stderrBuffer.append(chunk) }
            }

            let timeout0 = CancellableWorkItem(DispatchWorkItem { if process.isRunning { process.terminate() } })

            process.terminationHandler = { proc in
                timeout0.cancel()
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                close(masterFD)

                let remainingOut = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
                stdoutBuffer.append(remainingOut)
                let remainingErr = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
                stderrBuffer.append(remainingErr)

                let outData = stdoutBuffer.drain()
                let errData = stderrBuffer.drain()
                let status  = Int(proc.terminationStatus)

                if status == 0 {
                    continuation.resume(returning: outData)
                } else if status == 15, !outData.isEmpty {
                    let warning = String(data: errData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    Logger(subsystem: "com.jamfdash", category: "CLIExecutor")
                        .warning("Deprecated endpoint (exit 15) — data returned normally. \(warning)")
                    continuation.resume(returning: outData)
                } else {
                    let errOutput = errData.isEmpty ? outData : errData
                    let errMsg = String(data: errOutput, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    continuation.resume(throwing: CLIError.nonZeroExit(
                        code: status,
                        stderr: errMsg.isEmpty ? "exit \(status)" : errMsg
                    ))
                }
            }

            do {
                try process.run()
                // Write to master; the slave side (process stdin) sees it as keyboard input.
                // Zero the buffer immediately after writing to minimise the credential's
                // time-in-memory window (memset_s is guaranteed not to be elided by the
                // compiler, unlike plain memset).
                var mutableStdin = stdinData
                mutableStdin.withUnsafeMutableBytes { buf in
                    if let ptr = buf.baseAddress, buf.count > 0 {
                        _ = Darwin.write(masterFD, ptr, buf.count)
                        memset_s(ptr, buf.count, 0, buf.count)
                    }
                }
            } catch {
                close(masterFD)
                continuation.resume(throwing: CLIError.launchFailed(error.localizedDescription))
                return
            }

            timeout0.schedule(after: timeout)
        }
    }
}

// MARK: - CLIExecuting Protocol

/// Shared interface implemented by both the in-process executor and the XPC executor.
/// `CLIManager` depends on this abstraction so the execution backend is swappable.
protocol CLIExecuting: Sendable {
    func execute(
        binary: URL,
        arguments: [String],
        environment: [String: String],
        stdinData: Data?,
        timeout: TimeInterval
    ) async throws -> Data

    func executeInteractive(
        binary: URL,
        arguments: [String],
        environment: [String: String],
        stdinData: Data,
        timeout: TimeInterval
    ) async throws -> Data
}

extension CLIExecutor: CLIExecuting {}

extension CLIExecuting {
    func execute(
        binary: URL,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval
    ) async throws -> Data {
        try await execute(
            binary: binary,
            arguments: arguments,
            environment: environment,
            stdinData: nil,
            timeout: timeout
        )
    }
}

/// Sendable wrapper around DispatchWorkItem so it can be captured by @Sendable closures.
final class CancellableWorkItem: @unchecked Sendable {
    private let item: DispatchWorkItem
    init(_ item: DispatchWorkItem) { self.item = item }
    func schedule(after delay: TimeInterval) {
        DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: item)
    }
    func cancel() { item.cancel() }
}

/// NSLock-backed Sendable buffer for async pipe collection.
final class LockedBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ chunk: Data) {
        lock.withLock { storage.append(chunk) }
    }

    func drain() -> Data {
        lock.withLock {
            let copy = storage
            storage.removeAll(keepingCapacity: false)
            return copy
        }
    }
}
