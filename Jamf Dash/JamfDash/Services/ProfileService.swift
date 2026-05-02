import Foundation

/// Persists the selected jamf-cli profile name in UserDefaults.
/// The profile name is not sensitive — actual credentials live inside
/// jamf-cli's own keychain-backed profile store.
final class ProfileService: @unchecked Sendable {
    private let key = "selectedJamfProfile"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var selectedProfile: JamfProfile {
        get {
            let name = defaults.string(forKey: key) ?? ""
            return JamfProfile(name: name)
        }
        set {
            defaults.set(newValue.name, forKey: key)
        }
    }

    var hasConfiguredProfile: Bool {
        // Profile is optional — empty means "use active profile", which is valid
        true
    }

    // MARK: - Product type per profile

    /// Returns the Jamf product associated with a given profile name.
    /// Defaults to .pro for profiles that pre-date multi-product support.
    func product(for profileName: String) -> JamfProduct {
        guard !profileName.isEmpty else { return .pro }
        let raw = defaults.string(forKey: productKey(profileName)) ?? JamfProduct.pro.rawValue
        return JamfProduct(rawValue: raw) ?? .pro
    }

    func setProduct(_ product: JamfProduct, for profileName: String) {
        guard !profileName.isEmpty else { return }
        defaults.set(product.rawValue, forKey: productKey(profileName))
    }

    /// Convenience: product for the currently selected profile.
    var currentProduct: JamfProduct { product(for: selectedProfile.name) }

    private func productKey(_ name: String) -> String {
        "jamfDash.profileProduct.\(name)"
    }

    // MARK: - Server URL per profile (used for Jamf console deep links)

    func serverURL(for profileName: String) -> String? {
        defaults.string(forKey: serverURLKey(profileName))
    }

    func setServerURL(_ url: String, for profileName: String) {
        defaults.set(url, forKey: serverURLKey(profileName.isEmpty ? "_default_" : profileName))
    }

    var currentServerURL: String? { serverURL(for: selectedProfile.name) }

    private func serverURLKey(_ name: String) -> String {
        "jamfDash.profileServerURL.\(name.isEmpty ? "_default_" : name)"
    }

    // MARK: - Scope per profile (Jamf Pro local account only)

    func scope(for profileName: String) -> OnboardingViewModel.APIScope {
        let raw = defaults.integer(forKey: scopeKey(profileName))
        guard raw != 0 else { return .fullAdmin }
        return OnboardingViewModel.APIScope(rawValue: raw) ?? .fullAdmin
    }

    func setScope(_ scope: OnboardingViewModel.APIScope, for profileName: String) {
        guard !profileName.isEmpty else { return }
        defaults.set(scope.rawValue, forKey: scopeKey(profileName))
    }

    /// Convenience: scope for the currently selected profile.
    var currentScope: OnboardingViewModel.APIScope { scope(for: selectedProfile.name) }

    private func scopeKey(_ name: String) -> String {
        "jamfDash.profileScope.\(name)"
    }

    func removeProfileData(_ name: String) {
        guard !name.isEmpty else { return }
        defaults.removeObject(forKey: productKey(name))
        defaults.removeObject(forKey: serverURLKey(name))
        defaults.removeObject(forKey: scopeKey(name))
    }

    /// Returns available profiles by running `jamf-cli config list`.
    /// Falls back to empty array if the command fails or binary is missing.
    /// Prefer `KeychainService.jamfCLIProfiles()` for the authoritative list —
    /// this method is kept only as a secondary fallback.
    func availableProfiles(binaryURL: URL) -> [String] {
        guard FileManager.default.fileExists(atPath: binaryURL.path) else { return [] }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = binaryURL
        process.arguments = ["config", "list"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return [] }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8) else { return [] }
        // Output is one profile name per line (possibly with trailing status columns)
        return text
            .components(separatedBy: .newlines)
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return nil }
                // Take only the first whitespace-separated token (the profile name)
                return trimmed.components(separatedBy: .whitespaces).first
            }
            .filter { !$0.isEmpty }
    }
}
