import SwiftUI

// MARK: - Alerts (event feed)

struct ProtectEventsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text("Alerts Not Available via CLI")
                .font(.headline)
            Text("Triggered security alerts are only accessible through the Jamf Protect web console.\nThe jamf-cli tool does not expose an alerts list endpoint.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .navigationTitle("Protect Alerts")
    }
}

// MARK: - Overview

struct ProtectOverviewView: View {
    @Bindable var vm: ProtectViewModel
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Group {
            if env.isSyncing {
                SyncBar(
                    title: "Syncing Jamf Protect",
                    steps: env.syncStepLabels,
                    activeIndex: env.syncCompletedSteps
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                AsyncContentView(state: vm.overviewState, retry: { await vm.loadOverview(force: true) }) { _ in
                    let sections = vm.overviewSections
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 24) {
                            ForEach(sections, id: \.title) { section in
                                ProductSectionBlock(title: section.title, items: section.items)
                            }
                        }
                        .padding(20)
                    }
                }
            }
        }
        .navigationTitle("Protect Overview")
        .toolbar { refreshButton { await vm.loadOverview(force: true) } }
        .task { await vm.loadOverview() }
    }
}

// MARK: - Computers

struct ProtectComputersView: View {
    @Bindable var vm: ProtectViewModel
    @State private var searchText = ""
    @State private var selectedID: ProtectComputer.ID? = nil
    @State private var detailComputer: ProtectComputer? = nil

    var body: some View {
        AsyncContentView(state: vm.computersState, retry: { await vm.loadComputers(force: true) }) { computers in
            let filtered = searchText.isEmpty ? computers : computers.filter {
                $0.displayName.localizedCaseInsensitiveContains(searchText) ||
                ($0.serialNumber?.localizedCaseInsensitiveContains(searchText) == true) ||
                ($0.planName?.localizedCaseInsensitiveContains(searchText) == true)
            }

            if filtered.isEmpty {
                protectEmptyState(icon: "laptopcomputer",
                                  label: searchText.isEmpty ? "No computers enrolled in Protect" : "No computers match \"\(searchText)\"")
            } else {
                Table(filtered, selection: $selectedID) {
                    TableColumn("Host Name") { Text($0.displayName) }
                    TableColumn("Serial") { Text($0.serialNumber ?? "—").foregroundStyle(.secondary) }
                    TableColumn("OS Version") { Text($0.osVersion ?? "—").foregroundStyle(.secondary) }
                    TableColumn("Plan") { Text($0.planName ?? "—").foregroundStyle(.secondary) }
                    TableColumn("Status") { computer in
                        ConnectionStatusBadge(status: computer.connectionStatus)
                    }
                    TableColumn("Last Check-In") { computer in
                        Text(computer.formattedCheckinTime ?? "—").foregroundStyle(.secondary)
                    }
                }
                .onChange(of: selectedID) { _, newID in
                    guard let id = newID, let computer = filtered.first(where: { $0.id == id }) else { return }
                    detailComputer = computer
                    Task { await vm.loadComputerDetail(name: computer.displayName) }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search by hostname, serial, or plan")
        .navigationTitle("Protect Computers")
        .toolbar { refreshButton { await vm.loadComputers(force: true) } }
        .task { await vm.loadComputers() }
        .sheet(item: $detailComputer) { computer in
            ProtectComputerDetailSheet(computer: computer, vm: vm)
                .onDisappear { selectedID = nil }
        }
    }
}

// MARK: - Plans

struct ProtectPlansView: View {
    @Bindable var vm: ProtectViewModel
    @State private var selectedID: ProtectPlan.ID? = nil
    @State private var detailItem: ProtectPlan? = nil

    var body: some View {
        AsyncContentView(state: vm.plansState, retry: { await vm.loadPlans(force: true) }) { plans in
            if plans.isEmpty {
                protectEmptyState(icon: "doc.badge.gearshape", label: "No plans configured")
            } else {
                Table(plans, selection: $selectedID) {
                    TableColumn("Name") { Text($0.name) }
                    TableColumn("Action Config") { Text($0.actionConfig ?? "—").foregroundStyle(.secondary) }
                    TableColumn("Telemetry") { Text($0.telemetry ?? "—").foregroundStyle(.secondary) }
                    TableColumn("Log Level") { Text($0.logLevel ?? "—").foregroundStyle(.secondary) }
                }
                .onChange(of: selectedID) { _, newID in
                    guard let id = newID, let item = plans.first(where: { $0.id == id }) else { return }
                    detailItem = item
                }
            }
        }
        .navigationTitle("Protect Plans")
        .toolbar { refreshButton { await vm.loadPlans(force: true) } }
        .task { await vm.loadPlans() }
        .sheet(item: $detailItem) { item in
            PlanDetailSheet(item: item)
                .onDisappear { selectedID = nil }
        }
    }
}

// MARK: - Analytics

struct ProtectAlertsView: View {
    @Bindable var vm: ProtectViewModel
    @State private var selectedID: ProtectAnalytic.ID? = nil
    @State private var detailItem: ProtectAnalytic? = nil

    var body: some View {
        AsyncContentView(state: vm.analyticsState, retry: { await vm.loadAnalytics(force: true) }) { analytics in
            if analytics.isEmpty {
                protectEmptyState(icon: "waveform.path.ecg", label: "No analytics configured")
            } else {
                Table(analytics, selection: $selectedID) {
                    TableColumn("Name") { Text($0.name) }
                    TableColumn("Severity") { item in
                        SeverityBadge(severity: item.severity)
                    }
                    TableColumn("Categories") { Text($0.categories ?? "—").foregroundStyle(.secondary) }
                    TableColumn("Source") { item in
                        Text(item.jamf == true ? "Jamf" : "Custom")
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: selectedID) { _, newID in
                    guard let id = newID, let item = analytics.first(where: { $0.id == id }) else { return }
                    detailItem = item
                    Task { await vm.loadAnalyticDetail(name: item.name) }
                }
            }
        }
        .navigationTitle("Protect Analytics")
        .toolbar { refreshButton { await vm.loadAnalytics(force: true) } }
        .task { await vm.loadAnalytics() }
        .sheet(item: $detailItem) { item in
            AnalyticDetailSheet(item: item, vm: vm)
                .onDisappear { selectedID = nil }
        }
    }
}

// MARK: - Analytic Sets

struct ProtectInsightsView: View {
    @Bindable var vm: ProtectViewModel
    @State private var selectedID: ProtectAnalyticSet.ID? = nil
    @State private var detailItem: ProtectAnalyticSet? = nil

    var body: some View {
        AsyncContentView(state: vm.analyticSetsState, retry: { await vm.loadAnalyticSets(force: true) }) { sets in
            if sets.isEmpty {
                protectEmptyState(icon: "rectangle.stack", label: "No analytic sets configured")
            } else {
                Table(sets, selection: $selectedID) {
                    TableColumn("Name") { Text($0.name) }
                    TableColumn("Analytics") { item in
                        Text(item.analyticsCount.map(String.init) ?? "—")
                            .foregroundStyle(.secondary)
                    }
                    TableColumn("Types") { Text($0.types ?? "—").foregroundStyle(.secondary) }
                    TableColumn("Managed") { item in
                        Image(systemName: item.managed == true ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.managed == true ? .green : .secondary)
                    }
                }
                .onChange(of: selectedID) { _, newID in
                    guard let id = newID, let item = sets.first(where: { $0.id == id }) else { return }
                    detailItem = item
                }
            }
        }
        .navigationTitle("Protect Analytic Sets")
        .toolbar { refreshButton { await vm.loadAnalyticSets(force: true) } }
        .task { await vm.loadAnalyticSets() }
        .sheet(item: $detailItem) { item in
            AnalyticSetDetailSheet(item: item)
                .onDisappear { selectedID = nil }
        }
    }
}

// MARK: - Exception Sets

struct ProtectAuditLogsView: View {
    @Bindable var vm: ProtectViewModel
    @State private var selectedID: ProtectNamedItem.ID? = nil
    @State private var detailItem: ProtectNamedItem? = nil

    var body: some View {
        AsyncContentView(state: vm.exceptionSetsState, retry: { await vm.loadExceptionSets(force: true) }) { sets in
            if sets.isEmpty {
                protectEmptyState(icon: "shield.slash", label: "No exception sets found")
            } else {
                Table(sets, selection: $selectedID) {
                    TableColumn("Name") { Text($0.name) }
                    TableColumn("UUID") { Text($0.id).foregroundStyle(.secondary).font(.caption) }
                }
                .onChange(of: selectedID) { _, newID in
                    guard let id = newID, let item = sets.first(where: { $0.id == id }) else { return }
                    detailItem = item
                    Task { await vm.loadExceptionSetDetail(name: item.name) }
                }
            }
        }
        .navigationTitle("Protect Exception Sets")
        .toolbar { refreshButton { await vm.loadExceptionSets(force: true) } }
        .task { await vm.loadExceptionSets() }
        .sheet(item: $detailItem) { item in
            ExceptionSetDetailSheet(item: item, vm: vm)
                .onDisappear { selectedID = nil }
        }
    }
}

// MARK: - Plan detail sheet

private struct PlanDetailSheet: View {
    let item: ProtectPlan
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        DetailSheetContainer(title: item.name, subtitle: nil) {
            Group {
                if let v = item.actionConfig  { detailRow("Action Config", value: v) }
                if let v = item.telemetry     { detailRow("Telemetry", value: v) }
                if let v = item.logLevel      { detailRow("Log Level", value: v) }
                if let v = item.autoUpdate {
                    detailRow("Auto Update", value: v ? "Yes" : "No")
                }
            }
        }
    }
}

// MARK: - Analytic detail sheet

private struct AnalyticDetailSheet: View {
    let item: ProtectAnalytic
    @Bindable var vm: ProtectViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name).font(.title2).bold()
                    if let sev = item.severity {
                        SeverityBadge(severity: sev)
                    }
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            switch vm.analyticDetailState {
            case .loading:
                SyncingIndicator().frame(maxWidth: .infinity, maxHeight: .infinity)

            case .loaded(let detail):
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let v = detail.label, v != detail.name { detailRow("Label", value: v) }
                        if let v = detail.inputType              { detailRow("Input Type", value: v) }
                        if let cats = detail.categories, !cats.isEmpty {
                            detailRow("Categories", value: cats.joined(separator: ", "))
                        }
                        if let v = detail.jamf { detailRow("Source", value: v ? "Jamf Built-in" : "Custom") }
                        if let tags = detail.tags, !tags.isEmpty {
                            detailRow("Tags", value: tags.joined(separator: ", "))
                        }
                        if let actions = detail.analyticActions, !actions.isEmpty {
                            let names = actions.compactMap(\.name).joined(separator: ", ")
                            if !names.isEmpty { detailRow("Actions", value: names) }
                        }
                        if let v = detail.description, !v.isEmpty    { detailRow("Description", value: v) }
                        if let v = detail.longDescription, !v.isEmpty { detailRow("Details", value: v) }
                        if let v = detail.filter, !v.isEmpty          { detailRow("Filter", value: v) }
                        if let v = detail.remediation, !v.isEmpty     { detailRow("Remediation", value: v) }
                        if let v = detail.created { detailRow("Created", value: v) }
                        if let v = detail.updated { detailRow("Updated", value: v) }
                    }
                    .padding(20)
                }

            case .failed(let msg):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 36)).foregroundStyle(.orange)
                    Text("Could not load details").font(.headline)
                    Text(msg).font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).frame(maxWidth: 300)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding()

            case .idle:
                EmptyView()
            }
        }
        .frame(minWidth: 520, minHeight: 380)
    }
}

// MARK: - Analytic Set detail sheet

private struct AnalyticSetDetailSheet: View {
    let item: ProtectAnalyticSet
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        DetailSheetContainer(title: item.name, subtitle: item.description) {
            Group {
                if let v = item.analyticsCount { detailRow("Analytics", value: String(v)) }
                if let v = item.types          { detailRow("Types", value: v) }
                if let v = item.plans          { detailRow("Plans", value: v) }
                if let v = item.managed {
                    detailRow("Managed", value: v ? "Yes" : "No")
                }
            }
        }
    }
}

// MARK: - Exception Set detail sheet

private struct ExceptionSetDetailSheet: View {
    let item: ProtectNamedItem
    @Bindable var vm: ProtectViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.title2).bold()
                    Text(item.id)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            switch vm.exceptionSetDetailState {
            case .loading:
                SyncingIndicator().frame(maxWidth: .infinity, maxHeight: .infinity)

            case .loaded(let detail):
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let desc = detail.description, !desc.isEmpty {
                            detailRow("Description", value: desc)
                        }
                        detailRow("UUID", value: detail.id)
                    }
                    .padding(20)
                }

            case .failed(let msg):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 36)).foregroundStyle(.orange)
                    Text("Could not load details").font(.headline)
                    Text(msg).font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).frame(maxWidth: 300)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding()

            case .idle:
                EmptyView()
            }
        }
        .frame(minWidth: 440, minHeight: 280)
    }
}

// MARK: - ULF detail sheet

private struct ULFDetailSheet: View {
    let item: ProtectNamedEntry
    @Bindable var vm: ProtectViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name).font(.title2).bold()
                    if let enabled = item.enabled {
                        Text(enabled ? "Enabled" : "Disabled")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(enabled ? .green : .secondary)
                    }
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            switch vm.ulfDetailState {
            case .loading:
                SyncingIndicator().frame(maxWidth: .infinity, maxHeight: .infinity)

            case .loaded(let detail):
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let v = detail.description, !v.isEmpty { detailRow("Description", value: v) }
                        if let v = detail.filter, !v.isEmpty       { detailRow("Filter", value: v) }
                        if let tags = detail.tags, !tags.isEmpty   { detailRow("Tags", value: tags.joined(separator: ", ")) }
                        if let v = detail.created { detailRow("Created", value: v) }
                        if let v = detail.updated { detailRow("Updated", value: v) }
                        if let v = detail.uuid    { detailRow("UUID", value: v) }
                    }
                    .padding(20)
                }

            case .failed(let msg):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 36)).foregroundStyle(.orange)
                    Text("Could not load details").font(.headline)
                    Text(msg).font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).frame(maxWidth: 300)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding()

            case .idle:
                EmptyView()
            }
        }
        .frame(minWidth: 520, minHeight: 340)
    }
}

// MARK: - Computer detail sheet

private struct ProtectComputerDetailSheet: View {
    let computer: ProtectComputer
    @Bindable var vm: ProtectViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(computer.displayName).font(.title2).bold()
                    if let serial = computer.serialNumber {
                        Text(serial).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            switch vm.computerDetailState {
            case .loading:
                SyncingIndicator().frame(maxWidth: .infinity, maxHeight: .infinity)

            case .loaded(let detail):
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let v = detail.osVersion     { detailRow("OS Version", value: v) }
                        if let v = detail.modelName     { detailRow("Model", value: v) }
                        if let v = detail.arch          { detailRow("Architecture", value: v) }
                        if let v = detail.agentVersion  { detailRow("Agent Version", value: v) }
                        if let v = detail.planName      { detailRow("Plan", value: v) }
                        if let v = detail.connectionStatus { detailRow("Connection", value: v) }
                        if let v = detail.fullDiskAccess { detailRow("Full Disk Access", value: v) }
                        if let v = detail.lastConnectionIp { detailRow("Last IP", value: v) }
                        if let v = detail.signaturesVersion { detailRow("Signatures", value: String(v)) }
                        if let v = detail.webProtectionActive { detailRow("Web Protection", value: v ? "Active" : "Inactive") }
                        if let v = detail.checkinTime   { detailRow("Last Check-In", value: v) }
                    }
                    .padding(20)
                }

            case .failed(let msg):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 36)).foregroundStyle(.orange)
                    Text("Could not load details").font(.headline)
                    Text(msg).font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).frame(maxWidth: 300)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding()

            case .idle:
                EmptyView()
            }
        }
        .frame(minWidth: 440, minHeight: 320)
    }
}

// MARK: - Connection status badge

private struct ConnectionStatusBadge: View {
    let status: String?

    var body: some View {
        let s = status ?? "—"
        Text(s)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color(for: s).opacity(0.15), in: Capsule())
            .foregroundStyle(color(for: s))
    }

    private func color(for s: String) -> Color {
        switch s.lowercased() {
        case "connected":    return .green
        case "disconnected": return .secondary
        default:             return .secondary
        }
    }
}

// MARK: - Shared sheet container

private struct DetailSheetContainer<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title2).bold()
                    if let sub = subtitle {
                        Text(sub).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    content
                }
                .padding(20)
            }
        }
        .frame(minWidth: 400, minHeight: 240)
    }
}

// MARK: - Detail row helper (free function, usable in sheet body)

@ViewBuilder
private func detailRow(_ label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        Text(value)
            .textSelection(.enabled)
    }
}

// MARK: - Severity badge

private struct SeverityBadge: View {
    let severity: String?

    var body: some View {
        let s = severity ?? "—"
        Text(s)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color(for: s).opacity(0.15), in: Capsule())
            .foregroundStyle(color(for: s))
    }

    private func color(for s: String) -> Color {
        switch s.lowercased() {
        case "high":          return .red
        case "medium":        return .orange
        case "low":           return .yellow
        case "informational": return .blue
        default:              return .secondary
        }
    }
}

// MARK: - Toolbar refresh button

@MainActor @ToolbarContentBuilder
private func refreshButton(action: @escaping @MainActor () async -> Void) -> some ToolbarContent {
    ToolbarItem(placement: .primaryAction) {
        Button {
            Task { await action() }
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
        }
    }
}

// MARK: - Empty state

@ViewBuilder
private func protectEmptyState(icon: String, label: String) -> some View {
    VStack(spacing: 10) {
        Image(systemName: icon)
            .font(.system(size: 36))
            .foregroundStyle(.secondary)
        Text(label)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 300)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(40)
}

// MARK: - Removable Storage Control Sets

struct ProtectRemovableStorageView: View {
    @Bindable var vm: ProtectViewModel
    var body: some View {
        protectNamedEntryList(state: vm.removableStorageState,
                              title: "Removable Storage Control Sets",
                              icon: "externaldrive",
                              emptyLabel: "No removable storage control sets") {
            await vm.loadRemovableStorage(force: true)
        }
        .task { await vm.loadRemovableStorage() }
    }
}

// MARK: - Unified Logging Filters

struct ProtectUnifiedLoggingView: View {
    @Bindable var vm: ProtectViewModel
    @State private var selectedID: ProtectNamedEntry.ID? = nil
    @State private var detailItem: ProtectNamedEntry? = nil

    var body: some View {
        AsyncContentView(state: vm.unifiedLoggingState, retry: { await vm.loadUnifiedLogging(force: true) }) { entries in
            if entries.isEmpty {
                protectEmptyState(icon: "doc.text.magnifyingglass", label: "No unified logging filters")
            } else {
                Table(entries, selection: $selectedID) {
                    TableColumn("Name") { Text($0.name) }
                    TableColumn("Filter") { Text($0.description ?? "—").foregroundStyle(.secondary).lineLimit(1) }
                    TableColumn("Enabled") { entry in
                        if let enabled = entry.enabled {
                            Image(systemName: enabled ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(enabled ? .green : .secondary)
                        } else {
                            Text("—").foregroundStyle(.secondary)
                        }
                    }
                }
                .onChange(of: selectedID) { _, newID in
                    guard let id = newID, let item = entries.first(where: { $0.id == id }) else { return }
                    detailItem = item
                    Task { await vm.loadULFDetail(name: item.name) }
                }
            }
        }
        .navigationTitle("Unified Logging Filters")
        .toolbar { refreshButton { await vm.loadUnifiedLogging(force: true) } }
        .task { await vm.loadUnifiedLogging() }
        .sheet(item: $detailItem) { item in
            ULFDetailSheet(item: item, vm: vm)
                .onDisappear { selectedID = nil }
        }
    }
}

// MARK: - Action Configs

struct ProtectActionConfigsView: View {
    @Bindable var vm: ProtectViewModel
    var body: some View {
        protectNamedEntryList(state: vm.actionConfigsState,
                              title: "Action Configs",
                              icon: "bell.and.waveform",
                              emptyLabel: "No action configs configured") {
            await vm.loadActionConfigs(force: true)
        }
        .task { await vm.loadActionConfigs() }
    }
}

// MARK: - Telemetry Configurations

struct ProtectTelemetryView: View {
    @Bindable var vm: ProtectViewModel
    var body: some View {
        protectNamedEntryList(state: vm.telemetryState,
                              title: "Telemetry Configurations",
                              icon: "chart.xyaxis.line",
                              emptyLabel: "No telemetry configurations") {
            await vm.loadTelemetry(force: true)
        }
        .task { await vm.loadTelemetry() }
    }
}

// MARK: - Custom Prevent Lists

struct ProtectPreventListsView: View {
    @Bindable var vm: ProtectViewModel
    var body: some View {
        protectNamedEntryList(state: vm.preventListsState,
                              title: "Custom Prevent Lists",
                              icon: "hand.raised",
                              emptyLabel: "No custom prevent lists") {
            await vm.loadPreventLists(force: true)
        }
        .task { await vm.loadPreventLists() }
    }
}

// MARK: - Roles

struct ProtectRolesView: View {
    @Bindable var vm: ProtectViewModel

    var body: some View {
        AsyncContentView(state: vm.rolesState, retry: { await vm.loadRoles(force: true) }) { roles in
            if roles.isEmpty {
                protectEmptyState(icon: "person.fill.badge.plus", label: "No roles configured")
            } else {
                Table(roles) {
                    TableColumn("Name") { Text($0.name) }
                    TableColumn("Permissions") { Text($0.permissions.isEmpty ? "—" : $0.permissions).foregroundStyle(.secondary) }
                }
            }
        }
        .navigationTitle("Protect Roles")
        .toolbar { refreshButton { await vm.loadRoles(force: true) } }
        .task { await vm.loadRoles() }
    }
}

// MARK: - Users

struct ProtectUsersView: View {
    @Bindable var vm: ProtectViewModel

    var body: some View {
        AsyncContentView(state: vm.usersState, retry: { await vm.loadUsers(force: true) }) { users in
            if users.isEmpty {
                protectEmptyState(icon: "person.2", label: "No users found")
            } else {
                Table(users) {
                    TableColumn("Email") { Text($0.email) }
                    TableColumn("Role") { Text($0.role ?? "—").foregroundStyle(.secondary) }
                    TableColumn("Groups") { Text($0.groups ?? "—").foregroundStyle(.secondary) }
                }
            }
        }
        .navigationTitle("Protect Users")
        .toolbar { refreshButton { await vm.loadUsers(force: true) } }
        .task { await vm.loadUsers() }
    }
}

// MARK: - Groups

struct ProtectGroupsView: View {
    @Bindable var vm: ProtectViewModel

    var body: some View {
        AsyncContentView(state: vm.groupsState, retry: { await vm.loadGroups(force: true) }) { groups in
            if groups.isEmpty {
                protectEmptyState(icon: "person.3", label: "No groups configured")
            } else {
                Table(groups) {
                    TableColumn("Name") { Text($0.name) }
                    TableColumn("Roles") { Text($0.assignedRoles ?? "—").foregroundStyle(.secondary) }
                    TableColumn("Type") { group in
                        Text(group.accessGroup == true ? "Access Group" : "Standard")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Protect Groups")
        .toolbar { refreshButton { await vm.loadGroups(force: true) } }
        .task { await vm.loadGroups() }
    }
}

// MARK: - API Clients

struct ProtectAPIClientsView: View {
    @Bindable var vm: ProtectViewModel

    var body: some View {
        AsyncContentView(state: vm.apiClientsState, retry: { await vm.loadAPIClients(force: true) }) { clients in
            if clients.isEmpty {
                protectEmptyState(icon: "key", label: "No API clients configured")
            } else {
                Table(clients) {
                    TableColumn("Name") { Text($0.name) }
                    TableColumn("Role") { Text($0.role ?? "—").foregroundStyle(.secondary) }
                    TableColumn("Created") { Text($0.createdAt ?? "—").foregroundStyle(.secondary) }
                }
            }
        }
        .navigationTitle("Protect API Clients")
        .toolbar { refreshButton { await vm.loadAPIClients(force: true) } }
        .task { await vm.loadAPIClients() }
    }
}

// MARK: - Config-as-Code Export Sheet

struct ExportSheetView: View {
    @Bindable var vm: ProtectViewModel
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var selectedResources: Set<ExportResource> = Set(ExportResource.allCases)
    @State private var yamlOutput = ""
    @State private var isGenerating = false

    enum ExportResource: String, CaseIterable, Identifiable {
        case plans = "Plans"
        case analytics = "Analytics"
        case analyticSets = "Analytic Sets"
        case exceptionSets = "Exception Sets"
        case removableStorage = "Removable Storage CSets"
        case unifiedLogging = "Unified Logging Filters"
        case actionConfigs = "Action Configs"
        case telemetry = "Telemetry Configs"
        case preventLists = "Custom Prevent Lists"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Config-as-Code Export").font(.title2).bold()
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            HSplitView {
                // Resource picker
                VStack(alignment: .leading, spacing: 12) {
                    Text("Resources").font(.headline).padding(.horizontal, 16).padding(.top, 16)
                    List(ExportResource.allCases, selection: $selectedResources) { res in
                        Label(res.rawValue, systemImage: "checkmark")
                            .tag(res)
                    }
                    .listStyle(.sidebar)

                    Button {
                        Task { await generateYAML() }
                    } label: {
                        Label(isGenerating ? "Generating…" : "Generate YAML", systemImage: "doc.badge.gearshape")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isGenerating || selectedResources.isEmpty)
                    .padding(.horizontal, 16).padding(.bottom, 16)
                }
                .frame(minWidth: 200, maxWidth: 220)

                // YAML output
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("YAML").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        if !yamlOutput.isEmpty {
                            Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(yamlOutput, forType: .string) }
                                .buttonStyle(.bordered).controlSize(.small)
                            Button("Save…") { saveYAML() }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Color.primary.opacity(0.04))

                    Divider()

                    if yamlOutput.isEmpty {
                        Text("Select resources and click Generate YAML")
                            .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            Text(yamlOutput)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 720, minHeight: 500)
    }

    private func generateYAML() async {
        isGenerating = true
        defer { isGenerating = false }
        var sections: [String] = []
        for res in ExportResource.allCases where selectedResources.contains(res) {
            let yaml = await exportYAML(for: res)
            if !yaml.isEmpty { sections.append("# \(res.rawValue)\n\(yaml)") }
        }
        yamlOutput = sections.joined(separator: "\n\n")
    }

    private func exportYAML(for resource: ExportResource) async -> String {
        do {
            let cmd: CLICommand
            switch resource {
            case .plans:           cmd = .protectPlanExport(name: "--all")
            case .analytics:       cmd = .protectAnalyticExport(name: "--all")
            case .analyticSets:    cmd = .protectAnalyticSetExport(name: "--all")
            case .exceptionSets:   cmd = .protectExceptionSetExport(name: "--all")
            case .removableStorage: cmd = .protectRemovableStorageExport(name: "--all")
            case .unifiedLogging:  cmd = .protectUnifiedLoggingExport(name: "--all")
            case .actionConfigs:   cmd = .protectActionConfigExport(name: "--all")
            case .telemetry:       cmd = .protectTelemetryExport(name: "--all")
            case .preventLists:    cmd = .protectCustomPreventListExport(name: "--all")
            }
            let data = try await env.cliManager.run(cmd)
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return "# Error exporting \(resource.rawValue): \(error.localizedDescription)"
        }
    }

    private func saveYAML() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "jamf-protect-config.yaml"
        panel.allowedContentTypes = [.yaml]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? yamlOutput.write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - Named entry list (shared pattern for simple resource lists)

@MainActor @ViewBuilder
private func protectNamedEntryList(state: LoadState<[ProtectNamedEntry]>,
                                    title: String,
                                    icon: String,
                                    emptyLabel: String,
                                    refresh: @escaping () async -> Void) -> some View {
    AsyncContentView(state: state, retry: refresh) { entries in
        if entries.isEmpty {
            protectEmptyState(icon: icon, label: emptyLabel)
        } else {
            Table(entries) {
                TableColumn("Name") { Text($0.name) }
                TableColumn("Description") { Text($0.description ?? "—").foregroundStyle(.secondary) }
                TableColumn("Enabled") { entry in
                    if let enabled = entry.enabled {
                        Image(systemName: enabled ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(enabled ? .green : .secondary)
                    } else {
                        Text("—").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
    .navigationTitle(title)
    .toolbar { refreshButton { await refresh() } }
}

// MARK: - Overview section block

private struct ProductSectionBlock: View {
    let title: String
    let items: [OverviewItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DashSectionHeader(title, systemImage: "list.bullet")
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    HStack {
                        Text(item.resource).foregroundStyle(.primary)
                        Spacer()
                        Text(item.value).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
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
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        }
    }
}
