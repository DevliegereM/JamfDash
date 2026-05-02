import Foundation

/// Identifies which jamf-cli profile the app should use.
/// Credentials are stored entirely within jamf-cli's own keychain profile store —
/// set up once via `jamf-cli pro setup` on the command line.
struct JamfProfile: Sendable, Hashable {
    /// The jamf-cli profile name. Empty string means "use the active profile".
    var name: String

    var isDefault: Bool { name.isEmpty }

    static let defaultProfile = JamfProfile(name: "")
}
