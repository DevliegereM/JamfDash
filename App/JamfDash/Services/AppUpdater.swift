import Foundation
import OSLog
import Sparkle

/// Wraps SPUStandardUpdaterController for use in a @MainActor / Swift 6 context.
@MainActor
final class AppUpdater: NSObject {
    static let shared = AppUpdater()

    let controller: SPUStandardUpdaterController
    private let delegate = SparkleDelegate()

    private override init() {
        controller = SPUStandardUpdaterController(
            // No update checks inside the unit-test host: with automatic checks on, it would
            // hit the live appcast on every test run.
            startingUpdater: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
            updaterDelegate: delegate,
            userDriverDelegate: nil
        )
        super.init()
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    private var updater: SPUUpdater { controller.updater }

    /// Checks the appcast once a day in the background and offers new versions.
    /// On by default (SUEnableAutomaticChecks); the user's choice is stored by Sparkle.
    var automaticallyChecks: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }

    /// Also downloads updates in the background and installs them when the app quits.
    var automaticallyDownloads: Bool {
        get { updater.automaticallyDownloadsUpdates }
        set { updater.automaticallyDownloadsUpdates = newValue }
    }

    var lastCheck: Date? { updater.lastUpdateCheckDate }
    var canCheck: Bool { updater.canCheckForUpdates }
}

// MARK: - Sparkle delegate (logging only)

private final class SparkleDelegate: NSObject, SPUUpdaterDelegate {
    private let logger = Logger(subsystem: "com.jamfdash", category: "Sparkle")

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        logger.info("Update available: \(item.displayVersionString, privacy: .public) (build \(item.versionString, privacy: .public))")
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        logger.debug("No update found: \(error.localizedDescription, privacy: .public)")
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        logger.info("Update \(item.displayVersionString, privacy: .public) downloaded — ready to install")
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: any Error) {
        logger.error("Failed to download update \(item.displayVersionString, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        logger.error("Sparkle updater aborted: \(error.localizedDescription, privacy: .public)")
    }
}
