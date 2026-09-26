import AppIntents
import Foundation

// MARK: - CLI access for intents

/// Gives App Intents the same `CLIRunning` the app uses (real or Demo Mode).
/// `AppEnvironment` registers itself here; if an intent runs before the UI has built an
/// environment, a plain `CLIManager` for the active jamf-cli profile is created.
@MainActor
enum IntentCLIProvider {
    static var current: (any CLIRunning)?

    static func cli() -> any CLIRunning {
        if let current { return current }
        let cli = CLIManager(downloader: CLIDownloader(),
                             profileService: ProfileService(),
                             keychain: KeychainService())
        current = cli
        return cli
    }
}

// MARK: - Pure summaries (unit-tested)

enum IntentSummaries {
    struct Compliance: Sendable, Equatable {
        let compliant: Int
        let total: Int
        var percent: Int { total > 0 ? Int((Double(compliant) / Double(total) * 100).rounded()) : 0 }
    }

    /// Parses `pro report device-compliance -o json` rows.
    static func compliance(from data: Data) -> Compliance? {
        guard let rows = rows(from: data), !rows.isEmpty else { return nil }
        var compliant = 0
        var total = 0
        for row in rows {
            if let b = row["compliant"] as? Bool {
                total += 1; if b { compliant += 1 }
                continue
            }
            let status = ((row["compliance_status"] ?? row["status"] ?? row["complianceStatus"]) as? String)?
                .lowercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "")
            guard let status else { continue }
            total += 1
            if status == "compliant" { compliant += 1 }
        }
        return total > 0 ? Compliance(compliant: compliant, total: total) : nil
    }

    private static let upToDateStatuses: Set<String> = [
        "current", "uptodate", "idle", "installed", "none", "success", "completed", "plancompleted",
    ]

    /// Devices that still need an update from `pro report update-status -o json`.
    /// Supports per-device rows (`status`) and aggregated rows (`status` + `count`).
    static func devicesNeedingUpdates(from data: Data) -> Int? {
        guard let rows = rows(from: data) else { return nil }
        var count = 0
        for row in rows {
            guard let status = (row["status"] as? String)?.lowercased()
                .replacingOccurrences(of: "_", with: "").replacingOccurrences(of: " ", with: "") else { continue }
            if upToDateStatuses.contains(status) { continue }
            count += (row["count"] as? Int) ?? 1
        }
        return count
    }

    struct DDMFailures: Sendable, Equatable {
        let failedStatuses: Int
        let failingDeclarations: [String]
    }

    /// Failed DDM declaration statuses from `pro report ddm-status -o json`.
    static func ddmFailures(from data: Data) -> DDMFailures? {
        let decoder = JSONDecoder()
        var stats = try? decoder.decode([DDMDeclarationStat].self, from: data)
        if stats == nil, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["declarations", "results", "items", "data", "status"] {
                if let arr = obj[key], let d = try? JSONSerialization.data(withJSONObject: arr),
                   let decoded = try? decoder.decode([DDMDeclarationStat].self, from: d) {
                    stats = decoded; break
                }
            }
        }
        guard let stats else { return nil }
        let failing = stats.filter { $0.failedCount > 0 }
        return DDMFailures(failedStatuses: failing.reduce(0) { $0 + $1.failedCount },
                           failingDeclarations: failing.sorted { $0.failedCount > $1.failedCount }.map(\.declaration))
    }

    private static func rows(from data: Data) -> [[String: Any]]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let arr = json as? [[String: Any]] { return arr }
        if let obj = json as? [String: Any] {
            for key in ["results", "devices", "items", "data", "rows"] {
                if let arr = obj[key] as? [[String: Any]] { return arr }
            }
        }
        return nil
    }
}

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case unreadable(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .unreadable(let what): return "Jamf Dash couldn't read the \(what) report."
        }
    }
}

// MARK: - Intents (read-only)

struct FleetComplianceIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Fleet Compliance"
    static let description = IntentDescription("Returns the percentage of Jamf Pro computers that are compliant.")

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let cli = await IntentCLIProvider.cli()
        let data = try await cli.run(.reportDeviceCompliance)
        guard let c = IntentSummaries.compliance(from: data) else { throw IntentError.unreadable("device compliance") }
        return .result(value: c.percent,
                       dialog: "\(c.percent)% of computers are compliant (\(c.compliant) of \(c.total)).")
    }
}

struct DevicesNeedingUpdatesIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Devices Needing Updates"
    static let description = IntentDescription("Returns how many managed devices still have a pending or failed software update.")

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let cli = await IntentCLIProvider.cli()
        let data = try await cli.run(.reportUpdateStatus(includeFailures: false))
        guard let count = IntentSummaries.devicesNeedingUpdates(from: data) else { throw IntentError.unreadable("update status") }
        return .result(value: count,
                       dialog: count == 0 ? "All devices are up to date." : "\(count) devices need a software update.")
    }
}

struct DDMFailuresIntent: AppIntent {
    static let title: LocalizedStringResource = "Get DDM Declaration Failures"
    static let description = IntentDescription("Returns the number of failed Declarative Device Management declaration statuses across the fleet.")

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let cli = await IntentCLIProvider.cli()
        let data = try await cli.run(.reportDDMStatus)
        guard let f = IntentSummaries.ddmFailures(from: data) else { throw IntentError.unreadable("DDM status") }
        if f.failedStatuses == 0 {
            return .result(value: 0, dialog: "No DDM declarations are failing.")
        }
        let top = f.failingDeclarations.prefix(3).joined(separator: ", ")
        return .result(value: f.failedStatuses,
                       dialog: "\(f.failedStatuses) failed DDM statuses across \(f.failingDeclarations.count) declarations: \(top).")
    }
}

// MARK: - Shortcuts

struct JamfDashShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: FleetComplianceIntent(),
                    phrases: ["Get fleet compliance in \(.applicationName)",
                              "What's my fleet compliance in \(.applicationName)"],
                    shortTitle: "Fleet Compliance",
                    systemImageName: "checkmark.shield")
        AppShortcut(intent: DevicesNeedingUpdatesIntent(),
                    phrases: ["Devices needing updates in \(.applicationName)",
                              "How many devices need updates in \(.applicationName)"],
                    shortTitle: "Devices Needing Updates",
                    systemImageName: "arrow.down.circle")
        AppShortcut(intent: DDMFailuresIntent(),
                    phrases: ["DDM failures in \(.applicationName)",
                              "Show declaration failures in \(.applicationName)"],
                    shortTitle: "DDM Failures",
                    systemImageName: "exclamationmark.triangle")
    }
}
