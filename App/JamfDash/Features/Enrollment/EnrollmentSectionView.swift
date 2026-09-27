import SwiftUI

/// The Enrollment sidebar section: recent enrollments with each Mac's timeline, the flow a
/// new Mac follows through a PreStage, and the existing tokens and PreStages tables.
struct EnrollmentSectionView: View {
    @Bindable var vm: EnrollmentFlowViewModel
    @Bindable var fleetVM: FleetViewModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("Enrollment section", selection: $vm.tab) {
                ForEach(EnrollmentTab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(.bar)
            Divider()

            switch vm.tab {
            case .recent: RecentEnrollmentsView(vm: vm)
            case .flow:   EnrollmentFlowView(vm: vm)
            case .setup:  EnrollmentView(vm: fleetVM)
            }
        }
        .navigationTitle("Enrollment")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        if vm.tab == .setup {
                            await fleetVM.loadDepTokens(force: true)
                            await fleetVM.loadComputerPrestages(force: true)
                            await fleetVM.loadMobileDevicePrestages(force: true)
                        } else {
                            await vm.refresh()
                        }
                    }
                } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .help("Reload this tab from Jamf Pro")
            }
        }
    }
}

// MARK: - Recent Enrollments

private struct RecentEnrollmentsView: View {
    @Bindable var vm: EnrollmentFlowViewModel

    var body: some View {
        HSplitView {
            list
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
            detail
                .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { await vm.loadRecent() }
    }

    private var list: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Search Macs", text: $vm.searchText)
                    .textFieldStyle(.roundedBorder)
                Picker("Enrolled in the last", selection: $vm.windowDays) {
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                }
                .labelsHidden()
                .fixedSize()
                .help("How far back to look for enrollments")
            }
            .padding(10)

            AsyncContentView(state: vm.recentState, retry: { await vm.loadRecent(force: true) }) { _ in
                let macs = vm.filteredRecent
                if macs.isEmpty {
                    ContentUnavailableView {
                        Label("No Recent Enrollments", systemImage: "laptopcomputer")
                    } description: {
                        Text(vm.searchText.isEmpty
                             ? "No Macs enrolled in the last \(vm.windowDays) days. Choose a longer period above."
                             : "No recently enrolled Mac matches “\(vm.searchText)”.")
                    }
                } else {
                    List(selection: Binding(get: { vm.selectedSerial }, set: { vm.select(serial: $0) })) {
                        ForEach(macs) { mac in
                            RecentRow(mac: mac).tag(mac.serial)
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
            if let count = vm.recentState.value?.count, count > 0 {
                Text("\(count) Mac\(count == 1 ? "" : "s") enrolled in the last \(vm.windowDays) days")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(8)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch vm.timelineState {
        case .idle:
            ContentUnavailableView("Choose a Mac", systemImage: "clock.arrow.circlepath",
                                   description: Text("Pick a recently enrolled Mac to see what happened after it enrolled."))
        case .loading:
            VStack(spacing: 10) {
                ProgressView()
                Text("Reading inventory, MDM commands, command history, policy logs and DDM status…")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't Load the Timeline", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { vm.reloadTimeline() }
            }
        case .loaded(let timeline):
            EnrollmentTimelineView(vm: vm, timeline: timeline)
        }
    }
}

private struct RecentRow: View {
    let mac: RecentEnrollment

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(mac.name).fontWeight(.medium).lineLimit(1)
            HStack(spacing: 4) {
                if let d = mac.enrolledAt {
                    Text(d, format: .dateTime.day().month(.abbreviated).hour().minute())
                }
                if let m = mac.method {
                    Text("·")
                    Text(m).lineLimit(1)
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - One Mac's timeline

struct EnrollmentTimelineView: View {
    @Bindable var vm: EnrollmentFlowViewModel
    let timeline: EnrollmentTimeline
    @Environment(AppEnvironment.self) private var env
    @State private var page: Page = .timeline
    @State private var phaseFilter: EnrollmentPhase?
    @State private var confirmPush = false

    enum Page: String, CaseIterable, Identifiable {
        case timeline = "Timeline", profiles = "Profiles", policies = "Policies & Apps"
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                counts
                if !vm.attention.isEmpty { attentionBox }
                if let note = vm.retentionNote {
                    EnrollmentNote(text: note, symbol: "clock.badge.exclamationmark", tint: .orange)
                }
                unavailableSources
                Picker("Show", selection: $page) {
                    ForEach(Page.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                switch page {
                case .timeline: timelinePage
                case .profiles: EnrollmentProfilesPage(vm: vm)
                case .policies: policiesPage
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .confirmationDialog("Send a blank push to \(timeline.device.name)?", isPresented: $confirmPush) {
            Button("Send Blank Push") { Task { await vm.blankPush() } }
        } message: {
            Text("The Mac is asked to check in with Jamf Pro, so waiting commands can be delivered. Nothing else changes.")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(timeline.device.name).font(.title2.weight(.semibold))
                Text(headerLine).font(.callout).foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if let ddm = timeline.ddm {
                    Text(ddmLine(ddm)).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Show in Device Lookup") { env.showInDeviceLookup(timeline.device.serial) }
        }
    }

    private var headerLine: String {
        let d = timeline.device
        var parts = [d.serial]
        if let m = d.method { parts.append(m) }
        if let p = timeline.prestage?.name, p != d.method { parts.append("PreStage “\(p)”") }
        if let e = d.enrolledAt { parts.append("enrolled \(e.formatted(date: .abbreviated, time: .shortened))") }
        if d.supervised == true { parts.append("supervised") }
        return parts.joined(separator: " · ")
    }

    private func ddmLine(_ ddm: EnrollmentTimeline.DDMSummary) -> String {
        var parts = ["DDM: \(ddm.itemCount) status items"]
        if let awaiting = ddm.awaitingConfiguration { parts.append(awaiting ? "still awaiting configuration" : "configuration finished") }
        if let last = ddm.lastReport { parts.append("last report \(last.formatted(.relative(presentation: .named)))") }
        return parts.joined(separator: " · ")
    }

    private var counts: some View {
        let events = vm.visibleEvents
        let done = events.filter { $0.status == .completed }.count
        let failed = events.filter { $0.status == .failed }.count
        let pending = events.filter { $0.status == .pending }.count
        let stuck = events.filter { $0.status == .stuck }.count
        return HStack(spacing: 8) {
            StatusPill(status: .completed, text: "\(done) done")
            if failed > 0 { StatusPill(status: .failed, text: "\(failed) failed") }
            if stuck > 0 { StatusPill(status: .stuck, text: "\(stuck) stuck") }
            if pending > 0 { StatusPill(status: .pending, text: "\(pending) pending") }
            Spacer()
            Picker("Period", selection: $vm.timelineWindow) {
                ForEach(TimelineWindow.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            .help("Which part of the time since enrollment to show")
        }
    }

    private var attentionBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Needs Attention", systemImage: "exclamationmark.triangle.fill")
                .font(.headline).foregroundStyle(.red)
            ForEach(vm.attention) { e in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    StatusPill(status: e.status, text: e.status.label)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(e.title) · \(e.kind)").fontWeight(.medium)
                        Text(attentionReason(e)).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if e.status == .stuck {
                        Button("Send Blank Push…") { confirmPush = true }
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if let message = vm.actionMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.25)))
    }

    private func attentionReason(_ e: EnrollmentEvent) -> String {
        if e.status == .stuck {
            let hours = Int(Date().timeIntervalSince(e.date) / 3600)
            let contact = timeline.device.lastContact.map { ", and last checked in \($0.formatted(.relative(presentation: .named)))" } ?? ""
            return "Pending for \(hours) hours. The Mac checked in after it was sent\(contact)."
        }
        if let detail = e.detail { return detail }
        return "Failed \(e.date.formatted(date: .abbreviated, time: .shortened))."
    }

    @ViewBuilder
    private var unavailableSources: some View {
        let missing = EnrollmentSource.allCases.compactMap { source -> (EnrollmentSource, String)? in
            switch timeline.sources[source] {
            case .unavailable(let why): return (source, why)
            default: return nil
            }
        }
        if !missing.isEmpty {
            EnrollmentNote(
                text: "Some data couldn't be read, so the timeline may be incomplete: "
                    + missing.map { "\($0.0.rawValue) (\($0.1))" }.joined(separator: "; "),
                symbol: "exclamationmark.circle", tint: .yellow)
        }
    }

    // MARK: Timeline page

    private var timelinePage: some View {
        let events = vm.visibleEvents.filter { phaseFilter == nil || $0.phase == phaseFilter }
        let start = timeline.device.enrolledAt ?? events.first?.date ?? Date()
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Phase", selection: $phaseFilter) {
                    Text("All phases").tag(EnrollmentPhase?.none)
                    Divider()
                    ForEach(EnrollmentPhase.allCases) { Label($0.title, systemImage: $0.symbol).tag(Optional($0)) }
                }
                .fixedSize()
                Toggle("Inventory commands", isOn: $vm.showRoutineCommands)
                    .toggleStyle(.checkbox)
                    .help("Show routine inventory polling such as Device Information and Profile List")
                Spacer()
                sourcesLine
            }
            if events.isEmpty {
                ContentUnavailableView("No Events in This Period", systemImage: "clock",
                                       description: Text("Choose “Since enrollment” to see everything Jamf Pro recorded for this Mac."))
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, e in
                        TimelineEventRow(event: e, start: start, isLast: index == events.count - 1)
                    }
                }
            }
        }
    }

    private var sourcesLine: some View {
        HStack(spacing: 10) {
            ForEach(EnrollmentSource.allCases, id: \.self) { source in
                let status = timeline.sources[source]
                Label(source.rawValue, systemImage: status?.isOK == true ? "checkmark.circle.fill" : "minus.circle")
                    .foregroundStyle(status?.isOK == true ? Color.secondary : Color.orange)
                    .help(sourceHelp(status))
            }
        }
        .font(.caption)
        .labelStyle(.titleAndIcon)
    }

    private func sourceHelp(_ status: SourceStatus?) -> String {
        switch status {
        case .ok(let n): return "\(n) record\(n == 1 ? "" : "s")"
        case .unavailable(let why), .notApplicable(let why): return why
        case nil: return "Not loaded"
        }
    }

    // MARK: Policies & Apps page

    private var policiesPage: some View {
        let policies = vm.policyRows
        let apps = vm.appEvents
        return VStack(alignment: .leading, spacing: 16) {
            ScanPrompt(vm: vm, reason: "Scan policy scopes to see which enrollment policies should have run on this Mac.")
            GroupBox("Policies") {
                if policies.isEmpty {
                    Text("No policy logs since enrollment.").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(policies) { row in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                PolicyStatusPill(status: row.status)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(row.name).fontWeight(.medium)
                                        if row.enrollmentTriggered {
                                            Text("Enrollment").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                                                .background(Color.accentColor.opacity(0.15), in: Capsule())
                                        }
                                    }
                                    Text(row.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let d = row.date {
                                    Text(d, format: .dateTime.day().month(.abbreviated).hour().minute())
                                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            GroupBox("Apps and packages") {
                if apps.isEmpty {
                    Text("No app or package install commands in this period.").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(apps) { e in
                            HStack(spacing: 10) {
                                StatusPill(status: e.status, text: e.status.label)
                                Text(e.title).fontWeight(.medium)
                                Text(e.kind).font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Text(e.date, format: .dateTime.day().month(.abbreviated).hour().minute())
                                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

// MARK: - Profiles page

private struct EnrollmentProfilesPage: View {
    @Bindable var vm: EnrollmentFlowViewModel
    @State private var sortOrder = [KeyPathComparator(\ProfileRow.status)]

    var body: some View {
        let rows = vm.profileRows.sorted(using: sortOrder)
        VStack(alignment: .leading, spacing: 10) {
            ScanPrompt(vm: vm, reason: "Scan profile scopes to compare what this Mac should have with what it has.")
            if rows.isEmpty {
                Text("No configuration profiles found for this Mac.").foregroundStyle(.secondary)
            } else {
                Table(rows, sortOrder: $sortOrder) {
                    TableColumn("Status", value: \.status) { ProfileStatusPill(status: $0.status) }
                        .width(min: 90, ideal: 100)
                    TableColumn("Profile", value: \.name) { Text($0.name).help($0.identifier ?? "") }
                        .width(min: 160, ideal: 220)
                    TableColumn("Source", value: \.source) { Text($0.source).foregroundStyle(.secondary) }
                        .width(min: 80, ideal: 110)
                    TableColumn("Why") { Text($0.reason).foregroundStyle(.secondary).help($0.reason) }
                        .width(min: 140, ideal: 220)
                    TableColumn("Installed") { row in
                        Text(row.installedAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "—")
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                    .width(min: 110, ideal: 140)
                    TableColumn("Last command") { Text($0.lastCommand ?? "—").foregroundStyle(.secondary) }
                        .width(min: 110, ideal: 160)
                }
                .frame(minHeight: CGFloat(min(rows.count, 14)) * 26 + 32)
                .contextMenu(forSelectionType: ProfileRow.ID.self) { ids in
                    if let id = ids.first, let row = rows.first(where: { $0.id == id }) {
                        Button("Copy Name") { copy(row.name) }
                        if let identifier = row.identifier { Button("Copy Identifier") { copy(identifier) } }
                    }
                }
            }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Shared pieces

/// Offers the scope scan where the comparison needs it.
struct ScanPrompt: View {
    @Bindable var vm: EnrollmentFlowViewModel
    let reason: String

    var body: some View {
        switch vm.scanState {
        case .idle:
            HStack(spacing: 10) {
                Image(systemName: "scope").foregroundStyle(.tint).accessibilityHidden(true)
                Text(reason).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Scan Scopes") { vm.startScan() }
                    .help("Reads every policy and configuration profile once. On large instances this takes a few minutes.")
            }
            .padding(10)
            .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        case .scanning(let done, let total):
            HStack(spacing: 10) {
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                    .frame(maxWidth: 240)
                Text(total == 0 ? "Reading the policy and profile lists…" : "Scanning scopes: \(done) of \(total)")
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                Button("Cancel") { vm.cancelScan() }
            }
        case .finished(let result):
            Text("Compared with \(result.profiles.count) profiles and \(result.policies.count) policies, scanned \(result.scannedAt.formatted(.relative(presentation: .named)))"
                 + (result.failures > 0 ? " (\(result.failures) couldn't be read)" : "") + ".")
                .font(.caption).foregroundStyle(.secondary)
        case .failed(let message):
            HStack {
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                Spacer()
                Button("Try Again") { vm.startScan() }
            }
            .font(.callout)
        }
    }
}

struct EnrollmentNote: View {
    let text: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(tint)
        }
        .font(.callout)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct TimelineEventRow: View {
    let event: EnrollmentEvent
    let start: Date
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .trailing, spacing: 1) {
                Text(event.date, format: .dateTime.hour().minute().second())
                    .font(.system(.caption, design: .monospaced))
                Text(EnrollmentAnalyzer.relative(event.date, to: start))
                    .font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
            }
            .frame(width: 70, alignment: .trailing)

            VStack(spacing: 0) {
                marker
                if !isLast {
                    Rectangle().fill(Color.secondary.opacity(0.25)).frame(width: 2).frame(maxHeight: .infinity)
                }
            }
            .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: event.phase.symbol).foregroundStyle(.secondary).font(.caption)
                        .help(event.phase.title)
                    Text(event.title).fontWeight(.medium)
                    Text(event.kind).font(.caption).foregroundStyle(.secondary)
                }
                if let detail = event.detail {
                    Text(detail).font(.caption).foregroundStyle(event.status == .failed ? .red : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, 12)
            Spacer()
            StatusPill(status: event.status, text: event.isApproximate ? "Approx." : event.status.label)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.date.formatted(date: .omitted, time: .standard)), \(event.title), \(event.kind), \(event.status.label)")
    }

    @ViewBuilder
    private var marker: some View {
        if event.isApproximate {
            Circle().strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
                .foregroundStyle(.secondary).frame(width: 11, height: 11)
                .padding(.top, 3)
        } else {
            Circle().fill(StatusPill.color(for: event.status)).frame(width: 11, height: 11)
                .padding(.top, 3)
        }
    }
}

struct StatusPill: View {
    let status: EnrollmentEventStatus
    let text: String

    static func color(for status: EnrollmentEventStatus) -> Color {
        switch status {
        case .completed: return .green
        case .failed:    return .red
        case .stuck:     return .orange
        case .pending:   return .yellow
        case .info:      return .secondary
        }
    }

    static func symbol(for status: EnrollmentEventStatus) -> String {
        switch status {
        case .completed: return "checkmark"
        case .failed:    return "xmark"
        case .stuck:     return "exclamationmark"
        case .pending:   return "hourglass"
        case .info:      return "info"
        }
    }

    var body: some View {
        Pill(text: text, symbol: Self.symbol(for: status), color: Self.color(for: status))
    }
}

struct ProfileStatusPill: View {
    let status: ProfileRowStatus

    var body: some View {
        switch status {
        case .installed:  Pill(text: status.label, symbol: "checkmark", color: .green)
        case .failed:     Pill(text: status.label, symbol: "xmark", color: .red)
        case .stuck:      Pill(text: status.label, symbol: "exclamationmark", color: .orange)
        case .pending:    Pill(text: status.label, symbol: "hourglass", color: .yellow)
        case .missing:    Pill(text: status.label, symbol: "questionmark", color: .orange)
        case .unexpected: Pill(text: status.label, symbol: "info", color: .purple)
        case .notScoped:  Pill(text: status.label, symbol: "circle", color: .secondary)
        }
    }
}

struct PolicyStatusPill: View {
    let status: PolicyRowStatus

    var body: some View {
        switch status {
        case .completed: Pill(text: status.label, symbol: "checkmark", color: .green)
        case .failed:    Pill(text: status.label, symbol: "xmark", color: .red)
        case .notRunYet: Pill(text: status.label, symbol: "hourglass", color: .orange)
        }
    }
}

/// Colour plus symbol plus text, so status never depends on colour alone.
struct Pill: View {
    let text: String
    let symbol: String
    let color: Color

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(color == .secondary ? Color.secondary : color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
            .fixedSize()
    }
}
