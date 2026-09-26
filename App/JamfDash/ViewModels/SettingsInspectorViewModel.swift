import Foundation
import OSLog
import Observation

@MainActor
@Observable
final class SettingsInspectorViewModel {
    private static let logger = Logger(subsystem: "com.jamfdash", category: "SettingsInspectorViewModel")

    private(set) var selfServiceState: LoadState<Data> = .idle
    private(set) var checkInState: LoadState<Data> = .idle

    private let cli: any CLIRunning

    init(cli: any CLIRunning) { self.cli = cli }

    func load(force: Bool = false) async {
        async let ss: Void = loadSelfService(force: force)
        async let ci: Void = loadCheckIn(force: force)
        _ = await (ss, ci)
    }

    func loadSelfService(force: Bool = false) async {
        guard force || selfServiceState.value == nil else { return }
        guard force || !selfServiceState.isLoading else { return }
        selfServiceState = .loading
        do {
            selfServiceState = .loaded(try await cli.run(.selfServiceSettings))
        } catch {
            Self.logger.error("Failed to load Self Service settings: \(error)")
            selfServiceState = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    func loadCheckIn(force: Bool = false) async {
        guard force || checkInState.value == nil else { return }
        guard force || !checkInState.isLoading else { return }
        checkInState = .loading
        do {
            checkInState = .loaded(try await cli.run(.clientCheckInSettings))
        } catch {
            Self.logger.error("Failed to load Client Check-in settings: \(error)")
            checkInState = .failed(ErrorMessageFormatter.message(for: error))
        }
    }
}
