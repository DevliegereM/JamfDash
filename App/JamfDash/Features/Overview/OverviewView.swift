import SwiftUI

struct OverviewView: View {
    @Bindable var vm: OverviewViewModel
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24, pinnedViews: []) {
                if vm.state.isPending {
                    SyncingIndicator()
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if let error = vm.state.errorMessage {
                    ErrorStateView(message: error) { await vm.load(force: true) }
                } else {
                    headerCards
                    ForEach(vm.sections, id: \.title) { section in
                        SectionBlock(title: section.title, items: section.items)
                        if section.title == "Health & Alerts",
                           let notifications = env.notificationsState.value, !notifications.isEmpty {
                            AlertDetailsView(notifications: notifications)
                        }
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Overview")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await vm.load(force: true) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(vm.state.isLoading)
                .help("Refresh instance overview")
            }
        }
        .liquidGlassToolbar()
    }

    // MARK: - Header hero cards

    @ViewBuilder
    private var headerCards: some View {
        let health = vm.value(for: "Health Status") ?? "—"
        let managed = vm.value(for: "Managed Computers") ?? "—"
        let devices = vm.value(for: "Managed Devices") ?? "—"
        let version = vm.value(for: "Jamf Pro Version") ?? "—"
        let alerts = vm.value(for: "Active Alerts") ?? "None"
        // Treat the instance as online unless it explicitly reports an offline/error state.
        // Numeric values (e.g. "1") indicate a notification count, not an outage.
        let knownOffline: Set<String> = ["offline", "error", "down", "unreachable", "failed"]
        let isHealthy = health != "—" && !knownOffline.contains(health.lowercased())

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Instance Overview")
                    .font(.title2).bold()
                Spacer()
                StatusBadge(text: isHealthy ? "Online" : health.capitalized, isOK: isHealthy)
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                spacing: 12
            ) {
                StatCard(title: "Managed Computers", value: managed, icon: "desktopcomputer", color: .blue)
                StatCard(title: "Managed Devices", value: devices, icon: "iphone", color: .purple)
                StatCard(title: "Jamf Pro Version", value: version, icon: "tag", color: .teal)
                StatCard(title: "Active Alerts", value: alerts, icon: "bell", color: alerts == "None" ? .green : .orange)
            }
        }
    }
}

// MARK: - Alert details

/// Jamf Pro's notifications grouped by kind, with what each is about and how to fix it.
private struct AlertDetailsView: View {
    let notifications: [ProNotification]

    private var groups: [(title: String, type: String, items: [ProNotification])] {
        let byType = Dictionary(grouping: notifications, by: \.type)
        return byType.map { type, items in
            let title = items.first.map { $0.message.isEmpty ? AlertHints.readable(type) : $0.message }
                ?? AlertHints.readable(type)
            return (title, type, items)
        }
        .sorted { $0.items.count > $1.items.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(groups, id: \.type) { group in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            .accessibilityHidden(true)
                        Text(group.title).font(.subheadline.weight(.semibold))
                        if group.items.count > 1 {
                            Text("×\(group.items.count)").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    let subjects = group.items.compactMap(\.subject)
                    if !subjects.isEmpty {
                        Text("Affected: " + subjects.sorted().joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let hint = AlertHints.fix(for: group.type, message: group.title) {
                        Label(hint, systemImage: "wrench.and.screwdriver")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

enum AlertHints {
    /// "PATCH_EXTENSION_ATTRIBUTE" → "Patch extension attribute"
    static func readable(_ type: String) -> String {
        let words = type.replacingOccurrences(of: "_", with: " ").lowercased()
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    static func fix(for type: String, message: String) -> String? {
        let text = (type + " " + message).lowercased()
        if text.contains("patch"), text.contains("extension") {
            return "In Jamf Pro, open Settings → Computer management → Patch Management, select each affected software title, and accept its extension attribute under Extension Attributes. Until then the title can't report versions."
        }
        if text.contains("certificate") || text.contains("apns") || text.contains("push") {
            return "Renew it in Jamf Pro under Settings → Global → Push certificates (or the certificate named in the alert) before it expires."
        }
        if text.contains("vpp") || text.contains("volume purchasing") {
            return "Renew the Volume Purchasing token in Jamf Pro under Settings → Global → Volume purchasing."
        }
        if text.contains("dep") || text.contains("automated device enrollment") {
            return "Renew the Automated Device Enrollment token in Jamf Pro under Settings → Global → Automated Device Enrollment."
        }
        return nil
    }
}

// MARK: - Section block (table-style)

private struct SectionBlock: View {
    let title: String
    let items: [OverviewItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DashSectionHeader(title, systemImage: iconFor(title))
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    HStack {
                        Text(item.resource)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(item.value)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 12)
                    .background(idx.isMultiple(of: 2) ? Color.primary.opacity(0.03) : Color.clear)

                    if idx < items.count - 1 {
                        Divider().padding(.horizontal, 12)
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }

    private func iconFor(_ section: String) -> String {
        switch section {
        case "Health & Alerts": return "heart.fill"
        case "Instance": return "server.rack"
        case "Fleet": return "desktopcomputer"
        case "Configuration": return "slider.horizontal.3"
        case "Organization": return "building.2"
        case "Enrollment & Certificates": return "lock.shield"
        case "Features": return "star.circle"
        case "Security": return "shield.checkered"
        default: return "list.bullet"
        }
    }
}
