import Foundation

/// Jamf Pro connection credentials.
/// jamf-cli v1.9+ authenticates via OAuth client credentials
/// (JAMF_CLIENT_ID / JAMF_CLIENT_SECRET env vars).
struct JamfCredentials: Sendable, Hashable {
    let serverURL: URL
    let clientID: String
    let clientSecret: String
}
