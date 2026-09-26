import Foundation

// MARK: - Top-level parsed report

struct SecurityReport: Sendable {
    var summary: SecuritySummary?
    var osVersions: [OSVersionRow] = []
    var devices: [DeviceSecurity] = []

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
