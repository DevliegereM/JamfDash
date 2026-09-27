import Foundation
import OSLog

// MARK: - Documents

/// One searchable fact about the fleet: a policy, a Mac, a past digest, …
struct KnowledgeDocument: Codable, Sendable, Hashable {
    enum Kind: String, Codable, Sendable, CaseIterable {
        case computer, policy, configProfile, script, package, smartGroup
        case blueprint, complianceRule, digest

        var label: String {
            switch self {
            case .computer:       return "Mac"
            case .policy:         return "Policy"
            case .configProfile:  return "Configuration profile"
            case .script:         return "Script"
            case .package:        return "Package"
            case .smartGroup:     return "Smart group"
            case .blueprint:      return "Blueprint"
            case .complianceRule: return "Compliance rule"
            case .digest:         return "Daily digest"
            }
        }

        /// Words in a question that point at this kind ("which policies…").
        var hints: [String] {
            switch self {
            case .computer:       return ["mac", "macs", "computer", "computers", "device", "devices", "serial"]
            case .policy:         return ["policy", "policies"]
            case .configProfile:  return ["profile", "profiles", "configuration"]
            case .script:         return ["script", "scripts"]
            case .package:        return ["package", "packages", "pkg"]
            case .smartGroup:     return ["group", "groups"]
            case .blueprint:      return ["blueprint", "blueprints"]
            case .complianceRule: return ["compliance", "rule", "rules", "benchmark", "cis"]
            case .digest:         return ["digest", "digests", "yesterday", "week", "summary"]
            }
        }
    }

    let kind: Kind
    let title: String
    let body: String
    let date: Date?
}

// MARK: - Index

/// A small keyword index over data the app already loaded, rebuilt after each sync.
/// Lets Dashie look facts up ("what do we have for FileVault?") instead of guessing.
/// Stays on this Mac; nothing is added to the system Spotlight index.
struct FleetKnowledgeIndex: Codable, Sendable {
    var builtAt: Date
    var profile: String
    var documents: [KnowledgeDocument]

    static let stopwords: Set<String> = [
        "the", "a", "an", "and", "or", "of", "for", "to", "in", "on", "with", "what", "which", "who",
        "is", "are", "was", "were", "do", "does", "did", "we", "our", "us", "have", "has", "any",
        "anything", "about", "there", "show", "me", "find", "list", "all", "that", "this", "it",
        "how", "many", "much", "say", "said", "tell", "give", "can", "you", "my", "i",
    ]

    static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 2 && !stopwords.contains($0) }
    }

    /// Best matches for the query, strongest first. Title hits weigh more than body hits,
    /// and rare words more than common ones.
    func search(_ query: String, limit: Int = 8) -> [KnowledgeDocument] {
        let queryTokens = Array(Set(Self.tokens(query)))
        guard !queryTokens.isEmpty, !documents.isEmpty else { return [] }

        let kindHints = Set(KnowledgeDocument.Kind.allCases.filter { kind in
            kind.hints.contains { queryTokens.contains($0) }
        })
        // Words that only name a kind ("policies") shouldn't have to match the text itself.
        let hintWords = Set(kindHints.flatMap(\.hints))
        let contentTokens = queryTokens.filter { !hintWords.contains($0) }

        let docTokens = documents.map { (title: Set(Self.tokens($0.title)), body: Set(Self.tokens($0.body))) }
        let n = Double(documents.count)
        func idf(_ t: String) -> Double {
            let df = docTokens.filter { $0.title.contains(t) || $0.body.contains(t) }.count
            return log((n + 1) / (Double(df) + 1)) + 1
        }
        let weights = Dictionary(uniqueKeysWithValues: contentTokens.map { ($0, idf($0)) })

        var scored: [(doc: KnowledgeDocument, score: Double)] = []
        for (i, doc) in documents.enumerated() {
            var score = 0.0
            for t in contentTokens {
                let w = weights[t] ?? 1
                if docTokens[i].title.contains(t) { score += 3 * w }
                else if docTokens[i].title.contains(where: { $0.hasPrefix(t) && t.count >= 3 }) { score += 2 * w }
                if docTokens[i].body.contains(t) { score += w }
            }
            if contentTokens.isEmpty {
                // Only kind words ("list the blueprints"): return that kind.
                if kindHints.contains(doc.kind) { score = 1 }
            } else if score > 0, kindHints.contains(doc.kind) {
                score *= 1.5
            }
            if score > 0 { scored.append((doc, score)) }
        }
        return scored
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return (lhs.doc.date ?? .distantPast) > (rhs.doc.date ?? .distantPast)
            }
            .prefix(limit)
            .map(\.doc)
    }

    /// Search results as compact text for the model.
    func answer(_ query: String, limit: Int = 8, characterLimit: Int = 1_500) -> String {
        let hits = search(query, limit: limit)
        guard !hits.isEmpty else {
            return "No indexed Jamf data matches “\(query)”. The index holds names of policies, configuration profiles, scripts, packages, smart groups, Macs, blueprints, compliance rules and past daily digests."
        }
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        var lines = ["\(hits.count) match\(hits.count == 1 ? "" : "es") for “\(query)”:"]
        for doc in hits {
            var line = "• [\(doc.kind.label)] \(doc.title)"
            if !doc.body.isEmpty { line += " — \(doc.body)" }
            if let d = doc.date, doc.kind == .digest { line += " (\(df.string(from: d)))" }
            lines.append(line)
        }
        let text = lines.joined(separator: "\n")
        return text.count > characterLimit ? String(text.prefix(characterLimit)) + "\n…(truncated)" : text
    }
}

// MARK: - Building

extension FleetKnowledgeIndex {
    struct Sources: Sendable {
        var computers: [Computer] = []
        var policies: [Policy] = []
        var policyCategories: [Int: String] = [:]
        var configProfiles: [ConfigProfile] = []
        var profileCategories: [Int: String] = [:]
        var scripts: [JamfScript] = []
        var packages: [JamfPackage] = []
        var smartGroups: [SmartComputerGroup] = []
        var blueprints: [BlueprintStatus] = []
        var complianceRules: [BenchmarkRuleStat] = []
        var digests: [DigestEntry] = []
    }

    static func build(profile: String, from s: Sources, now: Date = Date()) -> FleetKnowledgeIndex {
        var docs: [KnowledgeDocument] = []
        for c in s.computers {
            var parts: [String] = []
            if let serial = c.serialNumber { parts.append("serial \(serial)") }
            if let os = c.osVersion { parts.append("macOS \(os)") }
            if let days = c.daysSinceContact { parts.append("last check-in \(days) day\(days == 1 ? "" : "s") ago") }
            if let managed = c.managed { parts.append(managed ? "managed" : "unmanaged") }
            docs.append(.init(kind: .computer, title: c.name, body: parts.joined(separator: ", "), date: nil))
        }
        for p in s.policies {
            let category = p.category?.name ?? s.policyCategories[p.id]
            docs.append(.init(kind: .policy, title: p.name, body: category.map { "category \($0)" } ?? "", date: nil))
        }
        for p in s.configProfiles {
            docs.append(.init(kind: .configProfile, title: p.name,
                              body: s.profileCategories[p.id].map { "category \($0)" } ?? "", date: nil))
        }
        for script in s.scripts {
            docs.append(.init(kind: .script, title: script.name,
                              body: script.category.map { "category \($0.name)" } ?? "", date: nil))
        }
        for pkg in s.packages {
            docs.append(.init(kind: .package, title: pkg.name, body: "", date: nil))
        }
        for g in s.smartGroups {
            docs.append(.init(kind: .smartGroup, title: g.name, body: "", date: nil))
        }
        for b in s.blueprints {
            var parts = [BlueprintStatusFormat.stateLabel(b.state ?? "unknown")]
            if b.hasCounts {
                parts.append("\(b.succeeded ?? 0) succeeded, \(b.failed ?? 0) failed, \(b.pending ?? 0) pending")
            }
            docs.append(.init(kind: .blueprint, title: b.name, body: parts.joined(separator: "; "), date: nil))
        }
        for r in s.complianceRules {
            let title = [r.ruleNumber, r.ruleTitle ?? r.ruleId].compactMap { $0 }.joined(separator: " ")
            docs.append(.init(kind: .complianceRule, title: title,
                              body: "\(r.failed ?? 0) failed, \(r.passed ?? 0) passed, \(r.unknown ?? 0) unknown",
                              date: nil))
        }
        for d in s.digests.suffix(30) {
            let text = d.bullets.map(DigestEntry.stripBullet).joined(separator: " · ")
            docs.append(.init(kind: .digest, title: "Digest", body: text, date: d.date))
        }
        return FleetKnowledgeIndex(builtAt: now, profile: profile, documents: docs)
    }
}

// MARK: - Store

/// Holds the current index in memory and on disk (Application Support, owner-only).
@MainActor
final class FleetKnowledgeStore {
    static let shared = FleetKnowledgeStore()
    private static let logger = Logger(subsystem: "com.jamfdash", category: "FleetKnowledge")

    private(set) var index: FleetKnowledgeIndex?
    private let fileURL: URL?

    init(fileURL: URL? = FleetKnowledgeStore.defaultURL) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL) {
            index = try? JSONDecoder().decode(FleetKnowledgeIndex.self, from: data)
        }
    }

    static var defaultURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("JamfDash", isDirectory: true)
            .appendingPathComponent("fleet-index.json")
    }

    /// `persist: false` keeps the index in memory only (demo mode must not overwrite real data).
    func replace(with newIndex: FleetKnowledgeIndex, persist: Bool = true) {
        index = newIndex
        Self.logger.info("Fleet index rebuilt: \(newIndex.documents.count) documents")
        guard persist, let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(newIndex)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            Self.logger.error("Couldn't save fleet index: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Drops the index (e.g. when switching to another Jamf instance).
    func clear() {
        index = nil
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
    }

    func answer(_ query: String) -> String {
        guard let index else {
            return "The fleet index isn't ready yet; it's built after the first sync. Use the other tools for now."
        }
        return index.answer(query)
    }
}
