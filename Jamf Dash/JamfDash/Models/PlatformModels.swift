import Foundation

struct JamfBlueprint: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
}

struct JamfBlueprintListResponse: Decodable, Sendable {
    let results: [JamfBlueprint]?
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
