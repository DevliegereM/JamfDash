import Foundation
import Sparkle

/// Wraps SPUStandardUpdaterController for use in a @MainActor / Swift 6 context.
@MainActor
final class AppUpdater: NSObject {
    static let shared = AppUpdater()

    let controller: SPUStandardUpdaterController

    private override init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
