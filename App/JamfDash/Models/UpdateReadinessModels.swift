import Foundation

// MARK: - OS version helper

enum OSVersionParser {
    /// Major version from strings like "27.0.1", "macOS 27.1", "15.4". Nil when unparseable.
    static func major(_ version: String?) -> Int? {
        guard let version else { return nil }
        let digits = version.drop { !$0.isNumber }
        return Int(digits.prefix { $0.isNumber })
    }
}

// MARK: - Managed software update plan (DDM)

/// One entry of `managed-software-updates-plans list`. For macOS 14+ Jamf Pro sends these
/// plans to devices as DDM software-update declarations.
struct ManagedUpdatePlan: Sendable, Hashable, Identifiable {
    let planUuid: String
    let deviceId: String?
    let objectType: String?
    let updateAction: String?
    let versionType: String?
    let specificVersion: String?
    let forceInstallLocalDateTime: String?
    let state: String?
    let errorReasons: [String]

    var id: String { planUuid }

    var isFailed: Bool {
        !errorReasons.isEmpty || (state?.lowercased().contains("fail") ?? false)
            || (state?.lowercased().contains("error") ?? false)
    }

    var targetDescription: String {
        if let v = specificVersion, !v.isEmpty, v != "NO_SPECIFIC_VERSION" { return v }
        return versionType?.replacingOccurrences(of: "_", with: " ").capitalized ?? "—"
    }
}

extension ManagedUpdatePlan: Decodable {
    private struct Device: Decodable { let deviceId: String?; let objectType: String? }
    private struct Status: Decodable { let state: String?; let errorReasons: [String]? }
    private enum CodingKeys: String, CodingKey {
        case planUuid, device, updateAction, versionType, specificVersion, forceInstallLocalDateTime, status
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        planUuid = (try? c.decode(String.self, forKey: .planUuid)) ?? UUID().uuidString
        let device = try? c.decode(Device.self, forKey: .device)
        deviceId = device?.deviceId
        objectType = device?.objectType
        updateAction = try? c.decode(String.self, forKey: .updateAction)
        versionType = try? c.decode(String.self, forKey: .versionType)
        specificVersion = try? c.decode(String.self, forKey: .specificVersion)
        forceInstallLocalDateTime = try? c.decode(String.self, forKey: .forceInstallLocalDateTime)
        if let status = try? c.decode(Status.self, forKey: .status) {
            state = status.state
            errorReasons = status.errorReasons ?? []
        } else {
            state = (try? c.decode(String.self, forKey: .status))
            errorReasons = []
        }
    }
}

// MARK: - Managed software update status

/// One entry of `managed-software-updates update-statuses`.
struct ManagedUpdateStatus: Sendable, Hashable {
    let deviceId: String?
    let objectType: String?
    let status: String?
    let productKey: String?
    let nextScheduledInstall: String?
    let updated: String?
}

extension ManagedUpdateStatus: Decodable {
    private struct Device: Decodable { let deviceId: String?; let objectType: String? }
    private enum CodingKeys: String, CodingKey {
        case device, status, productKey, nextScheduledInstall, updated
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let device = try? c.decode(Device.self, forKey: .device)
        deviceId = device?.deviceId
        objectType = device?.objectType
        status = try? c.decode(String.self, forKey: .status)
        productKey = try? c.decode(String.self, forKey: .productKey)
        nextScheduledInstall = try? c.decode(String.self, forKey: .nextScheduledInstall)
        updated = try? c.decode(String.self, forKey: .updated)
    }
}

// MARK: - Readiness computer

/// Computer record from `computers-inventory list` with GENERAL, HARDWARE,
/// OPERATING_SYSTEM and CONFIGURATION_PROFILES sections.
struct ReadinessComputer: Sendable, Hashable, Identifiable {
    struct InstalledProfile: Sendable, Hashable {
        let id: String?
        let name: String?
    }

    let id: String
    let name: String
    let serialNumber: String?
    let managementId: String?
    let osVersion: String?
    let ddmEnabled: Bool?
    let profiles: [InstalledProfile]

    var osMajor: Int? { OSVersionParser.major(osVersion) }
}

extension ReadinessComputer: Decodable {
    private struct General: Decodable {
        let name: String?
        let managementId: String?
        let declarativeDeviceManagementEnabled: Bool?
    }
    private struct Hardware: Decodable { let serialNumber: String? }
    private struct OS: Decodable { let version: String? }
    private struct Profile: Decodable {
        let id: String?
        let displayName: String?
        private enum CodingKeys: String, CodingKey { case id, profileId, displayName }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = (try? c.decode(String.self, forKey: .id))
                ?? (try? c.decode(Int.self, forKey: .id)).map(String.init)
                ?? (try? c.decode(String.self, forKey: .profileId))
            displayName = try? c.decode(String.self, forKey: .displayName)
        }
    }
    private enum CodingKeys: String, CodingKey {
        case id, general, hardware, operatingSystem, configurationProfiles
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id))
            ?? (try? c.decode(Int.self, forKey: .id)).map(String.init)
            ?? UUID().uuidString
        let general = try? c.decode(General.self, forKey: .general)
        name = general?.name ?? id
        managementId = general?.managementId
        ddmEnabled = general?.declarativeDeviceManagementEnabled
        serialNumber = (try? c.decode(Hardware.self, forKey: .hardware))?.serialNumber
        osVersion = (try? c.decode(OS.self, forKey: .operatingSystem))?.version
        profiles = ((try? c.decode([Profile].self, forKey: .configurationProfiles)) ?? [])
            .map { InstalledProfile(id: $0.id, name: $0.displayName) }
    }
}

// MARK: - Evaluation

enum ReadinessLevel: Int, Sendable, Comparable, CaseIterable {
    case ready = 0, info, attention, blocked

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .ready: return "Ready"
        case .info: return "Heads-up"
        case .attention: return "Needs attention"
        case .blocked: return "Not manageable"
        }
    }
}

struct ReadinessIssue: Sendable, Hashable {
    let level: ReadinessLevel
    let message: String
}

struct UpdateReadinessRow: Sendable, Identifiable, Hashable {
    let computer: ReadinessComputer
    let plan: ManagedUpdatePlan?
    let status: ManagedUpdateStatus?
    let legacyProfileNames: [String]
    let issues: [ReadinessIssue]

    var id: String { computer.id }
    var level: ReadinessLevel { issues.map(\.level).max() ?? .ready }
    var isOS27OrLater: Bool { (computer.osMajor ?? 0) >= 27 }
}

enum UpdateReadinessEvaluator {
    /// Evaluates macOS 27 software-update readiness per computer.
    ///
    /// - On macOS 27 the MDM software-update commands (ScheduleOSUpdate, AvailableOSUpdates …),
    ///   the `com.apple.SoftwareUpdate` payload and the restriction-based deferrals are removed;
    ///   only DDM software-update declarations work.
    /// - Jamf Pro Managed Software Update plans are delivered as DDM declarations on macOS 14+,
    ///   so a device with a plan is on the DDM path; one without a plan relies on legacy
    ///   commands/policies or the user.
    static func evaluate(
        computers: [ReadinessComputer],
        plans: [ManagedUpdatePlan],
        statuses: [ManagedUpdateStatus],
        legacyProfiles: [ScannedProfile]?
    ) -> [UpdateReadinessRow] {
        let computerPlans = plans.filter { ($0.objectType ?? "COMPUTER").uppercased() == "COMPUTER" }
        // Latest plan per device (plans list is ordered by planUuid; keep failures visible).
        var planByDevice: [String: ManagedUpdatePlan] = [:]
        for plan in computerPlans {
            guard let id = plan.deviceId else { continue }
            if let existing = planByDevice[id], existing.isFailed, !plan.isFailed { continue }
            planByDevice[id] = plan
        }
        var statusByDevice: [String: ManagedUpdateStatus] = [:]
        for s in statuses where (s.objectType ?? "COMPUTER").uppercased() == "COMPUTER" {
            if let id = s.deviceId { statusByDevice[id] = s }
        }
        let legacyIDs = Set((legacyProfiles ?? []).map { String($0.id) })
        let legacyNames = Set((legacyProfiles ?? []).map { $0.name.lowercased() })

        return computers.map { computer in
            let plan = planByDevice[computer.id]
            let status = statusByDevice[computer.id]
            let legacy = computer.profiles.filter { p in
                (p.id.map(legacyIDs.contains) ?? false) || (p.name.map { legacyNames.contains($0.lowercased()) } ?? false)
            }.compactMap(\.name)

            var issues: [ReadinessIssue] = []
            let major = computer.osMajor ?? 0
            if major >= 27 {
                if computer.ddmEnabled == false {
                    issues.append(.init(level: .blocked,
                        message: "DDM is not enabled — software updates can't be managed on macOS 27 (legacy MDM update commands are removed)."))
                }
                if !legacy.isEmpty {
                    issues.append(.init(level: .attention,
                        message: "Deferral / Software Update profile has no effect on macOS 27: \(legacy.joined(separator: ", "))."))
                }
                if plan == nil {
                    issues.append(.init(level: .attention,
                        message: "No DDM software update plan — updates rely on legacy MDM commands or policies, which macOS 27 no longer honours."))
                } else if let plan, plan.isFailed {
                    let reasons = plan.errorReasons.isEmpty ? (plan.state ?? "failed") : plan.errorReasons.joined(separator: ", ")
                    issues.append(.init(level: .attention, message: "DDM update plan failed: \(reasons)."))
                }
            } else if major > 0 {
                if !legacy.isEmpty {
                    issues.append(.init(level: .info,
                        message: "Uses deferral / Software Update profiles that stop working after upgrading to macOS 27: \(legacy.joined(separator: ", "))."))
                }
                if major >= 14, computer.ddmEnabled == false {
                    issues.append(.init(level: .info,
                        message: "DDM is not enabled — required for software update management once the Mac runs macOS 27."))
                }
            }
            return UpdateReadinessRow(computer: computer, plan: plan, status: status,
                                      legacyProfileNames: legacy, issues: issues)
        }
    }
}

// MARK: - Shared list decoding

enum JamfListDecoder {
    /// Decodes a plain array or a `{results|items|data: [...]}` wrapper.
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> [T]? {
        let decoder = JSONDecoder()
        if let list = try? decoder.decode([T].self, from: data) { return list }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["results", "items", "data", "plans", "updateStatuses"] {
                if let arr = obj[key],
                   let arrData = try? JSONSerialization.data(withJSONObject: arr),
                   let list = try? decoder.decode([T].self, from: arrData) {
                    return list
                }
            }
        }
        // NDJSON
        if let text = String(data: data, encoding: .utf8) {
            let items = text.split(whereSeparator: \.isNewline).compactMap { line in
                try? decoder.decode(T.self, from: Data(line.utf8))
            }
            if !items.isEmpty { return items }
        }
        return nil
    }
}

// MARK: - Single-device readiness (Device Lookup)

struct DeviceUpdateReadiness: Sendable {
    let row: UpdateReadinessRow
    /// Typed DDM status items (software update state etc.); nil when unavailable.
    let ddmSummary: DDMDeviceStatusSummary?
    /// Why DDM status items are missing, if they are.
    let ddmNote: String?
    /// False when no profile scan was available to check for deferral profiles.
    let profilesChecked: Bool

    static func load(for detail: ComputerDetail,
                     cli: any CLIRunning,
                     scanner: ProfileDeprecationScanner?) async -> DeviceUpdateReadiness {
        let computer = ReadinessComputer(
            id: detail.id,
            name: detail.name,
            serialNumber: detail.effectiveSerial,
            managementId: detail.general?.managementId,
            osVersion: detail.effectiveOS,
            ddmEnabled: detail.general?.declarativeDeviceManagementEnabled,
            profiles: (detail.configurationProfiles ?? []).map { .init(id: $0.profileId, name: $0.displayName) }
        )

        async let plansData = try? cli.run(.softwareUpdatePlansForComputer(computerId: detail.id))
        // Only use a cached profile scan here — a full scan is too expensive for a lookup.
        let legacy = await scanner?.cachedProfiles.map(DeprecationAuditRules.legacySoftwareUpdateProfiles(in:))

        var summary: DDMDeviceStatusSummary? = nil
        var note: String? = nil
        if let mid = computer.managementId, !mid.isEmpty {
            do {
                let data = try await cli.run(.ddmStatusItems(managementId: mid))
                summary = DDMDeviceStatusSummary(items: try DDMMonitorViewModel.decodeStatusItems(from: data))
            } catch CLIError.nonZeroExit(let code, _) where code == 15 {
                note = "DDM status items endpoint not supported by this Jamf Pro (exit 15)."
            } catch {
                note = "DDM status items unavailable: \(ErrorMessageFormatter.message(for: error))"
            }
        } else {
            note = "No DDM management ID for this computer."
        }

        let plans = (await plansData).flatMap { JamfListDecoder.decode(ManagedUpdatePlan.self, from: $0) } ?? []
        let row = UpdateReadinessEvaluator.evaluate(computers: [computer], plans: plans, statuses: [],
                                                    legacyProfiles: legacy)[0]
        return DeviceUpdateReadiness(row: row, ddmSummary: summary, ddmNote: note, profilesChecked: legacy != nil)
    }
}
