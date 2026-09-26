import Foundation

// MARK: - Top-level parsed report

struct SecurityReport: Sendable {
    var summary: SecuritySummary?
    var osVersions: [OSVersionRow] = []
    var devices: [DeviceSecurity] = []

    init(summary: SecuritySummary?, osVersions: [OSVersionRow], devices: [DeviceSecurity]) {
        self.summary = summary
        self.osVersions = osVersions
        self.devices = devices
    }

    init(from envelopes: [SecurityEnvelope]) {
        for envelope in envelopes {
            switch envelope.section {
            case "summary":
                if let s = envelope.summaryData { self.summary = s }
            case "os_version":
                if let row = envelope.osVersionRow { self.osVersions.append(row) }
            case "device":
                if let d = envelope.device { self.devices.append(d) }
            default:
                break
            }
        }
    }
}

// MARK: - Security Summary

struct SecuritySummary: Codable, Sendable, Hashable {
    let totalDevices: Int
    let filevaultEncrypted: Int
    let filevaultEncryptedPct: String
    let gatekeeperEnabled: Int
    let gatekeeperEnabledPct: String
    let sipEnabled: Int
    let sipEnabledPct: String
    let firewallEnabled: Int
    let firewallEnabledPct: String

    enum CodingKeys: String, CodingKey {
        case totalDevices = "total_devices"
        case filevaultEncrypted = "filevault_encrypted"
        case filevaultEncryptedPct = "filevault_encrypted_pct"
        case gatekeeperEnabled = "gatekeeper_enabled"
        case gatekeeperEnabledPct = "gatekeeper_enabled_pct"
        case sipEnabled = "sip_enabled"
        case sipEnabledPct = "sip_enabled_pct"
        case firewallEnabled = "firewall_enabled"
        case firewallEnabledPct = "firewall_enabled_pct"
    }
}

// MARK: - OS Version Distribution

struct OSVersionRow: Codable, Sendable, Hashable, Identifiable {
    var id: String { osVersion }
    let osVersion: String
    let count: Int
    let pct: String

    enum CodingKeys: String, CodingKey {
        case osVersion = "os_version"
        case count, pct
    }
}

// MARK: - Per-device Security State

struct DeviceSecurity: Codable, Sendable, Hashable, Identifiable {
    var id: String { serial }
    let name: String
    let serial: String
    let osVersion: String
    let filevault: String
    let gatekeeper: String
    let sip: String
    let firewall: Bool

    enum CodingKeys: String, CodingKey {
        case name, serial, filevault, gatekeeper, sip, firewall
        case osVersion = "os_version"
    }

    var isFilevaultEncrypted: Bool { filevault == "ENCRYPTED" }
    var isSIPEnabled: Bool { sip == "ENABLED" }
    var isGatekeeperEnabled: Bool { gatekeeper != "DISABLED" }

    var hasIssue: Bool { !isFilevaultEncrypted || !isSIPEnabled || !isGatekeeperEnabled || !firewall }
}

// MARK: - Raw envelope for heterogeneous JSON array

struct SecurityEnvelope: Decodable, Sendable {
    let section: String
    let summaryData: SecuritySummary?
    let osVersionRow: OSVersionRow?
    let device: DeviceSecurity?

    private enum CodingKeys: String, CodingKey {
        case section, data
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.section = try container.decode(String.self, forKey: .section)

        switch section {
        case "summary":
            self.summaryData = try container.decode(SecuritySummary.self, forKey: .data)
            self.osVersionRow = nil
            self.device = nil
        case "os_version":
            self.summaryData = nil
            self.osVersionRow = try OSVersionRow(from: decoder)
            self.device = nil
        case "device":
            self.summaryData = nil
            self.osVersionRow = nil
            self.device = try DeviceSecurity(from: decoder)
        default:
            self.summaryData = nil
            self.osVersionRow = nil
            self.device = nil
        }
    }
}

// MARK: - Building the report from computer inventory

extension SecurityReport {
    private struct InventoryPage: Decodable { let results: [InventoryComputer] }

    private struct InventoryComputer: Decodable {
        struct General: Decodable { let name: String? }
        struct Hardware: Decodable { let serialNumber: String? }
        struct OS: Decodable { let version: String?; let fileVault2Status: String? }
        struct Security: Decodable { let sipStatus: String?; let gatekeeperStatus: String?; let firewallEnabled: Bool? }
        struct DiskEncryption: Decodable {
            struct Boot: Decodable { let partitionFileVault2State: String? }
            let bootPartitionEncryptionDetails: Boot?
        }
        let general: General?
        let hardware: Hardware?
        let operatingSystem: OS?
        let security: Security?
        let diskEncryption: DiskEncryption?
    }

    /// Builds the same report `jamf-cli pro report security` produces, from
    /// `pro computers-inventory list` output (a bare array or `{"results": [...]}`).
    init(inventory data: Data) throws {
        let decoder = JSONDecoder()
        let computers: [InventoryComputer]
        if let array = try? decoder.decode([InventoryComputer].self, from: data) {
            computers = array
        } else {
            computers = try decoder.decode(InventoryPage.self, from: data).results
        }

        let devices = computers.map { c -> DeviceSecurity in
            let partition = c.diskEncryption?.bootPartitionEncryptionDetails?.partitionFileVault2State?.uppercased()
            let osStatus = c.operatingSystem?.fileVault2Status?.uppercased()
            let encrypted = partition == "ENCRYPTED" || osStatus == "ALL_ENCRYPTED" || osStatus == "BOOT_ENCRYPTED"
            return DeviceSecurity(
                name: c.general?.name ?? "",
                serial: c.hardware?.serialNumber ?? "",
                osVersion: c.operatingSystem?.version ?? "",
                filevault: encrypted ? "ENCRYPTED" : "NOT_ENCRYPTED",
                gatekeeper: c.security?.gatekeeperStatus?.uppercased() ?? "NOT_COLLECTED",
                sip: c.security?.sipStatus?.uppercased() ?? "NOT_COLLECTED",
                firewall: c.security?.firewallEnabled ?? false
            )
        }

        let total = devices.count
        func pct(_ n: Int) -> String {
            total == 0 ? "0.0%" : String(format: "%.1f%%", Double(n) * 100 / Double(total))
        }
        let fv = devices.filter(\.isFilevaultEncrypted).count
        let gk = devices.filter(\.isGatekeeperEnabled).count
        let sip = devices.filter(\.isSIPEnabled).count
        let fw = devices.filter(\.firewall).count
        let summary = SecuritySummary(
            totalDevices: total,
            filevaultEncrypted: fv, filevaultEncryptedPct: pct(fv),
            gatekeeperEnabled: gk, gatekeeperEnabledPct: pct(gk),
            sipEnabled: sip, sipEnabledPct: pct(sip),
            firewallEnabled: fw, firewallEnabledPct: pct(fw)
        )

        let counts = Dictionary(grouping: devices.map(\.osVersion).filter { !$0.isEmpty }, by: { $0 }).mapValues(\.count)
        let osVersions = counts
            .sorted { $0.value != $1.value ? $0.value > $1.value
                                            : $0.key.compare($1.key, options: .numeric) == .orderedDescending }
            .map { OSVersionRow(osVersion: $0.key, count: $0.value, pct: pct($0.value)) }

        self.init(summary: summary, osVersions: osVersions, devices: devices)
    }
}
