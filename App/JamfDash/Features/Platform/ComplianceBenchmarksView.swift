import SwiftUI

struct ComplianceBenchmarksView: View {
    // @Bindable required: provides $vm.selectedBenchmarkID binding for List(selection:)
    @Bindable var vm: PlatformViewModel
    @State private var refreshTask: Task<Void, Never>? = nil

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        switch env.access(for: .complianceBenchmarks) {
        case .available, .checking:
            content
        case let access:
            PlatformAPIUnavailableView(featureName: "Compliance Benchmarks", systemImage: "checkmark.shield",
                                       permission: "Compliance → Compliance Benchmarks: Read", access: access)
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
                Task { await vm.loadBenchmarkResults(id: id) }
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
            BenchmarkDetailView(result: result) {
                if let id = vm.selectedBenchmarkID {
                    BenchmarkResultsSection(vm: vm, benchmarkID: id) { env.showInDeviceLookup($0) }
                }
            }
        }
    }
}

// MARK: - Status Badge

private struct BenchmarkStatusBadge: View {
    let status: String

    private var badgeColor: Color {
        switch status.uppercased() {
        case "ACTIVE", "PASS", "ENABLED", "SYNCED": return .green
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

private struct BenchmarkDetailView<Results: View>: View {
    let result: BenchmarkDetailResult
    @ViewBuilder let results: () -> Results

    var body: some View {
        if let detail = result.detail {
            BenchmarkStructuredView(detail: detail, results: results)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    results()
                    Text(result.rawJSON)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
        }
    }
}

// MARK: - Benchmark Structured View

private struct BenchmarkStructuredView<Results: View>: View {
    let detail: BenchmarkDetail
    let results: () -> Results

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                results()
                detailsSection
                if let scope = detail.resolvedScope { scopeSection(scope) }
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
                Text(detail.displayName ?? "Unnamed Benchmark")
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let status = detail.displayStatus {
                    BenchmarkStatusBadge(status: status)
                }
                if detail.updateAvailable == true {
                    BenchmarkStatusBadge(status: "Update available")
                        .help("A newer version of this benchmark's baseline is available in Jamf.")
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
                // Each row after the first starts with a divider.
                let infoRows: [(String, String, Bool)] = [
                    detail.id.map { ("ID", $0, true) },
                    detail.version.map { ("Version", $0, false) },
                    detail.framework.map { ("Framework", $0, false) },
                ].compactMap { $0 }
                ForEach(Array(infoRows.enumerated()), id: \.offset) { idx, row in
                    if idx > 0 { Divider() }
                    BenchmarkInfoRow(label: row.0, value: row.1, selectable: row.2)
                }
                // Rule / control summary
                let ruleCount    = detail.rules?.count    ?? detail.controls?.count ?? 0
                let enabledCount = (detail.rules?.filter(\.isEnabled).count)
                                ?? (detail.controls?.filter(\.isEnabled).count)
                                ?? 0
                if ruleCount > 0 {
                    if !infoRows.isEmpty { Divider() }
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

// MARK: - Results

/// Compliance results from the Platform benchmark reports: overall percentage, the devices
/// failing most rules, and rules with failures (each expandable to its failing devices).
private struct BenchmarkResultsSection: View {
    @Bindable var vm: PlatformViewModel
    let benchmarkID: String
    let onLookUp: (String) -> Void
    @State private var showAllRules = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DashSectionHeader("Results", systemImage: "chart.bar.xaxis")
            switch vm.benchmarkResultsState {
            case .idle, .loading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading compliance results…").font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            case .failed(let error):
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            case .loaded(let results):
                summaryCard(results)
                failingDevicesCard
                rulesCard(results.rules)
            }
        }
    }

    // MARK: Summary

    private func summaryCard(_ results: BenchmarkResults) -> some View {
        let failing = results.rules.filter { $0.failedCount > 0 }.count
        let devices = results.rules.compactMap(\.numberOfDevices).max()
        // Devices that returned a pass/fail for at least one rule (a lower bound: the report
        // only has per-rule counts).
        let reporting = results.rules.map { ($0.passed ?? 0) + ($0.failed ?? 0) }.max() ?? 0
        return HStack(spacing: 20) {
            if let pct = results.compliancePercentage {
                Gauge(value: min(max(pct, 0), 100), in: 0...100) {
                    EmptyView()
                } currentValueLabel: {
                    Text(pct.formatted(.number.precision(.fractionLength(0...1))) + "%")
                        .font(.caption.weight(.semibold))
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(BenchmarkResultsFormat.color(forPercentage: pct))
                .accessibilityLabel("Compliance \(pct, specifier: "%.1f") percent")
                .help(BenchmarkResultsFormat.scoreExplanation)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("Fleet compliance").font(.subheadline.weight(.semibold))
                    Image(systemName: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                        .help(BenchmarkResultsFormat.scoreExplanation)
                        .accessibilityLabel(BenchmarkResultsFormat.scoreExplanation)
                }
                Text("\(failing) of \(results.rules.count) rules have failing devices")
                    .font(.caption).foregroundStyle(.secondary)
                if let devices {
                    if reporting < devices {
                        Label("Only \(reporting) of \(devices) devices in scope have reported results; the others count as unknown and pull the score down.",
                              systemImage: "exclamationmark.circle")
                            .font(.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("\(devices) device\(devices == 1 ? "" : "s") in scope")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Devices

    @ViewBuilder
    private var failingDevicesCard: some View {
        switch vm.failingDevicesState {
        case .idle:
            EmptyView()
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Finding devices with failing rules…").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        case .failed(let error):
            Label("Devices unavailable: \(error)", systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        case .loaded(let devices) where devices.isEmpty:
            Label("No devices are failing rules.", systemImage: "checkmark.seal.fill")
                .font(.subheadline).foregroundStyle(.green)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        case .loaded(let devices):
            VStack(alignment: .leading, spacing: 8) {
                Label("Devices with failing rules (\(devices.count))", systemImage: "desktopcomputer.trianglebadge.exclamationmark")
                    .font(.caption.weight(.semibold)).foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(devices.prefix(25).enumerated()), id: \.element) { idx, d in
                        if idx > 0 { Divider() }
                        HStack {
                            DeviceLinkButton(name: d.device, onLookUp: onLookUp)
                            Spacer()
                            if let failed = d.rulesFailed {
                                Text("\(failed) failing rule\(failed == 1 ? "" : "s")")
                                    .font(.caption).foregroundStyle(.red).monospacedDigit()
                            }
                        }
                    }
                    if devices.count > 25 {
                        Text("… and \(devices.count - 25) more").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: Rules

    private func rulesCard(_ rules: [BenchmarkRuleStat]) -> some View {
        let failing = rules.filter { $0.failedCount > 0 }
            .sorted { $0.failedCount > $1.failedCount }
        let shown = showAllRules ? rules : failing
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(showAllRules ? "All rules (\(rules.count))" : "Rules with failures (\(failing.count))",
                      systemImage: "list.bullet.clipboard")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(showAllRules ? Color.secondary : Color.orange)
                Spacer()
                if failing.count != rules.count {
                    Toggle("Show all rules", isOn: $showAllRules)
                        .toggleStyle(.switch).controlSize(.mini)
                        .font(.caption)
                }
            }
            if shown.isEmpty {
                Text("No rule has failing devices.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            } else {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(shown.enumerated()), id: \.element) { idx, rule in
                        if idx > 0 { Divider() }
                        RuleResultRow(rule: rule,
                                      devices: vm.ruleDevices[rule.ruleId],
                                      loadDevices: { Task { await vm.loadRuleDevices(benchmarkID: benchmarkID, ruleID: rule.ruleId) } },
                                      onLookUp: onLookUp)
                    }
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

private struct RuleResultRow: View {
    let rule: BenchmarkRuleStat
    let devices: LoadState<[BenchmarkRuleDevice]>?
    let loadDevices: () -> Void
    let onLookUp: (String) -> Void
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                if expanded, rule.failedCount > 0 { loadDevices() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption2).foregroundStyle(.secondary)
                        .frame(width: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            if let n = rule.ruleNumber {
                                Text(n).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            Text(rule.ruleTitle ?? rule.ruleId)
                                .font(.caption.weight(.semibold))
                                .multilineTextAlignment(.leading)
                        }
                        ResultCountsBar(passed: rule.passed ?? 0, failed: rule.failed ?? 0, unknown: rule.unknown ?? 0)
                    }
                    Spacer(minLength: 8)
                    if rule.failedCount > 0 {
                        Text("\(rule.failedCount) failed")
                            .font(.caption.weight(.medium)).foregroundStyle(.red).monospacedDigit()
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(expanded ? "Collapses the rule" : "Shows the rule's details and failing devices")

            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(rule.ruleId)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                    if let discussion = rule.discussion?.trimmingCharacters(in: .whitespacesAndNewlines), !discussion.isEmpty {
                        Text(discussion.replacingOccurrences(of: "_MUST_", with: "must"))
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if rule.failedCount > 0 { devicesList }
                }
                .padding(.leading, 18)
                .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var devicesList: some View {
        switch devices {
        case nil, .idle?, .loading?:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Loading failing devices…").font(.caption).foregroundStyle(.secondary)
            }
        case .failed(let error)?:
            Text("Devices unavailable: \(error)").font(.caption).foregroundStyle(.secondary)
        case .loaded(let list)?:
            if list.isEmpty {
                Text("No failing devices returned.").font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Failing devices").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(list) { d in
                        DeviceLinkButton(name: d.name, onLookUp: onLookUp)
                    }
                }
            }
        }
    }
}

/// Passed / failed / unknown as a thin stacked bar.
private struct ResultCountsBar: View {
    let passed: Int
    let failed: Int
    let unknown: Int

    var body: some View {
        let total = max(passed + failed + unknown, 1)
        HStack(spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Color.green.frame(width: geo.size.width * CGFloat(passed) / CGFloat(total))
                    Color.red.frame(width: geo.size.width * CGFloat(failed) / CGFloat(total))
                    Color.secondary.opacity(0.3).frame(width: geo.size.width * CGFloat(unknown) / CGFloat(total))
                }
            }
            .frame(width: 120, height: 5)
            .clipShape(Capsule())
            Text("\(passed) passed · \(failed) failed · \(unknown) unknown")
                .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(passed) passed, \(failed) failed, \(unknown) unknown")
    }
}

/// A device name that opens Device Lookup.
private struct DeviceLinkButton: View {
    let name: String
    let onLookUp: (String) -> Void

    var body: some View {
        Button { onLookUp(name) } label: {
            Label(name, systemImage: "desktopcomputer")
                .font(.caption)
        }
        .buttonStyle(.link)
        .help("Open \(name) in Device Lookup")
    }
}

enum BenchmarkResultsFormat {
    static let scoreExplanation = """
        Calculated by Jamf: each device gets a score (the share of the benchmark's rules it \
        passes), and the fleet score is the sum of those scores divided by the number of devices \
        in scope. Devices that haven't reported results score nothing, so they lower the percentage.
        """

    static func color(forPercentage pct: Double) -> Color {
        switch pct {
        case 90...: return .green
        case 60..<90: return .orange
        default: return .red
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
                    .accessibilityLabel(expanded ? "Hide details" : "Show details")
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
