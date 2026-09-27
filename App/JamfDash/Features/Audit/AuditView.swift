import SwiftUI

struct AuditView: View {
    @Bindable var vm: AuditViewModel
    @State private var selectedID: AuditFinding.ID?
    @State private var detailFinding: AuditFinding?

    var body: some View {
        VStack(spacing: 0) {
            summaryBar
            Divider()
            filterBar
            Divider()
            if !vm.failedChecks.isEmpty, vm.findingsState.value != nil {
                failedChecksBanner
                Divider()
            }

            AsyncContentView(
                state: vm.findingsState,
                retry: { await vm.load(force: true) },
                content: { _ in
                    if vm.filtered.isEmpty {
                        ContentUnavailableView(
                            vm.findingsState.value?.isEmpty == true
                                ? "No Findings" : "No Matching Findings",
                            systemImage: "checkmark.seal.fill",
                            description: Text(
                                vm.findingsState.value?.isEmpty != true
                                    ? "Try adjusting your filters."
                                    : vm.failedChecks.isEmpty
                                        ? "All audit checks passed — your environment looks healthy."
                                        : "The checks that ran found nothing. Some checks couldn't run; see above."
                            )
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        findingsTable
                            .sheet(item: $detailFinding) { finding in
                                AuditFindingDetailSheet(finding: finding)
                                    .onDisappear { selectedID = nil }
                            }
                    }
                }
            )
        }
        .navigationTitle("Audit Dashboard")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await vm.load(force: true) }
                } label: {
                    Label("Refresh", systemImage: "arrow.triangle.2.circlepath")
                }
                .help("Refresh audit findings")
            }
        }
        .liquidGlassToolbar()
        .task { await vm.load() }
        // Clear selection when filters change so stale finding isn't shown
        .onChange(of: vm.severityFilter) { _, _ in clearSelection() }
        .onChange(of: vm.categoryFilter) { _, _ in clearSelection() }
        .onChange(of: vm.searchText)    { _, _ in clearSelection() }
    }

    private func clearSelection() {
        selectedID = nil
        detailFinding = nil
    }

    // MARK: - Failed checks

    private var failedChecksBanner: some View {
        let names = vm.failedChecks.keys.sorted().map(\.capitalized).joined(separator: ", ")
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Some checks couldn't run: \(names)").font(.callout.weight(.medium))
                if let first = vm.failedChecks.sorted(by: { $0.key < $1.key }).first {
                    Text(first.value).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        .textSelection(.enabled)
                }
            }
            Spacer()
            Button("Try Again") { Task { await vm.load(force: true) } }
                .controlSize(.small)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Summary Bar

    private var summaryBar: some View {
        HStack(spacing: 16) {
            Spacer()
            AuditSeverityChip(severity: .critical, count: vm.criticalCount,
                              selected: vm.severityFilter == .critical) {
                vm.severityFilter = vm.severityFilter == .critical ? nil : .critical
            }
            AuditSeverityChip(severity: .warning, count: vm.warningCount,
                              selected: vm.severityFilter == .warning) {
                vm.severityFilter = vm.severityFilter == .warning ? nil : .warning
            }
            AuditSeverityChip(severity: .info, count: vm.infoCount,
                              selected: vm.severityFilter == .info) {
                vm.severityFilter = vm.severityFilter == .info ? nil : .info
            }
            Spacer()
        }
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search findings…", text: $vm.searchText)
                .textFieldStyle(.plain)

            if !vm.categories.isEmpty {
                Spacer()
                Picker("Category", selection: $vm.categoryFilter) {
                    Text("All Categories").tag(Optional<String>.none)
                    ForEach(vm.categories, id: \.self) { cat in
                        Text(cat.capitalized).tag(Optional(cat))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 200)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }

    // MARK: - Findings Table

    private var findingsTable: some View {
        Table(vm.filtered, selection: $selectedID) {
            TableColumn("") { finding in
                Image(systemName: finding.severity.icon)
                    .foregroundStyle(finding.severity.color)
                    .help(finding.severity.label)
            }
            .width(24)

            TableColumn("Finding") { finding in
                VStack(alignment: .leading, spacing: 2) {
                    Text(finding.title).lineLimit(1)
                    if let desc = finding.description {
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            TableColumn("Category") { finding in
                Text(finding.category.capitalized)
                    .font(.caption)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.15), in: Capsule())
                    .foregroundStyle(.secondary)
            }
            .width(120)

            TableColumn("Affected") { finding in
                if let count = finding.affectedCount {
                    Text("\(count)")
                        .foregroundStyle(count > 0 ? finding.severity.color : .secondary)
                        .monospacedDigit()
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
            }
            .width(80)

            TableColumn("Remediation") { finding in
                Text(finding.remediation ?? "—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .onChange(of: selectedID) { _, newID in
            detailFinding = vm.filtered.first { $0.id == newID }
        }
    }
}

// MARK: - Finding Detail Sheet

private struct AuditFindingDetailSheet: View {
    let finding: AuditFinding
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top, spacing: 16) {
                // Severity badge
                VStack(spacing: 4) {
                    Image(systemName: finding.severity.icon)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(finding.severity.color)
                    Text(finding.severity.label.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(finding.severity.color)
                        .tracking(0.5)
                }
                .frame(width: 64)
                .padding(12)
                .background(finding.severity.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))

                // Title and chips
                VStack(alignment: .leading, spacing: 6) {
                    Text(finding.title)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Label(finding.category.capitalized, systemImage: "tag")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.secondary.opacity(0.12), in: Capsule())
                            .foregroundStyle(.secondary)

                        if let count = finding.affectedCount {
                            Label("\(count) affected", systemImage: isProfileFinding ? "doc.badge.gearshape" : "desktopcomputer")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    count > 0
                                        ? finding.severity.color.opacity(0.12)
                                        : Color.secondary.opacity(0.08),
                                    in: Capsule()
                                )
                                .foregroundStyle(count > 0 ? finding.severity.color : .secondary)
                        }
                    }
                }

                Spacer()

                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Details
                    if let desc = finding.description {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Details", systemImage: "doc.text")
                                .font(.subheadline.weight(.semibold))
                            Text(desc)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    // Remediation
                    if let remediation = finding.remediation {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Remediation", systemImage: "wrench.and.screwdriver")
                                .font(.subheadline.weight(.semibold))
                            Text(remediation)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    // Affected Devices
                    if let count = finding.affectedCount {
                        affectedDevicesSection(count: count)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 580, minHeight: 480)
    }

    /// Deprecation findings list configuration profiles rather than devices.
    private var isProfileFinding: Bool { finding.category == DeprecationAuditRules.category }

    // MARK: - Affected Devices Section

    @ViewBuilder
    private func affectedDevicesSection(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(isProfileFinding ? "Affected Configuration Profiles" : "Affected Devices",
                  systemImage: isProfileFinding ? "doc.badge.gearshape" : "desktopcomputer")
                .font(.subheadline.weight(.semibold))

            if count == 0 {
                Label("No devices currently affected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            } else {
                let serials = finding.affectedDeviceSerials?.filter { !$0.isEmpty } ?? []
                let names   = finding.affectedDeviceNames?.filter  { !$0.isEmpty } ?? []
                let identifiers = serials.isEmpty ? names : serials
                let useSerials  = !serials.isEmpty

                if identifiers.isEmpty {
                    Text("\(count) device(s) affected — detailed list not available from this endpoint.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    let capped   = Array(identifiers.prefix(50))
                    let overflow = identifiers.count - capped.count

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(capped, id: \.self) { identifier in
                            HStack {
                                Text(identifier)
                                    .font(.callout.monospaced())
                                    .foregroundStyle(.primary)
                                Spacer()
                                if useSerials, let url = jamfURL(for: identifier) {
                                    Link("Open in Jamf Pro", destination: url)
                                        .font(.caption.weight(.medium))
                                }
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                        }

                        if overflow > 0 {
                            Text("…and \(overflow) more")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                        }
                    }
                }
            }
        }
    }

    private func jamfURL(for serial: String) -> URL? {
        guard let base = env.currentServerURL else { return nil }
        let root = base.hasSuffix("/") ? String(base.dropLast()) : base
        return URL(string: "\(root)/computers.html?searchType=SERIAL_NUMBER&query=\(serial)")
    }
}

// MARK: - Severity Chip

private struct AuditSeverityChip: View {
    let severity: AuditSeverity
    let count: Int
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: severity.icon)
                    .font(.caption.weight(.semibold))
                Text("\(count)")
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                Text(severity.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                selected
                    ? severity.color.opacity(0.15)
                    : Color.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? severity.color : Color.clear, lineWidth: 1)
            )
            .foregroundStyle(severity.color)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(severity.label), \(count) finding\(count == 1 ? "" : "s")")
        .accessibilityHint(selected ? "Tap to clear filter" : "Tap to filter by \(severity.label)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
