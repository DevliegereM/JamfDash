import Foundation
import OSLog
import Observation

@MainActor
@Observable
final class SecurityViewModel {
    private static let logger = Logger(subsystem: "com.jamfdash", category: "SecurityViewModel")
    private(set) var state: LoadState<SecurityReport> = .idle
    private let repository: SecurityRepository

    init(repository: SecurityRepository) {
        self.repository = repository
    }

    func load(force: Bool = false) async {
        guard force || state.value == nil else { return }
        guard force || !state.isLoading else { return }
        Self.logger.debug("Loading security report")
        state = .loading
        do {
            let report = try await repository.fetch()
            Self.logger.debug("Loaded security report: \(report.devices.count) devices")
            state = .loaded(report)
        } catch {
            Self.logger.error("Failed to load security report: \(error)")
            state = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    var summary: SecuritySummary? {
        state.value?.summary
    }

    var osVersions: [OSVersionRow] {
        state.value?.osVersions ?? []
    }

    var devices: [DeviceSecurity] {
        state.value?.devices ?? []
    }
}
