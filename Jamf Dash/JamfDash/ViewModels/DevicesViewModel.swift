import Foundation
import Observation

// MARK: - Bulk action types

struct BulkActionResult: Identifiable, Sendable {
    let id = UUID()
    let deviceName: String
    let serial: String
    let success: Bool
    let message: String
}

struct BulkActionSummary: Identifiable, Sendable {
    let id = UUID()
    let actionName: String
    let results: [BulkActionResult]
    var successCount: Int { results.filter(\.success).count }
    var failureCount: Int { results.filter { !$0.success }.count }
}

// MARK: - ViewModel

@MainActor
@Observable
final class DevicesViewModel {
    private(set) var state: LoadState<[Computer]> = .idle
    var bulkActionSummary: BulkActionSummary? = nil
    private(set) var isBulkRunning: Bool = false

    var staleThresholdDays: Int = (UserDefaults.standard.integer(forKey: "staleThresholdDays").nonZero ?? 30) {
        didSet { UserDefaults.standard.set(staleThresholdDays, forKey: "staleThresholdDays") }
    }

    var searchText = ""

    private let cli: any CLIRunning

    init(cli: any CLIRunning) {
        self.cli = cli
    }

    func load(force: Bool = false) async {
        guard force || state.value == nil else { return }
        guard force || !state.isLoading else { return }
        state = .loading
        do {
            let data = try await cli.run(.computers)
            if isNull(data) {
                state = .loaded([])
                return
            }
            let computers = try Self.decodeComputers(from: data)
            state = .loaded(computers)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Handles both a flat `[Computer]` array and the paginated Pro API wrapper
    /// `{"totalCount": N, "results": [...]}` that some jamf-cli versions return.
    private static func decodeComputers(from data: Data) throws -> [Computer] {
        let decoder = JSONDecoder()
        if let computers = try? decoder.decode([Computer].self, from: data) {
            return computers
        }
        struct PagedResponse: Decodable {
            let results: [Computer]
        }
        return try decoder.decode(PagedResponse.self, from: data).results
    }

    // MARK: - Computed

    private var all: [Computer] { state.value ?? [] }

    /// Publicly readable list of all loaded computers (used by DeviceSearchViewModel).
    var allComputers: [Computer] { all }

    var filtered: [Computer] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(q) ||
            ($0.serialNumber?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    var staleDevices: [Computer] {
        all.filter { ($0.daysSinceContact ?? 0) >= staleThresholdDays }
    }

    var osDistribution: [(version: String, count: Int)] {
        let grouped = Dictionary(grouping: all, by: { $0.osVersion ?? "Unknown" })
        return grouped
            .map { (version: $0.key, count: $0.value.count) }
            .sorted { lhs, rhs in
                lhs.version.compare(rhs.version, options: .numeric) == .orderedDescending
            }
    }

    var totalCount: Int { all.count }
    var managedCount: Int { all.filter { $0.managed == true }.count }

    func devicesForOS(_ version: String) -> [Computer] {
        all.filter { $0.osVersion == version }
    }

    // MARK: - Bulk actions

    func runBulkAction(
        _ makeCommand: @escaping @Sendable (String) -> CLICommand,
        actionName: String,
        devices: [(name: String, serial: String)]
    ) async {
        isBulkRunning = true
        var results: [BulkActionResult] = []
        await withTaskGroup(of: BulkActionResult.self) { group in
            for device in devices {
                let serial = device.serial
                let name   = device.name
                group.addTask {
                    do {
                        _ = try await self.cli.run(makeCommand(serial))
                        return BulkActionResult(deviceName: name, serial: serial, success: true, message: "Success")
                    } catch {
                        return BulkActionResult(deviceName: name, serial: serial, success: false, message: error.localizedDescription)
                    }
                }
            }
            for await result in group { results.append(result) }
        }
        results.sort { $0.deviceName < $1.deviceName }
        isBulkRunning = false
        bulkActionSummary = BulkActionSummary(actionName: actionName, results: results)
    }

    func clearBulkActionSummary() { bulkActionSummary = nil }

    private func isNull(_ data: Data) -> Bool {
        (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == "null"
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
