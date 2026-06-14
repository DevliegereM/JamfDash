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

@MainActor
@Observable
final class DDMMonitorViewModel {
    private static let logger = Logger(subsystem: "com.jamfdash", category: "DDMMonitorViewModel")
    private(set) var devicesState: LoadState<[DDMDevice]> = .idle
    private(set) var statusItemsState: LoadState<[DDMStatusItem]> = .idle
    var selectedDeviceId: String? = nil
    private(set) var fleetStatusState: LoadState<[DDMDeclarationStat]> = .idle

    private let cli: any CLIRunning

    init(cli: any CLIRunning) {
        self.cli = cli
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
            let devices = try Self.decodeDevices(from: data)
            Self.logger.debug("Loaded \(devices.count) DDM devices")
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
        do {
            let data = try await cli.run(.ddmStatusItems(managementId: device.managementId))
            let items = try Self.decodeStatusItems(from: data)
            Self.logger.debug("Loaded \(items.count) DDM status items")
            statusItemsState = .loaded(items)
        } catch CLIError.nonZeroExit(let code, _) where code == 15 {
            // Endpoint deprecated — CLIExecutor returns stdout when available; if stdout was
            // empty we still get here. An empty item list is better than a red error banner.
            Self.logger.warning("DDM status items endpoint is deprecated (exit 15) for device \(deviceId)")
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
            fleetStatusState = .loaded([])
        } catch {
            Self.logger.error("Failed to load DDM fleet status: \(error)")
            fleetStatusState = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    private static func decodeFleetStatus(from data: Data) throws -> [DDMDeclarationStat] {
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

    private static func decodeStatusItems(from data: Data) throws -> [DDMStatusItem] {
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

    private static func decodeDevices(from data: Data) throws -> [DDMDevice] {
        let decoder = JSONDecoder()
        // Try direct array
        if let devices = try? decoder.decode([DDMDevice].self, from: data) {
            return devices.filter { !$0.managementId.isEmpty }
        }
        // Try wrapped: {"results": [...]} or {"totalCount": N, "results": [...]}
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["results", "devices", "data", "items"] {
                if let arr = obj[key],
                   let arrData = try? JSONSerialization.data(withJSONObject: arr),
                   let devices = try? decoder.decode([DDMDevice].self, from: arrData) {
                    return devices.filter { !$0.managementId.isEmpty }
                }
            }
        }
        // Include a snippet of the raw response in the error to aid debugging
        let preview = String(data: data.prefix(300), encoding: .utf8) ?? "<unreadable>"
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unexpected format. Raw: \(preview)"))
    }
}
