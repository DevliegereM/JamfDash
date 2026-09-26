import Foundation

/// Jamf Platform API gateway region (the choices `jamf-cli platform setup` offers).
enum PlatformRegion: String, CaseIterable, Identifiable, Sendable {
    case us, eu, apac

    var id: String { rawValue }

    var label: String {
        switch self {
        case .us:   return "US"
        case .eu:   return "EU"
        case .apac: return "APAC"
        }
    }

    var gatewayURL: String { "https://\(rawValue).api.jamfcloud.com" }
}

/// The level an API integration was created at in Jamf Account. Its credentials only work
/// at that level; a platform environment spans several tenants and is preferred.
enum PlatformScopeLevel: String, CaseIterable, Identifiable, Sendable {
    case environment, tenant

    var id: String { rawValue }

    var label: String {
        switch self {
        case .environment: return "Environment ID"
        case .tenant:      return "Tenant ID"
        }
    }

    var placeholder: String {
        switch self {
        case .environment: return "Platform environment ID from account.jamf.com"
        case .tenant:      return "Tenant ID from account.jamf.com"
        }
    }

    /// The `jamf-cli config add-profile` flag for this level.
    var flag: String {
        switch self {
        case .environment: return "--environment-id"
        case .tenant:      return "--tenant-id"
        }
    }
}
