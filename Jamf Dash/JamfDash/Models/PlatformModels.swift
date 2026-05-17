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
}

struct JamfComplianceBenchmarkListResponse: Decodable, Sendable {
    let results: [JamfComplianceBenchmark]?
}
