import Foundation

// MARK: - Device (from computers-inventory GENERAL section)

struct DDMDevice: Sendable, Identifiable, Hashable {
    let id: String            // Jamf Pro computer ID
    let managementId: String  // UUID used for ddm-statuss calls
    let name: String
    let serialNumber: String?
    /// `general.declarativeDeviceManagementEnabled` — nil when the field is absent.
    var ddmEnabled: Bool? = nil
}

extension DDMDevice: Decodable {
    private struct GeneralSection: Decodable {
        let name: String?
        let managementId: String?
        let serialNumber: String?
        let declarativeDeviceManagementEnabled: Bool?
    }

    private enum CodingKeys: String, CodingKey {
        case id, general, serialNumber
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let strID = try? c.decode(String.self, forKey: .id) {
            id = strID
        } else if let intID = try? c.decode(Int.self, forKey: .id) {
            id = String(intID)
        } else {
            id = UUID().uuidString
        }
        let general = try? c.decode(GeneralSection.self, forKey: .general)
        managementId = general?.managementId ?? ""
        name = general?.name ?? id
        serialNumber = (try? c.decode(String.self, forKey: .serialNumber)) ?? general?.serialNumber
        ddmEnabled = general?.declarativeDeviceManagementEnabled
    }
}

// MARK: - Status items response

struct DDMStatusItemResponse: Decodable {
    let statusItems: [DDMStatusItem]
}

/// One status item from `jamf-cli pro ddm-status status-items <managementId>`.
///
/// Jamf Pro usually returns `value` as a string — for dictionaries it is a Java
/// `Map.toString()` rendering such as `{os-version=27.0, build-version=27A5}`.
/// `value` keeps that raw text for display; `parsedValue` is the typed form
/// (see `DDMStatusValue.parse`). Unknown keys are preserved untouched.
struct DDMStatusItem: Sendable, Hashable, Identifiable {
    let key: String
    let value: String?
    let lastUpdateTime: String?
    /// Typed representation of `value` (JSON, Java-map text, bool, number or string).
    let parsedValue: DDMStatusValue?

    var id: String { key }

    /// The known status item for `key`, or nil for keys JamfDash doesn't model yet.
    var knownKey: DDMStatusKey? { DDMStatusKey(rawValue: key) }

    init(key: String, value: String?, lastUpdateTime: String?, parsedValue: DDMStatusValue? = nil) {
        self.key = key
        self.value = value
        self.lastUpdateTime = lastUpdateTime
        self.parsedValue = parsedValue ?? value.map(DDMStatusValue.parse)
    }
}

extension DDMStatusItem: Decodable {
    private enum CodingKeys: String, CodingKey {
        case key, value, lastUpdateTime
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let key = (try? c.decode(String.self, forKey: .key)) ?? ""
        let lastUpdateTime = try? c.decode(String.self, forKey: .lastUpdateTime)
        if let s = try? c.decode(String.self, forKey: .value) {
            self.init(key: key, value: s, lastUpdateTime: lastUpdateTime)
        } else if let typed = try? c.decode(DDMStatusValue.self, forKey: .value), typed != .null {
            // Non-string JSON value (bool / number / object / array): keep it typed and
            // render a readable string for the raw list.
            self.init(key: key, value: typed.displayString, lastUpdateTime: lastUpdateTime, parsedValue: typed)
        } else {
            self.init(key: key, value: nil, lastUpdateTime: lastUpdateTime)
        }
    }
}

// MARK: - Typed status value

/// A loosely-typed status item value.
indirect enum DDMStatusValue: Sendable, Hashable {
    case string(String)
    case bool(Bool)
    case number(Double)
    case object([String: DDMStatusValue])
    case array([DDMStatusValue])
    case null

    var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .bool(let b): return b ? "true" : "false"
        case .number(let n): return n.rounded() == n ? String(Int(n)) : String(n)
        default: return nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let b): return b
        case .string(let s):
            switch s.lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: return nil
            }
        case .number(let n): return n != 0
        default: return nil
        }
    }

    var intValue: Int? {
        switch self {
        case .number(let n): return Int(n)
        case .string(let s): return Int(s.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    var objectValue: [String: DDMStatusValue]? {
        if case .object(let o) = self { return o }
        return nil
    }

    subscript(key: String) -> DDMStatusValue? { objectValue?[key] }

    var displayString: String {
        switch self {
        case .string(let s): return s
        case .bool, .number: return stringValue ?? ""
        case .null: return "null"
        case .array(let a): return "[" + a.map(\.displayString).joined(separator: ", ") + "]"
        case .object(let o):
            return "{" + o.keys.sorted().map { "\($0)=\(o[$0]!.displayString)" }.joined(separator: ", ") + "}"
        }
    }

    // MARK: Parsing

    /// Parses a status item string: JSON first, then Jamf's Java-map rendering
    /// (`{a=1, b={c=d}}` / `[x, y]`), then scalars.
    static func parse(_ text: String) -> DDMStatusValue {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmed.first, first == "{" || first == "[",
           let data = trimmed.data(using: .utf8),
           let json = try? JSONDecoder().decode(DDMStatusValue.self, from: data) {
            return json
        }
        if let first = trimmed.first, first == "{" || first == "[" {
            var parser = JavaMapParser(Array(trimmed))
            if let v = parser.parseValue(), parser.isAtEnd { return v }
        }
        return scalar(trimmed)
    }

    fileprivate static func scalar(_ s: String) -> DDMStatusValue {
        switch s.lowercased() {
        case "true": return .bool(true)
        case "false": return .bool(false)
        case "null": return .null
        default: break
        }
        return .string(s)
    }
}

extension DDMStatusValue: Decodable {
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([DDMStatusValue].self) { self = .array(a) }
        else if let o = try? c.decode([String: DDMStatusValue].self) { self = .object(o) }
        else { self = .null }
    }
}

/// Minimal parser for Java `Map.toString()` / `List.toString()` output.
private struct JavaMapParser {
    private let chars: [Character]
    private var pos = 0

    init(_ chars: [Character]) { self.chars = chars }

    var isAtEnd: Bool {
        var p = pos
        while p < chars.count, chars[p].isWhitespace { p += 1 }
        return p >= chars.count
    }

    private mutating func skipSpaces() {
        while pos < chars.count, chars[pos] == " " { pos += 1 }
    }

    mutating func parseValue() -> DDMStatusValue? {
        skipSpaces()
        guard pos < chars.count else { return nil }
        switch chars[pos] {
        case "{": return parseObject()
        case "[": return parseArray()
        default: return DDMStatusValue.scalar(readScalar(stopAt: [",", "}", "]"]))
        }
    }

    private mutating func readScalar(stopAt stops: Set<Character>) -> String {
        let start = pos
        while pos < chars.count, !stops.contains(chars[pos]) { pos += 1 }
        return String(chars[start..<pos]).trimmingCharacters(in: .whitespaces)
    }

    private mutating func parseObject() -> DDMStatusValue? {
        pos += 1 // {
        var dict: [String: DDMStatusValue] = [:]
        skipSpaces()
        if pos < chars.count, chars[pos] == "}" { pos += 1; return .object(dict) }
        while pos < chars.count {
            let key = readScalar(stopAt: ["=", "}", ","])
            guard pos < chars.count, chars[pos] == "=" else { return nil }
            pos += 1
            guard let value = parseValue() else { return nil }
            dict[key] = value
            skipSpaces()
            guard pos < chars.count else { return nil }
            if chars[pos] == "," { pos += 1; continue }
            if chars[pos] == "}" { pos += 1; return .object(dict) }
            return nil
        }
        return nil
    }

    private mutating func parseArray() -> DDMStatusValue? {
        pos += 1 // [
        var items: [DDMStatusValue] = []
        skipSpaces()
        if pos < chars.count, chars[pos] == "]" { pos += 1; return .array(items) }
        while pos < chars.count {
            guard let value = parseValue() else { return nil }
            items.append(value)
            skipSpaces()
            guard pos < chars.count else { return nil }
            if chars[pos] == "," { pos += 1; continue }
            if chars[pos] == "]" { pos += 1; return .array(items) }
            return nil
        }
        return nil
    }
}

// MARK: - Known status item keys

/// Status item keys JamfDash understands. Names and OS availability come from
/// Apple's device-management schema (github.com/apple/device-management,
/// `declarative/status/*.yaml`, release branch).
enum DDMStatusKey: String, Sendable, CaseIterable {
    // Device
    case serialNumber            = "device.identifier.serial-number"
    case udid                    = "device.identifier.udid"
    case modelFamily             = "device.model.family"
    case modelIdentifier         = "device.model.identifier"
    case modelMarketingName      = "device.model.marketing-name"
    case osBuildVersion          = "device.operating-system.build-version"
    case osFamily                = "device.operating-system.family"
    case osMarketingName         = "device.operating-system.marketing-name"
    case osVersion               = "device.operating-system.version"
    case batteryHealth           = "device.power.battery-health"
    case systemHealth            = "device.system.health"                 // OS 27 (iOS only)
    // Management
    case clientCapabilities      = "management.client-capabilities"
    case declarations            = "management.declarations"
    case enrollmentType          = "mdm.enrollment-type"                  // OS 27
    case isAwaitingConfiguration = "mdm.is-awaiting-configuration"        // OS 27
    case isReturnToService       = "mdm.is-return-to-service"             // OS 27 (iOS/visionOS)
    // Security
    case lockdownMode            = "security.lockdown-mode"               // OS 27
    case fileVaultEnabled        = "diskmanagement.filevault.enabled"
    case passcodeCompliant       = "passcode.is-compliant"
    case passcodePresent         = "passcode.is-present"
    // Software update
    case suInstallState          = "softwareupdate.install-state"
    case suPendingVersion        = "softwareupdate.pending-version"
    case suFailureReason         = "softwareupdate.failure-reason"
    case suInstallReason         = "softwareupdate.install-reason"
    case suBetaEnrollment        = "softwareupdate.beta-enrollment"
    case suDeviceID              = "softwareupdate.device-id"

    var title: String {
        switch self {
        case .serialNumber:            return "Serial Number"
        case .udid:                    return "UDID"
        case .modelFamily:             return "Model Family"
        case .modelIdentifier:         return "Model Identifier"
        case .modelMarketingName:      return "Model"
        case .osBuildVersion:          return "OS Build"
        case .osFamily:                return "OS Family"
        case .osMarketingName:         return "OS Name"
        case .osVersion:               return "OS Version"
        case .batteryHealth:           return "Battery Health"
        case .systemHealth:            return "Hardware Health"
        case .clientCapabilities:      return "Client Capabilities"
        case .declarations:            return "Declarations"
        case .enrollmentType:          return "Enrollment Type"
        case .isAwaitingConfiguration: return "Awaiting Configuration"
        case .isReturnToService:       return "Return to Service"
        case .lockdownMode:            return "Lockdown Mode"
        case .fileVaultEnabled:        return "FileVault"
        case .passcodeCompliant:       return "Passcode Compliant"
        case .passcodePresent:         return "Passcode Present"
        case .suInstallState:          return "Update Install State"
        case .suPendingVersion:        return "Pending Update"
        case .suFailureReason:         return "Update Failures"
        case .suInstallReason:         return "Update Install Reason"
        case .suBetaEnrollment:        return "Beta Enrollment"
        case .suDeviceID:              return "Software Update Device ID"
        }
    }

    /// True for status items introduced with the OS 27 releases.
    var isNewInOS27: Bool {
        switch self {
        case .systemHealth, .enrollmentType, .isAwaitingConfiguration, .isReturnToService, .lockdownMode:
            return true
        default:
            return false
        }
    }

    /// False for items Apple's schema marks as not available on macOS.
    var isReportedByMacOS: Bool {
        switch self {
        case .systemHealth, .isReturnToService, .passcodeCompliant: return false
        default: return true
        }
    }
}

// MARK: - Typed per-device summary

struct DDMSoftwareUpdateStatus: Sendable, Hashable {
    /// none / downloading / prepared / installing / failed
    var installState: String?
    var pendingOSVersion: String?
    var pendingBuildVersion: String?
    var targetLocalDateTime: String?
    var failureCount: Int?
    var failureReason: String?
    var installReason: String?

    var isReported: Bool {
        installState != nil || pendingOSVersion != nil || failureCount != nil
    }
    var isFailed: Bool {
        installState?.lowercased() == "failed" || (failureCount ?? 0) > 0
    }
    var hasPendingUpdate: Bool {
        guard let v = pendingOSVersion else { return false }
        return !v.isEmpty
    }
}

/// Typed view over a device's status items. Unknown keys are listed in `unknownKeys`
/// (and remain available as raw items) so new Apple keys never disappear.
struct DDMDeviceStatusSummary: Sendable, Hashable {
    var osVersion: String?
    var osBuild: String?
    var enrollmentType: String?
    var isAwaitingConfiguration: Bool?
    var isReturnToService: Bool?
    var lockdownModeEnabled: Bool?
    var fileVaultEnabled: Bool?
    /// component name → ok / error / non-genuine
    var systemHealth: [String: String]?
    var softwareUpdate = DDMSoftwareUpdateStatus()
    var unknownKeys: [String] = []

    init(items: [DDMStatusItem]) {
        for item in items {
            guard let known = item.knownKey else {
                unknownKeys.append(item.key)
                continue
            }
            let v = item.parsedValue
            switch known {
            case .osVersion:               osVersion = v?.stringValue
            case .osBuildVersion:          osBuild = v?.stringValue
            case .enrollmentType:          enrollmentType = v?.stringValue
            case .isAwaitingConfiguration: isAwaitingConfiguration = v?.boolValue
            case .isReturnToService:       isReturnToService = v?.boolValue
            case .lockdownMode:            lockdownModeEnabled = v?.boolValue
            case .fileVaultEnabled:        fileVaultEnabled = v?.boolValue
            case .systemHealth:
                if let obj = v?.objectValue {
                    systemHealth = obj.compactMapValues(\.stringValue)
                }
            case .suInstallState:          softwareUpdate.installState = v?.stringValue
            case .suInstallReason:
                // Dictionary with a `reason` array on current OSes; keep a readable string.
                if let reasons = v?["reason"] { softwareUpdate.installReason = reasons.displayString }
                else { softwareUpdate.installReason = v?.displayString }
            case .suPendingVersion:
                let os = v?["os-version"]?.stringValue
                softwareUpdate.pendingOSVersion = os
                softwareUpdate.pendingBuildVersion = v?["build-version"]?.stringValue
                softwareUpdate.targetLocalDateTime = v?["target-local-date-time"]?.stringValue
            case .suFailureReason:
                softwareUpdate.failureCount = v?["count"]?.intValue
                softwareUpdate.failureReason = v?["reason"]?.stringValue
            default:
                break
            }
        }
    }

    /// True when the device reports any of the OS 27 status items.
    var reportsOS27Items: Bool {
        enrollmentType != nil || isAwaitingConfiguration != nil || isReturnToService != nil
            || lockdownModeEnabled != nil || systemHealth != nil
    }

    /// Components whose health isn't `ok`.
    var unhealthyComponents: [String] {
        (systemHealth ?? [:]).filter { $0.value.lowercased() != "ok" }.map(\.key).sorted()
    }

    var enrollmentTypeLabel: String? {
        switch enrollmentType?.lowercased() {
        case nil: return nil
        case "supervised": return "Supervised"
        case "device": return "Device"
        case "user": return "User"
        case "none": return "Not enrolled"
        default: return enrollmentType
        }
    }
}

// MARK: - Declaration coverage

struct DDMCoverageSummary: Sendable, Hashable {
    let inventoryDevices: Int
    let ddmEnabledDevices: Int
    let declarationCount: Int
    let succeeded: Int
    let failed: Int
    let pending: Int

    var deviceCoverage: Double? {
        inventoryDevices > 0 ? Double(ddmEnabledDevices) / Double(inventoryDevices) : nil
    }
    var successRate: Double? {
        let total = succeeded + failed + pending
        return total > 0 ? Double(succeeded) / Double(total) : nil
    }
}

// MARK: - Status

enum DDMStatus: String, Sendable, Hashable {
    case active, pending, error, unknown
}
