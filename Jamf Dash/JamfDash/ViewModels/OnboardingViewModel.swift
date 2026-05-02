import Foundation
import Observation

@MainActor
@Observable
final class OnboardingViewModel {

    enum Step {
        case welcome
        case cliSetup
        case productPicker  // choose Pro / Protect / School
        case authMethod     // Pro only: Local Account vs SSO
        case proSetup       // Pro local account
        case ssoSetup       // Pro SSO/OAuth
        case protectSetup   // Protect OAuth
        case schoolSetup    // School API key
        case complete
    }

    enum AuthMethod {
        case localAccount
        case sso
    }

    enum APIScope: Int, CaseIterable, Identifiable {
        case readOnly  = 1
        case standard  = 2
        case fullAdmin = 3

        var id: Int { rawValue }
        var label: String {
            switch self {
            case .readOnly:  return "Read Only — read access to all resources"
            case .standard:  return "Standard — read, create, update (recommended)"
            case .fullAdmin: return "Full Admin — all privileges"
            }
        }
    }

    private(set) var step: Step
    private(set) var isDownloading    = false
    private(set) var downloadProgress = ""
    private(set) var isRunningSetup   = false
    private(set) var error: String?

    // Product selection
    var selectedProduct: JamfProduct = .pro

    // Pro — local account fields
    var serverURL   = ""
    var username    = ""
    var password    = ""
    var scope       = APIScope.standard
    var profileName = "Jamf-CLI - Standard"

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

    private let cliManager: CLIManager
    private let profileService: ProfileService

    init(cliManager: CLIManager, profileService: ProfileService, startAt: Step = .welcome) {
        self.cliManager     = cliManager
        self.profileService = profileService
        self.step           = startAt
    }

    // MARK: - Navigation

    func advance() {
        if step == .welcome { step = .cliSetup }
    }

    func skipCLISetup() {
        step = .productPicker
    }

    func chooseProduct(_ product: JamfProduct) {
        selectedProduct = product
        switch product {
        case .pro:      step = .authMethod
        case .protect:  step = .protectSetup
        case .school:   step = .schoolSetup
        }
    }

    func chooseAuthMethod(_ method: AuthMethod) {
        step = method == .localAccount ? .proSetup : .ssoSetup
    }

    // MARK: - CLI Download

    func downloadCLI() async {
        isDownloading    = true
        downloadProgress = "Downloading jamf-cli…"
        error            = nil
        do {
            try await cliManager.ensureBinary()
            downloadProgress = "jamf-cli installed successfully."
            step = await cliManager.hasProfiles() ? .complete : .productPicker
        } catch {
            self.error       = error.localizedDescription
            downloadProgress = ""
        }
        isDownloading = false
    }

    // MARK: - Pro Local Account Setup

    var canRunLocalSetup: Bool {
        !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.isEmpty
    }

    func runLocalSetup() async {
        isRunningSetup = true
        error          = nil
        do {
            let name = profileName.trimmingCharacters(in: .whitespaces).isEmpty
                           ? "Jamf-CLI - Standard"
                           : profileName.trimmingCharacters(in: .whitespaces)
            let trimmedURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try await cliManager.setup(
                serverURL:   trimmedURL,
                username:    username.trimmingCharacters(in: .whitespacesAndNewlines),
                password:    password,
                scope:       scope.rawValue,
                profileName: name
            )
            profileService.setProduct(.pro, for: name)
            profileService.setScope(scope, for: name)
            profileService.setServerURL(trimmedURL, for: name)
            try await verifyAndCleanup(profileName: name, product: .pro)
            step = .complete
        } catch {
            self.error = error.localizedDescription
        }
        isRunningSetup = false
    }

    // MARK: - Pro SSO / OAuth Setup

    var canRunSSOSetup: Bool {
        !ssoServerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !ssoClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !ssoClientSecret.isEmpty
    }

    func runSSOSetup() async {
        isRunningSetup = true
        error          = nil
        do {
            let name = ssoProfileName.trimmingCharacters(in: .whitespaces).isEmpty
                           ? "Jamf-CLI - SSO"
                           : ssoProfileName.trimmingCharacters(in: .whitespaces)
            let trimmedURL = ssoServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try await cliManager.setupOAuth(
                serverURL:    trimmedURL,
                profileName:  name,
                clientID:     ssoClientID.trimmingCharacters(in: .whitespacesAndNewlines),
                clientSecret: ssoClientSecret
            )
            profileService.setProduct(.pro, for: name)
            profileService.setScope(.fullAdmin, for: name)
            profileService.setServerURL(trimmedURL, for: name)
            try await verifyAndCleanup(profileName: name, product: .pro)
            step = .complete
        } catch {
            self.error = error.localizedDescription
        }
        isRunningSetup = false
    }

    // MARK: - Protect OAuth Setup

    var canRunProtectSetup: Bool {
        !protectServerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !protectClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !protectClientSecret.isEmpty
    }

    func runProtectSetup() async {
        isRunningSetup = true
        error          = nil
        do {
            let name = protectProfileName.trimmingCharacters(in: .whitespaces).isEmpty
                           ? "Jamf Protect"
                           : protectProfileName.trimmingCharacters(in: .whitespaces)
            let trimmedURL = protectServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try await cliManager.setupOAuth(
                serverURL:    trimmedURL,
                profileName:  name,
                clientID:     protectClientID.trimmingCharacters(in: .whitespacesAndNewlines),
                clientSecret: protectClientSecret
            )
            profileService.setProduct(.protect, for: name)
            profileService.setServerURL(trimmedURL, for: name)
            try await verifyAndCleanup(profileName: name, product: .protect)
            step = .complete
        } catch {
            self.error = error.localizedDescription
        }
        isRunningSetup = false
    }

    // MARK: - School API Key Setup

    var canRunSchoolSetup: Bool {
        !schoolServerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !schoolNetworkID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !schoolAPIKey.isEmpty
    }

    func runSchoolSetup() async {
        isRunningSetup = true
        error          = nil
        do {
            let name = schoolProfileName.trimmingCharacters(in: .whitespaces).isEmpty
                           ? "Jamf School"
                           : schoolProfileName.trimmingCharacters(in: .whitespaces)
            let trimmedURL = schoolServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try await cliManager.setupSchool(
                serverURL:   trimmedURL,
                profileName: name,
                networkID:   schoolNetworkID.trimmingCharacters(in: .whitespacesAndNewlines),
                apiKey:      schoolAPIKey
            )
            profileService.setProduct(.school, for: name)
            profileService.setServerURL(trimmedURL, for: name)
            try await verifyAndCleanup(profileName: name, product: .school)
            step = .complete
        } catch {
            self.error = error.localizedDescription
        }
        isRunningSetup = false
    }

    // MARK: - Verification

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
}
