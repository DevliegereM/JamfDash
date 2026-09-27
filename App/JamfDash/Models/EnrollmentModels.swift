import Foundation

// Models for the Enrollment section: the flow a new Mac follows through a PreStage and the
// actual timeline of one Mac. Everything here is in memory only; nothing is written to disk.

// MARK: - Phases

/// The order a Mac goes through enrollment. The flow and the timeline both use it.
enum EnrollmentPhase: Int, CaseIterable, Sendable, Comparable, Identifiable {
    case adeAssignment, setupAssistant, mdmEnrollment, prestageItems, setupManager, profiles
    case policies, apps, ddm, inventory, otherMDM

    var id: Int { rawValue }
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .adeAssignment:  return "ADE assignment"
        case .setupAssistant: return "Setup Assistant"
        case .mdmEnrollment:  return "MDM enrollment"
        case .prestageItems:  return "PreStage items"
        case .setupManager:   return "Setup Manager"
        case .profiles:       return "Configuration profiles"
        case .policies:       return "Policies"
        case .apps:           return "Apps"
        case .ddm:            return "Declarative management"
        case .inventory:      return "Inventory"
        case .otherMDM:       return "Other MDM commands"
        }
    }

    var symbol: String {
        switch self {
        case .adeAssignment:  return "building.2"
        case .setupAssistant: return "macwindow"
        case .mdmEnrollment:  return "person.badge.shield.checkmark"
        case .prestageItems:  return "shippingbox"
        case .setupManager:   return "list.bullet.rectangle.portrait"
        case .profiles:       return "doc.badge.gearshape"
        case .policies:       return "scroll"
        case .apps:           return "app.badge"
        case .ddm:            return "square.stack.3d.up"
        case .inventory:      return "list.clipboard"
        case .otherMDM:       return "antenna.radiowaves.left.and.right"
        }
    }
}

// MARK: - Timeline

enum EnrollmentEventStatus: String, Sendable, Hashable {
    case completed, pending, stuck, failed, info

    var label: String {
        switch self {
        case .completed: return "Done"
        case .pending:   return "Pending"
        case .stuck:     return "Stuck"
        case .failed:    return "Failed"
        case .info:      return "Info"
        }
    }
}

enum EnrollmentSource: String, CaseIterable, Sendable, Hashable {
    case inventory = "Inventory"
    case mdmCommands = "MDM commands"
    case commandHistory = "Command history"
    case policyLogs = "Policy logs"
    case ddm = "DDM status"
}

/// Whether a data source could be read for this Mac.
enum SourceStatus: Sendable, Hashable {
    case ok(count: Int)
    case unavailable(String)
    case notApplicable(String)

    var isOK: Bool { if case .ok = self { return true }; return false }
}

struct EnrollmentEvent: Identifiable, Sendable, Hashable {
    let id: String
    /// When the command was sent or the policy ran.
    let date: Date
    let completedDate: Date?
    let phase: EnrollmentPhase
    /// Readable command type, e.g. "Install Profile", or "Policy".
    let kind: String
    let title: String
    let detail: String?
    var status: EnrollmentEventStatus
    /// Derived from another event (e.g. end of Setup Assistant), not recorded as such by Jamf.
    let isApproximate: Bool
    let source: EnrollmentSource
    let profileIdentifier: String?
}

/// A Mac that enrolled recently, from the inventory list.
struct RecentEnrollment: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let serial: String?
    let enrolledAt: Date?
    let firstSeenAt: Date?
    let method: String?
    let methodID: String?
    /// e.g. "Computer PreStage" or "User-initiated - no invitation".
    var methodType: String? = nil
    let viaADE: Bool?
    let managementId: String?
    let lastContact: Date?
}

/// Everything known about one Mac's enrollment.
struct EnrollmentTimeline: Sendable {
    struct Device: Sendable {
        let computerID: String
        let name: String
        let serial: String
        let managementId: String?
        let enrolledAt: Date?
        let firstSeenAt: Date?
        let lastContact: Date?
        let method: String?
        let methodID: String?
        let supervised: Bool?
        let userApprovedMDM: Bool?
        let groups: [String]
        let department: String?
        let building: String?
    }

    struct InstalledProfile: Sendable, Hashable, Identifiable {
        var id: String { identifier ?? name }
        let name: String
        let identifier: String?
        let installedAt: Date?
        /// Jamf Pro's configuration profile ID, when inventory reports it.
        var jamfID: Int? = nil
    }

    struct DDMSummary: Sendable, Hashable {
        let itemCount: Int
        let awaitingConfiguration: Bool?
        let lastReport: Date?
    }

    let device: Device
    let events: [EnrollmentEvent]
    let sources: [EnrollmentSource: SourceStatus]
    let installedProfiles: [InstalledProfile]
    let ddm: DDMSummary?
    /// The PreStage the Mac enrolled through, when it could be matched.
    let prestage: PrestageDetail?
    /// Shortest history retention from Log Flushing, used to explain missing history.
    let historyRetention: HistoryRetention?
    let loadedAt: Date
}

struct HistoryRetention: Sendable, Hashable {
    let name: String
    let days: Int
    var label: String {
        if days % 365 == 0 { return "\(days / 365) year\(days == 365 ? "" : "s")" }
        if days % 30 == 0 { return "\(days / 30) month\(days == 30 ? "" : "s")" }
        if days % 7 == 0 { return "\(days / 7) week\(days == 7 ? "" : "s")" }
        return "\(days) day\(days == 1 ? "" : "s")"
    }
}

// MARK: - Raw records

struct MDMCommandRecord: Sendable, Hashable {
    let uuid: String?
    let commandType: String
    let status: EnrollmentEventStatus
    let dateSent: Date?
    let dateCompleted: Date?
    let profileIdentifier: String?
    var profileID: Int? = nil
    let errorText: String?
}

struct HistoryCommandRecord: Sendable, Hashable {
    let name: String
    /// What the command was about, e.g. the profile in "Install Configuration Profile Wi-Fi".
    var subject: String? = nil
    let status: EnrollmentEventStatus
    let issued: Date?
    let finished: Date?
    let message: String?
}

struct PolicyLogRecord: Sendable, Hashable {
    let policyID: Int?
    let name: String
    let status: String
    let date: Date?

    var failed: Bool {
        let s = status.lowercased()
        return s.contains("fail") || s.contains("error")
    }
}

// MARK: - PreStage

struct PrestageDetail: Sendable, Hashable {
    let id: String
    let name: String
    let profileIDs: [Int]
    let packageIDs: [Int]
    /// Setup Assistant pane → skipped.
    let skipItems: [String: Bool]
    let customizationID: String?
    let adeInstanceID: String?
    /// Other settings worth showing (label, value), in a stable order.
    let facts: [Fact]

    struct Fact: Sendable, Hashable, Identifiable {
        var id: String { label }
        let label: String
        let value: String
    }

    var skippedPanes: [String] { skipItems.filter(\.value).map(\.key).sorted() }
    var shownPanes: [String] { skipItems.filter { !$0.value }.map(\.key).sorted() }
}

// MARK: - Scope scan

struct ScopedProfile: Sendable, Identifiable {
    let id: Int
    let name: String
    let identifier: String?
    let scope: JamfScope
    /// Set when the profile configures Jamf Setup Manager (`com.jamf.setupmanager`).
    var setupManager: SetupManagerConfig? = nil
}

struct ScopedPolicy: Sendable, Identifiable {
    let id: Int
    let name: String
    let enabled: Bool
    let enrollmentTrigger: Bool
    let scope: JamfScope
    /// Custom event trigger (`jamf policy -event …`), used by Setup Manager policy steps.
    var customTrigger: String? = nil
}

struct ScopeScanResult: Sendable {
    let profiles: [ScopedProfile]
    let policies: [ScopedPolicy]
    let failures: Int
    let scannedAt: Date
}

// MARK: - Setup Manager

/// A Jamf Setup Manager configuration (https://github.com/jamf/setup-manager), read from the
/// configuration profile that sets the `com.jamf.setupmanager` preferences.
struct SetupManagerConfig: Sendable, Hashable {
    let title: String?
    /// "enrollment" (default) or "loginwindow".
    let runAt: String?
    /// "continue" (default), "restart", "shutdown" or "none".
    let finalAction: String?
    let finishedTrigger: String?
    let steps: [SetupManagerStep]

    var runAtLabel: String {
        runAt?.lowercased() == "loginwindow" ? "Starts at the login window" : "Starts right after enrollment"
    }

    var finalActionLabel: String {
        switch (finalAction ?? "continue").lowercased() {
        case "restart":  return "Restarts the Mac when done"
        case "shutdown": return "Shuts down the Mac when done"
        case "none":     return "No button when done"
        default:         return "Continues to Setup Assistant or the login window when done"
        }
    }
}

struct SetupManagerStep: Sendable, Hashable, Identifiable {
    enum Kind: String, Sendable, Hashable {
        case policy, installomator, shell, watchPath, wait, recon, waitForUserEntry, other

        var title: String {
            switch self {
            case .policy:           return "Policy"
            case .installomator:    return "Installomator"
            case .shell:            return "Shell"
            case .watchPath:        return "Wait for file"
            case .wait:             return "Wait"
            case .recon:            return "Inventory"
            case .waitForUserEntry: return "User entry"
            case .other:            return "Other"
            }
        }

        var symbol: String {
            switch self {
            case .policy:           return "scroll"
            case .installomator:    return "arrow.down.app"
            case .shell:            return "terminal"
            case .watchPath:        return "doc.viewfinder"
            case .wait:             return "hourglass"
            case .recon:            return "list.clipboard"
            case .waitForUserEntry: return "person.text.rectangle"
            case .other:            return "questionmark.square"
            }
        }
    }

    let id: Int
    let label: String
    let kind: Kind
    /// The policy trigger, Installomator label, command or path.
    let value: String?
}

/// Setup Manager configuration found in a profile, with where it came from.
struct SetupManagerSource: Sendable, Identifiable {
    var id: Int { profileID }
    let profileID: Int
    let profileName: String
    let config: SetupManagerConfig
    /// Why this one was chosen, e.g. "In the PreStage" or "Chosen in Settings".
    let reason: String
}

/// One Setup Manager step on one Mac.
struct SetupManagerStepRow: Identifiable, Sendable, Hashable {
    var id: Int { step.id }
    let step: SetupManagerStep
    /// Policies with the step's trigger.
    let policies: [String]
    let status: PolicyRowStatus?
    let date: Date?
    let note: String
}

// MARK: - Flow (what a new Mac gets)

enum FlowCertainty: Int, Sendable, Comparable {
    case certain, conditional, excluded
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .certain:     return "Certain"
        case .conditional: return "Conditional"
        case .excluded:    return "Excluded"
        }
    }
}

struct FlowItem: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let certainty: FlowCertainty
    /// Where it comes from or the condition, e.g. "PreStage", "All Computers", "If in “Engineering”".
    let condition: String
    let identifier: String?
}

struct FlowPhase: Identifiable, Sendable {
    var id: Int { phase.rawValue }
    let phase: EnrollmentPhase
    let summary: String
    let lines: [String]
    let items: [FlowItem]
    /// Items only appear after the scope scan.
    let needsScan: Bool
}

struct EnrollmentFlow: Sendable {
    let prestage: PrestageDetail
    let phases: [FlowPhase]
    /// Profiles and policies scoped only to named Macs, left out of the flow.
    let specificOnlyCount: Int
}

// MARK: - Expected vs actual (one Mac)

enum ProfileRowStatus: Int, Sendable, Comparable {
    case failed, stuck, pending, missing, installed, unexpected, notScoped
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .failed:     return "Failed"
        case .stuck:      return "Stuck"
        case .pending:    return "Pending"
        case .missing:    return "Missing"
        case .installed:  return "Installed"
        case .unexpected: return "Unexpected"
        case .notScoped:  return "Not scoped"
        }
    }
}

struct ProfileRow: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let identifier: String?
    let status: ProfileRowStatus
    let source: String
    let reason: String
    let installedAt: Date?
    let lastCommand: String?
}

enum PolicyRowStatus: Int, Sendable, Comparable {
    case failed, notRunYet, completed
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .failed:    return "Failed"
        case .notRunYet: return "No log yet"
        case .completed: return "Completed"
        }
    }
}

struct PolicyRow: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let status: PolicyRowStatus
    let date: Date?
    let enrollmentTriggered: Bool
    let detail: String
}

// MARK: - Parsing

/// Lenient parsers for jamf-cli output. Field names for MDM commands, computer history and
/// PreStage details differ between API versions, so each field accepts several spellings
/// and anything unknown is left out rather than failing the whole timeline.
enum EnrollmentParsing {

    // MARK: Generic helpers

    static func json(_ data: Data) -> Any? {
        guard !data.isEmpty else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    /// Rows from a bare array or an object wrapping it (`results`, `data`, …).
    static func rows(_ data: Data) -> [[String: Any]] {
        let root = json(data)
        if let array = root as? [[String: Any]] { return array }
        if let dict = root as? [String: Any] {
            for key in ["results", "data", "items", "commands"] {
                if let array = dict[key] as? [[String: Any]] { return array }
            }
        }
        return []
    }

    /// Classic API lists: `[..]`, `{"singular": [..]}` or `{"singular": {..}}`.
    static func classicList(_ value: Any?, singular: String) -> [[String: Any]] {
        if let array = value as? [[String: Any]] { return array }
        guard let dict = value as? [String: Any] else { return [] }
        if let inner = dict[singular] {
            if let array = inner as? [[String: Any]] { return array }
            if let single = inner as? [String: Any] { return [single] }
        }
        // A single record without the wrapper.
        return dict.keys.contains("name") ? [dict] : []
    }

    static func string(_ value: Any?) -> String? {
        switch value {
        case let s as String:
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }

    static func int(_ value: Any?) -> Int? {
        switch value {
        case let n as NSNumber: return n.intValue
        case let s as String: return Int(s.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    static func bool(_ value: Any?) -> Bool? {
        switch value {
        case let b as Bool: return b
        case let n as NSNumber: return n.boolValue
        case let s as String:
            switch s.lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: return nil
            }
        default: return nil
        }
    }

    static func first(_ dict: [String: Any], _ keys: [String]) -> Any? {
        for key in keys { if let v = dict[key], !(v is NSNull) { return v } }
        return nil
    }

    /// Dates from epoch milliseconds or seconds, ISO 8601 (with or without fractional
    /// seconds), `yyyy-MM-dd HH:mm:ss` (UTC) or the Classic `yyyy/MM/dd 'at' h:mm a` form.
    static func date(_ value: Any?) -> Date? {
        guard let d = parsedDate(value), d.timeIntervalSince1970 > 978_307_200 else { return nil }
        return d
    }

    private static func parsedDate(_ value: Any?) -> Date? {
        if let n = value as? NSNumber, !(value is Bool) { return epoch(n.doubleValue) }
        guard let s = string(value) else { return nil }
        if let d = Double(s), s.count >= 9 { return epoch(d) }
        if let d = try? Date(s, strategy: .iso8601) { return d }
        if let d = try? Date(s, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return d }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for (format, utc) in [("yyyy-MM-dd'T'HH:mm:ss.SSS", true), ("yyyy-MM-dd'T'HH:mm:ss", true),
                              ("yyyy-MM-dd HH:mm:ss", true), ("yyyy/MM/dd 'at' h:mm a", false),
                              ("yyyy-MM-dd", true)] {
            formatter.dateFormat = format
            formatter.timeZone = utc ? TimeZone(identifier: "UTC") : .current
            if let d = formatter.date(from: s) { return d }
        }
        return nil
    }

    private static func epoch(_ value: Double) -> Date? {
        guard value > 0 else { return nil }
        // Milliseconds when larger than any plausible seconds value.
        return Date(timeIntervalSince1970: value > 100_000_000_000 ? value / 1000 : value)
    }

    /// First date found among `<key>_epoch`, `<key>_utc`, `<key>`.
    static func classicDate(_ dict: [String: Any], _ key: String) -> Date? {
        date(dict["\(key)_epoch"]) ?? date(dict["\(key)_utc"]) ?? date(dict[key])
    }

    // MARK: Command names

    /// "INSTALL_PROFILE", "InstallProfile" and "Install Profile" all become "installprofile".
    static func commandKey(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter }
    }

    /// Readable command type: "INSTALL_PROFILE" → "Install Profile", "InstallProfile" → "Install Profile".
    static func readableCommand(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.contains("_") || trimmed == trimmed.uppercased() {
            return trimmed.split(separator: "_").map { $0.lowercased().capitalized }.joined(separator: " ")
        }
        if trimmed.contains(" ") { return trimmed }
        var out = ""
        for (i, ch) in trimmed.enumerated() {
            if i > 0, ch.isUppercase, let prev = out.last, prev.isLowercase { out.append(" ") }
            out.append(ch)
        }
        return out
    }

    static func phase(forCommand name: String) -> EnrollmentPhase {
        let key = commandKey(name)
        if key.contains("deviceconfigured") { return .setupAssistant }
        if key.contains("enterpriseapplication") { return .prestageItems }
        if key.contains("profile") && !key.contains("list") { return .profiles }
        if key.contains("declarativemanagement") || key.contains("declaration") { return .ddm }
        if key.contains("information") || key.hasSuffix("list") || key.contains("securityinfo")
            || key.contains("inventory") || key.contains("itunesaccount") {
            return .inventory
        }
        if key.contains("installapplication") || key.contains("installmedia") || key.contains("appinstall")
            || key.contains("vpp") || key.contains("managedapplication") || key.contains("installapp") { return .apps }
        return .otherMDM
    }

    static func status(fromState raw: String?, completed: Date?) -> EnrollmentEventStatus {
        let s = (raw ?? "").uppercased()
        if s.contains("ERROR") || s.contains("FAIL") { return .failed }
        if s.contains("ACK") || s.contains("COMPLETE") || s.contains("SUCCESS") { return .completed }
        if s.contains("PENDING") || s.contains("NOT_NOW") || s.contains("NOTNOW") || s.contains("QUEUED") { return .pending }
        return completed == nil ? .pending : .completed
    }

    // MARK: MDM commands (`pro mdm list`)

    static func mdmCommands(_ data: Data) -> [MDMCommandRecord] {
        rows(data).compactMap { row in
            guard let type = string(first(row, ["commandType", "command", "type", "name"])) else { return nil }
            let completed = date(first(row, ["dateCompleted", "completedDate", "completed"]))
            let state = string(first(row, ["commandState", "status", "state"]))
            return MDMCommandRecord(
                uuid: string(first(row, ["uuid", "id"])),
                commandType: type,
                status: status(fromState: state, completed: completed),
                dateSent: date(first(row, ["dateSent", "sentDate", "issued", "validAfter"])),
                dateCompleted: completed,
                profileIdentifier: string(first(row, ["profileIdentifier"])),
                profileID: int(first(row, ["profileId"])),
                errorText: errorText(first(row, ["commandError", "errorMessage", "error", "failureReason"]))
            )
        }
    }

    /// `commandError` is an object (often empty) in the Jamf Pro API; older output uses a string.
    static func errorText(_ value: Any?) -> String? {
        if let s = string(value) { return s }
        guard let dict = value as? [String: Any] else { return nil }
        let text = [first(dict, ["localizedDescription", "description", "message", "errorMessage"]),
                    first(dict, ["code", "errorCode"])].compactMap(string)
        return text.isEmpty ? nil : text.joined(separator: " · ")
    }

    /// Classic history names profile installs "Install Configuration Profile <name>".
    static func splitHistoryName(_ name: String) -> (command: String, subject: String?) {
        for (prefix, command) in [("Install Configuration Profile", "InstallProfile"),
                                  ("Remove Configuration Profile", "RemoveProfile")] {
            if name.hasPrefix(prefix) {
                let rest = name.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
                return (command, rest.isEmpty ? nil : rest)
            }
        }
        return (name, nil)
    }

    // MARK: Computer history (`pro classic-computer-history get --subset …`)

    private static func historyRoot(_ data: Data) -> [String: Any] {
        guard let root = json(data) as? [String: Any] else { return [:] }
        return (root["computer_history"] as? [String: Any]) ?? root
    }

    static func historyCommands(_ data: Data) -> [HistoryCommandRecord] {
        let root = historyRoot(data)
        let commands = (root["commands"] as? [String: Any]) ?? root
        var out: [HistoryCommandRecord] = []
        for row in classicList(commands["completed"], singular: "command") {
            guard let raw = string(row["name"]) else { continue }
            let (name, subject) = splitHistoryName(raw)
            out.append(.init(name: name, subject: subject, status: .completed,
                             issued: classicDate(row, "issued") ?? classicDate(row, "completed"),
                             finished: classicDate(row, "completed"), message: nil))
        }
        for row in classicList(commands["pending"], singular: "command") {
            guard let raw = string(row["name"]) else { continue }
            let (name, subject) = splitHistoryName(raw)
            out.append(.init(name: name, subject: subject, status: .pending,
                             issued: classicDate(row, "issued"), finished: nil,
                             message: string(row["status"])))
        }
        for row in classicList(commands["failed"], singular: "command") {
            guard let raw = string(row["name"]) else { continue }
            let (name, subject) = splitHistoryName(raw)
            out.append(.init(name: name, subject: subject, status: .failed,
                             issued: classicDate(row, "issued") ?? classicDate(row, "failed"),
                             finished: classicDate(row, "failed"), message: string(row["status"])))
        }
        return out
    }

    static func policyLogs(_ data: Data) -> [PolicyLogRecord] {
        let root = historyRoot(data)
        return classicList(root["policy_logs"], singular: "policy_log").compactMap { row in
            guard let name = string(first(row, ["policy_name", "name"])) else { return nil }
            return PolicyLogRecord(policyID: int(first(row, ["policy_id", "id"])), name: name,
                                   status: string(row["status"]) ?? "Unknown",
                                   date: classicDate(row, "date_completed"))
        }
    }

    // MARK: Inventory

    static func recentEnrollments(_ data: Data) -> [RecentEnrollment] {
        rows(data).compactMap { row in
            guard let id = string(row["id"]) else { return nil }
            let general = row["general"] as? [String: Any] ?? [:]
            let hardware = row["hardware"] as? [String: Any] ?? [:]
            let method = enrollmentMethod(general["enrollmentMethod"])
            return RecentEnrollment(
                id: id,
                name: string(general["name"]) ?? string(row["name"]) ?? id,
                serial: string(hardware["serialNumber"]) ?? string(general["serialNumber"]),
                enrolledAt: date(general["lastEnrolledDate"]),
                firstSeenAt: date(general["initialEntryDate"]),
                method: method.name,
                methodID: method.id,
                methodType: method.type,
                viaADE: bool(general["enrolledViaAutomatedDeviceEnrollment"]),
                managementId: string(general["managementId"]),
                lastContact: lastContact(general)
            )
        }
    }

    /// `enrollmentMethod` is a string in older output and `{id, objectName, objectType}` now.
    /// User-initiated enrollment has no `objectName`; the type then names the method.
    static func enrollmentMethod(_ value: Any?) -> (name: String?, id: String?, type: String?) {
        if let s = string(value) { return (s, nil, nil) }
        guard let obj = value as? [String: Any] else { return (nil, nil, nil) }
        let type = string(obj["objectType"])
        return (string(obj["objectName"]) ?? type, string(obj["id"]), type)
    }

    /// True when the enrollment method points at a PreStage (its ID is then a PreStage ID).
    static func isPrestageMethod(type: String?, viaADE: Bool?) -> Bool {
        let t = (type ?? "").lowercased()
        return t.contains("prestage") || t.contains("automated") || viaADE == true
    }

    /// Last check-in: `lastContactTime` in older output, `lastContact` / `lastCheckIn` now.
    static func lastContact(_ general: [String: Any]) -> Date? {
        date(first(general, ["lastContactTime", "lastContact", "lastCheckIn"]))
    }

    /// Installed profiles with their identifier, from the CONFIGURATION_PROFILES section.
    static func installedProfiles(_ data: Data) -> [EnrollmentTimeline.InstalledProfile] {
        guard let row = rows(data).first ?? (json(data) as? [String: Any]) else { return [] }
        let list = row["configurationProfiles"] as? [[String: Any]] ?? []
        return list.compactMap { p in
            guard let name = string(first(p, ["displayName", "name"])) else { return nil }
            return .init(name: name, identifier: string(first(p, ["uuid", "profileIdentifier"])),
                         installedAt: date(p["lastInstalled"]), jamfID: int(p["id"]))
        }
    }

    // MARK: PreStage detail

    static func prestageDetail(_ data: Data) -> PrestageDetail? {
        guard let dict = json(data) as? [String: Any] else { return nil }
        guard let id = string(dict["id"]) else { return nil }
        var skip: [String: Bool] = [:]
        for (key, value) in dict["skipSetupItems"] as? [String: Any] ?? [:] {
            if let b = bool(value) { skip[key] = b }
        }
        let ids: (Any?) -> [Int] = { value in
            (value as? [Any] ?? []).compactMap { int($0) }
        }
        var facts: [PrestageDetail.Fact] = []
        func fact(_ label: String, _ keys: [String], yes: String = "Yes", no: String = "No") {
            guard let v = first(dict, keys) else { return }
            if let n = v as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() {
                facts.append(.init(label: label, value: n.boolValue ? yes : no))
            } else if let s = string(v) {
                facts.append(.init(label: label, value: bool(s).map { $0 ? yes : no } ?? s))
            }
        }
        fact("Mandatory", ["isMandatory", "mandatory"])
        fact("MDM profile removable", ["isMdmRemovable", "mdmRemovable"])
        fact("Supervised", ["isSupervised", "supervised"])
        fact("Auto-advance Setup Assistant", ["autoAdvanceSetup"])
        fact("Install profiles during Setup Assistant", ["installProfilesDuringSetup"])
        fact("Recovery Lock", ["enableRecoveryLock"], yes: "On", no: "Off")
        if let account = dict["accountSettings"] as? [String: Any],
           let type = string(first(account, ["userAccountType", "preFillType"])) {
            facts.append(.init(label: "Local account", value: readableCommand(type)))
        }
        return PrestageDetail(
            id: id,
            name: string(first(dict, ["displayName", "name"])) ?? "PreStage \(id)",
            profileIDs: ids(dict["prestageInstalledProfileIds"]),
            packageIDs: ids(dict["customPackageIds"]),
            skipItems: skip,
            customizationID: string(dict["enrollmentCustomizationId"]).flatMap { $0 == "0" || $0 == "-1" ? nil : $0 },
            adeInstanceID: string(dict["deviceEnrollmentProgramInstanceId"]),
            facts: facts
        )
    }

    // MARK: Policy and profile details (Classic)

    static func scopedPolicy(_ data: Data, id: Int, fallbackName: String) -> ScopedPolicy {
        let root = json(data) as? [String: Any] ?? [:]
        let policy = (root["policy"] as? [String: Any]) ?? root
        let general = policy["general"] as? [String: Any] ?? [:]
        var result = ScopedPolicy(
            id: id,
            name: fallbackName.isEmpty ? (string(general["name"]) ?? "Untitled") : fallbackName,
            enabled: bool(general["enabled"]) ?? true,
            enrollmentTrigger: bool(first(general, ["trigger_enrollment_complete", "triggerEnrollmentComplete"])) ?? false,
            scope: FleetRepository.extractScope(from: data)
        )
        result.customTrigger = string(general["trigger_other"])
        return result
    }

    static func scopedProfile(_ data: Data, id: Int, fallbackName: String) -> ScopedProfile {
        let root = json(data) as? [String: Any] ?? [:]
        let profile = (root["os_x_configuration_profile"] as? [String: Any]) ?? root
        let general = profile["general"] as? [String: Any] ?? [:]
        var result = ScopedProfile(
            id: id,
            name: fallbackName.isEmpty ? (string(general["name"]) ?? "Untitled") : fallbackName,
            identifier: string(first(general, ["uuid", "payload_identifier"])),
            scope: FleetRepository.extractScope(from: data)
        )
        if let payloads = string(general["payloads"]), payloads.contains("enrollmentActions") {
            result.setupManager = setupManager(payloads: payloads)
        }
        return result
    }

    /// Reads Setup Manager's settings from a profile's payload plist. They sit in a custom
    /// settings payload (`com.apple.ManagedClient.preferences` → `com.jamf.setupmanager` →
    /// `Forced` → `mcx_preference_settings`) or directly in a `com.jamf.setupmanager` payload;
    /// the search looks for the dictionary with `enrollmentActions` wherever it is.
    static func setupManager(payloads: String) -> SetupManagerConfig? {
        guard let data = payloads.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let settings = findDictionary(withKey: "enrollmentActions", in: plist),
              let actions = settings["enrollmentActions"] as? [[String: Any]] else { return nil }
        let kinds: [(String, SetupManagerStep.Kind)] = [
            ("policy", .policy), ("installomator", .installomator), ("shell", .shell), ("watchPath", .watchPath),
            ("waitForUserEntry", .waitForUserEntry), ("recon", .recon), ("wait", .wait),
        ]
        let steps = actions.enumerated().map { index, action -> SetupManagerStep in
            let match = kinds.first { action[$0.0] != nil }
            var value = match.flatMap { string(action[$0.0]) }
            if match?.1 == .shell, let args = action["arguments"] as? [String], !args.isEmpty {
                value = ([value ?? ""] + args).joined(separator: " ")
            }
            if match?.1 == .recon || match?.1 == .waitForUserEntry { value = nil }
            return SetupManagerStep(id: index, label: string(action["label"]) ?? "Step \(index + 1)",
                                    kind: match?.1 ?? .other, value: value)
        }
        return SetupManagerConfig(title: string(settings["title"]), runAt: string(settings["runAt"]),
                                  finalAction: string(settings["finalAction"]),
                                  finishedTrigger: string(settings["finishedTrigger"]), steps: steps)
    }

    private static func findDictionary(withKey key: String, in value: Any) -> [String: Any]? {
        if let dict = value as? [String: Any] {
            if dict[key] != nil { return dict }
            for child in dict.values { if let hit = findDictionary(withKey: key, in: child) { return hit } }
        } else if let array = value as? [Any] {
            for child in array { if let hit = findDictionary(withKey: key, in: child) { return hit } }
        }
        return nil
    }

    // MARK: Settings

    /// Shortest retention among the Log Flushing policies that cover command history and policy logs.
    static func historyRetention(_ data: Data) -> HistoryRetention? {
        let root = json(data)
        let list: [[String: Any]] = (root as? [String: Any]).flatMap { $0["retentionPolicies"] as? [[String: Any]] }
            ?? (root as? [[String: Any]]) ?? []
        let relevant = list.compactMap { p -> HistoryRetention? in
            guard let name = string(first(p, ["displayName", "name", "qualifier"])),
                  let period = int(p["retentionPeriod"]), period > 0 else { return nil }
            let lower = name.lowercased()
            guard lower.contains("computer") || lower.contains("policy") || lower.contains("command")
                    || lower.contains("management history") else { return nil }
            let unit = (string(p["retentionPeriodUnit"]) ?? "DAY").uppercased()
            let perUnit = unit.hasPrefix("WEEK") ? 7 : unit.hasPrefix("MONTH") ? 30 : unit.hasPrefix("YEAR") ? 365 : 1
            return HistoryRetention(name: name, days: period * perUnit)
        }
        return relevant.min { $0.days < $1.days }
    }

    /// Check-in frequency in minutes from the client check-in settings.
    static func checkInMinutes(_ data: Data) -> Int? {
        guard let dict = json(data) as? [String: Any] else { return nil }
        return int(first(dict, ["checkInFrequency", "check_in_frequency", "frequency"]))
    }

    /// True for a Jamf management ID (a UUID). Anything else is never put in a filter.
    static func isManagementID(_ value: String) -> Bool {
        value.count == 36 && value.allSatisfy { $0.isHexDigit || $0 == "-" } && value.filter { $0 == "-" }.count == 4
    }
}
