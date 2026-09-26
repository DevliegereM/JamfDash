import SwiftUI

struct PlatformAuthRequiredView: View {
    let featureName: String

    var body: some View {
        ScrollView {
            VStack(alignment: .center, spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    Text("Platform Gateway Auth Required")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("\(featureName) require a Jamf platform profile with platform gateway authentication.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)

                    // Version requirement notice
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.blue)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Requires jamf-cli \(CLIManager.minimumCLIVersion) or later")
                                .font(.callout)
                                .fontWeight(.medium)
                            Link("Download the latest release at github.com/Jamf-Concepts/jamf-cli",
                                 destination: URL(string: "https://github.com/Jamf-Concepts/jamf-cli/releases")!)
                                .font(.caption)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .frame(maxWidth: 480)
                    .background(Color.blue.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: 16) {
                    instructionSection(
                        title: "Set up a platform profile",
                        content: """
                        jamf-cli platform setup --profile-name <name>
                        """
                    )

                    instructionSection(
                        title: "Or set environment variables",
                        content: "JAMF_URL (https://<region>.api.jamfcloud.com), JAMF_CLIENT_ID, JAMF_CLIENT_SECRET, and JAMF_ENVIRONMENT_ID or JAMF_TENANT_ID"
                    )
                }
                .frame(maxWidth: 480)
            }
            .padding(32)
        }
    }

    private func instructionSection(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.primary)

            Text(content)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

/// Shown instead of Blueprints / Compliance Benchmarks when the active profile can't load them.
struct PlatformAPIUnavailableView: View {
    let featureName: String
    let systemImage: String
    /// Jamf Account permission the integration needs, e.g. "Deployment → Blueprints: Read".
    let permission: String
    let access: AppEnvironment.PlatformFeatureAccess

    static func tooltip(for access: AppEnvironment.PlatformFeatureAccess) -> String {
        switch access {
        case .requiresPlatformAPI: return "Requires a Jamf Platform API connection"
        case .noPermission:        return "Not available to this Platform API connection"
        case .checking, .available: return ""
        }
    }

    var body: some View {
        ContentUnavailableView {
            Label(Self.tooltip(for: access), systemImage: systemImage)
        } description: {
            switch access {
            case .noPermission:
                Text("This API integration can't read \(featureName). In Jamf Account, create an API integration at the **platform environment** level with **\(permission)**, and add it in Settings → Connection as a Platform API connection with its Environment ID.")
            default:
                Text("jamf-cli offers \(featureName) only through the Jamf Platform API. Switch to a Platform API connection with the profile picker at the bottom of the sidebar.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
