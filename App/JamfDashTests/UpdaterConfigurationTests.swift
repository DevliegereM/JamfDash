import XCTest
@testable import JamfDash

/// Sparkle refuses to start with an inconsistent configuration ("The updater failed to
/// start"), and the unit tests never start Sparkle, so the settings are checked here.
final class UpdaterConfigurationTests: XCTestCase {
    private func value(_ key: String) -> Any? { Bundle.main.object(forInfoDictionaryKey: key) }

    func testSignedFeedSettingsAreConsistent() {
        XCTAssertEqual(value("SUFeedURL") as? String,
                       "https://github.com/DevliegereM/JamfDash/releases/latest/download/appcast.xml")
        XCTAssertFalse((value("SUPublicEDKey") as? String ?? "").isEmpty, "updates must be EdDSA-signed")
        XCTAssertEqual(value("SURequireSignedFeed") as? Bool, true)
        // Sparkle: SURequireSignedFeed needs SUVerifyUpdateBeforeExtraction.
        XCTAssertEqual(value("SUVerifyUpdateBeforeExtraction") as? Bool, true)
    }
}
