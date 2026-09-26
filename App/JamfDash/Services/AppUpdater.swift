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
            startingUpdater: true,
            updaterDelegate: delegate,
            userDriverDelegate: nil
        )
        super.init()
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
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
