import Foundation
import OSLog

/// Fetches every macOS configuration profile's payloads (one `classic-macos-config-profiles get`
/// per profile, bounded concurrency) and caches the parsed result so the Audit dashboard,
/// the Update Readiness view and Device Lookup can share one scan.
actor ProfileDeprecationScanner {
    private static let logger = Logger(subsystem: "com.jamfdash", category: "ProfileDeprecationScanner")
    private static let concurrency = 6
    private static let cacheLifetime: TimeInterval = 15 * 60

    private let cli: any CLIRunning
    private var cached: (date: Date, profiles: [ScannedProfile])?
    private var inFlight: Task<[ScannedProfile], any Error>?

    init(cli: any CLIRunning) {
        self.cli = cli
    }

    /// The last scan result, if any — never triggers CLI calls.
    var cachedProfiles: [ScannedProfile]? { cached?.profiles }

    func scan(force: Bool = false) async throws -> [ScannedProfile] {
        if !force, let cached, Date().timeIntervalSince(cached.date) < Self.cacheLifetime {
            return cached.profiles
        }
        if let inFlight { return try await inFlight.value }

        let cli = self.cli
        let task = Task { try await Self.performScan(cli: cli) }
        inFlight = task
        defer { inFlight = nil }
        let profiles = try await task.value
        cached = (Date(), profiles)
        return profiles
    }

    private static func performScan(cli: any CLIRunning) async throws -> [ScannedProfile] {
        let listData = try await cli.run(.configProfiles)
        let list = decodeProfileList(listData)
        logger.info("Scanning payloads of \(list.count) configuration profiles")

        var scanned: [ScannedProfile] = []
        var start = 0
        while start < list.count {
            try Task.checkCancellation()
            let chunk = list[start..<min(start + concurrency, list.count)]
            start += concurrency
            await withTaskGroup(of: ScannedProfile?.self) { group in
                for profile in chunk {
                    group.addTask {
                        guard let data = try? await cli.run(.configProfileDetail(id: profile.id)) else { return nil }
                        return ProfilePayloadParser.parse(detailJSON: data, fallbackID: profile.id, fallbackName: profile.name)
                    }
                }
                for await result in group {
                    if let result { scanned.append(result) }
                }
            }
        }
        logger.info("Profile payload scan complete — \(scanned.count)/\(list.count) parsed")
        return scanned.sorted { $0.id < $1.id }
    }

    private static func decodeProfileList(_ data: Data) -> [ConfigProfile] {
        let decoder = JSONDecoder()
        if let list = try? decoder.decode([ConfigProfile].self, from: data) { return list }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["os_x_configuration_profiles", "results", "items", "data"] {
                if let arr = obj[key],
                   let arrData = try? JSONSerialization.data(withJSONObject: arr),
                   let list = try? decoder.decode([ConfigProfile].self, from: arrData) {
                    return list
                }
            }
        }
        return []
    }
}
