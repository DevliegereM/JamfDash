import Foundation

struct CLIVersion: Sendable, Hashable {
    let semver: String
    let architecture: Architecture

    enum Architecture: String, Sendable {
        case arm64
        case x86_64
    }

    /// Returns true if `other` version string is newer than self.
    /// Strips leading "v" so "v1.9.0" and "1.9.0" compare correctly.
    func isOlderThan(_ other: String) -> Bool {
        let lhs = semver.hasPrefix("v") ? String(semver.dropFirst()) : semver
        let rhs = other.hasPrefix("v")  ? String(other.dropFirst())  : other
        return lhs.compare(rhs, options: .numeric) == .orderedAscending
    }
}
