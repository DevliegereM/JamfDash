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

/// Asks the user to approve a destructive action requested by the model.
/// Shown as a sheet on the key window when available so the main thread is not blocked;
/// falls back to an app-modal alert otherwise.
@MainActor
private func confirmAction(title: String, message: String, confirmTitle: String) async -> Bool {
    if let answer = DashieToolConfirmation.testOverride { return answer(title) }
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .warning
    alert.addButton(withTitle: confirmTitle)
    alert.addButton(withTitle: "Cancel")
    guard let window = NSApp.keyWindow ?? NSApp.mainWindow else {
        return alert.runModal() == .alertFirstButtonReturn
    }
    return await withCheckedContinuation { continuation in
        alert.beginSheetModal(for: window) { response in
            continuation.resume(returning: response == .alertFirstButtonReturn)
        }
    }
}

/// Lets tests answer action confirmations without showing a dialog. Never set in the app.
@MainActor
enum DashieToolConfirmation {
    static var testOverride: ((String) -> Bool)?
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
            let data = try await cli.run(.computerDetail(serial: arguments.serialNumber))
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
        do {
            let data = try await cli.run(.blankPush(serial: arguments.serialNumber))
            return String(data: data, encoding: .utf8) ?? "Blank push sent."
        } catch {
            return "Failed to send blank push to \(arguments.serialNumber): \(error.localizedDescription)"
        }
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
        let confirmed = await confirmAction(
            title: "Renew MDM Profile",
            message: "This will renew the MDM profile on \(arguments.serialNumber). Continue?",
            confirmTitle: "Renew"
        )
        guard confirmed else { return "MDM profile renewal cancelled by user." }
        do {
            let data = try await cli.run(.renewMDM(serial: arguments.serialNumber))
            return String(data: data, encoding: .utf8) ?? "MDM profile renewed."
        } catch {
            return "Failed to renew MDM profile on \(arguments.serialNumber): \(error.localizedDescription)"
        }
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
        let confirmed = await confirmAction(
            title: "Redeploy Management Framework",
            message: "This will redeploy the Jamf framework on \(arguments.serialNumber). Continue?",
            confirmTitle: "Redeploy"
        )
        guard confirmed else { return "Redeploy cancelled by user." }
        do {
            let data = try await cli.run(.redeployFramework(serial: arguments.serialNumber))
            return String(data: data, encoding: .utf8) ?? "Framework redeployed."
        } catch {
            return "Failed to redeploy framework on \(arguments.serialNumber): \(error.localizedDescription)"
        }
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
        let confirmed = await confirmAction(
            title: "Flush Failed Commands",
            message: "This will remove all failed MDM commands queued for \(arguments.serialNumber). Continue?",
            confirmTitle: "Flush"
        )
        guard confirmed else { return "Flush cancelled by user." }
        do {
            let data = try await cli.run(.flushFailedCommands(serial: arguments.serialNumber))
            return String(data: data, encoding: .utf8) ?? "Failed commands flushed."
        } catch {
            return "Failed to flush commands on \(arguments.serialNumber): \(error.localizedDescription)"
        }
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
        let confirmed = await confirmAction(
            title: "Restart Device",
            message: "This will immediately restart \(arguments.serialNumber) via MDM. Continue?",
            confirmTitle: "Restart"
        )
        guard confirmed else { return "Restart cancelled by user." }
        do {
            let data = try await cli.run(.restart(serial: arguments.serialNumber))
            return String(data: data, encoding: .utf8) ?? "Restart command sent."
        } catch {
            return "Failed to restart \(arguments.serialNumber): \(error.localizedDescription)"
        }
    }
}

@available(macOS 26, *)
struct ExecutePolicyTool: Tool {
    let name = "executePolicy"
    let description = "Trigger a Jamf Pro policy to run on a specific Mac by policy name and serial number. Use when you need to push a policy immediately rather than waiting for the next check-in."
    let cli: any CLIRunning

    @Generable struct Arguments {
        @Guide(description: "Name of the Jamf Pro policy to execute")
        let policyName: String
        @Guide(description: "Serial number of the target Mac")
        let serialNumber: String
    }

    func call(arguments: Arguments) async throws -> String {
        let confirmed = await confirmAction(
            title: "Execute Policy",
            message: "This will run policy '\(arguments.policyName)' on \(arguments.serialNumber). Continue?",
            confirmTitle: "Execute"
        )
        guard confirmed else { return "Policy execution cancelled by user." }
        do {
            let data = try await cli.run(.policyExecute(name: arguments.policyName, serial: arguments.serialNumber))
            return String(data: data, encoding: .utf8) ?? "Policy executed."
        } catch {
            return "Failed to execute policy '\(arguments.policyName)' on \(arguments.serialNumber): \(error.localizedDescription)"
        }
    }
}

@available(macOS 26, *)
struct BulkEnablePoliciesTool: Tool {
    let name = "bulkEnablePolicies"
    let description = "Enable all policies in a Jamf Pro category. For example, enable all policies in the 'Maintenance' category."
    let cli: any CLIRunning

    @Generable struct Arguments {
        @Guide(description: "The Jamf Pro policy category name (e.g. Maintenance, Security)")
        let category: String
    }

    func call(arguments: Arguments) async throws -> String {
        let confirmed = await confirmAction(
            title: "Bulk Enable Policies",
            message: "This will enable ALL policies in category '\(arguments.category)'. This affects the entire fleet. Continue?",
            confirmTitle: "Enable All"
        )
        guard confirmed else { return "Bulk enable cancelled by user." }
        do {
            let data = try await cli.run(.bulkEnablePolicies(category: arguments.category))
            return String(data: data, encoding: .utf8) ?? "Policies enabled."
        } catch {
            return "Failed to enable policies in category '\(arguments.category)': \(error.localizedDescription)"
        }
    }
}

@available(macOS 26, *)
struct BulkDisablePoliciesTool: Tool {
    let name = "bulkDisablePolicies"
    let description = "Disable all policies whose name matches a pattern. For example, disable all policies named 'Test*'."
    let cli: any CLIRunning

    @Generable struct Arguments {
        @Guide(description: "Name pattern to match (supports wildcards, e.g. 'Test*' or 'Legacy*')")
        let namePattern: String
    }

    func call(arguments: Arguments) async throws -> String {
        let pattern = arguments.namePattern.trimmingCharacters(in: .whitespaces)
        if Self.matchesEverything(pattern) {
            return "Refused: the pattern '\(arguments.namePattern)' would match every policy. Ask the user for a more specific name pattern."
        }
        let matching = await Self.matchingPolicyNames(pattern, cli: cli)
        if let matching, matching.isEmpty {
            return "No policies match '\(pattern)'. Nothing was disabled."
        }
        let countLine: String
        if let matching {
            let shown = matching.prefix(8).map { "• \($0)" }.joined(separator: "\n")
            let more = matching.count > 8 ? "\n… and \(matching.count - 8) more" : ""
            countLine = "\(matching.count) polic\(matching.count == 1 ? "y matches" : "ies match"):\n\(shown)\(more)"
        } else {
            countLine = "The number of matching policies could not be checked."
        }
        let confirmed = await confirmAction(
            title: "Bulk Disable Policies",
            message: "This will disable ALL policies matching '\(pattern)'. This affects the entire fleet.\n\n\(countLine)\n\nContinue?",
            confirmTitle: "Disable All"
        )
        guard confirmed else { return "Bulk disable cancelled by user." }
        do {
            let data = try await cli.run(.bulkDisablePolicies(pattern: pattern))
            return String(data: data, encoding: .utf8) ?? "Policies disabled."
        } catch {
            return "Failed to disable policies matching '\(pattern)': \(error.localizedDescription)"
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

#endif
