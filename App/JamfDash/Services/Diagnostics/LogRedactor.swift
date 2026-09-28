import Foundation

/// Removes personal and organisational data from text that goes into a problem report.
///
/// Known values (server addresses, profile, device and user names) are replaced first,
/// then patterns (URLs, host names, emails, IP and MAC addresses, UUIDs, serial numbers,
/// tokens, home folders). Each distinct value gets a numbered placeholder such as
/// `‹host-1›`, the same number every time it appears, so the report still shows which
/// lines are about the same thing.
struct LogRedactor: Sendable {

    enum Kind: String, CaseIterable, Sendable {
        case host, serial, name, token, id, email, address, user

        var label: String {
            switch self {
            case .host: return "hosts"
            case .serial: return "serials"
            case .name: return "names"
            case .token: return "tokens"
            case .id: return "IDs"
            case .email: return "emails"
            case .address: return "IP/MAC addresses"
            case .user: return "user names"
            }
        }
    }

    /// Number of replacements per kind.
    struct Counts: Sendable, Equatable {
        private(set) var byKind: [Kind: Int] = [:]
        mutating func add(_ kind: Kind, _ n: Int = 1) { byKind[kind, default: 0] += n }
        var total: Int { byKind.values.reduce(0, +) }
        static func + (a: Counts, b: Counts) -> Counts {
            var c = a
            for (k, v) in b.byKind { c.add(k, v) }
            return c
        }
        var summary: String {
            Kind.allCases.compactMap { k in byKind[k].map { "\($0) \(k.label)" } }.joined(separator: " · ")
        }
    }

    private var known: [(value: String, kind: Kind)] = []

    /// - Parameters:
    ///   - hosts: server URLs or host names (only the host part is used)
    ///   - names: profile names, device names, the Mac's name
    ///   - serials: serial numbers seen in the app
    ///   - userNames: the macOS account name and full name
    init(hosts: [String] = [], names: [String] = [], serials: [String] = [], userNames: [String] = []) {
        var list: [(String, Kind)] = []
        for h in hosts {
            let host = URL(string: h)?.host ?? h
            if host.count >= 4 { list.append((host, .host)) }
        }
        list += names.filter { $0.count >= 3 }.map { ($0, .name) }
        list += serials.filter { $0.count >= 6 }.map { ($0, .serial) }
        list += userNames.filter { $0.count >= 3 }.map { ($0, .user) }
        // Longest first, so "Finance MacBook Pro" is replaced before "Finance".
        known = list.sorted { $0.0.count > $1.0.count }
    }

    /// A redactor for this Mac and the app's current data.
    static func forThisMac(hosts: [String], names: [String], serials: [String]) -> LogRedactor {
        let host = Host.current().localizedName.map { [$0] } ?? []
        return LogRedactor(hosts: hosts, names: names + host, serials: serials,
                           userNames: [NSUserName(), NSFullUserName()])
    }

    func redact(_ text: String) -> (text: String, counts: Counts) {
        var state = State()
        var out = text
        for (value, kind) in known {
            out = state.replace(literal: value, kind: kind, in: out)
        }
        for rule in Self.rules {
            out = state.replace(rule, in: out)
        }
        return (out, state.counts)
    }

    // MARK: - Patterns

    struct Rule: Sendable {
        let kind: Kind
        let regex: NSRegularExpression
        /// Capture group to replace (0 = whole match).
        let group: Int
        /// Numbered placeholders, or one fixed placeholder (tokens).
        let numbered: Bool
    }

    private static func rule(_ kind: Kind, _ pattern: String, group: Int = 0, numbered: Bool = true,
                             options: NSRegularExpression.Options = []) -> Rule {
        // The patterns are constants; a mistake shows up in the tests.
        Rule(kind: kind, regex: try! NSRegularExpression(pattern: pattern, options: options),
             group: group, numbered: numbered)
    }

    private static let tlds = "com|net|org|io|be|nl|de|fr|uk|eu|us|ca|au|ch|at|se|no|dk|fi|es|it|cloud|edu|gov|local|internal|corp|lan"

    static let rules: [Rule] = [
        // Secrets after a key: token=…, "client_secret": "…", Authorization: Bearer …
        rule(.token, #"(?i)(?:bearer|token|secret|password|passwd|api[_-]?key|client[_-]?secret|authorization)["']?\s*[:=]?\s*(?:bearer\s+)?["']?([^\s"',;&]{6,})"#,
             group: 1, numbered: false),
        // Long opaque strings: JWTs, base64 and hex keys.
        rule(.token, #"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{5,}"#, numbered: false),
        // (Not after `$`: Swift symbol names in crash reports are long too.)
        rule(.token, #"(?<![A-Za-z0-9/+=$])[A-Za-z0-9+/_-]{40,}={0,2}(?![A-Za-z0-9/+=])"#, numbered: false),
        rule(.email, #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#),
        // Host part of URLs, then bare host names ending in a common top-level domain.
        rule(.host, #"(?i)\b[a-z][a-z0-9+.-]*://([^/\s:"'<>?#]+)"#, group: 1),
        rule(.host, #"(?i)\b(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+(?:\#(tlds))\b"#),
        rule(.address, #"\b(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b"#),
        rule(.address, #"\b(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)\b"#),
        rule(.address, #"(?i)\b(?:[0-9a-f]{1,4}:){4,7}[0-9a-f]{1,4}\b"#),
        rule(.id, #"(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b"#),
        // Apple serial numbers: 10–12 capitals and digits with both present.
        rule(.serial, #"\b(?=[A-Z0-9]*\d)(?=[A-Z0-9]*[A-Z])[A-Z0-9]{10,12}\b"#),
        rule(.user, #"(/Users/)([^/\s]+)"#, group: 2),
    ]

    // MARK: - Replacement state

    private struct State {
        var counts = Counts()
        var numbers: [Kind: [String: Int]] = [:]

        mutating func placeholder(for value: String, kind: Kind, numbered: Bool) -> String {
            counts.add(kind)
            guard numbered else { return "‹\(kind.rawValue)›" }
            let key = value.lowercased()
            if let n = numbers[kind]?[key] { return "‹\(kind.rawValue)-\(n)›" }
            let n = (numbers[kind]?.count ?? 0) + 1
            numbers[kind, default: [:]][key] = n
            return "‹\(kind.rawValue)-\(n)›"
        }

        mutating func replace(literal: String, kind: Kind, in text: String) -> String {
            var out = ""
            var rest = text[...]
            while let r = rest.range(of: literal, options: .caseInsensitive) {
                out += rest[..<r.lowerBound]
                out += placeholder(for: literal, kind: kind, numbered: true)
                rest = rest[r.upperBound...]
            }
            return out + rest
        }

        mutating func replace(_ rule: Rule, in text: String) -> String {
            let ns = text as NSString
            let matches = rule.regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            guard !matches.isEmpty else { return text }
            var out = ""
            var cursor = 0
            for m in matches {
                let r = m.range(at: rule.group)
                guard r.location != NSNotFound, r.location >= cursor else { continue }
                let value = ns.substring(with: r)
                // Don't redact what is already a placeholder.
                if value.contains("‹") { continue }
                out += ns.substring(with: NSRange(location: cursor, length: r.location - cursor))
                out += placeholder(for: value, kind: rule.kind, numbered: rule.numbered)
                cursor = r.location + r.length
            }
            return out + ns.substring(from: cursor)
        }
    }
}
