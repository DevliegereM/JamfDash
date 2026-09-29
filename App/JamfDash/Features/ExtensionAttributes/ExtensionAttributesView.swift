import SwiftUI

// MARK: - Extension Attributes

/// Computer and mobile device extension attributes and, after mapping, every smart group,
/// advanced search, policy, configuration profile, restricted software entry and patch
/// policy that depends on each one.
struct ExtensionAttributesView: View {
    @Bindable var vm: EADependencyViewModel
    @State private var showInspector = true

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if !vm.failures.isEmpty { failureBanner; Divider() }
            AsyncContentView(state: vm.attributes(vm.kind),
                             retry: { await vm.loadAttributes(force: true) }) { attributes in
                table(attributes)
            }
        }
        .navigationTitle("Extension Attributes")
        .searchable(text: $vm.searchText, placement: .toolbar, prompt: "Search attributes")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("Show", selection: $vm.filter) {
                    ForEach(EADependencyViewModel.UsageFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                .disabled(vm.graph == nil)
                .help(vm.graph == nil ? "Map dependencies to filter by usage" : "Filter by usage")

                Button {
                    Task { await vm.loadAttributes(force: true) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Reload the attribute list")

                Button {
                    withAnimation { showInspector.toggle() }
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                .help(showInspector ? "Hide the dependency inspector" : "Show the dependency inspector")
            }
        }
        .inspector(isPresented: $showInspector) {
            inspector
                .inspectorColumnWidth(min: 340, ideal: 420, max: 640)
        }
        .task(id: vm.kind) { await vm.loadAttributes() }
        .onChange(of: vm.kind) { _, _ in vm.selectedID = nil }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Picker("Device type", selection: $vm.kind) {
                ForEach(EAKind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 280)

            if let all = vm.attributes(vm.kind).value, let s = vm.summary(all) {
                Text("\(s.used) in use · \(s.unused) not used · \(s.attention) need attention")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            scanControl
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var scanControl: some View {
        switch vm.scanState {
        case .notScanned:
            Button {
                vm.scan()
            } label: {
                Label("Map Dependencies", systemImage: "point.3.connected.trianglepath.dotted")
            }
            .buttonStyle(.borderedProminent)
            .help("Read every smart group, advanced search, policy, profile, restricted software entry and patch policy to see where each attribute is used")
        case .scanning(let p):
            HStack(spacing: 8) {
                if p.total > 0 {
                    ProgressView(value: p.fraction).frame(width: 140)
                    Text("\(p.step.capitalizedFirst) · \(p.completed) of \(p.total)")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small)
                    Text(p.step.capitalizedFirst).font(.caption).foregroundStyle(.secondary)
                }
                Button("Stop") { vm.cancelScan() }
                    .controlSize(.small)
            }
            .accessibilityElement(children: .combine)
        case .scanned(let date):
            HStack(spacing: 8) {
                Text("Mapped \(date, format: .relative(presentation: .named))")
                    .font(.caption).foregroundStyle(.secondary)
                if let count = vm.graph?.inventory.objectCount {
                    Text("· \(count) objects").font(.caption).foregroundStyle(.secondary)
                }
                Button {
                    vm.scan()
                } label: {
                    Label("Map Again", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
            }
        }
    }

    private var failureBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("The map is incomplete", systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.orange)
            ForEach(vm.failures) { failure in
                Text(failure.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
    }

    // MARK: Table

    private func table(_ all: [ExtensionAttribute]) -> some View {
        let rows = vm.visibleAttributes(all)
        return Table(rows, selection: $vm.selectedID) {
            TableColumn("Name") { attr in
                HStack(spacing: 6) {
                    Text(attr.name)
                    if vm.report(for: attr)?.hasWarnings == true {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .imageScale(.small)
                            .accessibilityLabel("Needs attention")
                    }
                }
            }
            TableColumn("Used By") { attr in usedBy(attr) }
                .width(min: 90, ideal: 120)
            TableColumn("Input Type") { Text($0.inputType ?? "—").foregroundStyle(.secondary) }
                .width(min: 80, ideal: 110)
            TableColumn("Data Type") { Text($0.dataType ?? "—").foregroundStyle(.secondary) }
                .width(min: 60, ideal: 80)
            TableColumn("Enabled") { attr in
                if let enabled = attr.enabled {
                    Label(enabled ? "Yes" : "No", systemImage: enabled ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(enabled ? .green : .secondary)
                        .labelStyle(.titleAndIcon)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .width(min: 60, ideal: 70)
        }
        .overlay {
            if rows.isEmpty && !all.isEmpty {
                ContentUnavailableView.search(text: vm.searchText)
            } else if all.isEmpty {
                ContentUnavailableView("No Extension Attributes", systemImage: "function",
                                       description: Text("This instance has no \(vm.kind.title.lowercased()) extension attributes."))
            }
        }
        .onChange(of: vm.selectedID) { _, id in if id != nil { showInspector = true } }
    }

    @ViewBuilder
    private func usedBy(_ attr: ExtensionAttribute) -> some View {
        if let report = vm.report(for: attr) {
            if report.isUnused {
                Text("Not used").foregroundStyle(.secondary)
            } else {
                Text("\(report.dependencies.count) object\(report.dependencies.count == 1 ? "" : "s")")
                    .monospacedDigit()
            }
        } else {
            Text("—").foregroundStyle(.tertiary)
        }
    }

    // MARK: Inspector

    @ViewBuilder
    private var inspector: some View {
        if let id = vm.selectedID, let attr = vm.attributes(vm.kind).value?.first(where: { $0.id == id }) {
            EAInspector(attribute: attr, kind: vm.kind, report: vm.report(for: attr),
                        isScanning: vm.isScanning, hasIncompleteMap: !vm.failures.isEmpty) { vm.scan() }
                .id(attr.id)
        } else {
            ContentUnavailableView("No Attribute Selected", systemImage: "function",
                                   description: Text("Select an extension attribute to see its definition and where it's used."))
        }
    }
}

// MARK: - Inspector

private struct EAInspector: View {
    let attribute: ExtensionAttribute
    let kind: EAKind
    let report: EADependencyReport?
    let isScanning: Bool
    let hasIncompleteMap: Bool
    let onScan: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if let report {
                    impact(report)
                    if !report.findings.isEmpty { findings(report.findings) }
                    dependencies(report)
                } else {
                    notMapped
                }
                definition
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(attribute.name).font(.title3.bold()).textSelection(.enabled)
            HStack(spacing: 6) {
                Text("\(kind.singular) · ID \(attribute.id)")
                if let enabled = attribute.enabled {
                    Text("·")
                    Label(enabled ? "Enabled" : "Disabled",
                          systemImage: enabled ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(enabled ? .green : .red)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: Impact

    private func impact(_ report: EADependencyReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Impact")
            if report.isUnused {
                Text("Nothing depends on this attribute.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text("\(report.dependencies.count) object\(report.dependencies.count == 1 ? "" : "s") depend on it, \(report.directCount) directly.")
                    .font(.callout)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(kind.objectTypes) { type in
                    let n = report.dependencies(of: type).count
                    HStack(spacing: 6) {
                        Image(systemName: type.systemImage).frame(width: 16)
                        Text(type.title).lineLimit(2).minimumScaleFactor(0.9)
                        Spacer(minLength: 4)
                        Text("\(n)").monospacedDigit().bold()
                    }
                    .font(.caption)
                    .foregroundStyle(n == 0 ? .secondary : .primary)
                    .padding(8)
                    .background(n == 0 ? Color.primary.opacity(0.04) : Color.accentColor.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 6))
                    .accessibilityElement(children: .combine)
                }
            }
            if hasIncompleteMap {
                Label("Some objects couldn't be read, so there may be more.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    // MARK: Findings

    private func findings(_ findings: [EAFinding]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Findings")
            ForEach(findings.sorted { $0.severity > $1.severity }) { finding in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: finding.severity == .warning ? "exclamationmark.triangle.fill" : "info.circle.fill")
                        .foregroundStyle(finding.severity == .warning ? .orange : .blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(finding.title).font(.callout.weight(.semibold))
                        Text(finding.detail).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background((finding.severity == .warning ? Color.orange : Color.blue).opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 6))
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: Dependencies

    private func dependencies(_ report: EADependencyReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !report.isUnused { sectionTitle("Dependencies") }
            ForEach(kind.objectTypes) { type in
                let items = report.dependencies(of: type)
                if !items.isEmpty {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(items) { DependencyRow(dependency: $0) }
                        }
                        .padding(.top, 6)
                    } label: {
                        Label("\(type.title) (\(items.count))", systemImage: type.systemImage)
                            .font(.callout.weight(.medium))
                    }
                }
            }
        }
    }

    private var notMapped: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Dependencies")
            Text("Map dependencies to see which smart groups, advanced searches, policies, configuration profiles, restricted software and patch policies use this attribute.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Map Dependencies", action: onScan)
                .disabled(isScanning)
        }
    }

    // MARK: Definition

    private var definition: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Definition")
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 6) {
                row("Data Type", attribute.dataType)
                row("Input Type", attribute.inputType)
                row("Inventory Display", attribute.inventoryDisplayType)
                if !attribute.popupMenuChoices.isEmpty {
                    row("Menu Choices", attribute.popupMenuChoices.joined(separator: ", "))
                }
            }
            .font(.callout)
            if let desc = attribute.description, !desc.isEmpty {
                Text(desc).font(.callout).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let script = attribute.scriptContents, !script.isEmpty {
                DisclosureGroup("Script") {
                    ScrollView([.vertical, .horizontal]) {
                        Text(script)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 300)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                }
                .font(.callout)
            }
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            GridRow {
                Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                Text(value).textSelection(.enabled)
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
    }
}

// MARK: - Dependency row

private struct DependencyRow: View {
    let dependency: EADependency

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(dependency.object.name).font(.callout).textSelection(.enabled)
                Text(dependency.isDirect ? "Direct" : "Through a group")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background((dependency.isDirect ? Color.accentColor : Color.secondary).opacity(0.15), in: Capsule())
                    .foregroundStyle(dependency.isDirect ? Color.accentColor : Color.secondary)
            }
            ForEach(Array(dependency.reasons.enumerated()), id: \.offset) { _, reason in
                Label {
                    Text(reason.summary).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: icon(for: reason))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 4)
        .accessibilityElement(children: .combine)
    }

    private func icon(for reason: DependencyReason) -> String {
        switch reason {
        case .criterion:        return "line.3.horizontal.decrease"
        case .displayField:     return "tablecells"
        case .memberOf:         return "person.3"
        case .scope(_, let excluded, _): return excluded ? "minus.circle" : "scope"
        case .payloadVariable:  return "curlybraces"
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
