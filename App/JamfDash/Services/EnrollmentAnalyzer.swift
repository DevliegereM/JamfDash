import Foundation

/// Pure functions that turn raw enrollment data into the timeline, the expected-vs-actual
/// comparison and the PreStage flow. No I/O, so everything here is unit-tested directly.
enum EnrollmentAnalyzer {

    /// A pending command older than this, on a Mac that checked in after it was sent, is stuck.
    static let stuckThreshold: TimeInterval = 4 * 3600

    // MARK: - Timeline

    struct TimelineInput: Sendable {
        var enrolledAt: Date?
        var firstSeenAt: Date?
        var method: String?
        var supervised: Bool?
        var lastContact: Date?
        var mdmCommands: [MDMCommandRecord] = []
        var historyCommands: [HistoryCommandRecord] = []
        var policyLogs: [PolicyLogRecord] = []
        var installedProfiles: [EnrollmentTimeline.InstalledProfile] = []
        /// Policy IDs with the Enrollment Complete trigger, when the scope scan has run.
        var enrollmentPolicyIDs: Set<Int> = []
        /// Configuration profile names by Jamf Pro ID, to name commands for profiles that aren't installed.
        var profileNamesByID: [Int: String] = [:]
    }

    static func buildEvents(_ input: TimelineInput, now: Date = Date()) -> [EnrollmentEvent] {
        var events: [EnrollmentEvent] = []
        let profileNames = Dictionary(
            input.installedProfiles.compactMap { p in p.identifier.map { ($0.lowercased(), p.name) } },
            uniquingKeysWith: { a, _ in a }
        )

        if let enrolled = input.enrolledAt {
            var detail = [input.method, input.supervised == true ? "supervised" : nil].compactMap { $0 }
            if detail.isEmpty { detail = ["Enrollment date from inventory"] }
            events.append(EnrollmentEvent(
                id: "enrolled", date: enrolled, completedDate: enrolled, phase: .mdmEnrollment,
                kind: "Enrollment", title: "Enrolled in MDM", detail: detail.joined(separator: " · "),
                status: .completed, isApproximate: false, source: .inventory, profileIdentifier: nil))
        }
        if let first = input.firstSeenAt, let enrolled = input.enrolledAt, enrolled.timeIntervalSince(first) > 86_400 {
            events.append(EnrollmentEvent(
                id: "first-seen", date: first, completedDate: first, phase: .mdmEnrollment,
                kind: "Inventory", title: "First added to Jamf Pro", detail: "This Mac was enrolled before and re-enrolled later",
                status: .info, isApproximate: false, source: .inventory, profileIdentifier: nil))
        }

        // MDM commands (Jamf Pro API) are the richest source; history fills the gaps.
        for (i, cmd) in input.mdmCommands.enumerated() {
            guard let sent = cmd.dateSent ?? cmd.dateCompleted else { continue }
            let kind = EnrollmentParsing.readableCommand(cmd.commandType)
            let profileName = cmd.profileIdentifier.flatMap { profileNames[$0.lowercased()] }
                ?? cmd.profileID.flatMap { input.profileNamesByID[$0] }
            events.append(EnrollmentEvent(
                id: "mdm-\(cmd.uuid ?? String(i))", date: sent, completedDate: cmd.dateCompleted,
                phase: EnrollmentParsing.phase(forCommand: cmd.commandType), kind: kind,
                title: profileName ?? cmd.profileIdentifier ?? kind, detail: cmd.errorText,
                status: cmd.status, isApproximate: false, source: .mdmCommands,
                profileIdentifier: cmd.profileIdentifier))
        }
        // The same command often appears in both sources. Classic history only has the
        // completion time for completed commands, so match on either time.
        let apiCount = events.count
        for (i, cmd) in input.historyCommands.enumerated() {
            guard let issued = cmd.issued ?? cmd.finished else { continue }
            let key = EnrollmentParsing.commandKey(cmd.name)
            let near: (Date?, Date?) -> Bool = { a, b in
                guard let a, let b else { return false }
                return abs(a.timeIntervalSince(b)) <= 120
            }
            if let match = events.indices.first(where: { j in
                j < apiCount && events[j].source == .mdmCommands
                    && EnrollmentParsing.commandKey(events[j].kind) == key
                    && (near(events[j].date, cmd.issued) || near(events[j].completedDate, cmd.finished)
                        || near(events[j].date, cmd.finished))
            }) {
                // History names the profile; the API often only has its ID.
                if let subject = cmd.subject, events[match].title == events[match].kind {
                    let e = events[match]
                    events[match] = EnrollmentEvent(id: e.id, date: e.date, completedDate: e.completedDate, phase: e.phase,
                                                    kind: e.kind, title: subject, detail: e.detail, status: e.status,
                                                    isApproximate: e.isApproximate, source: e.source,
                                                    profileIdentifier: e.profileIdentifier)
                }
                continue
            }
            let kind = EnrollmentParsing.readableCommand(cmd.name)
            events.append(EnrollmentEvent(
                id: "hist-\(i)", date: issued, completedDate: cmd.finished,
                phase: EnrollmentParsing.phase(forCommand: cmd.name), kind: kind, title: cmd.subject ?? kind,
                detail: cmd.status == .failed ? cmd.message : nil, status: cmd.status,
                isApproximate: false, source: .commandHistory, profileIdentifier: nil))
        }

        // DeviceConfigured is sent when Setup Assistant may continue: the closest thing
        // Jamf records to "Setup Assistant finished".
        if let configured = events.first(where: { EnrollmentParsing.commandKey($0.kind) == "deviceconfigured" && $0.status == .completed }),
           let done = configured.completedDate ?? Optional(configured.date) {
            events.append(EnrollmentEvent(
                id: "setup-finished", date: done.addingTimeInterval(1), completedDate: done, phase: .setupAssistant,
                kind: "Setup Assistant", title: "Setup Assistant finished",
                detail: "Approximate, from the Device Configured command",
                status: .info, isApproximate: true, source: configured.source, profileIdentifier: nil))
        }

        for (i, log) in input.policyLogs.enumerated() {
            guard let date = log.date else { continue }
            let enrollment = log.policyID.map(input.enrollmentPolicyIDs.contains) ?? false
            events.append(EnrollmentEvent(
                id: "policy-\(i)", date: date, completedDate: date, phase: .policies,
                kind: enrollment ? "Enrollment policy" : "Policy", title: log.name,
                detail: log.failed ? log.status : nil,
                status: log.failed ? .failed : .completed, isApproximate: false,
                source: .policyLogs, profileIdentifier: nil))
        }

        // Installed profiles without a matching command (history flushed, or delivered in
        // Setup Assistant) still show when they were installed.
        let profileEvents = events.filter { $0.phase == .profiles }
        for (i, p) in input.installedProfiles.enumerated() {
            guard let at = p.installedAt else { continue }
            let covered = profileEvents.contains { e in
                (p.identifier != nil && e.profileIdentifier?.lowercased() == p.identifier?.lowercased())
                    || e.title == p.name
            }
            if covered { continue }
            events.append(EnrollmentEvent(
                id: "installed-\(i)", date: at, completedDate: at, phase: .profiles,
                kind: "Profile installed", title: p.name, detail: nil, status: .completed,
                isApproximate: false, source: .inventory, profileIdentifier: p.identifier))
        }

        return markStuck(events, lastContact: input.lastContact, now: now)
            .sorted { $0.date == $1.date ? $0.phase < $1.phase : $0.date < $1.date }
    }

    /// Pending commands older than `stuckThreshold` on a Mac that has checked in since.
    static func markStuck(_ events: [EnrollmentEvent], lastContact: Date?, now: Date = Date()) -> [EnrollmentEvent] {
        events.map { e in
            guard e.status == .pending, now.timeIntervalSince(e.date) >= stuckThreshold,
                  let contact = lastContact, contact > e.date else { return e }
            var copy = e
            copy.status = .stuck
            return copy
        }
    }

    /// Events of the enrollment period: from just before enrollment until `window` after it.
    static func eventsInWindow(_ events: [EnrollmentEvent], enrolledAt: Date?, window: TimeInterval?) -> [EnrollmentEvent] {
        guard let enrolled = enrolledAt else { return events }
        let start = enrolled.addingTimeInterval(-15 * 60)
        return events.filter { e in
            // Failed and waiting items always stay visible.
            if e.status == .stuck || e.status == .pending || e.status == .failed { return e.date >= start }
            guard e.date >= start else { return false }
            guard let window else { return true }
            return e.date <= enrolled.addingTimeInterval(window)
        }
    }

    static func attention(_ events: [EnrollmentEvent]) -> [EnrollmentEvent] {
        events.filter { $0.status == .failed || $0.status == .stuck }
            .sorted { ($0.status == .failed ? 0 : 1, $0.date) < ($1.status == .failed ? 0 : 1, $1.date) }
    }

    /// "+0:37", "+4:12", "+3h 12m", "+2d 4h".
    static func relative(_ date: Date, to start: Date) -> String {
        let seconds = Int(date.timeIntervalSince(start))
        let sign = seconds < 0 ? "−" : "+"
        let s = abs(seconds)
        if s < 3600 { return String(format: "%@%d:%02d", sign, s / 60, s % 60) }
        if s < 86_400 { return "\(sign)\(s / 3600)h \((s % 3600) / 60)m" }
        return "\(sign)\(s / 86_400)d \((s % 86_400) / 3600)h"
    }

    // MARK: - Scope for one Mac

    struct DeviceContext: Sendable {
        let computerID: Int?
        let name: String
        let groups: Set<String>
        let department: String?
        let building: String?

        init(_ device: EnrollmentTimeline.Device) {
            computerID = Int(device.computerID)
            name = device.name
            groups = Set(device.groups.map { $0.lowercased() })
            department = device.department?.lowercased()
            building = device.building?.lowercased()
        }

        init(computerID: Int?, name: String, groups: [String], department: String?, building: String?) {
            self.computerID = computerID
            self.name = name
            self.groups = Set(groups.map { $0.lowercased() })
            self.department = department?.lowercased()
            self.building = building?.lowercased()
        }
    }

    enum ScopeMatch: Sendable, Equatable {
        case applies(String)
        case excluded(String)
        case notScoped(String)
    }

    /// Whether a Classic scope targets this Mac, with the reason in words. User-based
    /// limitations are ignored: they decide per user, not per Mac.
    static func match(_ scope: JamfScope, device: DeviceContext) -> ScopeMatch {
        let ex = scope.exclusions
        if let g = ex.computerGroups.first(where: { device.groups.contains($0.name.lowercased()) }) {
            return .excluded("Excluded by “\(g.name)”")
        }
        if ex.computers.contains(where: { $0.id == device.computerID || $0.name == device.name }) {
            return .excluded("This Mac is excluded")
        }
        if let d = device.department, let hit = ex.departments.first(where: { $0.name.lowercased() == d }) {
            return .excluded("Department “\(hit.name)” is excluded")
        }
        if let b = device.building, let hit = ex.buildings.first(where: { $0.name.lowercased() == b }) {
            return .excluded("Building “\(hit.name)” is excluded")
        }
        if scope.allComputers { return .applies("All Computers") }
        if scope.computers.contains(where: { $0.id == device.computerID || $0.name == device.name }) {
            return .applies("Scoped to this Mac")
        }
        if let g = scope.computerGroups.first(where: { device.groups.contains($0.name.lowercased()) }) {
            return .applies("Member of “\(g.name)”")
        }
        if let d = device.department, let hit = scope.departments.first(where: { $0.name.lowercased() == d }) {
            return .applies("Department “\(hit.name)”")
        }
        if let b = device.building, let hit = scope.buildings.first(where: { $0.name.lowercased() == b }) {
            return .applies("Building “\(hit.name)”")
        }
        if let g = scope.computerGroups.first {
            return .notScoped(scope.computerGroups.count == 1 ? "Not in “\(g.name)”"
                                                              : "Not in any of \(scope.computerGroups.count) groups")
        }
        return .notScoped("Not scoped to this Mac")
    }

    // MARK: - Profiles: expected vs actual

    static func profileRows(timeline: EnrollmentTimeline, events: [EnrollmentEvent],
                            scan: ScopeScanResult?) -> [ProfileRow] {
        let device = DeviceContext(timeline.device)
        let prestageIDs = Set(timeline.prestage?.profileIDs ?? [])
        let profileCommands = events.filter { $0.phase == .profiles && $0.source != .inventory }
        var usedInstalled = Set<String>()
        var rows: [ProfileRow] = []

        func installed(for name: String, identifier: String?, id: Int? = nil) -> EnrollmentTimeline.InstalledProfile? {
            if let id, let hit = timeline.installedProfiles.first(where: { $0.jamfID == id }) { return hit }
            return timeline.installedProfiles.first { p in
                if let a = identifier?.lowercased(), let b = p.identifier?.lowercased(), a == b { return true }
                return p.name.caseInsensitiveCompare(name) == .orderedSame
            }
        }
        func lastCommand(for name: String, identifier: String?) -> EnrollmentEvent? {
            profileCommands.last { e in
                if let a = identifier?.lowercased(), let b = e.profileIdentifier?.lowercased(), a == b { return true }
                return e.title.caseInsensitiveCompare(name) == .orderedSame
                    || (e.detail ?? "").localizedCaseInsensitiveContains(name)
            }
        }
        func commandText(_ e: EnrollmentEvent?) -> String? {
            e.map { "\($0.kind) · \($0.status.label.lowercased())" }
        }

        if let scan {
            for profile in scan.profiles {
                let inPrestage = prestageIDs.contains(profile.id)
                let match = inPrestage ? .applies("In the PreStage") : match(profile.scope, device: device)
                let have = installed(for: profile.name, identifier: profile.identifier, id: profile.id)
                if let have { usedInstalled.insert(have.id) }
                let command = lastCommand(for: profile.name, identifier: profile.identifier)
                let source = inPrestage ? "PreStage" : sourceLabel(profile.scope)
                switch match {
                case .applies(let reason):
                    let status: ProfileRowStatus
                    if have != nil { status = .installed }
                    else if let command {
                        switch command.status {
                        case .failed: status = .failed
                        case .stuck: status = .stuck
                        case .pending: status = .pending
                        default: status = .missing
                        }
                    } else { status = .missing }
                    rows.append(ProfileRow(id: "p\(profile.id)", name: profile.name, identifier: profile.identifier,
                                           status: status, source: source, reason: reason,
                                           installedAt: have?.installedAt, lastCommand: commandText(command)))
                case .excluded(let reason), .notScoped(let reason):
                    if let have {
                        rows.append(ProfileRow(id: "p\(profile.id)", name: profile.name, identifier: profile.identifier,
                                               status: .unexpected, source: source,
                                               reason: "Installed, but \(reason.prefix(1).lowercased() + reason.dropFirst())",
                                               installedAt: have.installedAt, lastCommand: commandText(command)))
                    } else if !profile.scope.computerGroups.isEmpty || !profile.scope.exclusions.computerGroups.isEmpty {
                        rows.append(ProfileRow(id: "p\(profile.id)", name: profile.name, identifier: profile.identifier,
                                               status: .notScoped, source: source, reason: reason,
                                               installedAt: nil, lastCommand: nil))
                    }
                }
            }
        }

        // Installed profiles that aren't in Jamf's profile list (the MDM profile, user-level
        // profiles), or everything when the scan hasn't run.
        for p in timeline.installedProfiles where !usedInstalled.contains(p.id) {
            let command = lastCommand(for: p.name, identifier: p.identifier)
            rows.append(ProfileRow(id: "i-\(p.id)", name: p.name, identifier: p.identifier, status: .installed,
                                   source: scan == nil ? "—" : "Not a Jamf Pro profile",
                                   reason: scan == nil ? "Installed on the Mac" : "Installed outside Jamf Pro's profile list",
                                   installedAt: p.installedAt, lastCommand: commandText(command)))
        }

        // Failed or waiting install commands for profiles the list doesn't know yet.
        let known = Set(rows.map { $0.name.lowercased() } + rows.compactMap { $0.identifier?.lowercased() })
        for e in profileCommands where [.failed, .stuck, .pending].contains(e.status)
            && EnrollmentParsing.commandKey(e.kind).contains("install") {
            let key = (e.profileIdentifier ?? e.title).lowercased()
            if known.contains(key) || known.contains(e.title.lowercased()) { continue }
            let status: ProfileRowStatus = e.status == .failed ? .failed : e.status == .stuck ? .stuck : .pending
            rows.append(ProfileRow(id: "c-\(e.id)", name: e.title, identifier: e.profileIdentifier, status: status,
                                   source: "—", reason: e.detail ?? "Install command", installedAt: nil,
                                   lastCommand: commandText(e)))
        }

        return rows.sorted { ($0.status, $0.name.lowercased()) < ($1.status, $1.name.lowercased()) }
    }

    static func sourceLabel(_ scope: JamfScope) -> String {
        if scope.allComputers { return "All Computers" }
        if !scope.computerGroups.isEmpty { return scope.computerGroups.count == 1 ? "Group" : "Groups" }
        if !scope.departments.isEmpty { return "Department" }
        if !scope.buildings.isEmpty { return "Building" }
        if !scope.computers.isEmpty { return "Specific Macs" }
        return "—"
    }

    // MARK: - Policies: expected vs actual

    static func policyRows(timeline: EnrollmentTimeline, events: [EnrollmentEvent],
                           scan: ScopeScanResult?) -> [PolicyRow] {
        let device = DeviceContext(timeline.device)
        let enrollmentPolicies = (scan?.policies ?? []).filter { $0.enabled && $0.enrollmentTrigger }
        var rows: [PolicyRow] = []
        var seen = Set<String>()
        for e in events where e.source == .policyLogs {
            seen.insert(e.title.lowercased())
            rows.append(PolicyRow(id: e.id, name: e.title, status: e.status == .failed ? .failed : .completed,
                                  date: e.date, enrollmentTriggered: e.kind == "Enrollment policy",
                                  detail: e.detail ?? "Ran on this Mac"))
        }
        for policy in enrollmentPolicies where !seen.contains(policy.name.lowercased()) {
            guard case .applies(let reason) = match(policy.scope, device: device) else { continue }
            rows.append(PolicyRow(id: "exp-\(policy.id)", name: policy.name, status: .notRunYet, date: nil,
                                  enrollmentTriggered: true,
                                  detail: "Enrollment policy scoped to this Mac (\(reason)), no log found"))
        }
        return rows.sorted { a, b in
            if a.status != b.status { return a.status < b.status }
            return (a.date ?? .distantFuture) < (b.date ?? .distantFuture)
        }
    }

    // MARK: - Flow for a PreStage

    struct FlowInput: Sendable {
        var prestage: PrestageDetail
        var adeTokenName: String?
        var profileNames: [Int: String] = [:]
        var packageNames: [Int: String] = [:]
        var checkInMinutes: Int?
        var scan: ScopeScanResult?
        var appInstallers: [AppInstallerDeployment] = []
    }

    static func buildFlow(_ input: FlowInput) -> EnrollmentFlow {
        let p = input.prestage
        var phases: [FlowPhase] = []
        var specificOnly = 0

        phases.append(FlowPhase(
            phase: .adeAssignment,
            summary: input.adeTokenName.map { "Token “\($0)”" } ?? (p.adeInstanceID == nil ? "No token linked" : "Token \(p.adeInstanceID!)"),
            lines: ["Apple Business Manager assigns the Mac to this PreStage before it's unboxed."],
            items: [], needsScan: false))

        var setupLines: [String] = []
        if !p.skipItems.isEmpty {
            setupLines.append("\(p.skippedPanes.count) of \(p.skipItems.count) panes skipped.")
            if !p.shownPanes.isEmpty {
                setupLines.append("Shown: " + p.shownPanes.map(readablePane).joined(separator: ", "))
            }
            if !p.skippedPanes.isEmpty {
                setupLines.append("Skipped: " + p.skippedPanes.map(readablePane).joined(separator: ", "))
            }
        } else {
            setupLines.append("No Setup Assistant settings found in the PreStage.")
        }
        if let c = p.customizationID { setupLines.append("Enrollment Customization \(c) is shown during setup.") }
        phases.append(FlowPhase(phase: .setupAssistant,
                                summary: p.skipItems.isEmpty ? "Default panes" : "\(p.skippedPanes.count) panes skipped",
                                lines: setupLines, items: [], needsScan: false))

        phases.append(FlowPhase(phase: .mdmEnrollment,
                                summary: p.facts.first { $0.label == "MDM profile removable" }.map { "Removable: \($0.value)" } ?? "Enrolls in MDM",
                                lines: p.facts.map { "\($0.label): \($0.value)" },
                                items: [], needsScan: false))

        var prestageItems: [FlowItem] = p.profileIDs.map { id in
            FlowItem(id: "pp\(id)", name: input.profileNames[id] ?? "Profile \(id)", certainty: .certain,
                     condition: "PreStage profile", identifier: nil)
        }
        prestageItems += p.packageIDs.map { id in
            FlowItem(id: "pk\(id)", name: input.packageNames[id] ?? "Package \(id)", certainty: .certain,
                     condition: "PreStage package", identifier: nil)
        }
        phases.append(FlowPhase(phase: .prestageItems,
                                summary: "\(p.profileIDs.count) profile\(p.profileIDs.count == 1 ? "" : "s") · \(p.packageIDs.count) package\(p.packageIDs.count == 1 ? "" : "s")",
                                lines: ["Installed while Setup Assistant runs."],
                                items: prestageItems, needsScan: false))

        let prestageIDs = Set(p.profileIDs)
        var profileItems: [FlowItem] = []
        var policyItems: [FlowItem] = []
        if let scan = input.scan {
            for profile in scan.profiles where !prestageIDs.contains(profile.id) {
                guard let (certainty, condition) = flowCondition(profile.scope) else { specificOnly += 1; continue }
                profileItems.append(FlowItem(id: "cp\(profile.id)", name: profile.name, certainty: certainty,
                                             condition: condition, identifier: profile.identifier))
            }
            for policy in scan.policies where policy.enabled && policy.enrollmentTrigger {
                guard let (certainty, condition) = flowCondition(policy.scope) else { specificOnly += 1; continue }
                policyItems.append(FlowItem(id: "po\(policy.id)", name: policy.name, certainty: certainty,
                                            condition: condition, identifier: nil))
            }
        }
        profileItems.sort { ($0.certainty, $0.name.lowercased()) < ($1.certainty, $1.name.lowercased()) }
        // Jamf runs enrollment policies in name order.
        policyItems.sort { ($0.certainty, $0.name.lowercased()) < ($1.certainty, $1.name.lowercased()) }
        let certain = profileItems.filter { $0.certainty == .certain }.count
        phases.append(FlowPhase(phase: .profiles,
                                summary: input.scan == nil ? "Needs scan" : "\(certain) certain · \(profileItems.count - certain) conditional",
                                lines: ["Sent after enrollment. Smart group membership is decided after the first inventory, so conditional profiles can arrive later."],
                                items: profileItems, needsScan: input.scan == nil))
        phases.append(FlowPhase(phase: .policies,
                                summary: input.scan == nil ? "Needs scan" : "\(policyItems.count) enrollment polic\(policyItems.count == 1 ? "y" : "ies")",
                                lines: ["Policies with the Enrollment Complete trigger run after the first check-in, in name order."],
                                items: policyItems, needsScan: input.scan == nil))

        let apps: [FlowItem] = input.appInstallers.filter { $0.enabled != false }.map { app in
            let group = app.smartGroupName ?? ""
            let all = ["all computers", "all managed clients", "all managed computers"].contains(group.lowercased())
            let selfService = app.deploymentType?.uppercased() == "SELF_SERVICE"
            return FlowItem(id: "ai\(app.id)", name: app.name,
                            certainty: group.isEmpty || all ? .certain : .conditional,
                            condition: (group.isEmpty ? "No target group" : all ? group : "If in “\(group)”")
                                + (selfService ? " · Self Service" : ""),
                            identifier: nil)
        }.sorted { ($0.certainty, $0.name.lowercased()) < ($1.certainty, $1.name.lowercased()) }
        phases.append(FlowPhase(phase: .apps, summary: "\(apps.count) App Installer\(apps.count == 1 ? "" : "s")",
                                lines: ["App Installers deploy to their target smart group."],
                                items: apps, needsScan: false))

        phases.append(FlowPhase(phase: .inventory,
                                summary: input.checkInMinutes.map { "Check-in every \($0) min" } ?? "After first check-in",
                                lines: ["The first inventory decides smart group membership. Conditional items follow at the next check-in."],
                                items: [], needsScan: false))

        return EnrollmentFlow(prestage: p, phases: phases, specificOnlyCount: specificOnly)
    }

    /// Certainty of an item for a Mac that hasn't enrolled yet, or nil when it only targets named Macs.
    static func flowCondition(_ scope: JamfScope) -> (FlowCertainty, String)? {
        let excludedGroups = scope.exclusions.computerGroups.map { "“\($0.name)”" }
        if scope.allComputers {
            if excludedGroups.isEmpty { return (.certain, "All Computers") }
            return (.conditional, "All Computers, unless in " + excludedGroups.joined(separator: ", "))
        }
        var parts: [String] = []
        if !scope.computerGroups.isEmpty {
            parts.append("If in " + scope.computerGroups.prefix(3).map { "“\($0.name)”" }.joined(separator: " or ")
                         + (scope.computerGroups.count > 3 ? " or \(scope.computerGroups.count - 3) more" : ""))
        }
        if !scope.departments.isEmpty { parts.append("Department " + scope.departments.map(\.name).joined(separator: ", ")) }
        if !scope.buildings.isEmpty { parts.append("Building " + scope.buildings.map(\.name).joined(separator: ", ")) }
        guard !parts.isEmpty else { return nil }
        var text = parts.joined(separator: "; ")
        if !excludedGroups.isEmpty { text += ", unless in " + excludedGroups.joined(separator: ", ") }
        return (.conditional, text)
    }

    /// "TermsOfAddress" → "Terms Of Address", "iCloudStorage" → "iCloud Storage".
    static func readablePane(_ key: String) -> String {
        var out = ""
        for ch in key {
            if ch.isUppercase, let prev = out.last, prev.isLowercase, out != "i" { out.append(" ") }
            out.append(ch)
        }
        // Keep "iCloud" as Apple writes it; capitalise everything else.
        if out.hasPrefix("i"), out.dropFirst().first?.isUppercase == true { return out }
        return out.prefix(1).uppercased() + out.dropFirst()
    }

    // MARK: - Text summary (Dashie)

    static func summary(_ timeline: EnrollmentTimeline, now: Date = Date()) -> String {
        let d = timeline.device
        let df = Date.FormatStyle(date: .abbreviated, time: .shortened)
        var lines: [String] = []
        lines.append("\(d.name) (\(d.serial))")
        var enrolled = "Enrolled: " + (d.enrolledAt.map { $0.formatted(df) } ?? "unknown")
        if let m = d.method { enrolled += " via \(m)" }
        if let prestage = timeline.prestage?.name, prestage != d.method { enrolled += ", PreStage \(prestage)" }
        lines.append(enrolled)
        // Routine inventory polling is left out, as in the app's default view.
        let events = eventsInWindow(timeline.events, enrolledAt: d.enrolledAt, window: 7 * 86_400)
            .filter { $0.phase != .inventory }
        let done = events.filter { $0.status == .completed }.count
        let failed = events.filter { $0.status == .failed }
        let stuck = events.filter { $0.status == .stuck }
        let pending = events.filter { $0.status == .pending }
        lines.append("Since enrollment: \(done) done, \(failed.count) failed, \(stuck.count) stuck, \(pending.count) pending.")
        for e in failed.prefix(4) {
            lines.append("Failed: \(e.title) (\(e.kind))" + (e.detail.map { " — \($0)" } ?? ""))
        }
        for e in stuck.prefix(3) {
            let hours = Int(now.timeIntervalSince(e.date) / 3600)
            let contact = d.lastContact.map { ", last check-in \($0.formatted(df))" } ?? ""
            lines.append("Stuck: \(e.title) (\(e.kind)), pending \(hours) h although the Mac checked in after it was sent\(contact)")
        }
        if let first = events.first(where: { $0.source != .inventory }) , let start = d.enrolledAt {
            lines.append("First MDM activity \(relative(first.date, to: start)) after enrollment.")
        }
        lines.append("Profiles installed: \(timeline.installedProfiles.count).")
        let missing = timeline.sources.filter { !$0.value.isOK }.map(\.key.rawValue).sorted()
        if !missing.isEmpty { lines.append("Not available: " + missing.joined(separator: ", ") + ".") }
        return lines.joined(separator: "\n")
    }
}
