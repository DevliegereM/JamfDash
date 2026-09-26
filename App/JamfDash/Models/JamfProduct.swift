import Foundation

/// Identifies which Jamf platform a configured profile connects to.
/// Stored in UserDefaults per profile name by ProfileService.
enum JamfProduct: String, Codable, CaseIterable, Sendable {
    case pro     = "pro"
    case protect = "protect"
    case school  = "school"

    var displayName: String {
        switch self {
        case .pro:     return "Jamf Pro"
        case .protect: return "Jamf Protect"
        case .school:  return "Jamf School"
        }
    }

    var subtitle: String {
        switch self {
        case .pro:     return "MDM, policies, inventory & reporting"
        case .protect: return "Endpoint security, threat detection & compliance"
        case .school:  return "Education device management"
        }
    }

    var icon: String {
        switch self {
        case .pro:     return "server.rack"
        case .protect: return "shield.lefthalf.filled"
        case .school:  return "graduationcap.fill"
        }
    }

    /// The jamf-cli top-level product subcommand ("pro", "protect", "school").
    var cliProduct: String { rawValue }

    var defaultProfileName: String {
        switch self {
        case .pro:     return "Jamf Pro"
        case .protect: return "Jamf Protect"
        case .school:  return "Jamf School"
        }
    }

    /// Human-readable description of how auth credentials are obtained.
    var authDescription: String {
        switch self {
        case .pro:
            return "Provide admin credentials (auto-creates an API client) or paste OAuth2 client credentials created manually in Jamf Pro."
        case .protect:
            return "Create an API client in Jamf Protect → Administration → API Clients, then paste the Client ID and Client Secret below."
        case .school:
            return "Obtain your Network ID and API Key from Jamf School → Organisation → API."
        }
    }
}
