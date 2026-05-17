import Foundation
import OSLog
import Observation

// MARK: - Action result

enum DeviceActionResult: Equatable {
    case success(String)
    case failure(String)
}

@MainActor
@Observable
final class DeviceSearchViewModel {
    private static let logger = Logger(subsystem: "com.jamfdash", category: "DeviceSearchViewModel")

    var searchText = ""
    var selectedDevice: Computer? = nil
    private(set) var detailState: LoadState<ComputerDetail> = .idle

    // Action state
    private(set) var isRunningAction = false
    private(set) var runningActionName: String? = nil
    private(set) var lastActionResult: DeviceActionResult? = nil

    private let cli: any CLIRunning
    private let devicesVM: DevicesViewModel

    init(cli: any CLIRunning, devicesVM: DevicesViewModel) {
        self.cli = cli
        self.devicesVM = devicesVM
    }

    // MARK: - Local quick results (from cached device list)

    var localResults: [Computer] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return devicesVM.allComputers.filter {
            $0.name.localizedCaseInsensitiveContains(q) ||
            ($0.serialNumber?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    // MARK: - Detail fetch

    func selectDevice(_ device: Computer) {
        selectedDevice = device
        // Prefer ID-based lookup (always works); fall back to serial filter
        Task { await fetchDetail(id: device.id, serial: device.serialNumber) }
    }

    /// Primary entry point: use numeric ID when available, otherwise fall back to serial filter.
    func fetchDetail(id: String? = nil, serial: String? = nil) async {
        guard id != nil || serial != nil else {
            detailState = .idle
            return
        }
        detailState = .loading

        // Try by ID first (more reliable; works even if hardware section is empty)
        if let deviceId = id, !deviceId.isEmpty {
            if await tryFetchById(deviceId) { return }
        }
        // Fall back to RSQL serial filter
        if let s = serial, !s.isEmpty {
            await tryFetchBySerial(s)
        } else {
            detailState = .failed("Could not retrieve device details.")
        }
    }

    /// Direct serial search (used when user types a serial and presses Return).
    func fetchDetail(serial: String) async {
        await fetchDetail(id: nil, serial: serial)
    }

    private func tryFetchById(_ id: String) async -> Bool {
        do {
            let data = try await cli.run(.computerDetailById(id: id))
            return decode(data: data, paged: false)
        } catch {
            return false
        }
    }

    private func tryFetchBySerial(_ serial: String) async {
        do {
            let data = try await cli.run(.computerDetail(serial: serial))
            if !decode(data: data, paged: true) {
                detailState = .failed("Device not found — verify the serial number and profile permissions.")
            }
        } catch {
            Self.logger.error("Failed to fetch device detail by serial (\(serial)): \(error)")
            detailState = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    /// Decodes `data` into a `ComputerDetail`. Returns `true` on success.
    @discardableResult
    private func decode(data: Data, paged: Bool) -> Bool {
        let trimmed = (String(data: data, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "null" else { return false }

        let decoder = JSONDecoder()
        // Paged: {"totalCount": N, "results": [...]}
        struct PagedResponse: Decodable { let results: [ComputerDetail] }
        if paged, let paged = try? decoder.decode(PagedResponse.self, from: data) {
            guard let detail = paged.results.first else { return false }
            detailState = .loaded(detail)
            return true
        }
        // Single object
        if let detail = try? decoder.decode(ComputerDetail.self, from: data) {
            detailState = .loaded(detail)
            return true
        }
        return false
    }

    // MARK: - Device actions

    func runAction(_ command: CLICommand, name: String) async {
        guard !isRunningAction else { return }
        isRunningAction = true
        runningActionName = name
        lastActionResult = nil
        do {
            _ = try await cli.run(command)
            lastActionResult = .success("\(name) completed successfully.")
        } catch {
            lastActionResult = .failure(error.localizedDescription)
        }
        isRunningAction = false
        runningActionName = nil
    }

    func dismissActionResult() {
        lastActionResult = nil
    }

    // MARK: - Navigation

    func clearSelection() {
        selectedDevice = nil
        detailState = .idle
        lastActionResult = nil
    }

    func clearSearch() {
        searchText = ""
        clearSelection()
    }
}
