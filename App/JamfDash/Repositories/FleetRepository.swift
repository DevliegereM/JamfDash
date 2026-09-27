import Foundation
import OSLog

struct FleetRepository: Sendable {
    private static let logger = Logger(subsystem: "com.jamfdash", category: "FleetRepository")
    let cli: any CLIRunning

    func fetchPolicies() async throws -> [Policy] {
        let data = try await cli.run(.policies)
        return try decodeArray(data)
    }

    func fetchSmartGroups() async throws -> [SmartComputerGroup] {
        let data = try await cli.run(.smartComputerGroups)
        return try decodeArray(data)
    }

    func fetchCategories() async throws -> [JamfCategory] {
        let data = try await cli.run(.categories)
        return try decodeArray(data)
    }

    func fetchScripts() async throws -> [JamfScript] {
        let data = try await cli.run(.scripts)
        return try decodeArray(data)
    }

    func fetchPackages() async throws -> [JamfPackage] {
        let data = try await cli.run(.packages)
        return try decodeArray(data)
    }

    func fetchConfigProfiles() async throws -> [ConfigProfile] {
        let data = try await cli.run(.configProfiles)
        return try decodeArray(data)
    }

    /// Maximum number of simultaneous jamf-cli detail calls for category back-fill.
    /// Keeps subprocess count bounded so the system doesn't become overwhelmed during
    /// the initial sync when policies/profiles are fetched in parallel with other tasks.
    private static let categoryFetchConcurrency = 6

    func fetchPolicyCategoryMap(for policies: [Policy]) async -> [Int: String] {
        guard !policies.isEmpty else { return [:] }
        Self.logger.info("Back-filling categories for \(policies.count) uncategorized policies (batch size \(Self.categoryFetchConcurrency))")
        var map: [Int: String] = [:]
        for chunk in policies.chunked(by: Self.categoryFetchConcurrency) {
            guard !Task.isCancelled else {
                Self.logger.info("Policy category back-fill cancelled after \(map.count) entries")
                break
            }
            await withTaskGroup(of: (Int, String?).self) { group in
                for policy in chunk {
                    group.addTask { (policy.id, try? await self.policyCategory(id: policy.id)) }
                }
                for await (id, name) in group { if let name { map[id] = name } }
            }
        }
        Self.logger.info("Policy category back-fill complete — \(map.count)/\(policies.count) resolved")
        return map
    }

    func fetchConfigProfileCategoryMap(for profiles: [ConfigProfile]) async -> [Int: String] {
        guard !profiles.isEmpty else { return [:] }
        Self.logger.info("Back-filling categories for \(profiles.count) config profiles (batch size \(Self.categoryFetchConcurrency))")
        var map: [Int: String] = [:]
        for chunk in profiles.chunked(by: Self.categoryFetchConcurrency) {
            guard !Task.isCancelled else {
                Self.logger.info("Config profile category back-fill cancelled after \(map.count) entries")
                break
            }
            await withTaskGroup(of: (Int, String?).self) { group in
                for profile in chunk {
                    group.addTask { (profile.id, try? await self.configProfileCategory(id: profile.id)) }
                }
                for await (id, name) in group { if let name { map[id] = name } }
            }
        }
        Self.logger.info("Config profile category back-fill complete — \(map.count)/\(profiles.count) resolved")
        return map
    }

    private func policyCategory(id: Int) async throws -> String? {
        let data = try await cli.run(.policyDetail(id: id))
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let general = json["general"] as? [String: Any],
              let cat = general["category"] as? [String: Any],
              let catId = cat["id"] as? Int, catId > 0,
              let name = cat["name"] as? String, !name.isEmpty else { return nil }
        return name
    }

    private func configProfileCategory(id: Int) async throws -> String? {
        let data = try await cli.run(.configProfileDetail(id: id))
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let general = json["general"] as? [String: Any],
              let cat = general["category"] as? [String: Any],
              let catId = cat["id"] as? Int, catId != -1,
              let name = cat["name"] as? String, !name.isEmpty,
              name != "No category assigned" else { return nil }
        return name
    }

    func fetchSmartGroupDetail(id: String) async throws -> SmartGroupDetail {
        let data = try await cli.run(.smartGroupDetail(id: id))
        return try JSONDecoder().decode(SmartGroupDetail.self, from: data)
    }

    func fetchPolicyScope(id: Int) async throws -> JamfScope {
        let data = try await cli.run(.policyDetail(id: id))
        return Self.extractScope(from: data)
    }

    func fetchConfigProfileScope(id: Int) async throws -> JamfScope {
        let data = try await cli.run(.configProfileDetail(id: id))
        return Self.extractScope(from: data)
    }

    /// Scope of a Classic policy or configuration profile detail. Also used by the Enrollment section.
    static func extractScope(from data: Data) -> JamfScope {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let s = json["scope"] as? [String: Any] else { return JamfScope() }

        let lim = s["limitations"] as? [String: Any] ?? [:]
        let exc = s["exclusions"] as? [String: Any] ?? [:]

        return JamfScope(
            allComputers:   s["all_computers"] as? Bool ?? false,
            computers:      classicItems(s["computers"],       singular: "computer"),
            computerGroups: classicItems(s["computer_groups"], singular: "computer_group"),
            departments:    classicItems(s["departments"],     singular: "department"),
            buildings:      classicItems(s["buildings"],       singular: "building"),
            limitations: JamfScopeLimitations(
                users:           classicItems(lim["users"],            singular: "user"),
                userGroups:      classicItems(lim["user_groups"],      singular: "user_group"),
                networkSegments: classicItems(lim["network_segments"], singular: "network_segment"),
                ibeacons:        classicItems(lim["ibeacons"],         singular: "ibeacon")
            ),
            exclusions: JamfScopeExclusions(
                computers:       classicItems(exc["computers"],       singular: "computer"),
                computerGroups:  classicItems(exc["computer_groups"], singular: "computer_group"),
                departments:     classicItems(exc["departments"],     singular: "department"),
                buildings:       classicItems(exc["buildings"],       singular: "building"),
                users:           classicItems(exc["users"],           singular: "user"),
                userGroups:      classicItems(exc["user_groups"],     singular: "user_group"),
                networkSegments: classicItems(exc["network_segments"],singular: "network_segment")
            )
        )
    }

    /// Extracts an array of scope items from a Classic API field.
    /// Handles three formats: "" (empty), {"singular": {...}} (one), {"singular": [{...}]} (many),
    /// and plain [{...}] (flat array used in demo mode).
    private static func classicItems(_ value: Any?, singular: String) -> [JamfScopeItem] {
        if let array = value as? [[String: Any]] {
            return array.compactMap { classicScopeItem($0) }
        }
        guard let dict = value as? [String: Any], let inner = dict[singular] else { return [] }
        if let array = inner as? [[String: Any]] { return array.compactMap { classicScopeItem($0) } }
        if let single = inner as? [String: Any]  { return [classicScopeItem(single)].compactMap { $0 } }
        return []
    }

    private static func classicScopeItem(_ dict: [String: Any]) -> JamfScopeItem? {
        let name = (dict["name"] as? String) ?? ""
        guard !name.isEmpty else { return nil }
        let id: Int
        if let i = dict["id"] as? Int          { id = i }
        else if let s = dict["id"] as? String  { id = Int(s) ?? 0 }
        else                                    { id = 0 }
        return JamfScopeItem(id: id, name: name)
    }

    // MARK: - Raw command execution

    func run(_ command: CLICommand) async throws -> Data {
        try await cli.run(command)
    }

    // MARK: - Generic list fetch

    func fetchList<T: Decodable>(_ type: T.Type, command: CLICommand) async throws -> [T] {
        let data = try await cli.run(command)
        return try decodeArray(data)
    }

    // MARK: - Private

    /// Decodes a JSON array from data, treating JSON `null` as an empty array.
    /// Tries flat array first, then UAPI `{"results":[...]}` wrapper.
    /// Logs a warning when the decoded array is empty (possible schema change).
    private func decodeArray<T: Decodable>(_ data: Data) throws -> [T] {
        if isNull(data) { return [] }
        let decoder = JSONDecoder()
        if let flat = try? decoder.decode([T].self, from: data) {
            if flat.isEmpty { Self.logger.warning("Decoded empty array for \(T.self) — CLI may have returned no records") }
            return flat
        }
        if let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let results = raw["results"],
           let resultsData = try? JSONSerialization.data(withJSONObject: results),
           let paged = try? decoder.decode([T].self, from: resultsData) {
            if paged.isEmpty { Self.logger.warning("Decoded empty paged array for \(T.self) — CLI may have returned no records") }
            return paged
        }
        do { return try decoder.decode([T].self, from: data) }
        catch { throw CLIError.decodingFailed(error.localizedDescription) }
    }

    private func isNull(_ data: Data) -> Bool {
        guard let str = String(data: data, encoding: .utf8) else { return false }
        return str.trimmingCharacters(in: .whitespacesAndNewlines) == "null"
    }
}

// MARK: - Collection chunking

private extension Array {
    /// Splits the array into consecutive sub-arrays of at most `size` elements.
    func chunked(by size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
