import Foundation
import OSLog

/// The last jamf-cli commands of this session, for problem reports: the command name only
/// (e.g. `pro computers-inventory list`), never flags or values, with result and duration.
/// Kept in memory; nothing is written to disk.
final class DiagnosticsJournal: @unchecked Sendable {
    static let shared = DiagnosticsJournal()

    /// Identifies this launch in logs and reports.
    let sessionID = String(UUID().uuidString.prefix(8))
    let launchDate = Date()

    struct Entry: Sendable {
        let date: Date
        let command: String
        let outcome: String
        let seconds: Double
    }

    private let lock = NSLock()
    private var entries: [Entry] = []
    private let limit = 200

    private init() {
        Logger(subsystem: "com.jamfdash", category: "Diagnostics")
            .notice("Session \(self.sessionID, privacy: .public) started")
    }

    /// Records a finished command. Only the words before the first flag or separator are
    /// kept, and only if they look like command names.
    func record(arguments: [String], outcome: String, seconds: Double) {
        let command = Self.commandName(arguments)
        lock.withLock {
            entries.append(Entry(date: Date(), command: command, outcome: outcome, seconds: seconds))
            if entries.count > limit { entries.removeFirst(entries.count - limit) }
        }
    }

    var recent: [Entry] { lock.withLock { entries } }

    /// `["--profile", "X", "pro", "scripts", "get", "-o", "json", "--", "7"]` → `pro scripts get`.
    static func commandName(_ arguments: [String]) -> String {
        var args = arguments[...]
        if args.first == "--profile" { args = args.dropFirst(2) }
        let words = args.prefix { !$0.hasPrefix("-") }
            .prefix(4)
            .filter { $0.range(of: #"^[a-z][a-z0-9-]*$"#, options: .regularExpression) != nil }
        return words.isEmpty ? "(unknown)" : words.joined(separator: " ")
    }

    /// One line per command, oldest first.
    func renderedCommands() -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withTime, .withColonSeparatorInTime]
        let lines = recent.map { e in
            "\(fmt.string(from: e.date))  \(String(format: "%6.2fs", e.seconds))  \(e.outcome.padding(toLength: 22, withPad: " ", startingAt: 0))  \(e.command)"
        }
        return lines.isEmpty ? "No jamf-cli commands ran in this session.\n" : lines.joined(separator: "\n") + "\n"
    }
}
