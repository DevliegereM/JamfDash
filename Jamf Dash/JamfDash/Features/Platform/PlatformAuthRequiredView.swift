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
                            Text("Requires jamf-cli 1.17 or later")
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
                        jamf-cli config add-profile <name> \\
                          --auth-method platform \\
                          --url <gateway-url> \\
                          --tenant-id <id>
                        """
                    )

                    instructionSection(
                        title: "Or set environment variables",
                        content: "JAMF_URL, JAMF_CLIENT_ID, JAMF_CLIENT_SECRET, JAMF_TENANT_ID"
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
