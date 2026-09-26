import SwiftUI

struct ComplianceBenchmarksView: View {
    // @Bindable required: provides $vm.selectedBenchmarkID binding for List(selection:)
    @Bindable var vm: PlatformViewModel
    @State private var refreshTask: Task<Void, Never>? = nil

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        if SidebarItem.platformFeaturesAvailable {
            content
        } else {
            PlatformAPIUnavailableView(featureName: "Compliance Benchmarks", systemImage: "checkmark.shield",
                                       usesPlatformAPI: env.activeProfileUsesPlatformAPI)
        }
    }

    private var content: some View {
        Group {
            switch vm.complianceBenchmarksState {
            case .idle:
                ContentUnavailableView("Compliance Benchmarks", systemImage: "checkmark.shield")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loading:
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading compliance benchmarks…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let error):
                if PlatformViewModel.isPlatformAuthError(error) {
                    PlatformAuthRequiredView(featureName: "Compliance Benchmarks")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle").font(.system(size: 36)).foregroundStyle(.orange)
                        Text("Failed to load benchmarks").font(.headline)
                        Text(error).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 300)
                        Button("Retry") { Task { await vm.loadComplianceBenchmarks(force: true) } }.buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .loaded(let benchmarks):
                HStack(spacing: 0) {
                    benchmarkList(benchmarks)
                        .frame(width: 240)
                    Divider()
                    benchmarkDetail
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Compliance Benchmarks")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    refreshTask?.cancel()
                    refreshTask = Task { await vm.loadComplianceBenchmarks(force: true) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(vm.complianceBenchmarksState.isLoading)
            }
        }
        .task { await vm.loadComplianceBenchmarks() }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func benchmarkList(_ benchmarks: [JamfComplianceBenchmark]) -> some View {
        if benchmarks.isEmpty {
            ContentUnavailableView("No Benchmarks", systemImage: "checkmark.shield", description: Text("No compliance benchmarks found in this tenant."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: $vm.selectedBenchmarkID) {
                ForEach(benchmarks, id: \.id) { b in
                    Text(b.name).tag(b.id)
                }
            }
            .listStyle(.sidebar)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: vm.selectedBenchmarkID, initial: false) { _, id in
                guard let id else { return }
                Task { await vm.loadBenchmarkDetail(name: id) }
            }
        }
    }

    @ViewBuilder
    private var benchmarkDetail: some View {
        switch vm.benchmarkDetailState {
        case .idle:
            ContentUnavailableView("Select a Benchmark", systemImage: "checkmark.shield")
        case .loading:
            VStack { ProgressView(); Text("Loading detail…").foregroundStyle(.secondary) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let e):
            VStack { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange); Text(e).font(.caption) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let result):
            BenchmarkDetailView(result: result)
        }
    }
}

// MARK: - Status Badge

private struct BenchmarkStatusBadge: View {
    let status: String

    private var badgeColor: Color {
        switch status.uppercased() {
        case "ACTIVE", "PASS", "ENABLED": return .green
        case "INACTIVE", "FAIL", "DISABLED": return .red
        default: return .orange
        }
    }

    var body: some View {
        Text(status)
            .font(.caption.weight(.semibold))
            .foregroundStyle(badgeColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(badgeColor.opacity(0.15), in: Capsule())
            .accessibilityLabel("Status: \(status)")
    }
}

// MARK: - Benchmark Info Row

private struct BenchmarkInfoRow: View {
    let label: String
    let value: String
    var selectable = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            if selectable {
                Text(value)
                    .font(.subheadline)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(value)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Benchmark Detail View

private struct BenchmarkDetailView: View {
    let result: BenchmarkDetailResult

    var body: some View {
        if let detail = result.detail {
            BenchmarkStructuredView(detail: detail)
        } else {
            ScrollView {
                Text(result.rawJSON)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
    }
}

// MARK: - Benchmark Structured View

private struct BenchmarkStructuredView: View {
    let detail: BenchmarkDetail

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                detailsSection
                if let scope = detail.scope { scopeSection(scope) }
                if let controls = detail.controls, !controls.isEmpty {
                    controlsSection(controls)
                } else if let rules = detail.rules, !rules.isEmpty {
                    rulesSection(rules)
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(detail.name ?? "Unnamed Benchmark")
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let status = detail.status {
                    BenchmarkStatusBadge(status: status)
                }
                Spacer()
            }
            if let description = detail.description, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            DashSectionHeader("Details", systemImage: "info.circle")
            VStack(alignment: .leading, spacing: 8) {
                if let id = detail.id {
                    BenchmarkInfoRow(label: "ID", value: id, selectable: true)
                    Divider()
                }
                if let version = detail.version {
                    BenchmarkInfoRow(label: "Version", value: version)
                    Divider()
                }
                BenchmarkInfoRow(label: "Framework", value: detail.framework ?? "—")
                // Rule / control summary
                let ruleCount    = detail.rules?.count    ?? detail.controls?.count ?? 0
                let enabledCount = (detail.rules?.filter(\.isEnabled).count)
                                ?? (detail.controls?.filter(\.isEnabled).count)
                                ?? 0
                if ruleCount > 0 {
                    Divider()
                    HStack(spacing: 0) {
                        Text("Rules")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .frame(width: 110, alignment: .leading)
                        HStack(spacing: 10) {
                            Label("\(enabledCount) active", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green).font(.caption.weight(.medium))
                            Label("\(ruleCount - enabledCount) inactive", systemImage: "minus.circle")
                                .foregroundStyle(.secondary).font(.caption)
                        }
                    }
                }
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func scopeSection(_ scope: BenchmarkScope) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DashSectionHeader("Applied To", systemImage: "scope")
            VStack(alignment: .leading, spacing: 8) {
                let groups     = scope.deviceGroups ?? []
                let devices    = scope.devices      ?? []
                let users      = scope.users        ?? []
                let userGroups = scope.userGroups   ?? []
                if groups.isEmpty && devices.isEmpty && users.isEmpty && userGroups.isEmpty {
                    Text("No scope assigned")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    let rows: [(label: String, names: [String])] = [
                        ("Device Groups", groups),
                        ("Devices",       devices),
                        ("Users",         users),
                        ("User Groups",   userGroups),
                    ].filter { !$0.names.isEmpty }

                    ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                        if idx > 0 { Divider() }
                        scopeNameList(label: row.label, names: row.names)
                    }
                }
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func scopeNameList(label: String, names: [String]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(label)
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(names, id: \.self) { Text($0).font(.subheadline).textSelection(.enabled) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func controlsSection(_ controls: [BenchmarkControl]) -> some View {
        let enabled  = controls.filter  { $0.isEnabled }
        let disabled = controls.filter  { !$0.isEnabled }
        return VStack(alignment: .leading, spacing: 10) {
            DashSectionHeader("Controls (\(controls.count))", systemImage: "list.bullet.clipboard")
            if !enabled.isEmpty {
                ruleGroup(title: "Active", systemImage: "checkmark.circle.fill", color: .green) {
                    ForEach(Array(enabled.enumerated()), id: \.element) { idx, c in
                        if idx > 0 { Divider() }
                        BenchmarkControlRow(control: c)
                    }
                }
            }
            if !disabled.isEmpty {
                ruleGroup(title: "Inactive", systemImage: "minus.circle", color: .secondary) {
                    ForEach(Array(disabled.enumerated()), id: \.element) { idx, c in
                        if idx > 0 { Divider() }
                        BenchmarkControlRow(control: c)
                    }
                }
            }
        }
    }

    private func rulesSection(_ rules: [BenchmarkRule]) -> some View {
        let enabled  = rules.filter  { $0.isEnabled }
        let disabled = rules.filter  { !$0.isEnabled }
        return VStack(alignment: .leading, spacing: 10) {
            DashSectionHeader("Rules (\(rules.count))", systemImage: "list.bullet.clipboard")
            if !enabled.isEmpty {
                ruleGroup(title: "Active (\(enabled.count))", systemImage: "checkmark.circle.fill", color: .green) {
                    ForEach(Array(enabled.enumerated()), id: \.element) { idx, r in
                        if idx > 0 { Divider() }
                        BenchmarkRuleRow(rule: r)
                    }
                }
            }
            if !disabled.isEmpty {
                ruleGroup(title: "Inactive (\(disabled.count))", systemImage: "minus.circle", color: .secondary) {
                    ForEach(Array(disabled.enumerated()), id: \.element) { idx, r in
                        if idx > 0 { Divider() }
                        BenchmarkRuleRow(rule: r)
                    }
                }
            }
        }
    }

    private func ruleGroup<Content: View>(
        title: String,
        systemImage: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

// MARK: - Control / Rule Rows

private struct BenchmarkControlRow: View {
    let control: BenchmarkControl

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: control.isEnabled ? "checkmark.circle.fill" : "minus.circle")
                    .foregroundStyle(control.isEnabled ? .green : .secondary)
                    .font(.caption)
                Text(control.name ?? control.id ?? "Unknown")
                    .font(.caption.weight(.semibold))
                Spacer()
                if let severity = control.severity { severityBadge(severity) }
            }
            if let id = control.id {
                Text(id)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            if let description = control.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let rem = control.remediation, !rem.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remediation")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(rem)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 5))
            }
        }
    }

    private func severityBadge(_ severity: String) -> some View {
        let color: Color = severityColor(severity)
        return Text(severity)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(color.opacity(0.1), in: Capsule())
    }
}

private struct BenchmarkRuleRow: View {
    let rule: BenchmarkRule
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Primary row — always visible
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: rule.isEnabled ? "checkmark.circle.fill" : "minus.circle")
                    .foregroundStyle(rule.isEnabled ? .green : .secondary)
                    .font(.caption)
                VStack(alignment: .leading, spacing: 1) {
                    Text(rule.displayName ?? rule.id ?? "Unknown")
                        .font(.caption.weight(.semibold))
                    if let id = rule.id {
                        Text(id)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                    }
                }
                Spacer()
                if let severity = rule.severity { severityBadge(severity) }
                if rule.displayDescription != nil || rule.displayRemediation != nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                    } label: {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Expanded detail
            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    if let desc = rule.displayDescription, !desc.isEmpty {
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let rem = rule.displayRemediation, !rem.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Remediation")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(rem)
                                .font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 5))
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func severityBadge(_ severity: String) -> some View {
        let color: Color = severityColor(severity)
        return Text(severity)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(color.opacity(0.1), in: Capsule())
    }
}

private func severityColor(_ severity: String) -> Color {
    switch severity.uppercased() {
    case "HIGH", "CRITICAL": return .red
    case "MEDIUM":           return .orange
    case "LOW":              return .yellow
    default:                 return .secondary
    }
}
