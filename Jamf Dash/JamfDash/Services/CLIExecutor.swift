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

            process.terminationHandler = { proc in
                // Drain any remaining data
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                let remainingOut = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
                stdoutBuffer.append(remainingOut)
                let remainingErr = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
                stderrBuffer.append(remainingErr)

                let outData = stdoutBuffer.drain()
                let errData = stderrBuffer.drain()

                if proc.terminationStatus == 0 {
                    continuation.resume(returning: outData)
                } else {
                    // jamf-cli writes JSON errors to stdout (not stderr) when using -o json.
                    // Prefer stderr; fall back to stdout so the message is never lost.
                    let errOutput = errData.isEmpty ? outData : errData
                    let errMsg = String(data: errOutput, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    continuation.resume(throwing: CLIError.nonZeroExit(
                        code: Int(proc.terminationStatus),
                        stderr: errMsg.isEmpty ? "exit \(proc.terminationStatus)" : errMsg
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

            // Timeout guard — terminate the process after the allotted time
            Task.detached {
                try? await Task.sleep(for: .seconds(timeout))
                if process.isRunning {
                    process.terminate()
                }
            }
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

            process.terminationHandler = { proc in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                close(masterFD)

                let remainingOut = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
                stdoutBuffer.append(remainingOut)
                let remainingErr = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
                stderrBuffer.append(remainingErr)

                let outData = stdoutBuffer.drain()
                let errData = stderrBuffer.drain()

                if proc.terminationStatus == 0 {
                    continuation.resume(returning: outData)
                } else {
                    let errOutput = errData.isEmpty ? outData : errData
                    let errMsg = String(data: errOutput, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    continuation.resume(throwing: CLIError.nonZeroExit(
                        code: Int(proc.terminationStatus),
                        stderr: errMsg.isEmpty ? "exit \(proc.terminationStatus)" : errMsg
                    ))
                }
            }

            do {
                try process.run()
                // Write to master; the slave side (process stdin) sees it as keyboard input
                stdinData.withUnsafeBytes { buf in
                    if let ptr = buf.baseAddress, buf.count > 0 {
                        _ = Darwin.write(masterFD, ptr, buf.count)
                    }
                }
            } catch {
                close(masterFD)
                continuation.resume(throwing: CLIError.launchFailed(error.localizedDescription))
                return
            }

            Task.detached {
                try? await Task.sleep(for: .seconds(timeout))
                if process.isRunning { process.terminate() }
            }
        }
    }
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
