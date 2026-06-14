import Foundation
import OSLog
import Observation
import SwiftUI

// MARK: - Audit Models

enum AuditSeverity: String, CaseIterable, Sendable {
    case critical = "CRITICAL"
    case warning  = "WARNING"
    case info     = "INFO"

    var label: String {
        switch self {
        case .critical: return "Critical"
        case .warning:  return "Warning"
        case .info:     return "Info"
        }
    }

    var color: Color {
        switch self {
        case .critical: return .red
        case .warning:  return .orange
        case .info:     return .blue
        }
    }

    var icon: String {
        switch self {
        case .critical: return "xmark.octagon.fill"
        case .warning:  return "exclamationmark.triangle.fill"
        case .info:     return "info.circle.fill"
        }
    }
}

struct AuditFinding: Identifiable, Sendable {
    let id: String
    let severity: AuditSeverity
    let category: String
    let title: String
    let description: String?
    let affectedCount: Int?
    let remediation: String?
    let affectedDeviceSerials: [String]?
    let affectedDeviceNames: [String]?

    /// Memberwise init used when injecting a known category (e.g. from the CLI flag).
    init(id: String, severity: AuditSeverity, category: String, title: String,
         description: String?, affectedCount: Int?, remediation: String?,
         affectedDeviceSerials: [String]? = nil, affectedDeviceNames: [String]? = nil) {
        self.id                    = id
        self.severity              = severity
        self.category              = category
        self.title                 = title
        self.description           = description
        self.affectedCount         = affectedCount
        self.remediation           = remediation
        self.affectedDeviceSerials = affectedDeviceSerials
        self.affectedDeviceNames   = affectedDeviceNames
    }

    private enum CodingKeys: String, CodingKey {
        case id, severity, category, title, description, remediation
        case affectedCount, affected_count, affectedDevices, affected_devices, count
        case check, checkId, check_id, name
        case message, detail, details, summary
        case fix, recommendation
        case affectedDeviceSerials, affected_device_serials, serials, deviceSerials, device_serials
        case affectedDeviceNames, affected_device_names, deviceNames, device_names, computers, devices
    }
}

extension AuditFinding: Decodable {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else if let n = try? c.decode(Int.self, forKey: .id) { id = String(n) }
        else { id = (try? c.decode(String.self, forKey: .checkId))
                 ?? (try? c.decode(String.self, forKey: .check_id))
                 ?? (try? c.decode(String.self, forKey: .check))
                 ?? UUID().uuidString }

        let rawSeverity = (try? c.decode(String.self, forKey: .severity))?.uppercased() ?? "INFO"
        severity = AuditSeverity(rawValue: rawSeverity) ?? .info

        category    = (try? c.decode(String.self, forKey: .category)) ?? ""
        title       = (try? c.decode(String.self, forKey: .title))
                   ?? (try? c.decode(String.self, forKey: .name))
                   ?? (try? c.decode(String.self, forKey: .check))
                   ?? "Untitled Check"
        description = (try? c.decode(String.self, forKey: .description))
                   ?? (try? c.decode(String.self, forKey: .message))
                   ?? (try? c.decode(String.self, forKey: .detail))
                   ?? (try? c.decode(String.self, forKey: .details))
                   ?? (try? c.decode(String.self, forKey: .summary))
        affectedCount = (try? c.decode(Int.self, forKey: .affectedCount))
                     ?? (try? c.decode(Int.self, forKey: .affected_count))
                     ?? (try? c.decode(Int.self, forKey: .affectedDevices))
                     ?? (try? c.decode(Int.self, forKey: .affected_devices))
                     ?? (try? c.decode(Int.self, forKey: .count))
        remediation = (try? c.decode(String.self, forKey: .remediation))
                   ?? (try? c.decode(String.self, forKey: .fix))
                   ?? (try? c.decode(String.self, forKey: .recommendation))
        affectedDeviceSerials = (try? c.decode([String].self, forKey: .affectedDeviceSerials))
            ?? (try? c.decode([String].self, forKey: .affected_device_serials))
            ?? (try? c.decode([String].self, forKey: .serials))
            ?? (try? c.decode([String].self, forKey: .deviceSerials))
            ?? (try? c.decode([String].self, forKey: .device_serials))
        affectedDeviceNames = (try? c.decode([String].self, forKey: .affectedDeviceNames))
            ?? (try? c.decode([String].self, forKey: .affected_device_names))
            ?? (try? c.decode([String].self, forKey: .deviceNames))
            ?? (try? c.decode([String].self, forKey: .device_names))
            ?? (try? c.decode([String].self, forKey: .computers))
            ?? (try? c.decode([String].self, forKey: .devices))
    }

    /// Return a copy with the given category (used when the CLI flag provides it but the JSON omits it).
    func withCategory(_ cat: String) -> AuditFinding {
        AuditFinding(id: id, severity: severity, category: cat,
                     title: title, description: description,
                     affectedCount: affectedCount, remediation: remediation,
                     affectedDeviceSerials: affectedDeviceSerials,
                     affectedDeviceNames: affectedDeviceNames)
    }
}

// MARK: - AuditViewModel

@MainActor
@Observable
final class AuditViewModel {
    private static let logger = Logger(subsystem: "com.jamfdash", category: "AuditViewModel")
    private let cli: any CLIRunning

    private(set) var findingsState: LoadState<[AuditFinding]> = .idle
    var severityFilter: AuditSeverity? = nil
    var categoryFilter: String? = nil
    var searchText = ""

    init(cli: any CLIRunning) {
        self.cli = cli
    }

    // MARK: - Loading

    /// Valid category names accepted by `jamf-cli pro audit --checks <category>`.
    private static let auditCategories = ["security", "compliance", "hygiene", "enrollment", "platform"]

    func load(force: Bool = false) async {
        guard force || findingsState.value == nil else { return }
        guard force || !findingsState.isLoading else { return }
        Self.logger.debug("Loading audit findings across all categories")
        findingsState = .loading
        do {
            // Run all categories in parallel; collect results, ignore individual failures.
            var allFindings: [AuditFinding] = []
            await withTaskGroup(of: [AuditFinding].self) { group in
                for category in Self.auditCategories {
                    group.addTask {
                        guard let data = try? await self.cli.run(.proAudit(category: category)) else {
                            return []
                        }
                        let decoded = (try? Self.decode(from: data, categoryFallback: category)) ?? []
                        return decoded
                    }
                }
                for await findings in group {
                    allFindings.append(contentsOf: findings)
                }
            }
            Self.logger.debug("Loaded \(allFindings.count) audit findings total")
            findingsState = .loaded(allFindings)
        }
    }

    // MARK: - Filtering

    var filtered: [AuditFinding] {
        guard let findings = findingsState.value else { return [] }
        return findings.filter { finding in
            if let sev = severityFilter, finding.severity != sev { return false }
            if let cat = categoryFilter, finding.category != cat { return false }
            if !searchText.isEmpty {
                let q = searchText.lowercased()
                guard finding.title.lowercased().contains(q)
                   || (finding.description?.lowercased().contains(q) == true)
                   || finding.category.lowercased().contains(q) else { return false }
            }
            return true
        }
    }

    var categories: [String] {
        guard let findings = findingsState.value else { return [] }
        return Array(Set(findings.map(\.category))).sorted()
    }

    var criticalCount: Int { findingsState.value?.filter { $0.severity == .critical }.count ?? 0 }
    var warningCount:  Int { findingsState.value?.filter { $0.severity == .warning  }.count ?? 0 }
    var infoCount:     Int { findingsState.value?.filter { $0.severity == .info     }.count ?? 0 }

    // MARK: - Decode

    nonisolated private static func decode(from data: Data, categoryFallback: String) throws -> [AuditFinding] {
        let decoder = JSONDecoder()

        func inject(_ findings: [AuditFinding]) -> [AuditFinding] {
            // If the JSON already contains a non-empty category, keep it; otherwise inject the CLI category.
            findings.map { $0.category.isEmpty ? $0.withCategory(categoryFallback) : $0 }
        }

        if let findings = try? decoder.decode([AuditFinding].self, from: data) {
            return inject(findings)
        }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["findings", "checks", "results", "items", "data", "audit"] {
                if let arr = obj[key],
                   let arrData = try? JSONSerialization.data(withJSONObject: arr),
                   let findings = try? decoder.decode([AuditFinding].self, from: arrData) {
                    return inject(findings)
                }
            }
        }
        let preview = String(data: data.prefix(300), encoding: .utf8) ?? "<unreadable>"
        throw CLIError.decodingFailed("Unexpected audit response format. Raw: \(preview)")
    }
}
