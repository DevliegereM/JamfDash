import Foundation
import Observation
import AppKit

@MainActor
@Observable
final class SettingsViewModel {

    // MARK: - Product & Setup Method
    var selectedProduct: JamfProduct = .pro
    enum SetupMethod { case localAccount, sso }
    var setupMethod = SetupMethod.localAccount

    // Pro — local account fields
    var serverURLText = ""
    var username      = ""
    var password      = ""
    var setupScope    = OnboardingViewModel.APIScope.standard
    var profileName   = "Jamf-CLI - Standard"

    // Pro — SSO / OAuth fields
    var ssoServerURL    = ""
    var ssoProfileName  = "Jamf-CLI - SSO"
    var ssoClientID     = ""
    var ssoClientSecret = ""

    // Protect — OAuth fields
    var protectServerURL    = ""
    var protectProfileName  = "Jamf Protect"
    var protectClientID     = ""
    var protectClientSecret = ""

    // School — API key fields
    var schoolServerURL   = ""
    var schoolProfileName = "Jamf School"
    var schoolNetworkID   = ""
    var schoolAPIKey      = ""

    private(set) var isRunningSetup = false
    var setupError: String?
    var setupSuccess  = false

    // MARK: - Profile
    var profileName_selected: String = ""
    private(set) var availableProfiles: [String] = []   // read from keychain

    // MARK: - CLI
    private(set) var isCheckingUpdate = false
    private(set) var isUpdating       = false
    private(set) var isInstallingCLI  = false
    private(set) var updateStatus: String?
    private(set) var availableUpdate: String?
    private(set) var installedVersion: String?

    // MARK: - Branding
    private(set) var logoURL: URL?

    var deleteError: String?

    // MARK: - Callbacks wired by AppEnvironment.makeSettingsVM()

    var onProfilesChanged: (() -> Void)?
    var onProfileSwitched: ((String) -> Void)?

    private let cliManager: CLIManager
    private let profileService: ProfileService
    private let keychain: KeychainService

    init(keychain: KeychainService, profileService: ProfileService, cliManager: CLIManager) {
        self.cliManager     = cliManager
        self.profileService = profileService
        self.keychain       = keychain
    }

    func loadExisting() async {
        profileName_selected = profileService.selectedProfile.name
        availableProfiles    = await keychain.jamfCLIProfiles()
        installedVersion     = await cliManager.installedVersion?.semver
        logoURL              = BrandingService.logoURL
    }

    // MARK: - Setup

    var canRunSetup: Bool {
        switch selectedProduct {
        case .pro:
            switch setupMethod {
            case .localAccount:
                return !serverURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                       !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                       !password.isEmpty
            case .sso:
                return !ssoServerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                       !ssoClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                       !ssoClientSecret.isEmpty
            }
        case .protect:
            return !protectServerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                   !protectClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                   !protectClientSecret.isEmpty
        case .school:
            return !schoolServerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                   !schoolNetworkID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                   !schoolAPIKey.isEmpty
        }
    }

    func runSetup() async {
        isRunningSetup = true
        setupError     = nil
        setupSuccess   = false
        do {
            switch selectedProduct {
            case .pro:
                let name: String
                let scopeForProfile: OnboardingViewModel.APIScope
                switch setupMethod {
                case .localAccount:
                    name = profileName.trimmingCharacters(in: .whitespaces).isEmpty
                               ? "Jamf-CLI - Standard"
                               : profileName.trimmingCharacters(in: .whitespaces)
                    scopeForProfile = setupScope
                    let trimURL = serverURLText.trimmingCharacters(in: .whitespacesAndNewlines)
                    _ = try await cliManager.setup(
                        serverURL:   trimURL,
                        username:    username.trimmingCharacters(in: .whitespacesAndNewlines),
                        password:    password,
                        scope:       setupScope.rawValue,
                        profileName: name
                    )
                    profileService.setServerURL(trimURL, for: name)
                case .sso:
                    name = ssoProfileName.trimmingCharacters(in: .whitespaces).isEmpty
                               ? "Jamf-CLI - SSO"
                               : ssoProfileName.trimmingCharacters(in: .whitespaces)
                    scopeForProfile = .fullAdmin
                    let trimURL = ssoServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    _ = try await cliManager.setupOAuth(
                        serverURL:    trimURL,
                        profileName:  name,
                        clientID:     ssoClientID.trimmingCharacters(in: .whitespacesAndNewlines),
                        clientSecret: ssoClientSecret
                    )
                    profileService.setServerURL(trimURL, for: name)
                }
                profileService.setProduct(.pro, for: name)
                profileService.setScope(scopeForProfile, for: name)
                try await verifyAndCleanup(profileName: name, product: .pro)

            case .protect:
                let name = protectProfileName.trimmingCharacters(in: .whitespaces).isEmpty
                               ? "Jamf Protect"
                               : protectProfileName.trimmingCharacters(in: .whitespaces)
                let trimURL = protectServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
                _ = try await cliManager.setupOAuth(
                    serverURL:    trimURL,
                    profileName:  name,
                    clientID:     protectClientID.trimmingCharacters(in: .whitespacesAndNewlines),
                    clientSecret: protectClientSecret
                )
                profileService.setProduct(.protect, for: name)
                profileService.setServerURL(trimURL, for: name)
                try await verifyAndCleanup(profileName: name, product: .protect)

            case .school:
                let name = schoolProfileName.trimmingCharacters(in: .whitespaces).isEmpty
                               ? "Jamf School"
                               : schoolProfileName.trimmingCharacters(in: .whitespaces)
                let trimURL = schoolServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
                _ = try await cliManager.setupSchool(
                    serverURL:   trimURL,
                    profileName: name,
                    networkID:   schoolNetworkID.trimmingCharacters(in: .whitespacesAndNewlines),
                    apiKey:      schoolAPIKey
                )
                profileService.setProduct(.school, for: name)
                profileService.setServerURL(trimURL, for: name)
                try await verifyAndCleanup(profileName: name, product: .school)
            }
            setupSuccess      = true
            availableProfiles = await keychain.jamfCLIProfiles()
            onProfilesChanged?()
            clearSetupForm()
        } catch {
            setupError = error.localizedDescription
        }
        isRunningSetup = false
    }

    private func verifyAndCleanup(profileName: String, product: JamfProduct) async throws {
        do {
            try await cliManager.verifyConnection(profileName: profileName, product: product)
        } catch {
            try? await cliManager.removeProfile(profileName)
            profileService.removeProfileData(profileName)
            throw setupVerificationError(from: error, profile: profileName)
        }
    }

    private func setupVerificationError(from error: Error, profile: String) -> Error {
        if case CLIError.nonZeroExit(_, let stderr) = error {
            let lower = stderr.lowercased()
            let reason: String
            if lower.contains("authentication") || lower.contains("unauthorized") ||
               lower.contains("invalid") || lower.contains("forbidden") || lower.contains("401") {
                reason = "Authentication failed — check your credentials and try again."
            } else {
                reason = stderr.isEmpty ? error.localizedDescription : stderr
            }
            return NSError(domain: "JamfDash", code: 1,
                           userInfo: [NSLocalizedDescriptionKey: "Could not connect to \"\(profile)\": \(reason)"])
        }
        return NSError(domain: "JamfDash", code: 1,
                       userInfo: [NSLocalizedDescriptionKey: "Could not connect to \"\(profile)\": \(error.localizedDescription)"])
    }

    private func clearSetupForm() {
        serverURLText = ""; username = ""; password = ""
        ssoServerURL = ""; ssoClientID = ""; ssoClientSecret = ""
        protectServerURL = ""; protectClientID = ""; protectClientSecret = ""
        schoolServerURL = ""; schoolNetworkID = ""; schoolAPIKey = ""
    }

    // MARK: - Profile actions

    func saveProfile() {
        let name = profileName_selected.trimmingCharacters(in: .whitespaces)
        profileService.selectedProfile = JamfProfile(name: name)
        onProfileSwitched?(name)
    }

    func deleteProfile(_ name: String) async {
        deleteError = nil
        do {
            try await cliManager.removeProfile(name)
            profileService.removeProfileData(name)
            availableProfiles = await keychain.jamfCLIProfiles()
            onProfilesChanged?()
            if profileName_selected == name {
                profileName_selected = ""
                saveProfile()
            }
        } catch {
            deleteError = "Failed to remove \"\(name)\": \(error.localizedDescription)"
        }
    }

    // MARK: - CLI install / update actions

    func installCLI() async {
        isInstallingCLI = true
        updateStatus    = nil
        do {
            try await cliManager.ensureBinary()
            installedVersion = await cliManager.installedVersion?.semver
            updateStatus     = "jamf-cli installed successfully."
        } catch {
            updateStatus = "Installation failed: \(error.localizedDescription)"
        }
        isInstallingCLI = false
    }

    func checkForUpdate() async {
        isCheckingUpdate = true
        updateStatus     = nil
        availableUpdate  = nil
        do {
            if let newVersion = try await cliManager.checkForUpdate() {
                availableUpdate = newVersion
                updateStatus    = "Update available: \(newVersion)"
            } else {
                updateStatus = "jamf-cli is up to date."
            }
        } catch {
            updateStatus = "Update check failed: \(error.localizedDescription)"
        }
        isCheckingUpdate = false
    }

    func performUpdate() async {
        isUpdating   = true
        updateStatus = nil
        do {
            try await cliManager.performUpdate()
            installedVersion = await cliManager.installedVersion?.semver
            availableUpdate  = nil
            updateStatus     = "Updated to \(installedVersion ?? "latest") successfully."
        } catch {
            updateStatus = "Update failed: \(error.localizedDescription)"
        }
        isUpdating = false
    }

    // MARK: - Branding actions

    func chooseLogo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a company logo for PDF reports"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? BrandingService.saveLogo(from: url)
        logoURL = BrandingService.logoURL
    }

    func removeLogo() {
        try? BrandingService.removeLogo()
        logoURL = nil
    }

    func run(_ command: CLICommand) async throws -> Data {
        try await cliManager.run(command)
    }
}
