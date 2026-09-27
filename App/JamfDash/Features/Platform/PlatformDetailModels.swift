import Foundation

// MARK: - Blueprint Date Formatters

nonisolated(unsafe) let blueprintDateFormatterWithFrac: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

nonisolated(unsafe) let blueprintDateFormatterNoFrac: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

// MARK: - Benchmark Date Formatters

nonisolated(unsafe) let benchmarkDateFormatterWithFrac: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

nonisolated(unsafe) let benchmarkDateFormatterNoFrac: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

// MARK: - Blueprint JSON Models

struct BlueprintDetail: Decodable {
    let id: String
    let name: String
    let description: String?
    let created: Date?
    let updated: Date?
    let deploymentState: BlueprintDeploymentState?
    let scope: BlueprintScope?
    let steps: [BlueprintStep]?
}

struct BlueprintDeploymentState: Decodable {
    let state: String
    let lastDeployment: BlueprintLastDeployment?
}

struct BlueprintLastDeployment: Decodable {
    let started: Date?
    let state: String
}

struct BlueprintScope: Decodable {
    let deviceGroups: [String]?
    let devices: [String]?
    let users: [String]?
    let userGroups: [String]?
}

struct BlueprintStep: Decodable {
    let name: String
    let components: [BlueprintComponent]?
}

struct BlueprintComponent: Decodable {
    let identifier: String
    // The API ships the content in one of three shapes:
    // 1. component.configuration.declarations[]  (nested array)
    // 2. component.payload  (direct object)
    // 3. component.configuration  (flat settings object, not wrapped)
    let configuration: BlueprintComponentConfig?   // shape 1
    let directPayload: JSONPayload?                 // shape 2
    let rawConfiguration: JSONPayload?              // shape 3 (captured when shape 1 parse fails)
    // Optional top-level declaration metadata
    let type: String?
    let channelType: String?

    private enum CodingKeys: String, CodingKey {
        case identifier, type, channelType, configuration
        case directPayload = "payload"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        identifier    = try  c.decode(String.self,                   forKey: .identifier)
        type          = try? c.decode(String.self,                   forKey: .type)
        channelType   = try? c.decode(String.self,                   forKey: .channelType)
        directPayload = try? c.decode(JSONPayload.self,              forKey: .directPayload)
        let structured = try? c.decode(BlueprintComponentConfig.self, forKey: .configuration)
        configuration = structured
        // Shape 3: only capture raw config when the structured parse failed entirely
        rawConfiguration = (structured == nil)
            ? (try? c.decode(JSONPayload.self, forKey: .configuration))
            : nil
    }

    /// The best-available payload for display — prefers nested declarations,
    /// then direct payload, then raw configuration.
    var effectivePayload: JSONPayload? { directPayload ?? rawConfiguration }
    var hasPayload: Bool {
        let declarations = configuration?.declarations ?? []
        if !declarations.isEmpty { return true }
        return effectivePayload != nil
    }
}

struct BlueprintComponentConfig: Decodable {
    let declarations: [BlueprintDeclaration]?
}

struct BlueprintDeclaration: Decodable {
    let type: String
    let kind: String?
    let channelType: String?
    let payload: JSONPayload?
}

// Dynamic JSON value for arbitrary declaration payloads
enum JSONPayload: Decodable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONPayload])
    case object([String: JSONPayload])
    case null

    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil()              { self = .null }
        else if let v = try? c.decode(Bool.self)          { self = .bool(v) }
        else if let v = try? c.decode(Int.self)           { self = .int(v) }
        else if let v = try? c.decode(Double.self)        { self = .double(v) }
        else if let v = try? c.decode(String.self)        { self = .string(v) }
        else if let v = try? c.decode([JSONPayload].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONPayload].self)) }
    }

    var displayString: String {
        switch self {
        case .bool(let b):   return b ? "true" : "false"
        case .int(let i):    return "\(i)"
        case .double(let d): return "\(d)"
        case .string(let s): return s
        case .null:          return "null"
        case .array(let a):  return "[\(a.map(\.displayString).joined(separator: ", "))]"
        case .object(let d): return d.map { "\($0.key): \($0.value.displayString)" }.sorted().joined(separator: ", ")
        }
    }
}

// MARK: - Blueprint Decoder

func makeBlueprintDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .custom { dec in
        let container = try dec.singleValueContainer()
        let string = try container.decode(String.self)
        if let date = blueprintDateFormatterWithFrac.date(from: string) { return date }
        if let date = blueprintDateFormatterNoFrac.date(from: string) { return date }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot parse date: \(string)")
    }
    return decoder
}

// MARK: - Benchmark JSON Models

struct BenchmarkDetail: Decodable {
    let id: String?
    let name: String?
    /// The Platform API names the benchmark `title`.
    let title: String?
    let description: String?
    let version: String?
    let framework: String?
    let status: String?
    let syncState: String?
    let updateAvailable: Bool?
    let scope: BenchmarkScope?
    /// The Platform API puts the assigned device groups under `target`.
    let target: BenchmarkScope?
    let controls: [BenchmarkControl]?
    let rules: [BenchmarkRule]?

    var displayName: String? { name ?? title }
    var resolvedScope: BenchmarkScope? { scope ?? target }
    var displayStatus: String? { status ?? syncState }
}

/// Which devices / groups the benchmark is deployed to.
struct BenchmarkScope: Decodable {
    let deviceGroups: [String]?
    let devices: [String]?
    let users: [String]?
    let userGroups: [String]?
}

struct BenchmarkControl: Decodable, Hashable {
    let id: String?
    let name: String?
    let description: String?
    let severity: String?
    let status: String?
    let enabled: Bool?
    let remediation: String?

    /// True when this control is actively checked.
    var isEnabled: Bool {
        if let e = enabled { return e }
        if let s = status { return !["DISABLED", "INACTIVE", "OFF", "EXCLUDED"].contains(s.uppercased()) }
        return true
    }
}

struct BenchmarkRule: Decodable, Hashable {
    let id: String?
    // API may use "name" (Jamf) or "title" (mSCP native)
    let name: String?
    let title: String?
    // API may use "description" or "discussion" (mSCP native)
    let description: String?
    let discussion: String?
    let severity: String?
    let status: String?
    let enabled: Bool?
    // Remediation: "fix" (mSCP native) or "remediation" (Jamf)
    let fix: String?
    let remediation: String?

    var displayName: String? { name ?? title }
    var displayDescription: String? { discussion ?? description }
    var displayRemediation: String? { fix ?? remediation }

    /// True when this rule is actively enforced.
    var isEnabled: Bool {
        if let e = enabled { return e }
        if let s = status { return !["DISABLED", "INACTIVE", "OFF", "EXCLUDED"].contains(s.uppercased()) }
        return true
    }
}

// MARK: - Benchmark Decoder

func makeBenchmarkDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .custom { dec in
        let container = try dec.singleValueContainer()
        let string = try container.decode(String.self)
        if let date = benchmarkDateFormatterWithFrac.date(from: string) { return date }
        if let date = benchmarkDateFormatterNoFrac.date(from: string) { return date }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot parse date: \(string)")
    }
    return decoder
}

// MARK: - Detail Result Wrappers

/// Holds the result of a detail fetch — a decoded model plus the raw JSON as a fallback.
struct BlueprintDetailResult {
    let detail: BlueprintDetail?   // nil only if decoding completely failed
    let rawJSON: String
}

struct BenchmarkDetailResult {
    let detail: BenchmarkDetail?
    let rawJSON: String
}
