import AppKit
import Foundation
import OSLog

// MARK: - Log collection

enum LogCollector {
    /// `log show` for the com.jamfdash subsystem (the app and its helper), newest part kept
    /// when longer than `maxBytes`. Output is read while `log` runs, so it can't block on a
    /// full pipe.
    static func show(hours: Int, maxBytes: Int = 8 * 1024 * 1024) async throws -> String {
        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
            process.arguments = ["show", "--predicate", "subsystem == \"com.jamfdash\"",
                                 "--last", "\(max(1, min(hours, 48)))h", "--style", "syslog", "--info", "--debug"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let kept = data.count > maxBytes ? data.suffix(maxBytes) : data
            return String(decoding: kept, as: UTF8.self)
        }.value
    }
}

// MARK: - Report content

enum ReportArea: String, CaseIterable, Identifiable, Sendable {
    case general = "General"
    case connection = "Connections and setup"
    case overview = "Overview and Security"
    case devices = "Devices and Device Lookup"
    case configuration = "Configuration, patches and reports"
    case enrollment = "Enrollment"
    case protect = "Jamf Protect"
    case school = "Jamf School"
    case dashie = "Dashie"
    case updates = "Updates"
    var id: String { rawValue }
}

enum ReportFrequency: String, CaseIterable, Identifiable, Sendable {
    case always = "Every time"
    case sometimes = "Sometimes"
    case once = "Once"
    var id: String { rawValue }
}

/// One file in a report. Text files can be edited in the review step.
struct ReportFile: Identifiable, Sendable {
    let id = UUID()
    let name: String
    var text: String?
    var data: Data?
    var included: Bool
    let redactions: LogRedactor.Counts
    /// Explains why the file is there, shown in the review list.
    let note: String

    var byteCount: Int { text.map { $0.utf8.count } ?? data?.count ?? 0 }
}

/// What the person typed and chose, plus the files built from it.
@MainActor
@Observable
final class ProblemReportModel {
    static let recipient = "jamfdash@devliegere.be"
    static let repository = "DevliegereM/JamfDash"

    let reportID = "JD-" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6))

    var summary = ""
    var area: ReportArea = .general
    var frequency: ReportFrequency = .always
    var steps = ""
    var expected = ""
    var actual = ""

    var includeLogs = true
    var logHours = 2
    var includeCommands = true
    var includeCrashReports = true
    var includeServerAddress = false
    var attachments: [URL] = []

    /// An error message the report was started from, if any.
    var context: String?

    private(set) var files: [ReportFile] = []
    private(set) var isPreparing = false
    private(set) var preparationNote: String?
    var reviewed = false
    private(set) var statusMessage: String?

    var canReview: Bool { !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var crashReportCount: Int { CrashReports.recent().count }

    var totalRedactions: LogRedactor.Counts {
        files.filter(\.included).reduce(LogRedactor.Counts()) { $0 + $1.redactions }
    }

    func setText(_ text: String, for id: ReportFile.ID) {
        guard let i = files.firstIndex(where: { $0.id == id }) else { return }
        files[i].text = text
    }

    func setIncluded(_ included: Bool, for id: ReportFile.ID) {
        guard let i = files.firstIndex(where: { $0.id == id }), files[i].name != "report.md" else { return }
        files[i].included = included
    }

    // MARK: Building

    /// Collects and redacts everything for the review step.
    func prepare(environment info: ReportEnvironment) async {
        isPreparing = true
        preparationNote = nil
        reviewed = false
        defer { isPreparing = false }

        let redactor = LogRedactor.forThisMac(hosts: info.serverHosts, names: info.profileNames, serials: [])
        var result: [ReportFile] = []

        let (reportText, reportCounts) = redactor.redact(reportMarkdown(info))
        result.append(ReportFile(name: "report.md", text: reportText, included: true,
                                 redactions: reportCounts, note: "Your description and versions (required)"))

        if includeLogs {
            do {
                let (text, counts) = redactor.redact(try await LogCollector.show(hours: logHours))
                result.append(ReportFile(name: "logs/jamfdash.log", text: text, included: true,
                                         redactions: counts, note: "Jamf Dash logs, last \(logHours) h"))
            } catch {
                preparationNote = "The logs couldn't be read: \(error.localizedDescription)"
            }
        }
        if includeCommands {
            result.append(ReportFile(name: "cli-commands.txt", text: DiagnosticsJournal.shared.renderedCommands(),
                                     included: true, redactions: .init(),
                                     note: "jamf-cli commands of this session, names only"))
        }
        if includeCrashReports {
            for url in CrashReports.recent() {
                guard let raw = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let (text, counts) = redactor.redact(CrashReports.stripIdentifiers(raw))
                result.append(ReportFile(name: "crashes/\(url.lastPathComponent)", text: text, included: true,
                                         redactions: counts, note: "Crash report"))
            }
        }
        for url in attachments {
            guard let data = try? Data(contentsOf: url) else { continue }
            result.append(ReportFile(name: "attachments/\(url.lastPathComponent)", data: data, included: true,
                                     redactions: .init(), note: "Added by you — not redacted, check it"))
        }
        files = result
    }

    private func reportMarkdown(_ info: ReportEnvironment) -> String {
        func section(_ title: String, _ text: String) -> String {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return "## \(title)\n\n\(t.isEmpty ? "_Not given_" : t)\n\n"
        }
        var md = "# Jamf Dash problem report \(reportID)\n\n"
        md += "**Summary:** \(summary.trimmingCharacters(in: .whitespacesAndNewlines))\n\n"
        md += "**Area:** \(area.rawValue) · **How often:** \(frequency.rawValue)\n\n"
        md += section("Steps to reproduce", steps)
        md += section("Expected", expected)
        md += section("What happened", actual)
        if let context, !context.isEmpty {
            md += section("Error shown in the app", context)
        }
        md += "## Environment\n\n"
        md += info.lines(includeServer: includeServerAddress).map { "- \($0)" }.joined(separator: "\n")
        md += "\n"
        return md
    }

    // MARK: Output

    /// Writes the included files to a folder and zips it. The caller owns the returned file.
    func makeZip() throws -> URL {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("JamfDash-\(reportID)-\(UUID().uuidString.prefix(4))")
        let folder = work.appendingPathComponent("JamfDash-\(reportID)", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: folder) }
        var manifest: [[String: Any]] = []
        for file in files where file.included {
            let url = folder.appendingPathComponent(file.name)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let text = file.text { try Data(text.utf8).write(to: url) }
            else if let data = file.data { try data.write(to: url) }
            manifest.append(["file": file.name, "bytes": file.byteCount, "redactions": file.redactions.total])
        }
        let meta: [String: Any] = ["report": reportID, "created": ISO8601DateFormatter().string(from: Date()),
                                   "session": DiagnosticsJournal.shared.sessionID, "files": manifest]
        try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys])
            .write(to: folder.appendingPathComponent("manifest.json"))

        var zipped: URL?
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinationError) { tempZip in
            let dest = work.appendingPathComponent("JamfDash-\(reportID).zip")
            do { try fm.copyItem(at: tempZip, to: dest); zipped = dest } catch { copyError = error }
        }
        if let error = coordinationError ?? (copyError as NSError?) { throw error }
        guard let zipped else { throw CocoaError(.fileWriteUnknown) }
        return zipped
    }

    func saveZip() {
        do {
            let zip = try makeZip()
            let panel = NSSavePanel()
            panel.nameFieldStringValue = zip.lastPathComponent
            panel.allowedContentTypes = [.zip]
            guard panel.runModal() == .OK, let dest = panel.url else { return }
            if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
            try FileManager.default.moveItem(at: zip, to: dest)
            statusMessage = "Saved \(dest.lastPathComponent)."
            NSWorkspace.shared.activateFileViewerSelecting([dest])
        } catch {
            statusMessage = "Couldn't save the report: \(error.localizedDescription)"
        }
    }

    var emailSubject: String { "Jamf Dash problem \(reportID): \(summary.prefix(80))" }

    /// Opens a new email in Mail with the zip attached. Without a mail account set up,
    /// shows the zip in Finder and opens a plain email to attach it to.
    func email() {
        do {
            let zip = try makeZip()
            let body = "Report \(reportID). The zip holds the details; nothing in it was sent before you pressed Send.\n\n\(summary)"
            if let service = NSSharingService(named: .composeEmail), service.canPerform(withItems: [body, zip]) {
                service.recipients = [Self.recipient]
                service.subject = emailSubject
                service.perform(withItems: [body, zip])
                statusMessage = "Your email is ready in Mail. Check it and press Send."
            } else {
                var c = URLComponents()
                c.scheme = "mailto"
                c.path = Self.recipient
                c.queryItems = [URLQueryItem(name: "subject", value: emailSubject), URLQueryItem(name: "body", value: body)]
                if let url = c.url { NSWorkspace.shared.open(url) }
                NSWorkspace.shared.activateFileViewerSelecting([zip])
                statusMessage = "Attach \(zip.lastPathComponent) (shown in Finder) to the email."
            }
        } catch {
            statusMessage = "Couldn't build the report: \(error.localizedDescription)"
        }
    }

    /// A GitHub issue with the description and versions only: the repository is public,
    /// so logs and crash reports never go there.
    func openGitHubIssue(environment info: ReportEnvironment) {
        let redactor = LogRedactor.forThisMac(hosts: info.serverHosts, names: info.profileNames, serials: [])
        func clean(_ s: String) -> String { String(redactor.redact(s).text.prefix(1500)) }
        var c = URLComponents(string: "https://github.com/\(Self.repository)/issues/new")!
        c.queryItems = [
            URLQueryItem(name: "template", value: "bug_report.yml"),
            URLQueryItem(name: "title", value: clean("\(reportID): \(summary)")),
            URLQueryItem(name: "report-id", value: reportID),
            URLQueryItem(name: "area", value: area.rawValue),
            URLQueryItem(name: "steps", value: clean(steps)),
            URLQueryItem(name: "expected", value: clean(expected)),
            URLQueryItem(name: "actual", value: clean(actual)),
            URLQueryItem(name: "environment", value: info.lines(includeServer: false).joined(separator: "\n")),
        ]
        if let url = c.url { NSWorkspace.shared.open(url) }
        statusMessage = "The issue opens in your browser. Logs aren't included on GitHub; email the report for those."
    }
}

// MARK: - Environment

/// Versions and connection facts for a report, read from the app on the main actor.
struct ReportEnvironment: Sendable {
    var appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    var appBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    var osVersion = ProcessInfo.processInfo.operatingSystemVersionString
    var model = ReportEnvironment.hardwareModel()
    var cliVersion: String?
    var connection = "Unknown"
    var isDemo = false
    var serverURL: String?
    var profileNames: [String] = []
    var dashieActions = false
    var destructiveAllowed = false
    var verboseLogging = false

    var serverHosts: [String] { serverURL.map { [$0] } ?? [] }

    func lines(includeServer: Bool) -> [String] {
        var l = [
            "Jamf Dash \(appVersion) (build \(appBuild))",
            "macOS \(osVersion), \(model)",
            "jamf-cli \(cliVersion ?? "not installed")",
            "Connection: \(isDemo ? "Demo mode" : connection)",
        ]
        if includeServer, let serverURL { l.append("Server: \(serverURL)") }
        l.append("Dashie actions: \(dashieActions ? "on" : "off") · destructive actions: \(destructiveAllowed ? "allowed" : "off") · verbose logging: \(verboseLogging ? "on" : "off")")
        l.append("Session \(DiagnosticsJournal.shared.sessionID), started \(DiagnosticsJournal.shared.launchDate.formatted(date: .abbreviated, time: .shortened))")
        return l
    }

    static func hardwareModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }
}

// MARK: - Crash reports

enum CrashReports {
    static let lastSeenKey = "jamfDash.lastSeenCrashReport"

    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports")
    }

    /// Crash reports of the app and its helper from the last 14 days, newest first, at most 3.
    static func recent(days: Int = 14) -> [URL] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        return items
            .filter { $0.lastPathComponent.contains("JamfDash") && ["ips", "crash"].contains($0.pathExtension) }
            .compactMap { url -> (URL, Date)? in
                guard let d = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                      d > cutoff else { return nil }
                return (url, d)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(3)
            .map(\.0)
    }

    /// A crash newer than the last one the person has seen (or reported), for the banner.
    static func unseenCrash() -> URL? {
        let defaults = UserDefaults.standard
        guard let lastSeen = defaults.object(forKey: lastSeenKey) as? Date else {
            // First launch with this feature: older crashes aren't news.
            defaults.set(Date(), forKey: lastSeenKey)
            return nil
        }
        return recent(days: 7).first { url in
            ((try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast) > lastSeen
        }
    }

    static func markSeen() { UserDefaults.standard.set(Date(), forKey: lastSeenKey) }

    /// Removes per-Mac identifiers from the crash report header; the stack stays readable.
    static func stripIdentifiers(_ text: String) -> String {
        var out = text
        for key in ["crashReporterKey", "sleepWakeUUID", "deviceIdentifierForVendor", "userID", "sessionID", "incident_id", "incident", "Anonymous UUID"] {
            out = out.replacingOccurrences(
                of: #""\#(key)"\s*:\s*"[^"]*""#, with: "\"\(key)\" : \"‹removed›\"", options: .regularExpression)
            out = out.replacingOccurrences(
                of: #"(?m)^(\#(key):\s*).*$"#, with: "$1‹removed›", options: .regularExpression)
        }
        return out
    }
}

// MARK: - Opening the form

extension Notification.Name {
    /// Opens the Report a Problem window. `object` may be an error message (String).
    static let openReportProblem = Notification.Name("jamfDash.openReportProblem")
}

@MainActor
enum ReportProblem {
    /// The error message the next report starts with.
    static var pendingContext: String?
    /// A summary to start with (from Dashie), editable in the form.
    static var pendingSummary: String?

    static func open(context: String? = nil) {
        pendingContext = context
        NotificationCenter.default.post(name: .openReportProblem, object: nil)
    }
}
