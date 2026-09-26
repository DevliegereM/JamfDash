import Foundation
import OSLog
import Observation

@MainActor
@Observable
final class JamfSecurityViewModel {
    private static let logger = Logger(subsystem: "com.jamfdash", category: "JamfSecurityViewModel")

    private let repository: JamfSecurityRepository

    private(set) var state: LoadState<[JSCDevice]> = .idle
    private(set) var riskSummary: [JSCRiskLevel: Int] = [:]
    private(set) var availableOSTypes: [String] = []

    var searchText: String = ""
    var filterRisk: JSCRiskLevel? = nil
    var filterOS: String? = nil

    var devices: [JSCDevice] { state.value ?? [] }

    var filteredDevices: [JSCDevice] {
        var result = devices
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                ($0.deviceName?.lowercased().contains(query) ?? false) ||
                ($0.userDisplayName?.lowercased().contains(query) ?? false) ||
                ($0.userEmail?.lowercased().contains(query) ?? false) ||
                ($0.externalId?.lowercased().contains(query) ?? false)
            }
        }
        if let risk = filterRisk {
            result = result.filter { $0.riskLevel == risk }
        }
        if let os = filterOS {
            result = result.filter { $0.osType == os }
        }
        return result
    }

    var totalCount: Int { devices.count }
    var filteredCount: Int { filteredDevices.count }

    init(repository: JamfSecurityRepository) {
        self.repository = repository
    }

    func load(force: Bool = false) async {
        guard force || state.value == nil else { return }
        guard force || !state.isLoading else { return }
        Self.logger.info("Loading Jamf Security Cloud devices (force: \(force, privacy: .public))")
        state = .loading
        do {
            let devices = try await repository.fetchDevices()
            Self.logger.info("Loaded \(devices.count, privacy: .public) JSC devices")
            state = .loaded(devices)
            updateDerivedState(from: devices)
        } catch {
            Self.logger.error("Failed to load JSC devices: \(error)")
            state = .failed(error.localizedDescription)
        }
    }

    private func updateDerivedState(from devices: [JSCDevice]) {
        riskSummary = Dictionary(grouping: devices, by: \.riskLevel).mapValues(\.count)
        availableOSTypes = Array(Set(devices.compactMap(\.osType))).sorted()
    }
}
