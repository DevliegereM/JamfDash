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
            }
        }
    }

    // MARK: - Header hero cards

    @ViewBuilder
    private var headerCards: some View {
        let health = vm.value(for: "Health Status") ?? "—"
        let managed = vm.value(for: "Managed Computers") ?? "—"
        let devices = vm.value(for: "Managed Devices") ?? "—"
        let version = vm.value(for: "Jamf Pro Version") ?? "—"
        let alerts = vm.value(for: "Active Alerts") ?? "None"
        // jamf-cli returns "ok" for a healthy instance
        let isHealthy = health == "ok" || health == "online"

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
