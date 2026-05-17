import SwiftUI

struct ComplianceBenchmarksView: View {
    @Bindable var vm: PlatformViewModel
    @State private var showResults = false

    var body: some View {
        Group {
            switch vm.complianceBenchmarksState {
            case .idle, .loading:
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading compliance benchmarks…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let error):
                if PlatformViewModel.isPlatformAuthError(error) {
                    PlatformAuthRequiredView()
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
                HSplitView {
                    benchmarkList(benchmarks)
                        .frame(minWidth: 200, idealWidth: 240, maxWidth: 320)
                    benchmarkDetail
                        .frame(minWidth: 300, maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Compliance Benchmarks")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await vm.loadComplianceBenchmarks(force: true) } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(vm.complianceBenchmarksState.isLoading)
            }
        }
        .task { await vm.loadComplianceBenchmarks() }
    }

    private func benchmarkList(_ benchmarks: [JamfComplianceBenchmark]) -> some View {
        Group {
            if benchmarks.isEmpty {
                ContentUnavailableView("No Benchmarks", systemImage: "checkmark.shield", description: Text("No compliance benchmarks found in this tenant."))
            } else {
                List(selection: $vm.selectedBenchmarkID) {
                    ForEach(benchmarks, id: \.id) { b in
                        Text(b.name).tag(b.id)
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .onChange(of: vm.selectedBenchmarkID, initial: false) { _, id in
            guard let id else { return }
            showResults = false
            Task { await vm.loadBenchmarkDetail(name: id) }
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
        case .loaded(let json):
            BenchmarkDetailView(json: json, showResults: $showResults, vm: vm)
        }
    }
}

// MARK: - Benchmark JSON Models

private struct BenchmarkDetail: Decodable {
    let id: String?
    let name: String?
    let description: String?
    let version: String?
    let framework: String?
    let status: String?
    let controls: [BenchmarkControl]?
    let rules: [BenchmarkRule]?
}

private struct BenchmarkControl: Decodable {
    let id: String?
    let name: String?
    let description: String?
    let severity: String?
    let status: String?
}

private struct BenchmarkRule: Decodable {
    let id: String?
    let name: String?
    let severity: String?
    let status: String?
}

// MARK: - Benchmark Decoder

private func makeBenchmarkDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .custom { dec in
        let container = try dec.singleValueContainer()
        let string = try container.decode(String.self)
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFrac.date(from: string) { return date }
        let noFrac = ISO8601DateFormatter()
        noFrac.formatOptions = [.withInternetDateTime]
        if let date = noFrac.date(from: string) { return date }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot parse date: \(string)")
    }
    return decoder
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
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(badgeColor, in: Capsule())
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
    let json: String
    @Binding var showResults: Bool
    var vm: PlatformViewModel

    private var detail: BenchmarkDetail? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? makeBenchmarkDecoder().decode(BenchmarkDetail.self, from: data)
    }

    var body: some View {
        if let detail {
            BenchmarkStructuredView(detail: detail, showResults: $showResults, vm: vm)
        } else {
            VStack(spacing: 0) {
                resultsToggleBar
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(json)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if showResults {
                            Divider()
                            BenchmarkResultsSection(vm: vm)
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private var resultsToggleBar: some View {
        HStack {
            Spacer()
            Button(showResults ? "Hide Results" : "Load Compliance Results") {
                showResults.toggle()
                if showResults, let id = vm.selectedBenchmarkID {
                    Task { await vm.loadBenchmarkResults(name: id) }
                }
            }
            .buttonStyle(.bordered)
            .padding()
        }
    }
}

// MARK: - Benchmark Structured View

private struct BenchmarkStructuredView: View {
    let detail: BenchmarkDetail
    @Binding var showResults: Bool
    var vm: PlatformViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(showResults ? "Hide Results" : "Load Compliance Results") {
                    showResults.toggle()
                    if showResults, let id = vm.selectedBenchmarkID {
                        Task { await vm.loadBenchmarkResults(name: id) }
                    }
                }
                .buttonStyle(.bordered)
                .padding()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerSection
                    detailsSection
                    if let controls = detail.controls, !controls.isEmpty {
                        controlsSection(controls)
                    } else if let rules = detail.rules, !rules.isEmpty {
                        rulesSection(rules)
                    }
                    if showResults {
                        Divider()
                        BenchmarkResultsSection(vm: vm)
                            .padding(.top, 4)
                    }
                }
                .padding(20)
            }
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
                if let framework = detail.framework {
                    BenchmarkInfoRow(label: "Framework", value: framework)
                } else {
                    BenchmarkInfoRow(label: "Framework", value: "—")
                }
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func controlsSection(_ controls: [BenchmarkControl]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DashSectionHeader("Controls (\(controls.count))", systemImage: "list.bullet.clipboard")
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(controls.enumerated()), id: \.offset) { index, control in
                    if index > 0 { Divider() }
                    BenchmarkControlRow(control: control)
                }
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func rulesSection(_ rules: [BenchmarkRule]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DashSectionHeader("Rules (\(rules.count))", systemImage: "list.bullet.clipboard")
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(rules.enumerated()), id: \.offset) { index, rule in
                    if index > 0 { Divider() }
                    BenchmarkRuleRow(rule: rule)
                }
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

// MARK: - Control / Rule Rows

private struct BenchmarkControlRow: View {
    let control: BenchmarkControl

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(control.name ?? control.id ?? "Unknown")
                    .font(.caption.weight(.semibold))
                Spacer()
                if let severity = control.severity {
                    severityBadge(severity)
                }
                if let status = control.status {
                    BenchmarkStatusBadge(status: status)
                }
            }
            if let description = control.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func severityBadge(_ severity: String) -> some View {
        let color: Color = {
            switch severity.uppercased() {
            case "HIGH", "CRITICAL": return .red
            case "MEDIUM": return .orange
            case "LOW": return .yellow
            default: return .secondary
            }
        }()
        return Text(severity)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.1), in: Capsule())
    }
}

private struct BenchmarkRuleRow: View {
    let rule: BenchmarkRule

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(rule.name ?? rule.id ?? "Unknown")
                .font(.caption.weight(.semibold))
            Spacer()
            if let severity = rule.severity {
                severityBadge(severity)
            }
            if let status = rule.status {
                BenchmarkStatusBadge(status: status)
            }
        }
    }

    private func severityBadge(_ severity: String) -> some View {
        let color: Color = {
            switch severity.uppercased() {
            case "HIGH", "CRITICAL": return .red
            case "MEDIUM": return .orange
            case "LOW": return .yellow
            default: return .secondary
            }
        }()
        return Text(severity)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.1), in: Capsule())
    }
}

// MARK: - Results Section

private struct BenchmarkResultsSection: View {
    var vm: PlatformViewModel

    var body: some View {
        switch vm.benchmarkResultsState {
        case .idle:
            EmptyView()
        case .loading:
            HStack { ProgressView(); Text("Loading results…").foregroundStyle(.secondary) }
        case .failed(let e):
            Text(e).foregroundStyle(.red).font(.caption)
        case .loaded(let json):
            VStack(alignment: .leading, spacing: 8) {
                DashSectionHeader("Compliance Results", systemImage: "checkmark.shield")
                Text(json)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

// MARK: - Platform Auth Required View

private struct PlatformAuthRequiredView: View {
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

                    Text("Compliance Benchmarks require a Jamf platform profile with platform gateway authentication.")
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
