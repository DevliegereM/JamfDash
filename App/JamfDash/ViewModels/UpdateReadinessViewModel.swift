import Foundation
import OSLog
import Observation

enum ReadinessFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All Macs"
    case os27 = "macOS 27+"
    case issues = "With Issues"
    case noPlan = "No DDM Plan"
    case legacyProfiles = "Legacy Deferrals"

    var id: String { rawValue }
}

@MainActor
@Observable
final class UpdateReadinessViewModel {
    private static let logger = Logger(subsystem: "com.jamfdash", category: "UpdateReadinessViewModel")

    private(set) var rowsState: LoadState<[UpdateReadinessRow]> = .idle
    /// Non-fatal notes (e.g. plans endpoint unavailable) shown above the table.
    private(set) var notes: [String] = []
    var filter: ReadinessFilter = .issues
    var searchText = ""

    private let cli: any CLIRunning
    private let scanner: ProfileDeprecationScanner

    init(cli: any CLIRunning, scanner: ProfileDeprecationScanner) {
        self.cli = cli
        self.scanner = scanner
    }

    func load(force: Bool = false) async {
        guard force || rowsState.value == nil else { return }
        guard !rowsState.isLoading else { return }
        rowsState = .loading
        notes = []

        let cli = self.cli
        let scanner = self.scanner
        async let computersData = cli.run(.computersUpdateReadiness)
        async let plansResult = Self.capture { try await cli.run(.softwareUpdatePlans) }
        async let statusesResult = Self.capture { try await cli.run(.softwareUpdateStatuses) }
        async let profilesResult = Self.capture { try await scanner.scan(force: force) }

        do {
            let computers = JamfListDecoder.decode(ReadinessComputer.self, from: try await computersData) ?? []
            var plans: [ManagedUpdatePlan] = []
            switch await plansResult {
            case .success(let data): plans = JamfListDecoder.decode(ManagedUpdatePlan.self, from: data) ?? []
            case .failure(let error):
                notes.append("Managed software update plans unavailable: \(ErrorMessageFormatter.message(for: error))")
            }
            var statuses: [ManagedUpdateStatus] = []
            switch await statusesResult {
            case .success(let data): statuses = JamfListDecoder.decode(ManagedUpdateStatus.self, from: data) ?? []
            case .failure(let error):
                notes.append("Managed software update statuses unavailable: \(ErrorMessageFormatter.message(for: error))")
            }
            var legacy: [ScannedProfile]? = nil
            switch await profilesResult {
            case .success(let profiles): legacy = DeprecationAuditRules.legacySoftwareUpdateProfiles(in: profiles)
            case .failure(let error):
                notes.append("Couldn't scan configuration profiles for deferral restrictions: \(ErrorMessageFormatter.message(for: error))")
            }
            let rows = UpdateReadinessEvaluator.evaluate(computers: computers, plans: plans,
                                                         statuses: statuses, legacyProfiles: legacy)
                .sorted { ($0.level, $0.computer.osMajor ?? 0) > ($1.level, $1.computer.osMajor ?? 0) }
            Self.logger.debug("Evaluated update readiness for \(rows.count) computers")
            rowsState = .loaded(rows)
        } catch {
            Self.logger.error("Update readiness load failed: \(error)")
            rowsState = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    private nonisolated static func capture<T: Sendable>(_ body: @Sendable () async throws -> T) async -> Result<T, any Error> {
        do { return .success(try await body()) } catch { return .failure(error) }
    }

    // MARK: - Derived

    var filteredRows: [UpdateReadinessRow] {
        let rows = rowsState.value ?? []
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return rows.filter { row in
            switch filter {
            case .all: break
            case .os27: if !row.isOS27OrLater { return false }
            case .issues: if row.level == .ready { return false }
            case .noPlan: if row.plan != nil { return false }
            case .legacyProfiles: if row.legacyProfileNames.isEmpty { return false }
            }
            guard !q.isEmpty else { return true }
            return row.computer.name.lowercased().contains(q)
                || (row.computer.serialNumber?.lowercased().contains(q) ?? false)
        }
    }

    var os27Count: Int { (rowsState.value ?? []).filter(\.isOS27OrLater).count }
    func count(_ level: ReadinessLevel) -> Int { (rowsState.value ?? []).filter { $0.level == level }.count }
}
