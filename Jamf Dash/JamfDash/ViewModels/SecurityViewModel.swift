import Foundation
import Observation

@MainActor
@Observable
final class SecurityViewModel {
    private(set) var state: LoadState<SecurityReport> = .idle
    private let repository: SecurityRepository

    init(repository: SecurityRepository) {
        self.repository = repository
    }

    func load(force: Bool = false) async {
        guard force || state.value == nil else { return }
        guard force || !state.isLoading else { return }
        state = .loading
        do {
            let report = try await repository.fetch()
            state = .loaded(report)
        } catch {
            state = .failed(error.localizedDescription)
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
