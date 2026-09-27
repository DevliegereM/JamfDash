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

}
