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
            let timedOut = TimeoutFlag()
            let timeout0 = CancellableWorkItem(DispatchWorkItem {
                if process.isRunning {
                    timedOut.set()
                    process.terminate()
                }
            })

            process.terminationHandler = { proc in
                timeout0.cancel()
                // Drain any remaining data
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                let remainingOut = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
                stdoutBuffer.append(remainingOut)
                let remainingErr = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
                stderrBuffer.append(remainingErr)

                continuation.resume(with: CLIExecutor.completion(
                    for: proc,
                    timedOut: timedOut.isSet,
                    stdout: stdoutBuffer.drain(),
                    stderr: stderrBuffer.drain()
                ))
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

    /// Runs an interactive jamf-cli command (setup flows) and answers its questions.
    ///
    /// stdin is a PTY, so tools that call `tcgetattr()` (e.g. Go's `term.ReadPassword`)
    /// work. Instead of piping all answers up front, the output is watched and each answer
    /// is written only after the question it belongs to has been printed — `rules` are
    /// matched by prompt text, in whatever order jamf-cli asks them. If jamf-cli stops at a
    /// question none of the rules recognise, the process is stopped and
    /// `CLIError.unexpectedPrompt` is thrown, so an answer (e.g. a password) can never be
    /// typed into the wrong question. Secret answers are redacted from all returned output
    /// and error messages.
    func executeScripted(
        binary: URL,
        arguments: [String],
        environment: [String: String],
        rules: [PromptRule],
        timeout: TimeInterval,
        unansweredPromptGrace: TimeInterval
    ) async throws -> Data {
        let secrets = rules.filter(\.isSecret).map(\.answer)
        let result: Result<Data, Error> = await withCheckedContinuation { continuation in
            let masterFD = posix_openpt(O_RDWR | O_NOCTTY)
            guard masterFD >= 0 else {
                continuation.resume(returning: .failure(CLIError.launchFailed("posix_openpt failed: \(String(cString: strerror(errno)))")))
                return
            }
            guard grantpt(masterFD) == 0, unlockpt(masterFD) == 0, let slavePath = ptsname(masterFD) else {
                close(masterFD)
                continuation.resume(returning: .failure(CLIError.launchFailed("PTY setup failed")))
                return
            }
            let slaveFD = open(slavePath, O_RDWR)
            guard slaveFD >= 0 else {
                close(masterFD)
                continuation.resume(returning: .failure(CLIError.launchFailed("open slave PTY failed")))
                return
            }

            // No echo, so typed answers never show up in the output.
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
            let driver = PromptDriver(rules: rules, masterFD: masterFD)

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if !chunk.isEmpty { stdoutBuffer.append(chunk); driver.feed(chunk) }
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if !chunk.isEmpty { stderrBuffer.append(chunk); driver.feed(chunk) }
            }

            let timedOut = TimeoutFlag()
            let timeout0 = CancellableWorkItem(DispatchWorkItem {
                if process.isRunning {
                    timedOut.set()
                    process.terminate()
                }
            })

            // Watches for a question nobody answers: output that ends like a prompt and
            // then stays silent. jamf-cli would wait forever; stop it with a clear error.
            let watchdog = DispatchSource.makeTimerSource(queue: .global())
            watchdog.schedule(deadline: .now() + 0.5, repeating: 0.5)
            watchdog.setEventHandler {
                if process.isRunning, driver.isStuckAtUnansweredPrompt(grace: unansweredPromptGrace) {
                    process.terminate()
                }
            }

            process.terminationHandler = { proc in
                timeout0.cancel()
                watchdog.cancel()
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                driver.close()
                stdoutBuffer.append((try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data())
                stderrBuffer.append((try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data())

                if let question = driver.unansweredPrompt {
                    continuation.resume(returning: .failure(CLIError.unexpectedPrompt(question)))
                    return
                }
                continuation.resume(returning: CLIExecutor.completion(
                    for: proc,
                    timedOut: timedOut.isSet,
                    stdout: stdoutBuffer.drain(),
                    stderr: stderrBuffer.drain()
                ))
            }

            do {
                try process.run()
            } catch {
                driver.close()
                continuation.resume(returning: .failure(CLIError.launchFailed(error.localizedDescription)))
                return
            }
            timeout0.schedule(after: timeout)
            watchdog.resume()
        }
        return try Self.redacting(result, secrets: secrets).get()
    }

}

extension CLIExecutor {
    /// Maps a finished process to the value returned to callers.
    ///
    /// - A process killed by a signal (our own timeout sends SIGTERM) is a failure, even
    ///   though its `terminationStatus` is the signal number — SIGTERM is 15, which would
    ///   otherwise collide with jamf-cli's "deprecated endpoint" exit code.
    /// - Exit code 15 from a normal exit is jamf-cli's convention for "API call succeeded but
    ///   the endpoint returned a Deprecation header"; stdout is still valid.
    static func completion(
        for process: Process,
        timedOut: Bool,
        stdout outData: Data,
        stderr errData: Data
    ) -> Result<Data, Error> {
        completion(
            reason: process.terminationReason,
            status: Int(process.terminationStatus),
            timedOut: timedOut,
            stdout: outData,
            stderr: errData
        )
    }

    static func completion(
        reason: Process.TerminationReason,
        status: Int,
        timedOut: Bool,
        stdout outData: Data,
        stderr errData: Data
    ) -> Result<Data, Error> {
        if timedOut {
            return .failure(CLIError.timeout)
        }
        if reason == .uncaughtSignal {
            return .failure(CLIError.nonZeroExit(code: status, stderr: "jamf-cli terminated by signal \(status)"))
        }
        if status == 0 {
            return .success(outData)
        }
        if status == 15, !outData.isEmpty {
            let warning = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            Logger(subsystem: "com.jamfdash", category: "CLIExecutor")
                .warning("Deprecated endpoint (exit 15) — data returned normally. \(warning)")
            return .success(outData)
        }
        // jamf-cli writes JSON errors to stdout (not stderr) when using -o json.
        // Prefer stderr; fall back to stdout so the message is never lost.
        let errOutput = errData.isEmpty ? outData : errData
        let errMsg = String(data: errOutput, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return .failure(CLIError.nonZeroExit(
            code: status,
            stderr: errMsg.isEmpty ? "exit \(status)" : errMsg
        ))
    }
}

extension CLIExecutor {
    /// Removes secret answers from output and error messages before they leave the executor.
    static func redacting(_ result: Result<Data, Error>, secrets: [String]) -> Result<Data, Error> {
        let secrets = secrets.filter { !$0.isEmpty }
        guard !secrets.isEmpty else { return result }
        switch result {
        case .success(let data):
            let text = String(decoding: data, as: UTF8.self)
            return .success(Data(redact(text, secrets: secrets).utf8))
        case .failure(CLIError.nonZeroExit(let code, let stderr)):
            return .failure(CLIError.nonZeroExit(code: code, stderr: redact(stderr, secrets: secrets)))
        case .failure(CLIError.unexpectedPrompt(let question)):
            return .failure(CLIError.unexpectedPrompt(redact(question, secrets: secrets)))
        case .failure(let error):
            return .failure(error)
        }
    }

    /// Replaces every occurrence of each secret — raw, and as it appears inside a JSON string
    /// written by Go (which escapes `&`, `<`, `>` as `\u0026` etc.) — with a placeholder.
    static func redact(_ text: String, secrets: [String]) -> String {
        var result = text
        for secret in secrets where !secret.isEmpty {
            for form in Set([secret, goJSONEscaped(secret), jsonEscaped(secret)]) where !form.isEmpty {
                result = result.replacingOccurrences(of: form, with: "••••••")
            }
        }
        return result
    }

    private static func jsonEscaped(_ s: String) -> String {
        var out = ""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case _ where scalar.value < 0x20: out += String(format: "\\u%04x", scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    private static func goJSONEscaped(_ s: String) -> String {
        jsonEscaped(s)
            .replacingOccurrences(of: "&", with: "\\u0026")
            .replacingOccurrences(of: "<", with: "\\u003c")
            .replacingOccurrences(of: ">", with: "\\u003e")
    }
}

/// One question an interactive jamf-cli command may ask, and the answer to give.
struct PromptRule: Sendable, Equatable {
    /// Text that identifies the question (case-insensitive), e.g. `"Password:"`.
    let prompt: String
    let answer: String
    /// Secret answers are redacted from all output and error messages.
    let isSecret: Bool

    init(_ prompt: String, answer: String, isSecret: Bool = false) {
        self.prompt = prompt
        self.answer = answer
        self.isSecret = isSecret
    }
}

/// Answers questions printed by an interactive process, each at most once, only after the
/// matching prompt text has appeared.
final class PromptDriver: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: [PromptRule]
    private var masterFD: Int32
    /// Output since the last answered question.
    private var pending = ""
    private var lastOutput = Date()
    private var stuckPrompt: String?

    init(rules: [PromptRule], masterFD: Int32) {
        self.remaining = rules
        self.masterFD = masterFD
    }

    /// The question the process stopped at when none of the rules matched it.
    var unansweredPrompt: String? { lock.withLock { stuckPrompt } }

    func feed(_ chunk: Data) {
        lock.withLock {
            pending += String(decoding: chunk, as: UTF8.self)
            lastOutput = Date()
            answerMatchingPrompts()
        }
    }

    /// True (and records the question) when the output has ended in something that looks
    /// like a question for longer than `grace` without any rule answering it.
    func isStuckAtUnansweredPrompt(grace: TimeInterval) -> Bool {
        lock.withLock {
            guard stuckPrompt == nil, Date().timeIntervalSince(lastOutput) >= grace else { return stuckPrompt != nil }
            let tail = pending.trimmingCharacters(in: .whitespaces)
            guard let last = tail.last, [":", "?", "]", ")"].contains(last), !tail.hasSuffix("\n") else { return false }
            let line = tail.components(separatedBy: .newlines).last?.trimmingCharacters(in: .whitespaces) ?? tail
            stuckPrompt = String(line.suffix(200))
            return true
        }
    }

    func close() {
        lock.withLock {
            if masterFD >= 0 { Darwin.close(masterFD); masterFD = -1 }
        }
    }

    private func answerMatchingPrompts() {
        var matched = true
        while matched, masterFD >= 0 {
            matched = false
            let haystack = pending.lowercased()
            // Earliest prompt in the output first, so answers follow the process's order.
            let hits = remaining.enumerated().compactMap { index, rule -> (Int, Range<String.Index>)? in
                guard let r = haystack.range(of: rule.prompt.lowercased()) else { return nil }
                return (index, r)
            }
            guard let (index, range) = hits.min(by: { $0.1.lowerBound < $1.1.lowerBound }) else { return }
            let rule = remaining.remove(at: index)
            var bytes = Array((rule.answer + "\n").utf8)
            _ = bytes.withUnsafeMutableBytes { buf in
                let n = Darwin.write(masterFD, buf.baseAddress, buf.count)
                memset_s(buf.baseAddress, buf.count, 0, buf.count)
                return n
            }
            let offset = haystack.distance(from: haystack.startIndex, to: range.upperBound)
            pending = String(pending.dropFirst(offset))
            matched = true
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

    func executeScripted(
        binary: URL,
        arguments: [String],
        environment: [String: String],
        rules: [PromptRule],
        timeout: TimeInterval
    ) async throws -> Data
}

extension CLIExecutor: CLIExecuting {
    func executeScripted(
        binary: URL,
        arguments: [String],
        environment: [String: String],
        rules: [PromptRule],
        timeout: TimeInterval
    ) async throws -> Data {
        try await executeScripted(binary: binary, arguments: arguments, environment: environment,
                                  rules: rules, timeout: timeout, unansweredPromptGrace: 4)
    }
}

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

/// Set by the timeout work item so the termination handler can tell a timeout
/// apart from any other exit.
final class TimeoutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
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
