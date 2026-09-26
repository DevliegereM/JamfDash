import SwiftUI

struct DDMDeclarationDetailView: View {
    let state: LoadState<[DDMStatusItem]>
    let hasSelection: Bool
    /// True when jamf-cli reported the status-items endpoint as deprecated/unsupported (exit 15).
    var endpointUnsupported: Bool = false
    var onRetry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            switch state {
            case .idle:
                emptyPlaceholder

            case .loading:
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Loading status items…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))

            case .loaded(let items) where items.isEmpty && endpointUnsupported:
                DDMEndpointUnsupportedView(what: "DDM status items")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor))

            case .loaded(let items) where items.isEmpty:
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No DDM status items reported")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))

            case .loaded(let items):
                statusItemsList(items)

            case .failed(let message):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundStyle(.orange)
                    Text("Failed to load status items")
                        .font(.headline)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                    if let onRetry {
                        Button("Retry", action: onRetry)
                            .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))
            }
        }
    }

    private var emptyPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(hasSelection ? "No DDM status items reported" : "Select a device to view DDM status")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func statusItemsList(_ items: [DDMStatusItem]) -> some View {
        ScrollView {
            DDMStatusSummaryCard(summary: DDMDeviceStatusSummary(items: items))
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)

            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(item.knownKey?.title ?? item.key)
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                            if item.knownKey?.isNewInOS27 == true {
                                Text("OS 27")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(.tint.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.tint)
                            }
                        }
                        if item.knownKey != nil {
                            Text(item.key)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                        }
                        if let value = item.value {
                            Text(value)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        if let ts = item.lastUpdateTime {
                            Text(ts)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    if idx < items.count - 1 {
                        Divider()
                            .padding(.horizontal, 16)
                    }
                }
            }
        }
    }
}

// MARK: - Typed summary

struct DDMStatusSummaryCard: View {
    let summary: DDMDeviceStatusSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Status Summary")
                .font(.subheadline.weight(.semibold))
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                row("OS", value: [summary.osVersion, summary.osBuild.map { "(\($0))" }].compactMap { $0 }.joined(separator: " "))
                row("Enrollment Type", value: summary.enrollmentTypeLabel)
                row("Awaiting Configuration", value: summary.isAwaitingConfiguration.map { $0 ? "Yes" : "No" })
                row("Lockdown Mode", value: summary.lockdownModeEnabled.map { $0 ? "On" : "Off" })
                row("Return to Service", value: summary.isReturnToService.map { $0 ? "Yes" : "No" })
                if let health = summary.systemHealth {
                    row("Hardware Health", value: summary.unhealthyComponents.isEmpty
                        ? "All \(health.count) components OK"
                        : "Issues: " + summary.unhealthyComponents.joined(separator: ", "))
                }
                row("Update State", value: summary.softwareUpdate.installState?.capitalized)
                if summary.softwareUpdate.hasPendingUpdate {
                    row("Pending Update", value: [summary.softwareUpdate.pendingOSVersion,
                                                  summary.softwareUpdate.targetLocalDateTime.map { "enforced \($0)" }]
                        .compactMap { $0 }.joined(separator: " — "))
                }
                if let count = summary.softwareUpdate.failureCount, count > 0 {
                    row("Update Failures", value: "\(count)" + (summary.softwareUpdate.failureReason.map { " — \($0)" } ?? ""))
                }
            }
            if !summary.reportsOS27Items {
                Text("This device doesn't report the OS 27 status items (enrollment type, awaiting configuration, Lockdown Mode). They appear once it runs macOS 27 and Jamf Pro subscribes to them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func row(_ label: String, value: String?) -> some View {
        GridRow {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.flatMap { $0.isEmpty ? nil : $0 } ?? "Not reported")
                .font(.caption)
                .foregroundStyle(value == nil ? .tertiary : .primary)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Shown when jamf-cli exits 15 (deprecated / unsupported endpoint) without data.
struct DDMEndpointUnsupportedView: View {
    let what: String

    var body: some View {
        ContentUnavailableView {
            Label("Endpoint Not Supported", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
        } description: {
            Text("Jamf Pro reported the \(what) endpoint as deprecated or not supported (jamf-cli exit code 15), and returned no data. This is not the same as “no data” — check your Jamf Pro version and update jamf-cli.")
        }
    }
}

#Preview {
    DDMDeclarationDetailView(
        state: .loaded([
            DDMStatusItem(key: "device.identifier.serial-number", value: "ZWC4FXYGYV", lastUpdateTime: "2026-04-24T15:56:17.194"),
            DDMStatusItem(key: "management.declarations.activations", value: "{active=true, valid=valid}", lastUpdateTime: "2026-04-24T15:56:17.198")
        ]),
        hasSelection: true
    )
}
