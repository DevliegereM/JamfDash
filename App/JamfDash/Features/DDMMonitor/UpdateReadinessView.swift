import SwiftUI

/// macOS 27 software update readiness: flags Macs whose update management still relies on
/// legacy MDM software-update commands or restriction-profile deferrals (removed in OS 27)
/// and shows the DDM (Managed Software Update plan) status next to them.
struct UpdateReadinessView: View {
    @Bindable var vm: UpdateReadinessViewModel
    @State private var selection: UpdateReadinessRow.ID?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            AsyncContentView(state: vm.rowsState, retry: { await vm.load(force: true) }) { rows in
                if rows.isEmpty {
                    ContentUnavailableView("No Computers", systemImage: "desktopcomputer",
                                           description: Text("No computers were returned by the inventory."))
                } else if vm.filteredRows.isEmpty {
                    ContentUnavailableView("Nothing Matches", systemImage: "checkmark.seal",
                                           description: Text("No computers match this filter."))
                } else {
                    HSplitView {
                        table
                            .frame(minWidth: 480, maxHeight: .infinity)
                        detail
                            .frame(minWidth: 260, idealWidth: 320, maxWidth: 420, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            // Fill the remaining height so the header stays at the top.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 20) {
                summaryChip("macOS 27+", value: vm.os27Count, tint: .accentColor)
                summaryChip(ReadinessLevel.blocked.label, value: vm.count(.blocked), tint: .red)
                summaryChip(ReadinessLevel.attention.label, value: vm.count(.attention), tint: .orange)
                summaryChip(ReadinessLevel.info.label, value: vm.count(.info), tint: .blue)
                summaryChip(ReadinessLevel.ready.label, value: vm.count(.ready), tint: .green)
                Spacer()
                Picker("Filter", selection: $vm.filter) {
                    ForEach(ReadinessFilter.allCases) { f in Text(f.rawValue).tag(f) }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 200)
                TextField("Search", text: $vm.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)
            }
            ForEach(vm.notes, id: \.self) { note in
                Label(note, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("On macOS 27 the MDM software update commands, the Software Update payload and restriction-based deferrals are removed — only DDM software update declarations (Jamf Pro Managed Software Update plans / Blueprints) work.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    private func summaryChip(_ title: String, value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(value)").font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(tint)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Table

    private var table: some View {
        Table(vm.filteredRows, selection: $selection) {
            TableColumn("Computer") { row in
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.computer.name).lineLimit(1)
                    if let serial = row.computer.serialNumber {
                        Text(serial).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            TableColumn("macOS") { row in
                Text(row.computer.osVersion ?? "—")
                    .monospacedDigit()
                    .fontWeight(row.isOS27OrLater ? .semibold : .regular)
            }
            .width(70)
            TableColumn("DDM") { row in
                Text(row.computer.ddmEnabled.map { $0 ? "On" : "Off" } ?? "—")
                    .foregroundStyle(row.computer.ddmEnabled == false ? .red : .primary)
            }
            .width(45)
            TableColumn("DDM Update Plan") { row in
                if let plan = row.plan {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(plan.targetDescription).lineLimit(1)
                        Text(plan.state ?? "—").font(.caption2)
                            .foregroundStyle(plan.isFailed ? .red : .secondary)
                    }
                } else {
                    Text("None").foregroundStyle(.tertiary)
                }
            }
            TableColumn("Update Status") { row in
                Text(row.status?.status?.replacingOccurrences(of: "_", with: " ").capitalized ?? "—")
                    .foregroundStyle(row.status == nil ? .tertiary : .primary)
                    .lineLimit(1)
            }
            .width(110)
            TableColumn("Readiness") { row in
                Label(row.level.label, systemImage: icon(row.level))
                    .foregroundStyle(color(row.level))
                    .lineLimit(1)
            }
            .width(140)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let id = selection, let row = vm.filteredRows.first(where: { $0.id == id }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(row.computer.name).font(.headline)
                    Label(row.level.label, systemImage: icon(row.level))
                        .foregroundStyle(color(row.level))
                    if row.issues.isEmpty {
                        Text("No readiness issues found.").foregroundStyle(.secondary)
                    }
                    ForEach(row.issues, id: \.self) { issue in
                        Label(issue.message, systemImage: icon(issue.level))
                            .foregroundStyle(color(issue.level))
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let plan = row.plan {
                        Divider()
                        Text("DDM Software Update Plan").font(.subheadline.weight(.semibold))
                        LabeledContent("Action", value: plan.updateAction ?? "—")
                        LabeledContent("Target", value: plan.targetDescription)
                        LabeledContent("State", value: plan.state ?? "—")
                        if let date = plan.forceInstallLocalDateTime {
                            LabeledContent("Enforced by", value: date)
                        }
                    }
                    if let status = row.status {
                        Divider()
                        Text("Managed Update Status").font(.subheadline.weight(.semibold))
                        LabeledContent("Status", value: status.status ?? "—")
                        if let key = status.productKey { LabeledContent("Product", value: key) }
                        if let next = status.nextScheduledInstall { LabeledContent("Next install", value: next) }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView("Select a Computer", systemImage: "arrow.triangle.2.circlepath",
                                   description: Text("Select a row to see readiness details."))
        }
    }

    private func icon(_ level: ReadinessLevel) -> String {
        switch level {
        case .ready: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .attention: return "exclamationmark.triangle.fill"
        case .blocked: return "xmark.octagon.fill"
        }
    }

    private func color(_ level: ReadinessLevel) -> Color {
        switch level {
        case .ready: return .green
        case .info: return .blue
        case .attention: return .orange
        case .blocked: return .red
        }
    }
}
