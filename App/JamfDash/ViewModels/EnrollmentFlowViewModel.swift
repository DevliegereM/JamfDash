import Foundation
import Observation
import OSLog

enum EnrollmentTab: String, CaseIterable, Identifiable, Sendable {
    case recent, flow, setup
    var id: String { rawValue }
    var title: String {
        switch self {
        case .recent: return "Recent Enrollments"
        case .flow:   return "Flow"
        case .setup:  return "Tokens & PreStages"
        }
    }
}

enum TimelineWindow: String, CaseIterable, Identifiable, Sendable {
    case firstDay, firstWeek, all
    var id: String { rawValue }
    var title: String {
        switch self {
        case .firstDay:  return "First 24 hours"
        case .firstWeek: return "First 7 days"
        case .all:       return "Since enrollment"
        }
    }
    var seconds: TimeInterval? {
        switch self {
        case .firstDay:  return 86_400
        case .firstWeek: return 7 * 86_400
        case .all:       return nil
        }
    }
}

/// State for the Enrollment section. Everything is kept in memory for this session only:
/// nothing is written to disk or to preferences, and `reset()` clears it all.
@MainActor
@Observable
final class EnrollmentFlowViewModel {
    private static let logger = Logger(subsystem: "com.jamfdash", category: "EnrollmentFlow")
    private static let timelineCacheLifetime: TimeInterval = 5 * 60

    var tab: EnrollmentTab = .recent

    // Recent Enrollments
    var windowDays = 7 {
        didSet { if oldValue != windowDays { Task { await loadRecent(force: true) } } }
    }
    private(set) var recentState: LoadState<[RecentEnrollment]> = .idle
    var searchText = ""
    private(set) var selectedSerial: String?
    /// Status per Mac in the list (serial → badge), filled in the background for the first Macs.
    private(set) var badges: [String: RecentBadge] = [:]

    struct RecentBadge: Sendable, Hashable {
        let problems: Int      // failed + stuck
        let pending: Int
    }

    /// Settings → Enrollment: the Setup Manager profile to use (0 or missing = automatic).
    static let setupManagerProfileKey = "jamfDash.enrollment.setupManagerProfileID"
    private(set) var timelineState: LoadState<EnrollmentTimeline> = .idle
    var timelineWindow: TimelineWindow = .firstDay
    /// Routine inventory polling (Device Information, Profile List, …) is hidden by default.
    var showRoutineCommands = false
    private(set) var actionMessage: String?

    // Flow
    private(set) var prestagesState: LoadState<[ComputerPrestage]> = .idle
    private(set) var selectedPrestageID: String?
    private(set) var flowState: LoadState<EnrollmentFlow> = .idle

    // Scope scan (shared by the flow and the per-Mac comparison)
    enum ScanState: Sendable {
        case idle, scanning(done: Int, total: Int), finished(ScopeScanResult), failed(String)
    }
    private(set) var scanState: ScanState = .idle
    var scan: ScopeScanResult? { if case .finished(let r) = scanState { return r }; return nil }
    var isScanning: Bool { if case .scanning = scanState { return true }; return false }

    private let repository: EnrollmentRepository
    private var timelineCache: [String: EnrollmentTimeline] = [:]
    private var timelineTask: Task<Void, Never>?
    private var badgeTask: Task<Void, Never>?
    private var flowTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var flowInputs: (tokens: [String: String], profiles: [Int: String], packages: [Int: String],
                             checkIn: Int?, apps: [AppInstallerDeployment])?

    init(cli: any CLIRunning) {
        repository = EnrollmentRepository(cli: cli)
    }

    // MARK: - Derived

    var filteredRecent: [RecentEnrollment] {
        let all = recentState.value ?? []
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(q) || ($0.serial ?? "").localizedCaseInsensitiveContains(q)
                || ($0.method ?? "").localizedCaseInsensitiveContains(q)
        }
    }

    /// Timeline events in the chosen window.
    var visibleEvents: [EnrollmentEvent] {
        guard let t = timelineState.value else { return [] }
        return EnrollmentAnalyzer.eventsInWindow(t.events, enrolledAt: t.device.enrolledAt, window: timelineWindow.seconds)
            .filter { showRoutineCommands || $0.phase != .inventory }
    }

    var attention: [EnrollmentEvent] { EnrollmentAnalyzer.attention(visibleEvents) }

    var profileRows: [ProfileRow] {
        guard let t = timelineState.value else { return [] }
        return EnrollmentAnalyzer.profileRows(timeline: t, events: t.events, scan: scan)
    }

    var policyRows: [PolicyRow] {
        guard let t = timelineState.value else { return [] }
        let events = EnrollmentAnalyzer.eventsInWindow(t.events, enrolledAt: t.device.enrolledAt, window: nil)
        return EnrollmentAnalyzer.policyRows(timeline: t, events: events, scan: scan)
    }

    var appEvents: [EnrollmentEvent] { visibleEvents.filter { $0.phase == .apps || $0.phase == .prestageItems } }

    /// Explains why early history may be missing, when the Mac enrolled before the retention period.
    var retentionNote: String? {
        guard let t = timelineState.value, let r = t.historyRetention, let enrolled = t.device.enrolledAt else { return nil }
        guard Date().timeIntervalSince(enrolled) > Double(r.days) * 86_400 else { return nil }
        return "Jamf Pro keeps \(r.name.lowercased()) for \(r.label) (Log Flushing). This Mac enrolled earlier, so the first events may be gone."
    }

    // MARK: - Recent enrollments

    /// The selected row in the list, by Jamf computer ID (serials can be missing).
    var selectedRecentID: String? {
        guard let serial = selectedSerial else { return nil }
        return recentState.value?.first { $0.serial?.caseInsensitiveCompare(serial) == .orderedSame }?.id
    }

    func selectRecent(id: String?) {
        guard let id, let mac = recentState.value?.first(where: { $0.id == id }) else { return }
        guard let serial = mac.serial else {
            timelineTask?.cancel()
            selectedSerial = nil
            timelineState = .failed("\(mac.name) has no serial number in Jamf Pro, so its history can't be looked up.")
            return
        }
        select(serial: serial)
    }

    func loadRecent(force: Bool = false) async {
        guard force || recentState.value == nil, !recentState.isLoading else { return }
        recentState = .loading
        do {
            let list = try await repository.recentEnrollments(withinDays: windowDays)
            recentState = .loaded(list)
            let stillListed = list.contains { $0.serial?.caseInsensitiveCompare(selectedSerial ?? "") == .orderedSame }
            if !stillListed, timelineState.value == nil || selectedSerial == nil {
                if let first = list.first?.serial { select(serial: first) }
                else { timelineTask?.cancel(); selectedSerial = nil; timelineState = .idle }
            }
            prefetchBadges(list)
        } catch {
            Self.logger.error("Recent enrollments failed: \(ErrorMessageFormatter.logSummary(for: error), privacy: .public) \(error.localizedDescription, privacy: .private)")
            recentState = .failed(EnrollmentRepository.message(for: error))
        }
    }

    // MARK: - Timeline

    /// Loads the timelines of the first Macs in the background (three at a time) for the
    /// list's status badges. Results go into the same in-memory cache as a normal selection.
    private func prefetchBadges(_ list: [RecentEnrollment]) {
        badgeTask?.cancel()
        for mac in list { if let s = mac.serial, let t = timelineCache[s] { badges[s] = badge(for: t) } }
        let serials = list.prefix(12).compactMap(\.serial).filter { timelineCache[$0] == nil }
        guard !serials.isEmpty else { return }
        let policyIDs = enrollmentPolicyIDs, smPolicies = setupManagerPolicies
        badgeTask = Task { [repository] in
            await withTaskGroup(of: (String, EnrollmentTimeline?).self) { group in
                var queue = serials[...]
                func next() {
                    guard let serial = queue.popFirst() else { return }
                    group.addTask {
                        (serial, try? await repository.timeline(serial: serial, enrollmentPolicyIDs: policyIDs,
                                                                setupManagerPolicies: smPolicies))
                    }
                }
                for _ in 0..<3 { next() }
                for await (serial, timeline) in group {
                    if Task.isCancelled { group.cancelAll(); return }
                    if let timeline {
                        self.timelineCache[serial] = timeline
                        self.badges[serial] = self.badge(for: timeline)
                    }
                    next()
                }
            }
        }
    }

    private func badge(for t: EnrollmentTimeline) -> RecentBadge {
        let events = EnrollmentAnalyzer.eventsInWindow(t.events, enrolledAt: t.device.enrolledAt, window: 7 * 86_400)
            .filter { $0.phase != .inventory }
        return RecentBadge(problems: events.filter { $0.status == .failed || $0.status == .stuck }.count,
                           pending: events.filter { $0.status == .pending }.count)
    }

    func select(serial: String?) {
        guard serial != selectedSerial || timelineState.value == nil else { return }
        selectedSerial = serial
        actionMessage = nil
        timelineTask?.cancel()
        guard let serial else { timelineState = .idle; return }
        if let cached = timelineCache[serial], Date().timeIntervalSince(cached.loadedAt) < Self.timelineCacheLifetime {
            timelineState = .loaded(cached)
            return
        }
        timelineState = .loading
        let policyIDs = enrollmentPolicyIDs, smPolicies = setupManagerPolicies
        timelineTask = Task { [repository] in
            do {
                let timeline = try await repository.timeline(serial: serial, enrollmentPolicyIDs: policyIDs,
                                                             setupManagerPolicies: smPolicies)
                guard !Task.isCancelled, self.selectedSerial == serial else { return }
                self.timelineCache[serial] = timeline
                self.badges[serial] = self.badge(for: timeline)
                self.timelineState = .loaded(timeline)
            } catch {
                guard !Task.isCancelled, self.selectedSerial == serial else { return }
                self.timelineState = .failed(EnrollmentRepository.message(for: error))
            }
        }
    }

    func reloadTimeline() {
        guard let serial = selectedSerial else { return }
        timelineCache[serial] = nil
        selectedSerial = nil
        select(serial: serial)
    }

    /// Opens the timeline for a Mac from elsewhere in the app (Device Lookup).
    func showTimeline(serial: String) {
        tab = .recent
        select(serial: serial)
    }

    private var enrollmentPolicyIDs: Set<Int> {
        Set((scan?.policies ?? []).filter { $0.enabled && $0.enrollmentTrigger }.map(\.id))
    }

    // MARK: - Setup Manager

    var preferredSetupManagerID: Int? {
        let id = UserDefaults.standard.integer(forKey: Self.setupManagerProfileKey)
        return id > 0 ? id : nil
    }

    /// Profiles that configure Setup Manager (known after the scope scan).
    var setupManagerCandidates: [ScopedProfile] { EnrollmentAnalyzer.setupManagerCandidates(scan) }

    /// Policies triggered by any Setup Manager profile's steps, so their logs show as Setup Manager.
    private var setupManagerPolicies: [Int: String] {
        var out: [Int: String] = [:]
        for p in setupManagerCandidates {
            let source = SetupManagerSource(profileID: p.id, profileName: p.name, config: p.setupManager!, reason: "")
            out.merge(EnrollmentAnalyzer.setupManagerPolicyIDs(source, scan: scan)) { a, _ in a }
        }
        return out
    }

    /// The Setup Manager configuration for the selected Mac.
    var timelineSetupManager: SetupManagerSource? {
        guard let t = timelineState.value else { return nil }
        let installed = Set(t.installedProfiles.compactMap(\.jamfID))
        return EnrollmentAnalyzer.setupManagerSource(scan: scan, preferredProfileID: preferredSetupManagerID,
                                                     prestage: t.prestage, installedProfileIDs: installed)
    }

    var setupManagerRows: [SetupManagerStepRow] {
        guard let source = timelineSetupManager, let t = timelineState.value else { return [] }
        let events = EnrollmentAnalyzer.eventsInWindow(t.events, enrolledAt: t.device.enrolledAt, window: nil)
        return EnrollmentAnalyzer.setupManagerRows(source, scan: scan, events: events)
    }

    /// The Setup Manager configuration for the PreStage shown in the Flow tab.
    var flowSetupManager: SetupManagerSource? {
        guard let flow = flowState.value else { return nil }
        return EnrollmentAnalyzer.setupManagerSource(scan: scan, preferredProfileID: preferredSetupManagerID,
                                                     prestage: flow.prestage)
    }

    var flowSetupManagerRows: [SetupManagerStepRow] {
        flowSetupManager.map { EnrollmentAnalyzer.setupManagerRows($0, scan: scan, events: nil) } ?? []
    }

    /// Call after the Setup Manager choice changes in Settings.
    func setupManagerPreferenceChanged() {
        refreshFlowFromScan()
    }

    /// Sends a blank push so a stuck Mac checks in; the existing safe device action.
    func blankPush() async {
        guard let serial = timelineState.value?.device.serial else { return }
        do {
            _ = try await repository.cli.runConfirmed(.blankPush(serial: serial))
            actionMessage = "Blank push sent to \(serial). Reload the timeline after the Mac checks in."
        } catch {
            actionMessage = "Blank push failed: \(EnrollmentRepository.message(for: error))"
        }
    }

    // MARK: - Flow

    func loadPrestages(force: Bool = false) async {
        guard force || prestagesState.value == nil, !prestagesState.isLoading else { return }
        prestagesState = .loading
        do {
            let list = try await repository.prestages()
            prestagesState = .loaded(list)
            if selectedPrestageID == nil, let first = list.first { selectPrestage(first.id) }
        } catch {
            prestagesState = .failed(EnrollmentRepository.message(for: error))
        }
    }

    func selectPrestage(_ id: String?) {
        guard id != selectedPrestageID || flowState.value == nil else { return }
        selectedPrestageID = id
        flowTask?.cancel()
        guard let id else { flowState = .idle; return }
        flowState = .loading
        flowTask = Task { [repository] in
            do {
                guard let detail = try await repository.prestageDetail(id: id) else {
                    throw CLIError.decodingFailed("This PreStage's details couldn't be read.")
                }
                let inputs = await self.loadFlowInputs()
                guard !Task.isCancelled, self.selectedPrestageID == id else { return }
                self.flowState = .loaded(self.makeFlow(detail, inputs: inputs))
            } catch {
                guard !Task.isCancelled, self.selectedPrestageID == id else { return }
                self.flowState = .failed(EnrollmentRepository.message(for: error))
            }
        }
    }

    private func loadFlowInputs() async -> (tokens: [String: String], profiles: [Int: String], packages: [Int: String],
                                             checkIn: Int?, apps: [AppInstallerDeployment]) {
        if let flowInputs { return flowInputs }
        async let tokens = repository.depTokenNames()
        async let profiles = repository.namedList(.configProfiles)
        async let packages = repository.namedList(.packages)
        async let checkIn = repository.checkInMinutes()
        async let apps = repository.appInstallers()
        let inputs = await (tokens: tokens, profiles: profiles, packages: packages, checkIn: checkIn, apps: apps)
        flowInputs = inputs
        return inputs
    }

    private func makeFlow(_ detail: PrestageDetail,
                          inputs: (tokens: [String: String], profiles: [Int: String], packages: [Int: String],
                                   checkIn: Int?, apps: [AppInstallerDeployment])) -> EnrollmentFlow {
        EnrollmentAnalyzer.buildFlow(.init(
            prestage: detail,
            adeTokenName: detail.adeInstanceID.flatMap { inputs.tokens[$0] },
            profileNames: inputs.profiles, packageNames: inputs.packages,
            checkInMinutes: inputs.checkIn, scan: scan, appInstallers: inputs.apps,
            setupManager: EnrollmentAnalyzer.setupManagerSource(scan: scan, preferredProfileID: preferredSetupManagerID,
                                                                prestage: detail)))
    }

    /// Rebuilds the flow after the scan finishes, without new calls.
    private func refreshFlowFromScan() {
        guard let flow = flowState.value, let inputs = flowInputs else { return }
        flowState = .loaded(makeFlow(flow.prestage, inputs: inputs))
    }

    // MARK: - Scope scan

    func startScan() {
        guard !isScanning else { return }
        scanState = .scanning(done: 0, total: 0)
        scanTask = Task { [repository] in
            do {
                let result = try await repository.scanScopes { done, total in
                    await MainActor.run { self.scanState = .scanning(done: done, total: total) }
                }
                self.scanState = .finished(result)
                self.refreshFlowFromScan()
                // Policy log entries can now be marked as enrollment and Setup Manager policies.
                self.timelineCache.removeAll()
                self.badges.removeAll()
                if let list = self.recentState.value { self.prefetchBadges(list) }
                if let serial = self.selectedSerial, self.timelineState.value != nil {
                    self.selectedSerial = nil
                    self.select(serial: serial)
                }
            } catch is CancellationError {
                self.scanState = .idle
            } catch {
                self.scanState = .failed(EnrollmentRepository.message(for: error))
            }
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        scanState = .idle
    }

    // MARK: - Refresh / reset

    func refresh() async {
        switch tab {
        case .recent:
            timelineCache.removeAll()
            badges.removeAll()
            await repository.cache.removeAll()
            await loadRecent(force: true)
            reloadTimeline()
        case .flow:
            flowInputs = nil
            await repository.cache.removeAll()
            await loadPrestages(force: true)
            if let id = selectedPrestageID { selectedPrestageID = nil; selectPrestage(id) }
        case .setup:
            break
        }
    }

    /// Forgets everything, e.g. after switching to another Jamf instance.
    func reset() {
        timelineTask?.cancel(); flowTask?.cancel(); scanTask?.cancel(); badgeTask?.cancel()
        badges.removeAll()
        Task { [repository] in await repository.cache.removeAll() }
        recentState = .idle
        selectedSerial = nil
        timelineState = .idle
        timelineCache.removeAll()
        prestagesState = .idle
        selectedPrestageID = nil
        flowState = .idle
        flowInputs = nil
        scanState = .idle
        actionMessage = nil
        searchText = ""
    }
}
