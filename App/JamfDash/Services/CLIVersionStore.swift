import Foundation
import OSLog

/// Manages a versioned binary store for jamf-cli.
///
/// Directory layout inside Application Support/JamfDash:
/// ```
///   bin/
///   ├── jamf-cli                  ← active running binary (plain copy)
///   └── versions/
///       ├── 1.5.0/
///       │   └── jamf-cli
///       └── 1.6.0/
///           └── jamf-cli
/// ```
actor CLIVersionStore {
    let supportDirectory: URL
    private let logger = Logger(subsystem: "com.jamfdash", category: "CLIVersionStore")

    private static let pinnedKey = "jamfDash.pinnedCLIVersion"

    init(supportDirectory: URL) {
        self.supportDirectory = supportDirectory
    }

    // MARK: - Paths

    var activeBinaryURL: URL {
        supportDirectory.appendingPathComponent("bin/jamf-cli")
    }

    /// Release tags look like `v1.31.1` or `1.31.1-beta.2`. Anything else (for example a
    /// tag with `/` or `..`) is refused, because tags become folder names.
    static func isValidTag(_ tag: String) -> Bool {
        tag.range(of: #"^v?[0-9]{1,4}\.[0-9]{1,4}\.[0-9]{1,4}(-[A-Za-z0-9.]{1,32})?$"#,
                  options: .regularExpression) != nil
    }

    /// Replaces `destination` with a copy of `source` in one step: the copy is made next to
    /// the destination and renamed over it, so a failure never leaves a missing or
    /// half-written binary.
    static func installAtomically(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        let temp = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        try fm.copyItem(at: source, to: temp)
        do {
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temp.path)
            guard rename(temp.path, destination.path) == 0 else {
                throw CLIError.downloadFailed("Couldn't install jamf-cli: \(String(cString: strerror(errno)))")
            }
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
    }

    private var versionsDirectory: URL {
        supportDirectory.appendingPathComponent("bin/versions", isDirectory: true)
    }

    private func versionBinaryURL(_ version: String) -> URL {
        versionsDirectory
            .appendingPathComponent(version, isDirectory: true)
            .appendingPathComponent("jamf-cli")
    }

    // MARK: - Installed versions

    /// All locally stored version tags, newest first.
    var installedVersions: [String] {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: versionsDirectory.path) else {
            return []
        }
        return items
            .filter { !$0.hasPrefix(".") && Self.isValidTag($0) }
            .sorted { lhs, rhs in
                let l = lhs.hasPrefix("v") ? String(lhs.dropFirst()) : lhs
                let r = rhs.hasPrefix("v") ? String(rhs.dropFirst()) : rhs
                return l.compare(r, options: .numeric) == .orderedDescending
            }
    }

    var hasStoredVersions: Bool { !installedVersions.isEmpty }

    // MARK: - Pin / unpin

    var pinnedVersion: String? {
        UserDefaults.standard.string(forKey: Self.pinnedKey)
    }

    func pin(_ version: String) throws {
        guard installedVersions.contains(version) else {
            throw CLIError.versionNotFound(version)
        }
        try activate(version: version)
        UserDefaults.standard.set(version, forKey: Self.pinnedKey)
        logger.info("Pinned to jamf-cli \(version)")
    }

    func unpin() {
        UserDefaults.standard.removeObject(forKey: Self.pinnedKey)
        logger.info("Removed jamf-cli version pin")
    }

    // MARK: - Install & activate

    /// Copies the active binary into the versioned slot. Called after a fresh download.
    func install(version: String) throws {
        guard Self.isValidTag(version) else { throw CLIError.versionNotFound(version) }
        let fm = FileManager.default
        let dest = versionBinaryURL(version)
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.installAtomically(from: activeBinaryURL, to: dest)
        logger.info("Stored jamf-cli \(version) in version archive")
    }

    /// Overwrites the active binary from a versioned slot.
    func activate(version: String) throws {
        guard Self.isValidTag(version) else { throw CLIError.versionNotFound(version) }
        let src = versionBinaryURL(version)
        guard FileManager.default.fileExists(atPath: src.path) else {
            throw CLIError.versionNotFound(version)
        }
        try CodeSignatureVerifier.verifyJamfCLI(at: src)
        try Self.installAtomically(from: src, to: activeBinaryURL)
        logger.info("Activated jamf-cli \(version)")
    }

    // MARK: - Rollback

    /// The most-recent stored version that is not the latest, suitable for rollback.
    var rollbackVersion: String? {
        let versions = installedVersions
        guard versions.count >= 2 else { return nil }
        return versions[1]
    }

    /// Activates the previous version and pins to it.
    func rollback() throws {
        guard let target = rollbackVersion else {
            throw CLIError.versionNotFound("No previous version available for rollback")
        }
        try activate(version: target)
        UserDefaults.standard.set(target, forKey: Self.pinnedKey)
        logger.info("Rolled back to jamf-cli \(target)")
    }

    // MARK: - Prune old versions

    /// Removes all but the most recent `keepLatest` versioned directories.
    func prune(keepLatest count: Int = 3) {
        let versions = installedVersions
        guard versions.count > count else { return }
        for version in versions.dropFirst(count) {
            let dir = versionsDirectory.appendingPathComponent(version, isDirectory: true)
            try? FileManager.default.removeItem(at: dir)
            logger.info("Pruned jamf-cli \(version) from version archive")
        }
    }

    // MARK: - Migration

    /// If the active binary is present but no versioned directory exists yet,
    /// record the current binary under `currentVersion` to bootstrap the store.
    func migrateIfNeeded(currentVersion: String?) {
        guard !hasStoredVersions, FileManager.default.fileExists(atPath: activeBinaryURL.path) else {
            return
        }
        let version = currentVersion ?? "unknown"
        try? install(version: version)
        logger.info("Migrated existing jamf-cli binary to version store as \(version)")
    }

}
