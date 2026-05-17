import Foundation
import OSLog
import Observation

@MainActor
@Observable
final class DDMMonitorViewModel {
    private static let logger = Logger(subsystem: "com.jamfdash", category: "DDMMonitorViewModel")
    private(set) var devicesState: LoadState<[DDMDevice]> = .idle
    private(set) var statusItemsState: LoadState<[DDMStatusItem]> = .idle
    var selectedDeviceId: String? = nil

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
        } catch {
            Self.logger.error("Failed to load DDM status items for device \(deviceId): \(error)")
            statusItemsState = .failed(ErrorMessageFormatter.message(for: error))
        }
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
