import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    enum Phase {
        case launching
        case onboarding   // binary not yet installed
        case setup        // binary installed but no profile configured
        case main
    }

    private(set) var phase: Phase = .launching
    private(set) var updateAvailable: String?
    private(set) var isUpdatingBinary = false
    private(set) var updateError: String?

    /// Set to true when the user activates demo mode from the welcome screen.
    private(set) var demoModeRequested = false
    /// True once the demo environment is active and data is loading.
    private(set) var isDemoMode = false

    /// Convenience for displaying the installed CLI version in UI.
    var installedCLIVersion: String? { get async { await env.cliManager.installedVersion?.semver } }

    private let env: AppEnvironment

    init(env: AppEnvironment) {
        self.env = env
    }

    func bootstrap() async {
        let binaryInstalled = await env.cliManager.isBinaryInstalled
        guard binaryInstalled else {
            phase = .onboarding
            return
        }

        await env.cliManager.refreshVersion()
        let hasProfiles = await env.cliManager.hasProfiles()
        phase = hasProfiles ? .main : .setup

        if phase == .main {
            env.loadMainData()
            await env.loadProfiles()
            Task.detached(priority: .background) { [weak self] in
                guard let self else { return }
                _ = try? await self.checkForCLIUpdate()
            }
        }
    }

    func completeOnboarding() {
        phase = .main
        env.loadMainData()
        Task { await env.cliManager.refreshVersion() }
        Task { await env.loadProfiles() }
    }

    /// Called after `jamf-cli pro setup` completes successfully from the setup screen.
    func completeSetup() {
        phase = .main
        env.loadMainData()
        Task { await env.cliManager.refreshVersion() }
        Task { await env.loadProfiles() }
    }

    /// Polls GitHub for the latest jamf-cli release and sets updateAvailable if newer.
    /// Returns the new version string if an update is available, nil if already current.
    /// Throws on network/API failure so callers can surface the error.
    /// Does NOT re-run bootstrap or change the app phase.
    @discardableResult
    func checkForCLIUpdate() async throws -> String? {
        let newVersion = try await env.cliManager.checkForUpdate()
        if let v = newVersion { updateAvailable = v }
        return newVersion
    }

    // MARK: - Demo mode

    /// Called from the onboarding welcome screen to request a demo environment.
    /// The actual environment swap happens in JamfDashApp via .onChange.
    func requestDemoMode() {
        demoModeRequested = true
    }

    /// Called by JamfDashApp after it has created the demo AppEnvironment.
    /// Transitions directly to .main and triggers a data load.
    func activateDemoMode(demoEnv: AppEnvironment) {
        isDemoMode = true
        phase = .main
        demoEnv.loadMainData()
    }

    // MARK: - Binary update

    func performBinaryUpdate() async {
        isUpdatingBinary = true
        updateError = nil
        do {
            try await env.cliManager.performUpdate()
            updateAvailable = nil
        } catch {
            updateError = error.localizedDescription
        }
        isUpdatingBinary = false
    }
}
