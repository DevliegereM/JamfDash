import Foundation
import Observation
import OSLog

/// Extension Attributes section: the attribute lists and, after a scan, where each one is used.
/// Everything is kept in memory for the current instance only.
@MainActor
@Observable
final class EADependencyViewModel {
    private static let logger = Logger(subsystem: "com.jamfdash", category: "EADependencies")

    enum ScanState: Equatable {
        case notScanned
        case scanning(DependencyScanProgress)
        case scanned(Date)
    }

    enum UsageFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case used = "In Use"
        case unused = "Not Used"
        case attention = "Needs Attention"
        var id: String { rawValue }
    }

    private(set) var computerAttributes: LoadState<[ExtensionAttribute]> = .idle
    private(set) var mobileAttributes: LoadState<[ExtensionAttribute]> = .idle
    private(set) var scanState: ScanState = .notScanned
    private(set) var graph: EADependencyGraph?

    var kind: EAKind = .computer
    var filter: UsageFilter = .all
    var searchText = ""
    var selectedID: String?

    private let repository: EADependencyRepository
    private var scanTask: Task<Void, Never>?

    init(cli: any CLIRunning) {
        self.repository = EADependencyRepository(cli: cli)
    }

    // MARK: - Loading

    func attributes(_ kind: EAKind) -> LoadState<[ExtensionAttribute]> {
        kind == .computer ? computerAttributes : mobileAttributes
    }

    func loadAttributes(force: Bool = false) async {
        let kind = self.kind
        let state = attributes(kind)
        guard force || (state.value == nil && !state.isLoading) else { return }
        set(.loading, for: kind)
        do {
            set(.loaded(try await repository.attributes(kind)), for: kind)
        } catch {
            Self.logger.error("Failed to load \(kind.rawValue, privacy: .public) extension attributes: \(ErrorMessageFormatter.logSummary(for: error), privacy: .public)")
            set(.failed(ErrorMessageFormatter.message(for: error)), for: kind)
        }
    }

    private func set(_ state: LoadState<[ExtensionAttribute]>, for kind: EAKind) {
        if kind == .computer { computerAttributes = state } else { mobileAttributes = state }
    }

    // MARK: - Scan

    var isScanning: Bool {
        if case .scanning = scanState { return true }
        return false
    }

    func scan() {
        guard !isScanning else { return }
        scanState = .scanning(DependencyScanProgress(step: "Starting", completed: 0, total: 0))
        let repository = self.repository
        let onProgress: @Sendable (DependencyScanProgress) -> Void = { [weak self] progress in
            Task { @MainActor in
                guard let self, self.isScanning else { return }
                self.scanState = .scanning(progress)
            }
        }
        scanTask = Task { [weak self] in
            let inventory = await repository.scan(progress: onProgress)
            guard let self, !Task.isCancelled else { return }
            let graph = await Task.detached(priority: .userInitiated) { EADependencyGraph(inventory: inventory) }.value
            guard !Task.isCancelled else { return }
            self.graph = graph
            // The scan read the attribute lists too; show those.
            if !inventory.failures.contains(where: { $0.type == nil && $0.kind == .computer }) {
                self.computerAttributes = .loaded(inventory.computerAttributes)
            }
            if !inventory.failures.contains(where: { $0.type == nil && $0.kind == .mobileDevice }) {
                self.mobileAttributes = .loaded(inventory.mobileAttributes)
            }
            self.scanState = .scanned(inventory.scannedAt)
            self.scanTask = nil
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        scanState = graph.map { .scanned($0.inventory.scannedAt) } ?? .notScanned
    }

    /// Another Jamf instance: forget everything.
    func reset() {
        scanTask?.cancel()
        scanTask = nil
        graph = nil
        scanState = .notScanned
        computerAttributes = .idle
        mobileAttributes = .idle
        selectedID = nil
        searchText = ""
        filter = .all
    }

    // MARK: - Results

    func report(for attribute: ExtensionAttribute) -> EADependencyReport? {
        graph?.report(for: attribute, kind: kind)
    }

    var failures: [DependencyScanFailure] {
        graph?.inventory.failures.filter { $0.kind == kind } ?? []
    }

    /// The current kind's attributes after search and filter.
    func visibleAttributes(_ all: [ExtensionAttribute]) -> [ExtensionAttribute] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return all.filter { attribute in
            if !query.isEmpty,
               !attribute.name.localizedCaseInsensitiveContains(query),
               !(attribute.description ?? "").localizedCaseInsensitiveContains(query) {
                return false
            }
            guard filter != .all else { return true }
            guard let report = report(for: attribute) else { return false }
            switch filter {
            case .all:       return true
            case .used:      return !report.isUnused
            case .unused:    return report.isUnused
            case .attention: return report.hasWarnings
            }
        }
    }

    /// Counts for the summary above the table, once scanned.
    func summary(_ all: [ExtensionAttribute]) -> (used: Int, unused: Int, attention: Int)? {
        guard graph != nil else { return nil }
        let reports = all.compactMap { report(for: $0) }
        return (reports.filter { !$0.isUnused }.count,
                reports.filter(\.isUnused).count,
                reports.filter(\.hasWarnings).count)
    }
}
