#if canImport(FoundationModels)
import AppKit
import Foundation
import FoundationModels

// MARK: - Helpers

private typealias JSONObject = [String: Any]
private typealias JSONArray  = [JSONObject]

private func parse(_ data: Data) -> Any? {
    try? JSONSerialization.jsonObject(with: data)
}

private func parseArray(_ data: Data) -> JSONArray? {
    if let arr = parse(data) as? JSONArray { return arr }
    if let wrap = parse(data) as? JSONObject,
       let results = wrap["results"] as? JSONArray { return results }
    return nil
}

/// Output sizes were tuned for a 4 096-token model; macOS 27's on-device models have 8 192
/// (measured on AFM 3 Core Advanced), so tool output may use proportionally more.
enum DashieBudget {
    static let scale: Double = {
        guard #available(macOS 26, *) else { return 1 }
        let size = SystemLanguageModel.default.contextSize
        return min(max(Double(size) / 4_096, 1), 2)
    }()

    static func characters(_ base: Int) -> Int { Int(Double(base) * scale) }
}

/// Cap a string at `limit` chars (scaled to the model's context); append a notice if cut.
private func cap(_ s: String, _ limit: Int = 800) -> String {
    let limit = DashieBudget.characters(limit)
    guard s.count > limit else { return s }
    return String(s.prefix(limit)) + "\n…(truncated)"
}

/// Asks the person to approve an action Dashie wants to run. The text is built from what
/// Jamf Dash looked up itself, never from the model's words. With `typed`, the person must
/// type that exact text before the confirm button works.
/// Shown as a sheet on the key window when there is one.
@MainActor
private func confirmAction(title: String, message: String, confirmTitle: String, typed: String? = nil) async -> Bool {
    #if DEBUG
    if let answer = DashieToolConfirmation.testOverride { return answer(title) }
    #endif
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .warning
    alert.addButton(withTitle: confirmTitle)
    alert.addButton(withTitle: "Cancel")
    var field: NSTextField?
    var observer: NSObjectProtocol?
    if let typed {
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        input.placeholderString = typed
        alert.accessoryView = input
        let confirm = alert.buttons[0]
        confirm.isEnabled = false
        observer = NotificationCenter.default.addObserver(
            forName: NSControl.textDidChangeNotification, object: input, queue: .main
        ) { _ in
            MainActor.assumeIsolated { confirm.isEnabled = input.stringValue == typed }
        }
        field = input
    }
    defer { if let observer { NotificationCenter.default.removeObserver(observer) } }
    let approved: Bool
    if let window = NSApp.keyWindow ?? NSApp.mainWindow {
        if let field { alert.window.initialFirstResponder = field }
        approved = await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { response in
                continuation.resume(returning: response == .alertFirstButtonReturn)
            }
        }
    } else {
        approved = alert.runModal() == .alertFirstButtonReturn
    }
    guard approved else { return false }
    if let typed { return field?.stringValue == typed }
    return true
}

#if DEBUG
/// Lets tests answer action confirmations without showing a dialog. Debug builds only.
@MainActor
enum DashieToolConfirmation {
    static var testOverride: ((String) -> Bool)?
}
#endif

/// Dashie's actions are off until the person turns them on in Settings → Dashie.
enum DashieActions {
    static let enabledKey = "jamfDash.dashieActionsEnabled"
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
}

/// One Mac as Jamf Pro describes it, for the confirmation text.
struct DeviceIdentity: Sendable, Equatable {
    let name: String
    let model: String?
    let serial: String
    let lastContact: String?

    enum Lookup: Sendable, Equatable {
        case found(DeviceIdentity)
        case notFound
        case ambiguous(Int)
        case failed(String)
    }

    static func lookup(serial: String, cli: any CLIRunning) async -> Lookup {
        do {
            return parse(try await cli.run(.deviceIdentity(serial: serial)), serial: serial)
        } catch {
            return .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    static func parse(_ data: Data, serial: String) -> Lookup {
        let json = try? JSONSerialization.jsonObject(with: data)
        let rows = (json as? [[String: Any]]) ?? ((json as? [String: Any])?["results"] as? [[String: Any]]) ?? []
        guard !rows.isEmpty else { return .notFound }
        guard rows.count == 1 else { return .ambiguous(rows.count) }
        let general = rows[0]["general"] as? [String: Any]
        let hardware = rows[0]["hardware"] as? [String: Any]
        let name = (general?["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Unnamed Mac"
        return .found(DeviceIdentity(
            name: String(name.prefix(80)),
            model: (hardware?["model"] as? String).map { String($0.prefix(60)) },
            serial: (hardware?["serialNumber"] as? String) ?? serial,
            lastContact: (general?["lastContactTime"] as? String) ?? (general?["lastReportedDate"] as? String)
        ))
    }

    var description: String {
        var parts = ["“\(name)”"]
        if let model { parts.append(model) }
        parts.append("serial \(serial)")
        if let lastContact, let date = ISO8601DateFormatter().date(from: lastContact) {
            parts.append("last check-in \(date.formatted(.relative(presentation: .named)))")
        }
        return parts.joined(separator: ", ")
    }
}

/// Looks up the Mac, asks the person with what was found, and runs the action.
/// Returns plain text for the model; the CLI output isn't passed back to it.
@available(macOS 26, *)
private func runDeviceAction(
    _ command: CLICommand, serial: String, cli: any CLIRunning,
    title: String, explanation: String, confirmTitle: String, done: String
) async -> String {
    guard DashieActions.isEnabled else {
        return "Actions are turned off. The user can turn them on in Settings → Dashie."
    }
    let device: DeviceIdentity
    switch await DeviceIdentity.lookup(serial: serial, cli: cli) {
    case .found(let d): device = d
    case .notFound: return "No Mac with serial \(serial) was found. Nothing was sent."
    case .ambiguous(let n): return "\(n) Macs match serial \(serial), so nothing was sent. Use Device Lookup instead."
    case .failed(let message): return "Couldn't look up \(serial): \(message). Nothing was sent."
    }
    let confirmed = await confirmAction(
        title: title,
        message: "\(explanation)\n\n\(device.description)",
        confirmTitle: confirmTitle)
    guard confirmed else { return "The user cancelled. Nothing was sent." }
    do {
        _ = try await cli.runConfirmed(command)
        return "\(done) \(device.name) (\(device.serial))."
    } catch {
        return "Failed: \(ErrorMessageFormatter.message(for: error))"
    }
}

// MARK: - Query tools

@available(macOS 26, *)
struct ListComputersTool: Tool {
    let name = "listComputers"
    let description = """
        List managed computers (name, serial number, macOS version, last check-in). \
        Use the optional filters to narrow the list instead of reading the whole fleet.
        """
    let cli: any CLIRunning

    @Generable struct Arguments {
        @Guide(description: "Only Macs whose name contains this text (case-insensitive). Omit for all names.")
        let nameContains: String?
        @Guide(description: "Only Macs on this macOS version or version prefix, e.g. \"15\" or \"14.7\". Omit for all versions.")
        let osVersion: String?
        @Guide(description: "Only Macs that have not checked in for at least this many days. Omit for all.")
        let notSeenForDays: Int?
    }

    struct Filter: Sendable {
        var nameContains: String?
        var osVersion: String?
        var notSeenForDays: Int?

        var isEmpty: Bool { nameContains == nil && osVersion == nil && notSeenForDays == nil }

        var summary: String {
            var parts: [String] = []
            if let n = nameContains { parts.append("name contains “\(n)”") }
            if let v = osVersion { parts.append("macOS \(v)") }
            if let d = notSeenForDays { parts.append("not seen for \(d)+ days") }
            return parts.joined(separator: ", ")
        }
    }

    /// Rows listed in full; beyond this only the count is given.
    static var maxListed: Int { Int(25 * DashieBudget.scale) }

    func call(arguments: Arguments) async throws -> String {
        let filter = Filter(
            nameContains: arguments.nameContains.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 },
            osVersion: arguments.osVersion.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 },
            notSeenForDays: arguments.notSeenForDays.flatMap { $0 > 0 ? $0 : nil }
        )
        do {
            let data = try await cli.run(.computers)
            return Self.summarize(data, filter: filter)
        } catch {
            return "Failed to list computers: \(error.localizedDescription)"
        }
    }

    static func summarize(_ data: Data, filter: Filter = Filter(), now: Date = Date()) -> String {
        let items: JSONArray
        var total: Int? = nil
        if let wrap = parse(data) as? JSONObject,
           let results = wrap["results"] as? JSONArray {
            items = results
            total = wrap["totalCount"] as? Int
        } else if let arr = parse(data) as? JSONArray {
            items = arr
        } else {
            return "Could not parse computer list."
        }

        struct Row { let name, serial, version, lastSeen: String; let lastDate: Date? }
        let rows: [Row] = items.map { item in
            let gen  = item["general"]  as? JSONObject
            let hw   = item["hardware"] as? JSONObject
            let os   = item["operatingSystem"] as? JSONObject
            let lastIn = gen?["lastContactTime"] as? String
                      ?? gen?["lastCheckIn"]     as? String
                      ?? item["lastCheckIn"]     as? String
            return Row(
                name:    gen?["name"]        as? String ?? item["name"]         as? String ?? "Unknown",
                serial:  hw?["serialNumber"] as? String ?? item["serialNumber"] as? String ?? "—",
                version: os?["version"]      as? String ?? item["osVersion"]    as? String ?? "—",
                lastSeen: lastIn.map { String($0.prefix(10)) } ?? "—",
                lastDate: lastIn.flatMap(dayDate)
            )
        }

        let matches = rows.filter { row in
            if let n = filter.nameContains, !row.name.localizedCaseInsensitiveContains(n) { return false }
            if let v = filter.osVersion, !(row.version == v || row.version.hasPrefix(v + ".")) { return false }
            if let days = filter.notSeenForDays {
                guard let last = row.lastDate else { return true }   // never seen counts as not seen
                if now.timeIntervalSince(last) < Double(days) * 86_400 { return false }
            }
            return true
        }

        let count = total ?? items.count
        var lines = ["Total: \(count) managed Mac\(count == 1 ? "" : "s")."]
        if !filter.isEmpty {
            lines.append("Matching \(filter.summary): \(matches.count).")
        }
        for row in matches.prefix(maxListed) {
            lines.append("• \(row.name) (SN: \(row.serial)) — macOS \(row.version) — last seen \(row.lastSeen)")
        }
        if matches.count > maxListed {
            lines.append("… and \(matches.count - maxListed) more. Use a filter to narrow the list.")
        }
        return cap(lines.joined(separator: "\n"), 2400)
    }

    /// The day of a Jamf timestamp such as `2026-09-01T10:12:00.123Z`.
    private static func dayDate(_ timestamp: String) -> Date? {
        let day = timestamp.prefix(10)
        guard day.count == 10 else { return nil }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(day))
    }
}

@available(macOS 26, *)
struct GetComputerDetailTool: Tool {
    let name = "getComputerDetail"
    let description = """
        Get complete details for a specific Mac: make, model, CPU type and speed, \
        RAM amount, disk size and free space, serial number, macOS version, last check-in, \
        enrolled user, group membership, MDM status, and installed software. \
        Use this to answer any hardware-spec question about a known device. Requires the serial number.
        """
    let cli: any CLIRunning

    @Generable struct Arguments {
        @Guide(description: "The serial number of the Mac to look up (e.g. C02XG2JCJG5J)")
        let serialNumber: String
    }

    func call(arguments: Arguments) async throws -> String {
        do {
            let data = try await cli.run(.computerDetail(serial: arguments.serialNumber))
            return Self.summarize(data, serial: arguments.serialNumber)
        } catch {
            return "Failed to get details for \(arguments.serialNumber): \(error.localizedDescription)"
        }
    }

    static func summarize(_ data: Data, serial: String) -> String {
        // The command returns a paged list filtered to one device.
        let item: JSONObject?
        if let wrap = parse(data) as? JSONObject,
           let results = wrap["results"] as? JSONArray {
            item = results.first
        } else if let arr = parse(data) as? JSONArray {
            item = arr.first
        } else if let obj = parse(data) as? JSONObject {
            item = obj
        } else {
            return "Could not parse device detail."
        }
        guard let item else { return "Device \(serial) not found." }

        let gen = item["general"]          as? JSONObject
        let hw  = item["hardware"]         as? JSONObject
        let os  = item["operatingSystem"]  as? JSONObject
        let sec = item["security"]         as? JSONObject
        let loc = item["location"]         as? JSONObject
        let grp = item["groupMemberships"] as? JSONArray

        var lines: [String] = []
        func add(_ label: String, _ value: String?) {
            if let v = value, !v.isEmpty { lines.append("\(label): \(v)") }
        }

        add("Name",        gen?["name"] as? String)
        add("Serial",      hw?["serialNumber"] as? String ?? serial)
        add("Model",       hw?["model"] as? String)
        add("Chip",        hw?["processorType"] as? String)
        let ramMB = hw?["totalRamMegabytes"] as? Int
        add("RAM",         ramMB.map { "\($0 / 1024) GB" })
        add("macOS",       os?["version"] as? String)
        add("FileVault",   os?["fileVault2Status"] as? String)
        add("Last seen",   (gen?["lastContactTime"] as? String).map { String($0.prefix(19)) })
        add("User",        loc?["username"] as? String ?? loc?["realName"] as? String)
        add("Department",  loc?["department"] as? String)
        add("Supervised",  (gen?["supervised"] as? Bool).map { $0 ? "Yes" : "No" })
        let sipEnabled = sec?["sipStatus"] as? String
        add("SIP",         sipEnabled)
        add("Firewall",    (sec?["firewallEnabled"] as? Bool).map { $0 ? "Enabled" : "Disabled" })

        if let groups = grp, !groups.isEmpty {
            let names = groups.compactMap { $0["groupName"] as? String ?? $0["name"] as? String }.prefix(10)
            if !names.isEmpty { lines.append("Groups: \(names.joined(separator: ", "))") }
        }

        return cap(lines.joined(separator: "\n"), 1200)
    }
}

@available(macOS 26, *)
struct GetSecurityReportTool: Tool {
    let name = "getSecurityReport"
    let description = "Get the security posture report: FileVault, Gatekeeper, SIP, firewall, and MDM-lock status across all managed Macs."
    let cli: any CLIRunning

    @Generable struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        do {
            let data = try await cli.run(.securityReport)
            return Self.summarize(data)
        } catch {
            return "Failed to fetch security report: \(error.localizedDescription)"
        }
    }

    static func summarize(_ data: Data) -> String {
        guard let rows = parse(data) as? JSONArray else { return "Could not parse security report." }
        var lines: [String] = []

        // Summary row
        if let summary = rows.first(where: { ($0["section"] as? String) == "summary" }),
           let d = summary["data"] as? JSONObject {
            let total = d["total_devices"] as? Int ?? 0
            lines.append("Security report — \(total) devices:")
            for key in ["filevault_encrypted", "gatekeeper_enabled", "sip_enabled", "firewall_enabled"] {
                if let n = d[key] as? Int, let pct = d["\(key)_pct"] as? String {
                    let label = key.replacingOccurrences(of: "_", with: " ").capitalized
                    lines.append("  \(label): \(n)/\(total) (\(pct))")
                }
            }
        }

        // OS version breakdown
        let osRows = rows.filter { ($0["section"] as? String) == "os_version" }
        if !osRows.isEmpty {
            lines.append("macOS versions:")
            for row in osRows.prefix(8) {
                let ver = row["os_version"] as? String ?? "?"
                let cnt = row["count"] as? Int ?? 0
                let pct = row["pct"] as? String ?? ""
                lines.append("  \(ver): \(cnt) (\(pct))")
            }
        }

        // Non-compliant devices
        let devices = rows.filter { ($0["section"] as? String) == "device" }
        let nonCompliant = devices.filter {
            ($0["filevault"] as? String) == "NOT_ENCRYPTED"
            || ($0["sip"] as? String) == "DISABLED"
            || ($0["gatekeeper"] as? String) == "DISABLED"
            || ($0["firewall"] as? Bool) == false
        }
        if !nonCompliant.isEmpty {
            lines.append("Non-compliant devices (\(nonCompliant.count)):")
            for dev in nonCompliant.prefix(20) {
                let name   = dev["name"]   as? String ?? "Unknown"
                let serial = dev["serial"] as? String ?? "—"
                var issues: [String] = []
                if (dev["filevault"]  as? String) == "NOT_ENCRYPTED"  { issues.append("no FileVault") }
                if (dev["sip"]        as? String) == "DISABLED"        { issues.append("SIP off") }
                if (dev["gatekeeper"] as? String) == "DISABLED"        { issues.append("Gatekeeper off") }
                if (dev["firewall"]   as? Bool)   == false             { issues.append("firewall off") }
                lines.append("  • \(name) (\(serial)): \(issues.joined(separator: ", "))")
            }
            if nonCompliant.count > 20 { lines.append("  … and \(nonCompliant.count - 20) more.") }
        } else if !devices.isEmpty {
            lines.append("All \(devices.count) devices are compliant.")
        }

        return cap(lines.joined(separator: "\n"), 1400)
    }
}

@available(macOS 26, *)
struct GetComplianceTool: Tool {
    let name = "getCompliance"
    let description = "Get device compliance status: which computers meet organisational security requirements and which do not."
    let cli: any CLIRunning

    @Generable struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        do {
            let data = try await cli.run(.reportDeviceCompliance)
            return Self.summarize(data)
        } catch {
            return "Failed to fetch compliance report: \(error.localizedDescription)"
        }
    }

    static func summarize(_ data: Data) -> String {
        // Try array-of-rows format
        if let rows = parseArray(data) {
            let compliant    = rows.filter { ($0["compliant"] as? Bool) == true
                                          || ($0["status"]   as? String)?.lowercased() == "compliant" }
            let nonCompliant = rows.filter { ($0["compliant"] as? Bool) == false
                                          || ($0["status"]   as? String)?.lowercased() == "non-compliant"
                                          || ($0["status"]   as? String)?.lowercased() == "noncompliant" }
            var lines = ["Compliance — \(rows.count) devices: \(compliant.count) compliant, \(nonCompliant.count) non-compliant."]
            if !nonCompliant.isEmpty {
                lines.append("Non-compliant:")
                for dev in nonCompliant.prefix(20) {
                    let name   = dev["name"]         as? String ?? dev["computerName"] as? String ?? "Unknown"
                    let serial = dev["serialNumber"] as? String ?? dev["serial"]       as? String ?? "—"
                    lines.append("  • \(name) (\(serial))")
                }
                if nonCompliant.count > 20 { lines.append("  … and \(nonCompliant.count - 20) more.") }
            }
            return cap(lines.joined(separator: "\n"))
        }
        // Fallback: format any top-level keys as stats
        if let obj = parse(data) as? JSONObject {
            let pairs = obj.map { "\($0.key): \($0.value)" }.sorted().prefix(30)
            return cap(pairs.joined(separator: "\n"))
        }
        return "Could not parse compliance report."
    }
}

@available(macOS 26, *)
struct GetOverviewTool: Tool {
    let name = "getOverview"
    let description = "Get a high-level summary of the Jamf Pro instance: total device count, recent enrolments, OS distribution, and key stats."
    let cli: any CLIRunning

    @Generable struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        do {
            let data = try await cli.run(.overview)
            return Self.summarize(data)
        } catch {
            return "Failed to fetch overview: \(error.localizedDescription)"
        }
    }

    static func summarize(_ data: Data) -> String {
        guard let rows = parse(data) as? JSONArray else { return "Could not parse overview." }
        // Group by section
        var sections: [String: [(String, String)]] = [:]
        var order: [String] = []
        for row in rows {
            let section  = row["section"]  as? String ?? "Other"
            let resource = row["resource"] as? String ?? ""
            let value    = row["value"]    as? String ?? ""
            if sections[section] == nil { order.append(section) }
            sections[section, default: []].append((resource, value))
        }
        var lines: [String] = []
        for section in order {
            lines.append("\(section):")
            for (res, val) in sections[section] ?? [] {
                lines.append("  \(res): \(val)")
            }
        }
        return cap(lines.joined(separator: "\n"), 1200)
    }
}

@available(macOS 26, *)
struct GetPatchStatusTool: Tool {
    let name = "getPatchStatus"
    let description = "Get patch management status across the fleet: which software titles are up-to-date, outdated, or missing patches."
    let cli: any CLIRunning

    @Generable struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        do {
            let data = try await cli.run(.reportPatchStatus)
            return Self.summarize(data)
        } catch {
            return "Failed to fetch patch status: \(error.localizedDescription)"
        }
    }

    static func summarize(_ data: Data) -> String {
        guard let rows = parseArray(data) else {
            if let obj = parse(data) as? JSONObject {
                let pairs = obj.map { "\($0.key): \($0.value)" }.sorted().prefix(30)
                return cap(pairs.joined(separator: "\n"))
            }
            return "Could not parse patch status."
        }
        var upToDate = 0, outdated = 0, unknown = 0
        var outdatedTitles: [(String, Int)] = []
        for row in rows {
            let status = (row["status"] as? String ?? row["patchStatus"] as? String ?? "").lowercased()
            let title  = row["name"] as? String ?? row["title"] as? String ?? row["softwareTitle"] as? String ?? ""
            let affected = row["devicesAffected"] as? Int ?? row["affected"] as? Int ?? 0
            if status.contains("up") || status == "current" || status == "latest" {
                upToDate += 1
            } else if status.contains("out") || status == "outdated" || status == "behind" {
                outdated += 1
                if !title.isEmpty { outdatedTitles.append((title, affected)) }
            } else {
                unknown += 1
            }
        }
        var lines = ["Patch status — \(rows.count) titles: \(upToDate) current, \(outdated) outdated, \(unknown) unknown."]
        if !outdatedTitles.isEmpty {
            lines.append("Outdated titles:")
            for (title, count) in outdatedTitles.sorted(by: { $0.1 > $1.1 }).prefix(20) {
                let suffix = count > 0 ? " (\(count) device\(count == 1 ? "" : "s"))" : ""
                lines.append("  • \(title)\(suffix)")
            }
        }
        return cap(lines.joined(separator: "\n"))
    }
}

@available(macOS 26, *)
struct GetPoliciesTool: Tool {
    let name = "getPolicies"
    let description = "List all Jamf Pro policies: names, enabled/disabled state, triggers, frequency, and scope."
    let cli: any CLIRunning

    @Generable struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        do {
            let data = try await cli.run(.policies)
            return Self.summarize(data)
        } catch {
            return "Failed to fetch policies: \(error.localizedDescription)"
        }
    }

    static func summarize(_ data: Data) -> String {
        guard let rows = parseArray(data) else { return "Could not parse policies." }
        // Group by category
        var categories: [String: [String]] = [:]
        var order: [String] = []
        for row in rows {
            let name    = row["name"] as? String ?? "Unnamed"
            let catObj  = row["category"] as? JSONObject
            let catName = catObj?["name"] as? String
                       ?? row["categoryName"] as? String
                       ?? row["category"] as? String
                       ?? "Uncategorised"
            let enabled = row["enabled"] as? Bool
            let suffix  = enabled == false ? " [disabled]" : ""
            if categories[catName] == nil { order.append(catName) }
            categories[catName, default: []].append(name + suffix)
        }
        var lines = ["Policies — \(rows.count) total:"]
        for cat in order {
            let names = categories[cat] ?? []
            lines.append("\(cat) (\(names.count)):")
            for n in names.prefix(10) { lines.append("  • \(n)") }
            if names.count > 10 { lines.append("  … and \(names.count - 10) more.") }
        }
        return cap(lines.joined(separator: "\n"), 1200)
    }
}

@available(macOS 26, *)
struct GetSmartGroupsTool: Tool {
    let name = "getSmartGroups"
    let description = "List all smart computer groups: names, member counts, and criteria."
    let cli: any CLIRunning

    @Generable struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        do {
            let data = try await cli.run(.smartComputerGroups)
            return Self.summarize(data)
        } catch {
            return "Failed to fetch smart groups: \(error.localizedDescription)"
        }
    }

    static func summarize(_ data: Data) -> String {
        guard let rows = parseArray(data) else { return "Could not parse smart groups." }
        var lines = ["Smart groups — \(rows.count) total:"]
        for row in rows.prefix(50) {
            let name  = row["name"]               as? String ?? "Unknown"
            let count = row["memberCount"]        as? Int
                     ?? row["size"]               as? Int
                     ?? row["computerCount"]      as? Int
            let suffix = count.map { " (\($0) member\($0 == 1 ? "" : "s"))" } ?? ""
            lines.append("• \(name)\(suffix)")
        }
        if rows.count > 50 { lines.append("… and \(rows.count - 50) more.") }
        return cap(lines.joined(separator: "\n"), 1200)
    }
}

@available(macOS 26, *)
struct GetInventorySummaryTool: Tool {
    let name = "getInventorySummary"
    let description = """
        Get a fleet-wide inventory summary: breakdown by hardware model (MacBook Pro, Mac mini, …), \
        CPU types, RAM distribution, disk sizes, macOS version spread, and storage usage. \
        Use this to answer fleet-level hardware questions such as \
        "how many devices have 8 GB RAM?" or "which Mac models are in use?".
        """
    let cli: any CLIRunning

    @Generable struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        do {
            let data = try await cli.run(.reportInventorySummary)
            return Self.summarize(data)
        } catch {
            return "Failed to fetch inventory summary: \(error.localizedDescription)"
        }
    }

    static func summarize(_ data: Data) -> String {
        // The inventory summary report may be a flat array of category rows
        // or a structured object — handle both shapes defensively.
        if let rows = parseArray(data) {
            // Group by section/category key
            var sections: [String: [String]] = [:]
            var order: [String] = []
            for row in rows {
                let section = row["section"] as? String
                           ?? row["category"] as? String
                           ?? row["type"]     as? String
                           ?? "Other"
                let label = row["name"]  as? String
                         ?? row["model"] as? String
                         ?? row["value"] as? String
                         ?? row["label"] as? String
                         ?? ""
                let count = row["count"] as? Int
                         ?? row["total"] as? Int
                         ?? row["deviceCount"] as? Int
                let pct   = row["pct"]  as? String ?? ""
                let entry = "\(label): \(count.map(String.init) ?? "—")\(pct.isEmpty ? "" : " (\(pct))")"
                if sections[section] == nil { order.append(section) }
                sections[section, default: []].append(entry)
            }
            var lines: [String] = ["Inventory summary:"]
            for section in order {
                lines.append("\(section):")
                for entry in (sections[section] ?? []).prefix(15) { lines.append("  \(entry)") }
            }
            return cap(lines.joined(separator: "\n"), 1200)
        }
        if let obj = parse(data) as? JSONObject {
            let pairs = obj.map { "\($0.key): \($0.value)" }.sorted().prefix(40)
            return cap("Inventory summary:\n" + pairs.joined(separator: "\n"), 1200)
        }
        return "Could not parse inventory summary."
    }
}

@available(macOS 26, *)
struct GetInstalledAppsTool: Tool {
    let name = "getInstalledApps"
    let description = "Get the list of applications installed on a specific Mac. Returns app names, versions, and bundle IDs. Requires the serial number."
    let cli: any CLIRunning

    @Generable struct Arguments {
        @Guide(description: "Serial number of the Mac (e.g. C02XG2JCJG5J)")
        let serialNumber: String
    }

    func call(arguments: Arguments) async throws -> String {
        do {
            let data = try await cli.run(.installedApps(serial: arguments.serialNumber))
            return Self.summarize(data)
        } catch {
            return "Failed to get installed apps for \(arguments.serialNumber): \(error.localizedDescription)"
        }
    }

    static func summarize(_ data: Data) -> String {
        let obj: JSONObject?
        if let wrap = parse(data) as? JSONObject, let results = wrap["results"] as? JSONArray {
            obj = results.first
        } else if let arr = parse(data) as? JSONArray {
            obj = arr.first
        } else {
            obj = parse(data) as? JSONObject
        }
        // Try common keys for the software/app list
        let appsRaw: Any? = obj?["software"] ?? obj?["applications"] ?? obj?["installedApplications"]
        let apps: JSONArray?
        if let a = appsRaw as? JSONArray { apps = a }
        else if let wrapped = appsRaw as? JSONObject {
            apps = wrapped["applications"] as? JSONArray ?? wrapped["installedApplications"] as? JSONArray
        } else { apps = nil }

        guard let apps else { return "No app list found for this device." }
        var lines = ["\(apps.count) app\(apps.count == 1 ? "" : "s") installed:"]
        for app in apps.prefix(60) {
            let name    = app["name"]        as? String ?? app["applicationTitle"] as? String ?? "Unknown"
            let version = app["version"]     as? String ?? app["applicationVersion"] as? String ?? ""
            let suffix  = version.isEmpty ? "" : " \(version)"
            lines.append("• \(name)\(suffix)")
        }
        if apps.count > 60 { lines.append("… and \(apps.count - 60) more.") }
        return cap(lines.joined(separator: "\n"), 1400)
    }
}

@available(macOS 26, *)
struct SearchFleetKnowledgeTool: Tool {
    let name = "searchFleetKnowledge"
    let description = """
        Search a local index of this Jamf instance by keyword: names of policies, configuration \
        profiles, scripts, packages, smart groups and Macs, blueprint states, compliance rule \
        results and past daily digests. Use it for "what do we have for X?", to find objects \
        by name, or for what earlier digests said.
        """

    @Generable struct Arguments {
        @Guide(description: "Keywords to look up, e.g. \"FileVault\", \"Chrome\", \"digest patches\"")
        let query: String
    }

    func call(arguments: Arguments) async throws -> String {
        let query = String(arguments.query.prefix(200))
        return await MainActor.run { FleetKnowledgeStore.shared.answer(query) }
    }
}

@available(macOS 26, *)
struct SearchHelpTool: Tool {
    let name = "searchHelp"
    let description = """
        Search Jamf Dash's own help: how to use the app, where things are, setup, \
        connections and permissions, Dashie, and troubleshooting. Use it for "how do I…", \
        "where is…" and "why is … greyed out / not working" questions about Jamf Dash.
        """

    @Generable struct Arguments {
        @Guide(description: "The user's question or its key words, e.g. \"add Platform API connection\"")
        let query: String
    }

    func call(arguments: Arguments) async throws -> String {
        HelpSearch.answer(String(arguments.query.prefix(200)), characterLimit: DashieBudget.characters(2_400))
    }
}

// MARK: - Device action tools

@available(macOS 26, *)
struct BlankPushTool: Tool {
    let name = "blankPush"
    let description = "Send a blank MDM push to a Mac to wake it up and prompt it to check in with Jamf Pro. Requires the serial number."
    let cli: any CLIRunning

    @Generable struct Arguments {
        @Guide(description: "Serial number of the Mac to push (e.g. C02XG2JCJG5J)")
        let serialNumber: String
    }

    func call(arguments: Arguments) async throws -> String {
        let serial = String(arguments.serialNumber.prefix(40))
        return await runDeviceAction(.blankPush(serial: serial), serial: serial, cli: cli,
                                     title: "Send Blank Push", explanation: "Dashie wants to send a blank push, which asks this Mac to check in:",
                                     confirmTitle: "Send", done: "Blank push sent to")
    }
}

@available(macOS 26, *)
struct RenewMDMProfileTool: Tool {
    let name = "renewMDMProfile"
    let description = "Renew the MDM profile on a Mac. Use when the device has lost MDM trust or shows as 'MDM profile expired'. Requires the serial number."
    let cli: any CLIRunning

    @Generable struct Arguments {
        @Guide(description: "Serial number of the Mac")
        let serialNumber: String
    }

    func call(arguments: Arguments) async throws -> String {
        let serial = String(arguments.serialNumber.prefix(40))
        return await runDeviceAction(.renewMDM(serial: serial), serial: serial, cli: cli,
                                     title: "Renew MDM Profile", explanation: "Dashie wants to renew the MDM profile on this Mac:",
                                     confirmTitle: "Renew", done: "MDM profile renewal sent to")
    }
}

@available(macOS 26, *)
struct RedeployFrameworkTool: Tool {
    let name = "redeployFramework"
    let description = "Redeploy the Jamf Pro management framework on a Mac. Use when the Jamf binary is missing or corrupted. Requires the serial number."
    let cli: any CLIRunning

    @Generable struct Arguments {
        @Guide(description: "Serial number of the Mac")
        let serialNumber: String
    }

    func call(arguments: Arguments) async throws -> String {
        let serial = String(arguments.serialNumber.prefix(40))
        return await runDeviceAction(.redeployFramework(serial: serial), serial: serial, cli: cli,
                                     title: "Redeploy Management Framework", explanation: "Dashie wants to redeploy the Jamf management framework on this Mac:",
                                     confirmTitle: "Redeploy", done: "Framework redeploy sent to")
    }
}

@available(macOS 26, *)
struct FlushFailedCommandsTool: Tool {
    let name = "flushFailedCommands"
    let description = "Flush all failed MDM commands from the queue for a specific Mac. Use when a device is stuck processing failed commands. Requires the serial number."
    let cli: any CLIRunning

    @Generable struct Arguments {
        @Guide(description: "Serial number of the Mac")
        let serialNumber: String
    }

    func call(arguments: Arguments) async throws -> String {
        let serial = String(arguments.serialNumber.prefix(40))
        return await runDeviceAction(.flushFailedCommands(serial: serial), serial: serial, cli: cli,
                                     title: "Flush Failed Commands", explanation: "Dashie wants to remove all failed MDM commands queued for this Mac:",
                                     confirmTitle: "Flush", done: "Failed commands flushed for")
    }
}

@available(macOS 26, *)
struct RestartDeviceTool: Tool {
    let name = "restartDevice"
    let description = "Remotely restart a Mac via MDM. The device will restart immediately. Requires the serial number."
    let cli: any CLIRunning

    @Generable struct Arguments {
        @Guide(description: "Serial number of the Mac to restart")
        let serialNumber: String
    }

    func call(arguments: Arguments) async throws -> String {
        let serial = String(arguments.serialNumber.prefix(40))
        return await runDeviceAction(.restart(serial: serial), serial: serial, cli: cli,
                                     title: "Restart Mac", explanation: "Dashie wants to restart this Mac immediately. Unsaved work on it may be lost:",
                                     confirmTitle: "Restart", done: "Restart sent to")
    }
}

@available(macOS 26, *)
struct BulkSetPoliciesTool: Tool {
    let name = "bulkSetPolicies"
    let description = "Enable or disable many Jamf Pro policies at once. Enabling takes a policy category (e.g. 'Maintenance'); disabling takes a policy name pattern with wildcards (e.g. 'Test*')."
    let cli: any CLIRunning

    @Generable struct Arguments {
        @Guide(description: "true to enable policies, false to disable them")
        let enable: Bool
        @Guide(description: "When enabling: the policy category name, e.g. Maintenance. When disabling: a policy name pattern with wildcards, e.g. Test* or Legacy*")
        let target: String
    }

    func call(arguments: Arguments) async throws -> String {
        let target = arguments.target.trimmingCharacters(in: .whitespaces)
        return arguments.enable ? await enable(category: target) : await disable(pattern: target)
    }

    private func enable(category: String) async -> String {
        guard DashieActions.isEnabled else {
            return "Actions are turned off. The user can turn them on in Settings → Dashie."
        }
        guard !category.isEmpty else { return "Refused: name the policy category to enable." }
        let category = String(category.prefix(100))
        let confirmed = await confirmAction(
            title: "Enable Policies in a Category",
            message: "Dashie wants to enable every policy in the category below. Enabled policies run on the Macs in their scope.\n\nType the category name to confirm:",
            confirmTitle: "Enable Policies",
            typed: category
        )
        guard confirmed else { return "The user cancelled. Nothing was changed." }
        do {
            _ = try await cli.runConfirmed(.bulkEnablePolicies(category: category))
            return "Policies in category '\(category)' were enabled."
        } catch {
            return "Failed to enable policies in category '\(category)': \(ErrorMessageFormatter.message(for: error))"
        }
    }

    private func disable(pattern: String) async -> String {
        guard DashieActions.isEnabled else {
            return "Actions are turned off. The user can turn them on in Settings → Dashie."
        }
        let pattern = String(pattern.prefix(100))
        if Self.matchesEverything(pattern) {
            return "Refused: the pattern '\(pattern)' would match every policy. Ask the user for a more specific name pattern."
        }
        guard let matching = await Self.matchingPolicyNames(pattern, cli: cli) else {
            return "Couldn't read the policy list to check which policies match, so nothing was changed."
        }
        if matching.isEmpty {
            return "No policies match '\(pattern)'. Nothing was disabled."
        }
        let shown = matching.prefix(8).map { "• \($0)" }.joined(separator: "\n")
        let more = matching.count > 8 ? "\n… and \(matching.count - 8) more" : ""
        let confirmed = await confirmAction(
            title: "Disable \(matching.count) Polic\(matching.count == 1 ? "y" : "ies")",
            message: "Dashie wants to disable these policies:\n\n\(shown)\(more)\n\nType \(matching.count) to confirm:",
            confirmTitle: "Disable Policies",
            typed: String(matching.count)
        )
        guard confirmed else { return "The user cancelled. Nothing was changed." }
        do {
            _ = try await cli.runConfirmed(.bulkDisablePolicies(pattern: pattern))
            return "\(matching.count) policies matching '\(pattern)' were disabled."
        } catch {
            return "Failed to disable policies matching '\(pattern)': \(ErrorMessageFormatter.message(for: error))"
        }
    }

    /// True for empty patterns and patterns made only of wildcards (`*`, `**`, `?*`).
    static func matchesEverything(_ pattern: String) -> Bool {
        let p = pattern.filter { !$0.isWhitespace }
        if p.isEmpty { return true }
        return p.contains("*") && p.allSatisfy { $0 == "*" || $0 == "?" }
    }

    /// Policy names matching the glob, from the policy list; nil when the list can't be read.
    static func matchingPolicyNames(_ pattern: String, cli: any CLIRunning) async -> [String]? {
        guard let data = try? await cli.run(.policies), let rows = parseArray(data) else { return nil }
        return matchingNames(pattern, in: rows.compactMap { $0["name"] as? String })
    }

    static func matchingNames(_ pattern: String, in names: [String]) -> [String] {
        names.filter { name in fnmatch(pattern, name, 0) == 0 }
    }
}

@available(macOS 26, *)
struct ExplainEnrollmentTool: Tool {
    let name = "explainEnrollment"
    let description = "Explain what happened when a Mac enrolled: enrollment method and PreStage, MDM commands, profiles and policies delivered, and failed or stuck commands. Use for questions like 'what happened when AAA111 enrolled?' or 'why didn't Wi-Fi install on a new Mac?'. Needs the serial number."
    let cli: any CLIRunning

    @Generable struct Arguments {
        @Guide(description: "Serial number of the Mac")
        let serialNumber: String
    }

    func call(arguments: Arguments) async throws -> String {
        let serial = CLICommand.sanitizedSerial(arguments.serialNumber)
        guard !serial.isEmpty else { return "Give the Mac's serial number." }
        do {
            let timeline = try await EnrollmentRepository(cli: cli).timeline(serial: serial)
            return cap(EnrollmentAnalyzer.summary(timeline)
                + "\nFull timeline: Enrollment → Recent Enrollments in Jamf Dash.", 1_200)
        } catch {
            return "Couldn't read the enrollment of \(serial): \(error.localizedDescription)"
        }
    }
}

#endif
