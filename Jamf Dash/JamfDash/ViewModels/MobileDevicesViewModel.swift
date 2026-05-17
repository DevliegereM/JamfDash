import Foundation
import OSLog
import Observation

// MARK: - Mobile Device Models

struct MobileDevice: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let serialNumber: String?
    let model: String?
    let osVersion: String?
    let lastContactTime: String?
    let managed: Bool?
    let supervised: Bool?
    let enrolled: Bool?

    private enum CodingKeys: String, CodingKey {
        case id, uuid
        case name, deviceName, hostName
        case serialNumber, serial
        case model, modelIdentifier
        case osVersion, version, osBuildVersion
        case lastContactTime, lastContact, lastInventoryUpdateTimestamp
        case managed, enrolledViaDEP, isManaged
        case supervised, isSupervised
        case enrolled, mdmEnrolled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .uuid)   { id = s }
        else if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else { id = String(try c.decode(Int.self, forKey: .id)) }

        name         = (try? c.decode(String.self, forKey: .name))
                    ?? (try? c.decode(String.self, forKey: .deviceName))
                    ?? (try? c.decode(String.self, forKey: .hostName))
                    ?? id
        serialNumber = (try? c.decode(String.self, forKey: .serialNumber))
                    ?? (try? c.decode(String.self, forKey: .serial))
        model        = (try? c.decode(String.self, forKey: .model))
                    ?? (try? c.decode(String.self, forKey: .modelIdentifier))
        osVersion    = (try? c.decode(String.self, forKey: .osVersion))
                    ?? (try? c.decode(String.self, forKey: .version))
                    ?? (try? c.decode(String.self, forKey: .osBuildVersion))
        lastContactTime = (try? c.decode(String.self, forKey: .lastContactTime))
                       ?? (try? c.decode(String.self, forKey: .lastContact))
                       ?? (try? c.decode(String.self, forKey: .lastInventoryUpdateTimestamp))
        managed     = (try? c.decode(Bool.self, forKey: .managed))
                   ?? (try? c.decode(Bool.self, forKey: .isManaged))
        supervised  = (try? c.decode(Bool.self, forKey: .supervised))
                   ?? (try? c.decode(Bool.self, forKey: .isSupervised))
        enrolled    = (try? c.decode(Bool.self, forKey: .enrolled))
                   ?? (try? c.decode(Bool.self, forKey: .mdmEnrolled))
    }

    var daysSinceContact: Int? {
        guard let raw = lastContactTime else { return nil }
        let formatters: [DateFormatter] = {
            let iso = DateFormatter()
            iso.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
            let iso2 = DateFormatter()
            iso2.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
            return [iso, iso2]
        }()
        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = isoFmt.date(from: raw)
            ?? ISO8601DateFormatter().date(from: raw)
            ?? formatters.first.flatMap { $0.date(from: raw) }
        guard let d = date else { return nil }
        return Calendar.current.dateComponents([.day], from: d, to: Date()).day
    }
}

// MARK: - ViewModel

@MainActor
@Observable
final class MobileDevicesViewModel {
    private static let logger = Logger(subsystem: "com.jamfdash", category: "MobileDevicesViewModel")
    private(set) var state: LoadState<[MobileDevice]> = .idle
    var searchText = ""
    var staleThresholdDays: Int = {
        let v = UserDefaults.standard.integer(forKey: "mobileStaleThresholdDays")
        return v == 0 ? 30 : v
    }() {
        didSet { UserDefaults.standard.set(staleThresholdDays, forKey: "mobileStaleThresholdDays") }
    }

    var actionResult: String? = nil
    var isActionRunning = false

    private let cli: any CLIRunning

    init(cli: any CLIRunning) {
        self.cli = cli
    }

    func load(force: Bool = false) async {
        guard force || state.value == nil else { return }
        guard force || !state.isLoading else { return }
        Self.logger.debug("Loading mobile devices")
        state = .loading
        do {
            let data = try await cli.run(.mobileDeviceList)
            let devices = try Self.decodeDevices(from: data)
            Self.logger.debug("Loaded \(devices.count) mobile devices")
            state = .loaded(devices)
        } catch {
            Self.logger.error("Failed to load mobile devices: \(error)")
            state = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    private static func decodeDevices(from data: Data) throws -> [MobileDevice] {
        let decoder = JSONDecoder()
        if let items = try? decoder.decode([MobileDevice].self, from: data) { return items }
        struct Paged: Decodable { let results: [MobileDevice] }
        if let paged = try? decoder.decode(Paged.self, from: data) { return paged.results }
        struct Items: Decodable { let items: [MobileDevice] }
        return try decoder.decode(Items.self, from: data).items
    }

    // MARK: - Computed

    private var all: [MobileDevice] { state.value ?? [] }

    var filtered: [MobileDevice] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(q) ||
            ($0.serialNumber?.localizedCaseInsensitiveContains(q) ?? false) ||
            ($0.model?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    var staleDevices: [MobileDevice] {
        all.filter { ($0.daysSinceContact ?? 0) >= staleThresholdDays }
    }

    var osDistribution: [(version: String, count: Int)] {
        let grouped = Dictionary(grouping: all, by: { $0.osVersion ?? "Unknown" })
        return grouped
            .map { (version: $0.key, count: $0.value.count) }
            .sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }
    }

    var totalCount: Int { all.count }
    var managedCount: Int { all.filter { $0.managed == true }.count }

    func devicesForOS(_ version: String) -> [MobileDevice] {
        all.filter { $0.osVersion == version }
    }

    // MARK: - Device actions

    func runAction(_ command: CLICommand, label: String) async {
        isActionRunning = true
        defer { isActionRunning = false }
        do {
            _ = try await cli.run(command)
            actionResult = "\(label) sent successfully."
        } catch {
            actionResult = "\(label) failed: \(error.localizedDescription)"
        }
    }
}
