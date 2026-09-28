import Foundation
import OSLog
import Observation

// MARK: - DDMDeclarationStat

struct DDMDeclarationStat: Identifiable, Sendable {
    var id: String { declaration }
    let declaration: String
    let succeededCount: Int
    let failedCount: Int
    let pendingCount: Int
    var totalCount: Int { succeededCount + failedCount + pendingCount }

    private enum CodingKeys: String, CodingKey {
        case declaration, identifier, name
        case succeededCount, succeeded_count, succeeded
        case failedCount, failed_count, failed
        case pendingCount, pending_count, pending
    }
}

extension DDMDeclarationStat: Decodable {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        declaration   = (try? c.decode(String.self, forKey: .declaration))
                     ?? (try? c.decode(String.self, forKey: .identifier))
                     ?? (try? c.decode(String.self, forKey: .name))
                     ?? "Unknown"
        succeededCount = (try? c.decode(Int.self, forKey: .succeededCount))
                      ?? (try? c.decode(Int.self, forKey: .succeeded_count))
                      ?? (try? c.decode(Int.self, forKey: .succeeded))
                      ?? 0
        failedCount    = (try? c.decode(Int.self, forKey: .failedCount))
                      ?? (try? c.decode(Int.self, forKey: .failed_count))
                      ?? (try? c.decode(Int.self, forKey: .failed))
                      ?? 0
        pendingCount   = (try? c.decode(Int.self, forKey: .pendingCount))
                      ?? (try? c.decode(Int.self, forKey: .pending_count))
                      ?? (try? c.decode(Int.self, forKey: .pending))
                      ?? 0
    }
}

// MARK: - Per-device status row (fleet status-items scan)

struct DDMDeviceStatusRow: Identifiable, Sendable, Hashable {
    let device: DDMDevice
    let summary: DDMDeviceStatusSummary?
    let error: String?
    var id: String { device.id }
}

enum DDMStatusFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All Devices"
    case reportsOS27 = "Reports OS 27 Items"
    case lockdownMode = "Lockdown Mode On"
    case awaitingConfiguration = "Awaiting Configuration"
    case updateFailed = "Update Failed"
    case updatePending = "Update Pending"
    case hardwareIssue = "Hardware Issue"

    var id: String { rawValue }

    func matches(_ row: DDMDeviceStatusRow) -> Bool {
        guard let s = row.summary else { return self == .all }
        switch self {
        case .all:                   return true
        case .reportsOS27:           return s.reportsOS27Items
        case .lockdownMode:          return s.lockdownModeEnabled == true
        case .awaitingConfiguration: return s.isAwaitingConfiguration == true
        case .updateFailed:          return s.softwareUpdate.isFailed
        case .updatePending:         return s.softwareUpdate.hasPendingUpdate
        case .hardwareIssue:         return !s.unhealthyComponents.isEmpty
        }
    }
}

@MainActor
@Observable
final class DDMMonitorViewModel {
    private static let logger = Logger(subsystem: "com.jamfdash", category: "DDMMonitorViewModel")
    private(set) var devicesState: LoadState<[DDMDevice]> = .idle
    private(set) var statusItemsState: LoadState<[DDMStatusItem]> = .idle
    var selectedDeviceId: String? = nil
    private(set) var fleetStatusState: LoadState<[DDMDeclarationStat]> = .idle

    /// Set when jamf-cli exits 15 (endpoint deprecated / not supported) with no usable output,
    /// so the UI can say so instead of showing an empty list.
    private(set) var statusItemsEndpointUnsupported = false
    private(set) var fleetStatusEndpointUnsupported = false

    /// Total computers in inventory (before filtering to devices with a management ID).
    private(set) var inventoryDeviceCount: Int? = nil

    /// Status items for every DDM device (N CLI calls, loaded on demand).
    private(set) var deviceStatusState: LoadState<[DDMDeviceStatusRow]> = .idle
    private(set) var deviceStatusProgress: (done: Int, total: Int) = (0, 0)
    var statusFilter: DDMStatusFilter = .all

    /// macOS 27 software update readiness (shares the profile scan with the Audit dashboard).
    let readiness: UpdateReadinessViewModel

    private let cli: any CLIRunning
    private static let statusScanConcurrency = 6
    /// The status scan makes one jamf-cli call per device, so large fleets are capped.
    static let statusScanLimit = 500
    /// Devices left out of the last status scan because of `statusScanLimit`.
    private(set) var statusScanSkipped = 0

    init(cli: any CLIRunning, deprecationScanner: ProfileDeprecationScanner? = nil) {
        self.cli = cli
        self.readiness = UpdateReadinessViewModel(
            cli: cli,
            scanner: deprecationScanner ?? ProfileDeprecationScanner(cli: cli)
        )
    }

    /// Typed summary of the selected device's status items.
    var selectedSummary: DDMDeviceStatusSummary? {
        statusItemsState.value.map(DDMDeviceStatusSummary.init(items:))
    }

    /// Declaration coverage from the device list + fleet declaration report (whatever is loaded).
    var coverage: DDMCoverageSummary? {
        let stats = fleetStatusState.value ?? []
        let devices = devicesState.value ?? []
        guard !stats.isEmpty || !devices.isEmpty else { return nil }
        return DDMCoverageSummary(
            inventoryDevices: inventoryDeviceCount ?? devices.count,
            ddmEnabledDevices: devices.filter { $0.ddmEnabled ?? true }.count,
            declarationCount: stats.count,
            succeeded: stats.reduce(0) { $0 + $1.succeededCount },
            failed: stats.reduce(0) { $0 + $1.failedCount },
            pending: stats.reduce(0) { $0 + $1.pendingCount }
        )
    }

    var filteredDeviceStatusRows: [DDMDeviceStatusRow] {
        (deviceStatusState.value ?? []).filter(statusFilter.matches)
    }

    // MARK: - Loading

    func load(force: Bool = false) async {
        guard force || devicesState.value == nil else { return }
        guard force || !devicesState.isLoading else { return }
        Self.logger.debug("Loading DDM devices")
        devicesState = .loading
        statusItemsState = .idle
        selectedDeviceId = nil
        do {
            let data = try await cli.run(.ddmComputers)
            let (devices, total) = try Self.decodeDevices(from: data)
            Self.logger.debug("Loaded \(devices.count) DDM devices")
            inventoryDeviceCount = total
            devicesState = .loaded(devices)
        } catch {
            Self.logger.error("Failed to load DDM devices: \(error)")
            devicesState = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    func loadStatusItems(for deviceId: String) async {
        guard case .loaded(let devices) = devicesState,
              let device = devices.first(where: { $0.id == deviceId }),
              !device.managementId.isEmpty else {
            statusItemsState = .failed("No management ID available for this device")
            return
        }
        Self.logger.debug("Loading DDM status items for device \(deviceId)")
        statusItemsState = .loading
        statusItemsEndpointUnsupported = false
        do {
            let data = try await cli.run(.ddmStatusItems(managementId: device.managementId))
            let items = try Self.decodeStatusItems(from: data)
            Self.logger.debug("Loaded \(items.count) DDM status items")
            statusItemsState = .loaded(items)
        } catch CLIError.nonZeroExit(let code, _) where code == 15 {
            // Endpoint deprecated — CLIExecutor returns stdout when available; if stdout was
            // empty we still get here. An empty item list is better than a red error banner.
            Self.logger.warning("DDM status items endpoint is deprecated (exit 15) for device \(deviceId)")
            statusItemsEndpointUnsupported = true
            statusItemsState = .loaded([])
        } catch {
            Self.logger.error("Failed to load DDM status items for device \(deviceId): \(error)")
            statusItemsState = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    func loadFleetStatus(force: Bool = false) async {
        guard force || fleetStatusState.value == nil else { return }
        guard force || !fleetStatusState.isLoading else { return }
        Self.logger.debug("Loading DDM fleet status")
        fleetStatusState = .loading
        fleetStatusEndpointUnsupported = false
        do {
            let data  = try await cli.run(.reportDDMStatus)
            let stats = try Self.decodeFleetStatus(from: data)
            Self.logger.debug("Loaded \(stats.count) DDM declaration stats")
            fleetStatusState = .loaded(stats)
        } catch CLIError.nonZeroExit(let code, _) where code == 15 {
            // jamf-cli exits 15 when the DDM report endpoint returns a Deprecation header.
            // The data is often still valid (CLIExecutor tries to return stdout), but if
            // stdout was empty we land here. Treat as empty — endpoint works, just deprecated.
            Self.logger.warning("DDM fleet status endpoint is deprecated (exit 15) — loaded 0 stats")
            fleetStatusEndpointUnsupported = true
            fleetStatusState = .loaded([])
        } catch {
            Self.logger.error("Failed to load DDM fleet status: \(error)")
            fleetStatusState = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    /// Loads status items for every DDM device so the new OS 27 items can be shown as columns.
    func loadAllDeviceStatusItems(force: Bool = false) async {
        guard force || deviceStatusState.value == nil else { return }
        guard !deviceStatusState.isLoading else { return }
        if devicesState.value == nil { await load() }
        guard let allDevices = devicesState.value else {
            deviceStatusState = .failed(devicesState.errorMessage ?? "No DDM devices loaded")
            return
        }
        // Macs with DDM turned off report no status items; skip them, then cap the rest.
        let candidates = allDevices.filter { $0.ddmEnabled != false }
        let devices = Array(candidates.prefix(Self.statusScanLimit))
        statusScanSkipped = candidates.count - devices.count
        deviceStatusState = .loading
        deviceStatusProgress = (0, devices.count)
        let cli = self.cli
        var rows: [DDMDeviceStatusRow] = []
        var unsupportedCount = 0
        var start = 0
        while start < devices.count {
            if Task.isCancelled { break }
            let chunk = devices[start..<min(start + Self.statusScanConcurrency, devices.count)]
            start += Self.statusScanConcurrency
            await withTaskGroup(of: (DDMDeviceStatusRow, Bool).self) { group in
                for device in chunk {
                    group.addTask {
                        do {
                            let data = try await cli.run(.ddmStatusItems(managementId: device.managementId))
                            let items = try Self.decodeStatusItems(from: data)
                            return (DDMDeviceStatusRow(device: device, summary: DDMDeviceStatusSummary(items: items), error: nil), false)
                        } catch CLIError.nonZeroExit(let code, _) where code == 15 {
                            return (DDMDeviceStatusRow(device: device, summary: nil, error: "Endpoint not supported"), true)
                        } catch {
                            return (DDMDeviceStatusRow(device: device, summary: nil,
                                                       error: ErrorMessageFormatter.message(for: error)), false)
                        }
                    }
                }
                for await (row, unsupported) in group {
                    rows.append(row)
                    if unsupported { unsupportedCount += 1 }
                    deviceStatusProgress.done += 1
                }
            }
        }
        statusItemsEndpointUnsupported = !devices.isEmpty && unsupportedCount == devices.count
        deviceStatusState = .loaded(rows.sorted { $0.device.name.localizedCaseInsensitiveCompare($1.device.name) == .orderedAscending })
    }

    /// jamf-cli prints nothing on stdout (and "No DDM declaration data found." on stderr)
    /// when there is no data, so empty output means an empty list, not a format error.
    nonisolated static func isEmptyOutput(_ data: Data) -> Bool {
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty || text == "null"
    }

    nonisolated static func decodeFleetStatus(from data: Data) throws -> [DDMDeclarationStat] {
        if isEmptyOutput(data) { return [] }
        let decoder = JSONDecoder()
        if let stats = try? decoder.decode([DDMDeclarationStat].self, from: data) {
            return stats
        }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["declarations", "results", "items", "data", "status"] {
                if let arr = obj[key],
                   let arrData = try? JSONSerialization.data(withJSONObject: arr),
                   let stats = try? decoder.decode([DDMDeclarationStat].self, from: arrData) {
                    return stats
                }
            }
        }
        let preview = String(data: data.prefix(300), encoding: .utf8) ?? "<unreadable>"
        throw CLIError.decodingFailed("Unexpected DDM fleet status format. Raw: \(preview)")
    }

    nonisolated static func decodeStatusItems(from data: Data) throws -> [DDMStatusItem] {
        if isEmptyOutput(data) { return [] }
        let decoder = JSONDecoder()
        // {"statusItems": [...]}
        if let r = try? decoder.decode(DDMStatusItemResponse.self, from: data) {
            return r.statusItems
        }
        // Plain array [...]
        if let items = try? decoder.decode([DDMStatusItem].self, from: data) {
            return items
        }
        // Any top-level object — scan common wrapper keys
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["statusItems", "status_items", "items", "results", "data"] {
                if let arr = obj[key],
                   let arrData = try? JSONSerialization.data(withJSONObject: arr),
                   let items = try? decoder.decode([DDMStatusItem].self, from: arrData) {
                    return items
                }
            }
        }
        // NDJSON (one JSON object per line)
        if let text = String(data: data, encoding: .utf8) {
            let items = text.components(separatedBy: .newlines).compactMap { line -> DDMStatusItem? in
                guard !line.trimmingCharacters(in: .whitespaces).isEmpty,
                      let lineData = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(DDMStatusItem.self, from: lineData)
            }
            if !items.isEmpty { return items }
        }
        let preview = String(data: data.prefix(300), encoding: .utf8) ?? "<unreadable>"
        throw CLIError.decodingFailed("Unexpected response format. Raw: \(preview)")
    }

    // MARK: - Private

    /// Returns devices with a management ID plus the total inventory count.
    nonisolated static func decodeDevices(from data: Data) throws -> (devices: [DDMDevice], total: Int) {
        let decoder = JSONDecoder()
        // Try direct array
        if let devices = try? decoder.decode([DDMDevice].self, from: data) {
            return (devices.filter { !$0.managementId.isEmpty }, devices.count)
        }
        // Try wrapped: {"results": [...]} or {"totalCount": N, "results": [...]}
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["results", "devices", "data", "items"] {
                if let arr = obj[key],
                   let arrData = try? JSONSerialization.data(withJSONObject: arr),
                   let devices = try? decoder.decode([DDMDevice].self, from: arrData) {
                    return (devices.filter { !$0.managementId.isEmpty }, devices.count)
                }
            }
        }
        // Include a snippet of the raw response in the error to aid debugging
        let preview = String(data: data.prefix(300), encoding: .utf8) ?? "<unreadable>"
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unexpected format. Raw: \(preview)"))
    }
}
