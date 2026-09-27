import CryptoKit
import Foundation
import OSLog

/// Where data that belongs to one Jamf instance is kept on disk: drift history and daily
/// digests. Each connection profile gets its own folder, named by a hash so the folder
/// name doesn't reveal the profile or server. Demo mode uses a temporary folder that's
/// emptied at launch, so it never touches real data.
enum InstanceStorage {
    private static let logger = Logger(subsystem: "com.jamfdash", category: "InstanceStorage")

    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JamfDash", isDirectory: true)
    }

    /// A stable, non-reversible folder name for a profile.
    static func key(forProfile name: String) -> String {
        let digest = SHA256.hash(data: Data(name.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// The folder for one profile, created if needed. The first time any profile gets a
    /// folder, drift and digest files from before 1.0 (one shared store) move into it:
    /// they came from the profile that was in use, which is almost always this one.
    static func directory(forProfile name: String) -> URL {
        let instances = root.appendingPathComponent("instances", isDirectory: true)
        let dir = instances.appendingPathComponent(key(forProfile: name), isDirectory: true)
        let fm = FileManager.default
        let isFirstInstance = !fm.fileExists(atPath: instances.path)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        if isFirstInstance { adoptLegacyFiles(into: dir) }
        return dir
    }

    /// A temporary folder for demo mode, emptied the first time it's used in each launch.
    static let demoDirectory: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("JamfDashDemo", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static func adoptLegacyFiles(into dir: URL) {
        let fm = FileManager.default
        for name in ["drift.db", "digests.json"] {
            let old = root.appendingPathComponent(name)
            guard fm.fileExists(atPath: old.path) else { continue }
            do {
                try fm.moveItem(at: old, to: dir.appendingPathComponent(name))
                logger.info("Moved \(name, privacy: .public) into the instance folder")
            } catch {
                logger.error("Couldn't move \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
