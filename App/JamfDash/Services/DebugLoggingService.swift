import AppKit
import Foundation
import OSLog

// MARK: - DebugLoggingService

/// Manages verbose unified-log capture for the `com.jamfdash` subsystem.
///
/// By default the OS only persists `.notice` and above to the unified log store;
/// `.debug` and `.info` messages are discarded unless a subsystem-level override
/// is installed.  This service writes (or removes) the standard macOS logging-
/// configuration plist at:
///
///   ~/Library/Preferences/Logging/Subsystems/com.jamfdash.plist
///
/// Once the plist exists the logging daemon picks it up automatically; a full
/// `level:debug` capture becomes active for every Logger in the app.
///
/// Call `applyOnLaunch()` from `JamfDashApp.init()` so the setting takes effect
/// before any log messages are emitted.
@Observable
final class DebugLoggingService: @unchecked Sendable {

    static let shared = DebugLoggingService()

    private static let logger = Logger(subsystem: "com.jamfdash", category: "DebugLoggingService")
    private let subsystem = "com.jamfdash"

    // MARK: - State

    /// Whether verbose debug logging is currently enabled.
    var isEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "debugLoggingEnabled")
            isEnabled ? installConfig() : removeConfig()
        }
    }

    /// Human-readable path shown in the UI so users know where to look.
    var configFilePath: String { configURL.path }

    /// Last export result (url on success, message on failure)
    private(set) var lastExportURL: URL? = nil
    private(set) var exportError: String? = nil
    private(set) var isExporting: Bool = false

    // MARK: - Init

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: "debugLoggingEnabled")
    }

    // MARK: - Launch hook

    /// Call once from `JamfDashApp.init()` — reinstalls the config plist if
    /// debug logging was enabled in the previous session.
    func applyOnLaunch() {
        if isEnabled {
            installConfig()
            Self.logger.notice("Debug logging active — all levels captured for subsystem \(self.subsystem, privacy: .public)")
        }
    }

    // MARK: - Config plist

    private var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/Logging/Subsystems/\(subsystem).plist")
    }

    private func installConfig() {
        let dir = configURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let config: NSDictionary = ["DEFAULT-OPTIONS": ["level": "debug"]]
            config.write(to: configURL, atomically: true)
            Self.logger.info("Logging config installed at \(self.configURL.path, privacy: .public)")
        } catch {
            Self.logger.error("Failed to install logging config: \(error)")
        }
    }

    private func removeConfig() {
        do {
            if FileManager.default.fileExists(atPath: configURL.path) {
                try FileManager.default.removeItem(at: configURL)
                Self.logger.info("Logging config removed")
            }
        } catch {
            Self.logger.error("Failed to remove logging config: \(error)")
        }
    }

    // MARK: - Log export

    /// Runs `log show` for the last `hours` hours and saves the result to a
    /// timestamped file in the user's Downloads folder.
    @MainActor
    func exportLogs(hours: Int = 4) async {
        isExporting = true
        lastExportURL = nil
        exportError = nil

        let fileName = "JamfDash-\(formattedNow()).log"
        let outputURL = downloadsURL().appendingPathComponent(fileName)

        do {
            let output = try await LogCollector.show(hours: hours, maxBytes: 64 * 1024 * 1024)
            guard !output.isEmpty else {
                throw NSError(domain: "JamfDash", code: 1, userInfo: [NSLocalizedDescriptionKey:
                    "No log entries found for the last \(hours) hour(s). Enable debug logging and reproduce the issue first."])
            }
            try output.write(to: outputURL, atomically: true, encoding: .utf8)
            // Restrict to owner-read/write only — log content may include hostnames and profile names.
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: outputURL.path)
            lastExportURL = outputURL
            Self.logger.info("Logs exported to \(outputURL.path, privacy: .public)")
        } catch {
            exportError = error.localizedDescription
            Self.logger.error("Log export failed: \(error)")
        }
        isExporting = false
    }

    /// Reveals the exported log file in Finder.
    func revealInFinder() {
        guard let url = lastExportURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Private helpers

    private func downloadsURL() -> URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    private func formattedNow() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return fmt.string(from: Date())
    }
}
