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
            let items = section == "Health & Alerts" ? Self.groupingAlerts(group) : group
            return (title: section, items: items)
        }
    }

    /// jamf-cli lists every active alert as its own row: the first under "Alert Types", the
    /// rest with an empty name. Identical alerts are collapsed into one row with a count
    /// ("Patch extension attribute issue ×5").
    nonisolated static func groupingAlerts(_ items: [OverviewItem]) -> [OverviewItem] {
        var out: [OverviewItem] = []
        var counts: [(value: String, count: Int)] = []
        var inAlerts = false
        var section = ""

        func flush() {
            for (i, entry) in counts.enumerated() {
                out.append(OverviewItem(
                    id: "\(section)-alert-\(entry.value)",
                    section: section,
                    resource: i == 0 ? "Alert Types" : "",
                    value: entry.count > 1 ? "\(entry.value) ×\(entry.count)" : entry.value))
            }
            counts = []
        }

        for item in items {
            if item.resource == "Alert Types" || (inAlerts && item.resource.isEmpty) {
                inAlerts = true
                section = item.section
                if let i = counts.firstIndex(where: { $0.value == item.value }) {
                    counts[i].count += 1
                } else {
                    counts.append((item.value, 1))
                }
                continue
            }
            if inAlerts { flush(); inAlerts = false }
            out.append(item)
        }
        if inAlerts { flush() }
        return out
    }

    func value(for resource: String) -> String? {
        guard case .loaded(let items) = state else { return nil }
        return items.first(where: { $0.resource == resource })?.value
    }


}
