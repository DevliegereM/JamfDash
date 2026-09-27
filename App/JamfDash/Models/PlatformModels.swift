import Foundation

struct JamfBlueprint: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
}

struct JamfBlueprintListResponse: Decodable, Sendable {
    let results: [JamfBlueprint]?
}

/// One row of `pro report blueprint-status`. Device counts are only present for
/// deployed blueprints.
struct BlueprintStatus: Decodable, Sendable, Equatable {
    let name: String
    let state: String?
    let scope: Int?
    let steps: Int?
    let succeeded: Int?
    let failed: Int?
    let pending: Int?

    var hasCounts: Bool { succeeded != nil || failed != nil || pending != nil }
    var total: Int { (succeeded ?? 0) + (failed ?? 0) + (pending ?? 0) }

    /// Rows keyed by blueprint name; the report has no IDs.
    static func byName(_ data: Data) -> [String: BlueprintStatus] {
        guard let rows = try? JSONDecoder().decode([BlueprintStatus].self, from: data) else { return [:] }
        return Dictionary(rows.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

// MARK: - Benchmark reports

/// One rule of `pro benchmark-reports rules <id>`.
struct BenchmarkRuleStat: Decodable, Identifiable, Sendable, Hashable {
    let ruleId: String
    let ruleTitle: String?
    let ruleNumber: String?
    let discussion: String?
    let passed: Int?
    let failed: Int?
    let unknown: Int?
    let passPercentage: Double?
    let numberOfDevices: Int?

    var id: String { ruleId }
    var failedCount: Int { failed ?? 0 }

    static func decodeList(_ data: Data) -> [BenchmarkRuleStat]? {
        if let rows = try? JSONDecoder().decode([BenchmarkRuleStat].self, from: data) { return rows }
        struct Wrapped: Decodable { let results: [BenchmarkRuleStat] }
        return (try? JSONDecoder().decode(Wrapped.self, from: data))?.results
    }
}

/// One device of `pro report compliance-devices <title>`: devices ranked by failing rules.
struct BenchmarkDeviceCompliance: Decodable, Identifiable, Sendable, Hashable {
    let device: String
    let deviceId: String?
    let compliance: String?
    let rulesFailed: Int?
    let rulesPassed: Int?

    var id: String { deviceId ?? device }
}

/// A device returned for one rule by `pro benchmark-reports devices`. The field names are
/// read loosely because the command's output isn't documented.
struct BenchmarkRuleDevice: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let result: String?

    static func decodeList(_ data: Data) -> [BenchmarkRuleDevice]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let rows: [[String: Any]]
        if let a = json as? [[String: Any]] { rows = a }
        else if let o = json as? [String: Any], let a = (o["results"] ?? o["devices"]) as? [[String: Any]] { rows = a }
        else { return nil }
        return rows.enumerated().compactMap { index, row in
            func string(_ keys: String...) -> String? {
                for k in keys { if let v = row[k] as? String, !v.isEmpty { return v } }
                return nil
            }
            guard let name = string("deviceName", "device", "name", "computerName") else { return nil }
            let result = string("ruleResult", "result", "state")
            // Keep only failures even if the server ignored the --rule-result filter.
            if let r = result, r.uppercased() != "FAILED" { return nil }
            return BenchmarkRuleDevice(id: string("deviceId", "id") ?? "\(index)-\(name)", name: name, result: result)
        }
    }
}

struct BenchmarkResults: Sendable {
    var compliancePercentage: Double?
    var rules: [BenchmarkRuleStat]
}

struct JamfComplianceBenchmark: Decodable, Identifiable, Sendable {
    let id: String
    let name: String

    // Accept a variety of field-name patterns returned by the platform API.
    private enum CodingKeys: String, CodingKey {
        case id, name
        // Alternative name keys
        case benchmarkName, displayName, title
        // Alternative id keys
        case benchmarkId, uuid
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        // --- name: prefer "name", fall back to "benchmarkName" / "displayName" / "title"
        if let v = try? c.decode(String.self, forKey: .name), !v.isEmpty {
            name = v
        } else if let v = try? c.decode(String.self, forKey: .benchmarkName), !v.isEmpty {
            name = v
        } else if let v = try? c.decode(String.self, forKey: .displayName), !v.isEmpty {
            name = v
        } else if let v = try? c.decode(String.self, forKey: .title), !v.isEmpty {
            name = v
        } else {
            name = try c.decode(String.self, forKey: .name) // let it throw naturally
        }

        // --- id: prefer "id", fall back to "benchmarkId" / "uuid", then use name as key
        // (the CLI uses the name/identifier to look up a benchmark via `cb get <name>`)
        if let v = try? c.decode(String.self, forKey: .id), !v.isEmpty {
            id = v
        } else if let v = try? c.decode(Int.self, forKey: .id) {
            id = String(v)
        } else if let v = try? c.decode(String.self, forKey: .benchmarkId), !v.isEmpty {
            id = v
        } else if let v = try? c.decode(String.self, forKey: .uuid), !v.isEmpty {
            id = v
        } else {
            id = name
        }
    }
}

/// Wraps a variety of top-level response shapes returned by different API / CLI versions.
struct JamfComplianceBenchmarkListResponse: Decodable, Sendable {
    let results: [JamfComplianceBenchmark]?
    let benchmarks: [JamfComplianceBenchmark]?
    let items: [JamfComplianceBenchmark]?

    var resolved: [JamfComplianceBenchmark] {
        results ?? benchmarks ?? items ?? []
    }
}
