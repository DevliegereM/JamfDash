import Foundation
import SwiftUI

// MARK: - Credentials

struct JSCCredentials: Codable, Sendable {
    let applicationID: String
    let applicationSecret: String
}

// MARK: - API Response wrappers

struct JSCDeviceListResponse: Decodable, Sendable {
    let customerId: String?
    let userDeviceList: [JSCDevice]
}

private struct JSCLoginResponse: Decodable, Sendable {
    let token: String
}

// MARK: - Device

struct JSCDevice: Decodable, Identifiable, Sendable {
    let guid: String
    let externalId: String?
    let phoneNumber: String?
    let user: JSCUser?
    let status: String?
    let info: JSCDeviceInfo?
    let hardwareSpec: JSCHardwareSpec?
    let statusUpdate: JSCStatusUpdate?
    let connectorState: String?
    let riskCategory: String?
    let deploymentState: String?
    let lastPrivateAccessDnsTraffic: Int?
    let lastDnsTraffic: Int?
    let joinDate: Int?
    let appVersion: String?

    var id: String { guid }

    // MARK: Convenience accessors

    var deviceName: String? { info?.device?.deviceName }
    var osType: String? { info?.device?.osType ?? hardwareSpec?.osType }
    var userDisplayName: String? { user?.name?.nilIfEmpty ?? user?.email?.nilIfEmpty }
    var userEmail: String? { user?.email }
    var isEnrolled: Bool { statusUpdate?.connector?.payload?.isEnrolled ?? false }
    var riskLevel: JSCRiskLevel {
        JSCRiskLevel(rawValue: riskCategory?.uppercased() ?? "") ?? .unknown
    }
    var lastSeenDate: Date? {
        guard let ms = lastDnsTraffic ?? lastPrivateAccessDnsTraffic, ms > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(ms) / 1000)
    }
    var joinedDate: Date? {
        guard let ms = joinDate, ms > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(ms) / 1000)
    }

    // Sort keys (non-optional for KeyPathComparator)
    var deviceNameForSort: String { deviceName ?? "" }
    var userForSort: String { userDisplayName ?? "" }
    var osTypeForSort: String { osType ?? "" }
    var lastSeenForSort: Int { lastDnsTraffic ?? lastPrivateAccessDnsTraffic ?? 0 }
}

// MARK: - Sub-models

struct JSCUser: Decodable, Sendable {
    let email: String?
    let name: String?
}

struct JSCDeviceInfo: Decodable, Sendable {
    let device: JSCDeviceDetail?
}

struct JSCDeviceDetail: Decodable, Sendable {
    let deviceName: String?
    let deviceSystemVersion: Int?
    let osType: String?
}

struct JSCHardwareSpec: Decodable, Sendable {
    let osType: String?
}

struct JSCStatusUpdate: Decodable, Sendable {
    let connector: JSCConnector?
}

struct JSCConnector: Decodable, Sendable {
    let lastStatusUpdateUtcMs: String?
    let payload: JSCConnectorPayload?
}

struct JSCConnectorPayload: Decodable, Sendable {
    let isEnrolled: Bool?
}

// MARK: - Risk level

enum JSCRiskLevel: String, Codable, Comparable, Sendable {
    case secure  = "SECURE"
    case low     = "LOW"
    case medium  = "MEDIUM"
    case high    = "HIGH"
    case unknown = "UNKNOWN"

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.order < rhs.order }

    private var order: Int {
        switch self {
        case .unknown: return -1
        case .secure:  return 0
        case .low:     return 1
        case .medium:  return 2
        case .high:    return 3
        }
    }

    var displayName: String {
        switch self {
        case .secure:  return "Secure"
        case .low:     return "Low"
        case .medium:  return "Medium"
        case .high:    return "High"
        case .unknown: return "Unknown"
        }
    }

    var color: Color {
        switch self {
        case .secure:  return .green
        case .low:     return .yellow
        case .medium:  return .orange
        case .high:    return .red
        case .unknown: return .secondary
        }
    }

    var icon: String {
        switch self {
        case .secure:  return "checkmark.shield.fill"
        case .low:     return "exclamationmark.triangle"
        case .medium:  return "exclamationmark.triangle.fill"
        case .high:    return "xmark.shield.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}

// MARK: - Error

enum JSCError: Error, LocalizedError {
    case invalidCredentials
    case authFailed(Int)
    case httpError(Int)
    case rateLimited
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:   return "Invalid Jamf Security Cloud credentials."
        case .authFailed(let code): return "Authentication failed (HTTP \(code)). Check your Application ID and Secret."
        case .httpError(let code):  return "Jamf Security Cloud API error (HTTP \(code))."
        case .rateLimited:          return "Jamf Security Cloud is rate limiting requests. Try again in a few minutes."
        case .invalidResponse:      return "Jamf Security Cloud returned an unexpected response."
        }
    }
}

// MARK: - Helpers

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
