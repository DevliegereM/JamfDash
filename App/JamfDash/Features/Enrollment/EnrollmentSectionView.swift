import SwiftUI

/// The Enrollment sidebar section: recent enrollments with each Mac's timeline, the flow a
/// new Mac follows through a PreStage, and the existing tokens and PreStages tables.
struct EnrollmentSectionView: View {
    @Bindable var vm: EnrollmentFlowViewModel
    @Bindable var fleetVM: FleetViewModel

    var body: some View {
        Group {
            switch vm.tab {
            case .recent: RecentEnrollmentsView(vm: vm)
            case .flow:   EnrollmentFlowView(vm: vm)
            case .setup:  EnrollmentView(vm: fleetVM)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Enrollment")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Enrollment section", selection: $vm.tab) {
                    ForEach(EnrollmentTab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
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
        HStack(spacing: 0) {
            list
                .frame(width: 290)
                .frame(maxHeight: .infinity)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { await vm.loadRecent() }
    }

    private var list: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                    TextField("Search Macs", text: $vm.searchText).textFieldStyle(.plain)
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
                Picker("Enrolled in the last", selection: $vm.windowDays) {
                    Text("Last 7 days").tag(7)
                    Text("Last 30 days").tag(30)
                    Text("Last 90 days").tag(90)
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
                    .frame(maxHeight: .infinity)
                } else {
                    List(selection: Binding(get: { vm.selectedRecentID }, set: { vm.selectRecent(id: $0) })) {
                        ForEach(macs) { mac in
                            RecentRow(mac: mac, badge: mac.serial.flatMap { vm.badges[$0] }).tag(mac.id)
                        }
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            if let count = vm.recentState.value?.count, count > 0 {
                Divider()
                Text("\(count) Mac\(count == 1 ? "" : "s") enrolled in the last \(vm.windowDays) days")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
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
    let badge: EnrollmentFlowViewModel.RecentBadge?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(mac.name).fontWeight(.semibold).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 4)
            badgeView
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let d = mac.enrolledAt { parts.append(d.formatted(.dateTime.day().month(.abbreviated))) }
        if let m = mac.method {
            let isPrestage = EnrollmentParsing.isPrestageMethod(type: mac.methodType, viaADE: mac.viaADE)
            parts.append(isPrestage ? "PreStage “\(m)”" : m)
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var badgeView: some View {
        if let badge {
            if badge.problems > 0 {
                CountBadge(text: "\(badge.problems)", color: .red)
                    .help("\(badge.problems) failed or stuck")
                    .accessibilityLabel("\(badge.problems) failed or stuck")
            } else if badge.pending > 0 {
                CountBadge(text: "\(badge.pending)", color: .orange)
                    .help("\(badge.pending) pending")
                    .accessibilityLabel("\(badge.pending) pending")
            } else {
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold)).foregroundStyle(.green)
                    .frame(width: 20, height: 20)
                    .background(Color.green.opacity(0.15), in: Circle())
                    .help("Nothing failed or waiting")
                    .accessibilityLabel("Nothing failed or waiting")
            }
        }
    }
}

private struct CountBadge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold)).monospacedDigit()
            .foregroundStyle(color)
            .frame(minWidth: 20, minHeight: 20)
            .background(color.opacity(0.15), in: Circle())
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
        case timeline = "Timeline", profiles = "Profiles", policies = "Policies & Apps", setupManager = "Setup Manager"
        var id: String { rawValue }
    }

    private var pages: [Page] {
        vm.timelineSetupManager == nil ? [.timeline, .profiles, .policies] : Page.allCases
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                counts
                if !vm.attention.isEmpty { attentionBox }
                if let note = vm.retentionNote {
                    EnrollmentNote(text: note, symbol: "clock.badge.exclamationmark", tint: .orange)
                }
                unavailableSources
                Picker("Show", selection: $page) {
                    ForEach(pages) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .padding(.top, 4)

                switch page {
                case .timeline:     timelinePage
                case .profiles:     EnrollmentProfilesPage(vm: vm)
                case .policies:     policiesPage
                case .setupManager: setupManagerPage
                }

                Divider().padding(.top, 6)
                sourcesLine
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: pages) { _, now in if !now.contains(page) { page = .timeline } }
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
                headerLine
                if let ddm = timeline.ddm {
                    Text(ddmLine(ddm)).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Show in Device Lookup") { env.showInDeviceLookup(timeline.device.serial) }
        }
    }

    private var headerLine: some View {
        let d = timeline.device
        var parts: [String] = []
        if let m = d.method { parts.append(m) }
        if let p = timeline.prestage?.name, p != d.method { parts.append("PreStage “\(p)”") }
        if let e = d.enrolledAt { parts.append("enrolled \(e.formatted(date: .abbreviated, time: .shortened))") }
        if d.supervised == true { parts.append("supervised") }
        return (Text(d.serial).font(.system(.callout, design: .monospaced))
            + Text(parts.isEmpty ? "" : " · " + parts.joined(separator: " · ")))
            .font(.callout).foregroundStyle(.secondary)
            .textSelection(.enabled)
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
            if pending + stuck > 0 {
                StatusPill(status: stuck > 0 ? .stuck : .pending,
                           text: "\(pending + stuck) pending" + (stuck > 0 ? " · \(stuck) stuck" : ""))
            }
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
        let start = timeline.device.enrolledAt
        return VStack(alignment: .leading, spacing: 10) {
            Text("NEEDS ATTENTION")
                .font(.caption.weight(.bold)).tracking(0.6)
                .foregroundStyle(.red)
            ForEach(vm.attention) { e in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        StatusPill(status: e.status, text: e.status.label)
                        (Text(e.title).fontWeight(.semibold) + Text(" · \(e.kind)").foregroundStyle(.secondary))
                            .lineLimit(1)
                        Spacer()
                        if e.status == .stuck {
                            Button("Send Blank Push…") { confirmPush = true }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                        } else if let start {
                            Text(EnrollmentAnalyzer.relative(e.date, to: start))
                                .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                        }
                    }
                    Text(attentionReason(e)).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 4)
                }
                .accessibilityElement(children: .combine)
            }
            if let message = vm.actionMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.3)))
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
            if case .unavailable(let why) = timeline.sources[source] { return (source, why) }
            return nil
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
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Picker("Phase", selection: $phaseFilter) {
                    Text("All phases").tag(EnrollmentPhase?.none)
                    Divider()
                    ForEach(EnrollmentPhase.allCases) { Label($0.title, systemImage: $0.symbol).tag(Optional($0)) }
                }
                .fixedSize()
                Toggle("Show inventory commands", isOn: $vm.showRoutineCommands)
                    .toggleStyle(.checkbox)
                    .help("Routine inventory polling such as Device Information and Profile List")
                Spacer()
            }
            .padding(.bottom, 6)
            if events.isEmpty {
                ContentUnavailableView("No Events in This Period", systemImage: "clock",
                                       description: Text("Choose “Since enrollment” to see everything Jamf Pro recorded for this Mac."))
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(Array(events.enumerated()), id: \.element.id) { index, e in
                    if index == 0 || events[index - 1].phase != e.phase {
                        PhaseHeader(phase: e.phase).padding(.top, index == 0 ? 0 : 10)
                    }
                    TimelineEventRow(event: e, start: start)
                }
            }
        }
    }

    private var sourcesLine: some View {
        HStack(spacing: 12) {
            Text("Sources:")
            ForEach(EnrollmentSource.allCases, id: \.self) { source in
                let status = timeline.sources[source]
                HStack(spacing: 3) {
                    Text(source.rawValue)
                    Image(systemName: status?.isOK == true ? "checkmark" : "minus")
                        .foregroundStyle(status?.isOK == true ? Color.green : Color.orange)
                }
                .help(sourceHelp(status))
            }
        }
        .font(.caption).foregroundStyle(.secondary)
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
            SectionCard(title: "Policies") {
                if policies.isEmpty {
                    Text("No policy logs since enrollment.").foregroundStyle(.secondary)
                } else {
                    ForEach(policies) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            PolicyStatusPill(status: row.status)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(row.name).fontWeight(.medium)
                                    if row.enrollmentTriggered { Tag(text: "Enrollment") }
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
            }
            SectionCard(title: "Apps and packages") {
                if apps.isEmpty {
                    Text("No app or package install commands in this period.").foregroundStyle(.secondary)
                } else {
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
            }
        }
    }

    // MARK: Setup Manager page

    @ViewBuilder
    private var setupManagerPage: some View {
        if let source = vm.timelineSetupManager {
            VStack(alignment: .leading, spacing: 12) {
                Text("“\(source.profileName)” · \(source.reason). \(source.config.runAtLabel). \(source.config.finalActionLabel).")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                SetupManagerStepList(rows: vm.setupManagerRows, showStatus: true)
                Text("Status comes from this Mac's policy logs in Jamf Pro. Steps that aren't policies run on the Mac only; their result is in /private/var/log/setupManager.log on the Mac.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
                        .width(min: 160, ideal: 240)
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
                .frame(height: CGFloat(min(rows.count, 16)) * 26 + 34)
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

/// Setup Manager's steps in order, with the policies they run and (for one Mac) their status.
struct SetupManagerStepList: View {
    let rows: [SetupManagerStepRow]
    let showStatus: Bool

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(row.step.id + 1)")
                        .font(.caption.weight(.bold)).monospacedDigit()
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Color.accentColor, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(row.step.label).fontWeight(.medium)
                            Tag(text: row.step.kind.title, symbol: row.step.kind.symbol)
                            if let v = row.step.value, !v.isEmpty {
                                Text(v).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                        }
                        if !row.policies.isEmpty {
                            Text("Runs " + row.policies.joined(separator: ", "))
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !row.note.isEmpty {
                            Text(row.note).font(.caption)
                                .foregroundStyle(row.note.hasPrefix("No enabled policy") ? Color.orange : Color.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                    if showStatus {
                        if let status = row.status {
                            VStack(alignment: .trailing, spacing: 2) {
                                PolicyStatusPill(status: status)
                                if let d = row.date {
                                    Text(d, format: .dateTime.day().month(.abbreviated).hour().minute())
                                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                                }
                            }
                        } else {
                            Text("—").foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.vertical, 8).padding(.horizontal, 10)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Step \(row.step.id + 1): \(row.step.label), \(row.step.kind.title)\(row.status.map { ", \($0.label)" } ?? "")")
                Divider().padding(.leading, 40)
            }
        }
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }
}

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
                    .help("Reads every policy and configuration profile once.")
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

/// A titled group with a subtle background, lighter than GroupBox.
struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).tracking(0.5).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) { content }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

/// Small capsule label, e.g. "PreStage" or "Policy".
struct Tag: View {
    let text: String
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol).accessibilityHidden(true) }
            Text(text)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Color.secondary.opacity(0.15), in: Capsule())
        .fixedSize()
    }
}

private struct PhaseHeader: View {
    let phase: EnrollmentPhase

    var body: some View {
        Label(phase.title.uppercased(), systemImage: phase.symbol)
            .font(.caption.weight(.semibold))
            .tracking(0.5)
            .foregroundStyle(.secondary)
            .padding(.leading, 124)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct TimelineEventRow: View {
    let event: EnrollmentEvent
    let start: Date

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(event.date, format: .dateTime.hour().minute().second())
                .font(.system(.callout, design: .monospaced))
                .frame(width: 66, alignment: .leading)
            Text(EnrollmentAnalyzer.relative(event.date, to: start))
                .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)
            marker
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if event.kind != event.title {
                        Text(event.kind).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    Text(event.title).fontWeight(.semibold)
                }
                if let detail = event.detail {
                    Text(detail).font(.caption).foregroundStyle(event.status == .failed ? .red : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            StatusPill(status: event.status, text: event.isApproximate ? "Inferred" : event.status.label)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.date.formatted(date: .omitted, time: .standard)), \(event.title), \(event.kind), \(event.status.label)")
    }

    @ViewBuilder
    private var marker: some View {
        if event.isApproximate {
            Circle().strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
                .foregroundStyle(.secondary).frame(width: 10, height: 10)
        } else {
            Circle().fill(StatusPill.color(for: event.status)).frame(width: 10, height: 10)
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
