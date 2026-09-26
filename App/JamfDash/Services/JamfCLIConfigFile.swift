import Foundation

/// Small, line-based edits to jamf-cli's `config.yaml`.
///
/// Only two things are ever changed, both the way jamf-cli's own messages tell users to:
/// the top-level `default-profile` value, and a profile's `url`. Every other line —
/// including comments and fields Jamf Dash doesn't know — is written back untouched.
/// A copy of the previous file is kept next to it as `config.yaml.jamfdash-backup`.
struct JamfCLIConfigFile: Sendable {
    let url: URL

    enum EditError: LocalizedError {
        case profileNotFound(String)
        case urlLineNotFound(String)

        var errorDescription: String? {
            switch self {
            case .profileNotFound(let name): return "Profile “\(name)” was not found in the jamf-cli config file."
            case .urlLineNotFound(let name): return "Profile “\(name)” has no url in the jamf-cli config file."
            }
        }
    }

    /// `~/.config/jamf-cli/config.yaml`. Jamf Dash runs jamf-cli with a minimal environment
    /// that has no `XDG_CONFIG_HOME`, so this is always the file jamf-cli uses for the app.
    static var standardURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/jamf-cli/config.yaml")
    }

    // MARK: - default-profile

    func defaultProfile() throws -> String {
        let lines = try readLines()
        guard let line = lines.first(where: { $0.hasPrefix("default-profile:") }) else { return "" }
        return Self.scalar(String(line.dropFirst("default-profile:".count)))
    }

    func setDefaultProfile(_ name: String) throws {
        var lines = try readLines()
        let newLine = "default-profile: \(Self.quoted(name))"
        if let i = lines.firstIndex(where: { $0.hasPrefix("default-profile:") }) {
            guard lines[i] != newLine else { return }
            lines[i] = newLine
        } else {
            lines.insert(newLine, at: 0)
        }
        try write(lines)
    }

    // MARK: - Profile url

    func profileURL(_ name: String) throws -> String? {
        let lines = try readLines()
        guard let i = try urlLineIndex(for: name, in: lines) else { return nil }
        return Self.scalar(String(lines[i].split(separator: ":", maxSplits: 1)[1]))
    }

    func setURL(_ newURL: String, forProfile name: String) throws {
        var lines = try readLines()
        guard let i = try urlLineIndex(for: name, in: lines) else { throw EditError.urlLineNotFound(name) }
        let indent = lines[i].prefix { $0 == " " }
        lines[i] = "\(indent)url: \(newURL)"
        try write(lines)
    }

    // MARK: - Parsing

    /// Index of the `url:` line inside the profile's block under `profiles:`.
    private func urlLineIndex(for name: String, in lines: [String]) throws -> Int? {
        guard let profilesLine = lines.firstIndex(where: { $0.hasPrefix("profiles:") }) else {
            throw EditError.profileNotFound(name)
        }
        var i = profilesLine + 1
        var entryIndent: Int?
        while i < lines.count {
            let line = lines[i]
            let indent = Self.indent(of: line)
            if line.trimmingCharacters(in: .whitespaces).isEmpty || line.trimmingCharacters(in: .whitespaces).hasPrefix("#") {
                i += 1; continue
            }
            if indent == 0 { break }                       // left the profiles map
            if entryIndent == nil { entryIndent = indent }
            if indent == entryIndent, Self.key(of: line) == name {
                // Scan this profile's block for `url:`.
                var j = i + 1
                while j < lines.count {
                    let child = lines[j]
                    let trimmed = child.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty, !trimmed.hasPrefix("#"), Self.indent(of: child) <= indent { break }
                    if trimmed.hasPrefix("url:") { return j }
                    j += 1
                }
                return nil
            }
            i += 1
        }
        throw EditError.profileNotFound(name)
    }

    private static func indent(of line: String) -> Int { line.prefix { $0 == " " }.count }

    /// The mapping key of a `key:` line, unquoted.
    private static func key(of line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix(":") else { return nil }
        return scalar(String(trimmed.dropLast()))
    }

    /// A YAML scalar with surrounding quotes removed.
    private static func scalar(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if s.count >= 2, s.hasPrefix("\""), s.hasSuffix("\"") {
            return String(s.dropFirst().dropLast())
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }
        if s.count >= 2, s.hasPrefix("'"), s.hasSuffix("'") {
            return String(s.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        return s
    }

    private static func quoted(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    // MARK: - IO

    private func readLines() throws -> [String] {
        try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
    }

    private func write(_ lines: [String]) throws {
        let fm = FileManager.default
        let backup = url.appendingPathExtension("jamfdash-backup")
        try? fm.removeItem(at: backup)
        try fm.copyItem(at: url, to: backup)
        try Data(lines.joined(separator: "\n").utf8).write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
    }
}

// MARK: - Retired Platform gateway

extension JamfCLIConfigFile {
    /// The URL jamf-cli asks for when a profile still points at the retired
    /// `*.apigw.jamf.com` gateway, e.g. `https://eu.api.jamfcloud.com`.
    /// Only a `https://<region>.api.jamfcloud.com` URL is ever accepted from the message.
    static func retiredGatewayReplacement(in message: String) -> String? {
        guard message.localizedCaseInsensitiveContains("retired Jamf Platform gateway") else { return nil }
        guard let match = message.range(of: #"https://[a-z0-9-]+\.api\.jamfcloud\.com"#, options: .regularExpression) else {
            return nil
        }
        return String(message[match])
    }
}
