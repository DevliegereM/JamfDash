import Foundation
import OSLog
import Observation

@MainActor
@Observable
final class CorrelationViewModel {
    private static let logger = Logger(subsystem: "com.jamfdash", category: "CorrelationViewModel")

    // MARK: - Properties

    private(set) var devices: [CorrelatedDevice] = []
    var searchText: String = ""
    var filter: CorrelationFilter = .all

    /// Clears the result, e.g. after switching instance.
    func reset() { devices = [] }

    // MARK: - Correlation

    /// Merges Pro computers and Protect computers by serial number.
    func correlate(pro: [Computer], protect: [ProtectComputer]) {
        var result: [CorrelatedDevice] = []

        // Index both by serial (lowercased for case-insensitive matching)
        var proBySerial: [String: Computer] = [:]
        for computer in pro {
            if let serial = computer.serialNumber, !serial.isEmpty {
                proBySerial[serial.lowercased()] = computer
            }
        }

        var protectBySerial: [String: ProtectComputer] = [:]
        for computer in protect {
            if let serial = computer.serialNumber, !serial.isEmpty {
                protectBySerial[serial.lowercased()] = computer
            }
        }

        // Build matched and Pro-only entries
        for (serial, proComputer) in proBySerial {
            let protectComputer = protectBySerial[serial]
            let state: MatchState = protectComputer != nil ? .matched : .proOnly
            let rawSerial = proComputer.serialNumber ?? serial
            result.append(CorrelatedDevice(
                id: rawSerial,
                serial: proComputer.serialNumber,
                proComputer: proComputer,
                protectComputer: protectComputer,
                matchState: state
            ))
        }

        // Add Protect-only entries (not matched to any Pro device)
        for (serial, protectComputer) in protectBySerial {
            guard proBySerial[serial] == nil else { continue }
            let rawSerial = protectComputer.serialNumber ?? serial
            result.append(CorrelatedDevice(
                id: rawSerial,
                serial: protectComputer.serialNumber,
                proComputer: nil,
                protectComputer: protectComputer,
                matchState: .protectOnly
            ))
        }

        // Sort: matched first, then Pro-only, then Protect-only; alphabetical within groups
        let order: [MatchState] = [.matched, .proOnly, .protectOnly]
        devices = result.sorted { lhs, rhs in
            if lhs.matchState != rhs.matchState {
                let lhsIndex = order.firstIndex(of: lhs.matchState) ?? 99
                let rhsIndex = order.firstIndex(of: rhs.matchState) ?? 99
                return lhsIndex < rhsIndex
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }

        Self.logger.debug(
            "Correlated \(result.count) devices (\(result.filter { $0.matchState == .matched }.count) matched)"
        )
    }

    // MARK: - Filtered Results

    var filtered: [CorrelatedDevice] {
        var result = devices

        switch filter {
        case .all:          break
        case .matched:      result = result.filter { $0.matchState == .matched }
        case .proOnly:      result = result.filter { $0.matchState == .proOnly }
        case .protectOnly:  result = result.filter { $0.matchState == .protectOnly }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return result }

        return result.filter {
            $0.displayName.localizedCaseInsensitiveContains(query) ||
            ($0.serial?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    // MARK: - Summary Counts

    var matchedCount: Int      { devices.filter { $0.matchState == .matched }.count }
    var proOnlyCount: Int      { devices.filter { $0.matchState == .proOnly }.count }
    var protectOnlyCount: Int  { devices.filter { $0.matchState == .protectOnly }.count }
}
