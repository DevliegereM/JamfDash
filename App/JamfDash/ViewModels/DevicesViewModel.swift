import Foundation
import OSLog
import Observation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Fleet query

/// Structured filters for the device list, built from a plain-language question.
/// Only fields the device list actually has can be filtered.
struct FleetQuery: Sendable, Equatable {
    var nameContains: String?
    /// "15" matches 15.x; "14.7" matches 14.7 and 14.7.x.
    var osVersionPrefix: String?
    /// Strictly older than this version.
    var osOlderThan: String?
    /// This version or newer.
    var osAtLeast: String?
    var notSeenForDays: Int?
    var seenWithinDays: Int?
    var managed: Bool?
    /// Criteria the user asked for that the device list can't filter on (e.g. "department").
    var unsupported: [String] = []

    var isEmpty: Bool {
        nameContains == nil && osVersionPrefix == nil && osOlderThan == nil && osAtLeast == nil
            && notSeenForDays == nil && seenWithinDays == nil && managed == nil
    }

    enum Field: String, CaseIterable, Sendable {
        case name, osVersion, osOlderThan, osAtLeast, notSeen, seenWithin, managed
    }

    /// Human-readable chips, one per active filter.
    var chips: [(field: Field, label: String)] {
        var out: [(Field, String)] = []
        if let v = nameContains    { out.append((.name, "Name contains “\(v)”")) }
        if let v = osVersionPrefix { out.append((.osVersion, "macOS \(v)")) }
        if let v = osOlderThan     { out.append((.osOlderThan, "macOS older than \(v)")) }
        if let v = osAtLeast       { out.append((.osAtLeast, "macOS \(v) or newer")) }
        if let v = notSeenForDays  { out.append((.notSeen, "Not seen for \(v)+ days")) }
        if let v = seenWithinDays  { out.append((.seenWithin, "Seen in last \(v) days")) }
        if let v = managed         { out.append((.managed, v ? "Managed" : "Unmanaged")) }
        return out
    }

    mutating func remove(_ field: Field) {
        switch field {
        case .name:        nameContains = nil
        case .osVersion:   osVersionPrefix = nil
        case .osOlderThan: osOlderThan = nil
        case .osAtLeast:   osAtLeast = nil
        case .notSeen:     notSeenForDays = nil
        case .seenWithin:  seenWithinDays = nil
        case .managed:     managed = nil
        }
    }

    /// `days` is the device's days since last check-in (nil = never / unknown).
    func matches(name: String, osVersion: String?, days: Int?, managed isManaged: Bool?) -> Bool {
        if let n = nameContains, !name.localizedCaseInsensitiveContains(n) { return false }
        if osVersionPrefix != nil || osOlderThan != nil || osAtLeast != nil {
            guard let v = osVersion, Self.isVersion(v) else { return false }
            if let p = osVersionPrefix, !(v == p || v.hasPrefix(p + ".")) { return false }
            if let o = osOlderThan, v.compare(o, options: .numeric) != .orderedAscending { return false }
            if let a = osAtLeast, v.compare(a, options: .numeric) == .orderedAscending { return false }
        }
        if let d = notSeenForDays, let days, days < d { return false }       // never seen counts as not seen
        if let d = seenWithinDays { guard let days, days <= d else { return false } }
        if let m = managed, isManaged != m { return false }
        return true
    }

    func matches(_ c: Computer) -> Bool {
        matches(name: c.name, osVersion: c.osVersion, days: c.daysSinceContact, managed: c.managed)
    }

    static func isVersion(_ s: String) -> Bool {
        s.range(of: #"^\d{1,3}(\.\d{1,3}){0,2}$"#, options: .regularExpression) != nil
    }
}

// MARK: Grounding

extension FleetQuery {
    /// macOS marketing names → major version.
    static let codenames: [String: String] = [
        "monterey": "12", "ventura": "13", "sonoma": "14", "sequoia": "15", "tahoe": "26",
    ]

    enum Kind: String, Sendable, CaseIterable {
        case nameContains, osVersionIs, osOlderThan, osAtLeast
        case notSeenForDays, seenWithinDays, managedOnly, unmanagedOnly, unsupported
    }

    /// Builds a query from (kind, value) pairs proposed by the model, keeping only the ones the
    /// question itself supports. The small on-device model tends to fill every slot, so each
    /// filter must be traceable to words in the question.
    static func grounded(_ proposals: [(kind: Kind, value: String)], question: String) -> FleetQuery {
        let q = question.lowercased()
        let words = Set(q.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "-" }).map(String.init))
        func has(_ any: String...) -> Bool { any.contains { q.contains($0) } }

        func version(_ raw: String) -> String? {
            var v = raw.trimmingCharacters(in: .whitespaces).lowercased()
            if v.hasPrefix("macos") { v = v.dropFirst(5).trimmingCharacters(in: .whitespaces) }
            if let major = codenames[v] { v = major }
            guard isVersion(v) else { return nil }
            // The version, or a codename for it, must be in the question.
            let named = codenames.contains { q.contains($0.key) && $0.value == v }
            let pattern = "(^|[^0-9.])" + NSRegularExpression.escapedPattern(for: v) + "($|[^0-9])"
            let typed = q.range(of: pattern, options: .regularExpression) != nil
            return named || typed ? v : nil
        }
        func days(_ raw: String) -> Int? {
            guard let n = Int(raw.trimmingCharacters(in: .whitespaces)), (1...3650).contains(n) else { return nil }
            return n
        }
        let staleWords = has("not seen", "haven't", "havent", "hasn't", "not checked", "not check", "stale",
                             "offline", "inactive", "no check", "without check", "missing", "since")
        let recentWords = has("within", "last ", "recent", "active", "seen in", "checked in in", "past ")

        var query = FleetQuery()
        for p in proposals {
            let value = p.value.trimmingCharacters(in: .whitespacesAndNewlines)
            switch p.kind {
            case .nameContains:
                if !value.isEmpty, value.count <= 64, q.contains(value.lowercased()),
                   !["mac", "macs", "device", "devices", "computer", "computers"].contains(value.lowercased()) {
                    query.nameContains = value
                }
            case .osVersionIs:
                if query.osVersionPrefix == nil, let v = version(value),
                   !has("older", "below", "before", "earlier", "newer", "or later", "at least", "above") {
                    query.osVersionPrefix = v
                }
            case .osOlderThan:
                if let v = version(value), has("older", "below", "before", "earlier", "lower", "less than", "outdated") {
                    query.osOlderThan = v
                }
            case .osAtLeast:
                if let v = version(value), has("newer", "or later", "at least", "above", "or higher", "later than") {
                    query.osAtLeast = v
                }
            case .notSeenForDays:
                if staleWords, let d = days(value) { query.notSeenForDays = d }
            case .seenWithinDays:
                if recentWords, !staleWords, let d = days(value) { query.seenWithinDays = d }
            case .managedOnly:
                if words.contains("managed") { query.managed = true }
            case .unmanagedOnly:
                if words.contains("unmanaged") || has("not managed") { query.managed = false }
            case .unsupported:
                if !value.isEmpty, query.unsupported.count < 4 { query.unsupported.append(String(value.prefix(40))) }
            }
        }
        // Unambiguous in the text, so it doesn't depend on the model noticing it.
        if words.contains("unmanaged") || has("not managed") { query.managed = false }
        return query
    }
}

#if canImport(FoundationModels)
@available(macOS 26, *)
@Generable
enum FleetFilterKind: String {
    case nameContains, osVersionIs, osOlderThan, osAtLeast
    case notSeenForDays, seenWithinDays, managedOnly, unmanagedOnly, unsupported
}

@available(macOS 26, *)
@Generable
struct FleetFilter {
    let kind: FleetFilterKind
    @Guide(description: "The value: text, a macOS version like 14 or 15.6, a number of days, or empty")
    let value: String
}

@available(macOS 26, *)
@Generable
struct FleetFilterList {
    @Guide(description: "Only the filters the question asks for", .maximumCount(5))
    let filters: [FleetFilter]
}

@available(macOS 26, *)
enum FleetQueryParser {
    static let instructions = """
        Turn a Jamf admin's question about Macs into a short list of filters. Use only filters the \
        question clearly asks for. Kinds:
        - nameContains: text that must appear in the device name
        - osVersionIs: an exact macOS version, e.g. 14 or 15.6
        - osOlderThan / osAtLeast: version bounds
        - notSeenForDays: has NOT checked in for at least N days
        - seenWithinDays: DID check in within the last N days
        - managedOnly / unmanagedOnly (value empty)
        - unsupported: anything else asked for (department, model, user, RAM, location…)
        A week is 7 days, a month 30 days. Sonoma is 14, Sequoia 15, Tahoe 26.

        Examples:
        "Macs on macOS 14 not seen for two weeks" → osVersionIs 14, notSeenForDays 14
        "devices older than macOS 15" → osOlderThan 15
        "unmanaged Macs with LAB in the name" → unmanagedOnly, nameContains LAB
        "Finance laptops active this week" → unsupported department Finance, seenWithinDays 7
        """

    static func parse(_ question: String) async throws -> FleetQuery {
        let session = LanguageModelSession(model: .default, instructions: instructions)
        let list = try await session.respond(
            to: question,
            generating: FleetFilterList.self,
            options: GenerationOptions(temperature: 0)
        ).content
        let proposals = list.filters.compactMap { f -> (kind: FleetQuery.Kind, value: String)? in
            FleetQuery.Kind(rawValue: f.kind.rawValue).map { ($0, f.value) }
        }
        return FleetQuery.grounded(proposals, question: question)
    }
}
#endif

// MARK: - Bulk action types

struct BulkActionResult: Identifiable, Sendable {
    let id = UUID()
    let deviceName: String
    let serial: String
    let success: Bool
    let message: String
}

struct BulkActionSummary: Identifiable, Sendable {
    let id = UUID()
    let actionName: String
    let results: [BulkActionResult]
    var successCount: Int { results.filter(\.success).count }
    var failureCount: Int { results.filter { !$0.success }.count }
}

// MARK: - ViewModel

@MainActor
@Observable
final class DevicesViewModel {
    private static let logger = Logger(subsystem: "com.jamfdash", category: "DevicesViewModel")
    private(set) var state: LoadState<[Computer]> = .idle
    var bulkActionSummary: BulkActionSummary? = nil
    private(set) var isBulkRunning: Bool = false

    var staleThresholdDays: Int = (UserDefaults.standard.integer(forKey: "staleThresholdDays").nonZero ?? 30) {
        didSet { UserDefaults.standard.set(staleThresholdDays, forKey: "staleThresholdDays") }
    }

    var searchText = ""
    var filterManaged: Bool? = nil

    /// Filters built from a plain-language question ("Ask" in the search field).
    var fleetQuery: FleetQuery?
    private(set) var isParsingQuery = false
    private(set) var queryError: String?

    /// True when the on-device model can turn questions into filters.
    var canAskInPlainLanguage: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// Turns the search text into structured filters with the on-device model.
    func askInPlainLanguage() async {
        let question = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isParsingQuery else { return }
        queryError = nil
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            isParsingQuery = true
            defer { isParsingQuery = false }
            do {
                let query = try await FleetQueryParser.parse(question)
                if query.isEmpty {
                    queryError = query.unsupported.isEmpty
                        ? "Couldn't turn that into filters. Try e.g. “Macs on macOS 14 not seen for 2 weeks”."
                        : "The device list can't filter on \(query.unsupported.joined(separator: ", "))."
                    return
                }
                fleetQuery = query
                searchText = ""
            } catch {
                Self.logger.error("Plain-language query failed: \(String(describing: error), privacy: .public)")
                queryError = "The on-device model couldn't answer: \(error.localizedDescription)"
            }
            return
        }
        #endif
        queryError = "Plain-language search needs Apple Intelligence (macOS 26 or later)."
    }

    func removeQueryFilter(_ field: FleetQuery.Field) {
        fleetQuery?.remove(field)
        if fleetQuery?.isEmpty == true { fleetQuery = nil }
    }

    func clearFleetQuery() {
        fleetQuery = nil
        queryError = nil
    }

    var filteredManaged: [Computer] {
        guard let managed = filterManaged else { return filtered }
        return filtered.filter { $0.managed == managed }
    }

    private let cli: any CLIRunning

    init(cli: any CLIRunning) {
        self.cli = cli
    }

    func load(force: Bool = false) async {
        guard force || state.value == nil else {
            Self.logger.debug("Computers already cached — skipping")
            return
        }
        guard force || !state.isLoading else { return }
        Self.logger.debug("Loading computers")
        state = .loading
        do {
            let data = try await cli.run(.computers)
            if isNull(data) {
                Self.logger.debug("Loaded 0 computers (null response)")
                state = .loaded([])
                return
            }
            let computers = try Self.decodeComputers(from: data)
            Self.logger.debug("Loaded \(computers.count) computers")
            state = .loaded(computers)
        } catch {
            Self.logger.error("Failed to load computers: \(error)")
            state = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    /// Handles both a flat `[Computer]` array and the paginated Pro API wrapper
    /// `{"totalCount": N, "results": [...]}` that some jamf-cli versions return.
    private static func decodeComputers(from data: Data) throws -> [Computer] {
        let decoder = JSONDecoder()
        if let computers = try? decoder.decode([Computer].self, from: data) {
            return computers
        }
        struct PagedResponse: Decodable {
            let results: [Computer]
        }
        return try decoder.decode(PagedResponse.self, from: data).results
    }

    // MARK: - Computed

    private var all: [Computer] { state.value ?? [] }

    /// Publicly readable list of all loaded computers (used by DeviceSearchViewModel).
    var allComputers: [Computer] { all }

    var filtered: [Computer] {
        let base = fleetQuery.map { query in all.filter(query.matches) } ?? all
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return base }
        return base.filter {
            $0.name.localizedCaseInsensitiveContains(q) ||
            ($0.serialNumber?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    var staleDevices: [Computer] {
        all.filter { ($0.daysSinceContact ?? 0) >= staleThresholdDays }
    }

    var osDistribution: [(version: String, count: Int)] {
        let grouped = Dictionary(grouping: all, by: { $0.osVersion ?? "Unknown" })
        return grouped
            .map { (version: $0.key, count: $0.value.count) }
            .sorted { lhs, rhs in
                lhs.version.compare(rhs.version, options: .numeric) == .orderedDescending
            }
    }

    var totalCount: Int { all.count }
    var managedCount: Int { all.filter { $0.managed == true }.count }

    func devicesForOS(_ version: String) -> [Computer] {
        all.filter { $0.osVersion == version }
    }

    // MARK: - Bulk actions

    func runBulkAction(
        _ makeCommand: @escaping @Sendable (String) -> CLICommand,
        actionName: String,
        devices: [(name: String, serial: String)]
    ) async {
        isBulkRunning = true
        var results: [BulkActionResult] = []
        await withTaskGroup(of: BulkActionResult.self) { group in
            for device in devices {
                let serial = device.serial
                let name   = device.name
                group.addTask {
                    do {
                        _ = try await self.cli.run(makeCommand(serial))
                        return BulkActionResult(deviceName: name, serial: serial, success: true, message: "Success")
                    } catch {
                        return BulkActionResult(deviceName: name, serial: serial, success: false, message: error.localizedDescription)
                    }
                }
            }
            for await result in group { results.append(result) }
        }
        results.sort { $0.deviceName < $1.deviceName }
        isBulkRunning = false
        bulkActionSummary = BulkActionSummary(actionName: actionName, results: results)
    }

    func clearBulkActionSummary() { bulkActionSummary = nil }

    private func isNull(_ data: Data) -> Bool {
        (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == "null"
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
