import Foundation
import OSLog
import Observation

@MainActor
@Observable
final class OverviewViewModel {
    private static let logger = Logger(subsystem: "com.jamfdash", category: "OverviewViewModel")
    private(set) var state: LoadState<[OverviewItem]> = .idle
    private let repository: OverviewRepository

    init(repository: OverviewRepository) {
        self.repository = repository
    }

    func load(force: Bool = false) async {
        guard force || state.value == nil else { return }
        guard force || !state.isLoading else { return }
        Self.logger.debug("Loading overview")
        state = .loading
        do {
            let items = try await repository.fetch()
            Self.logger.debug("Loaded \(items.count) overview items")
            state = .loaded(items)
        } catch {
            Self.logger.error("Failed to load overview: \(error)")
            state = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    // MARK: - Computed views on data

    var sections: [(title: String, items: [OverviewItem])] {
        guard case .loaded(let items) = state else { return [] }
        let grouped = Dictionary(grouping: items, by: \.section)
        let sectionOrder = [
            "Health & Alerts",
            "Instance",
            "Fleet",
            "Configuration",
            "Organization",
            "Enrollment & Certificates",
            "Features",
            "Security"
        ]
        return sectionOrder.compactMap { section in
            guard let group = grouped[section], !group.isEmpty else { return nil }
            return (title: section, items: group)
        }
    }

    func value(for resource: String) -> String? {
        guard case .loaded(let items) = state else { return nil }
        return items.first(where: { $0.resource == resource })?.value
    }


}
