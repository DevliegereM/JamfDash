import Foundation
import OSLog

struct OverviewRepository: Sendable {
    private static let logger = Logger(subsystem: "com.jamfdash", category: "OverviewRepository")
    let cli: any CLIRunning

    func fetch() async throws -> [OverviewItem] {
        let data = try await cli.run(.overview)
        do {
            let all = try JSONDecoder().decode([OverviewItem].self, from: data)
            if all.isEmpty {
                Self.logger.warning("Overview response decoded to an empty array — jamf-cli may have returned no data")
            }
            // Items with no section AND no resource carry no useful display information.
            // Log them at debug level (expected when jamf-cli adds new fields we don't map)
            // and filter them out so the UI only shows rows it can meaningfully group.
            let valid    = all.filter { !$0.section.isEmpty || !$0.resource.isEmpty }
            let skipped  = all.count - valid.count
            if skipped > 0 {
                Self.logger.debug("Skipping \(skipped) overview item(s) with no section/resource (unmapped CLI fields)")
            }
            return valid
        } catch {
            throw CLIError.decodingFailed(error.localizedDescription)
        }
    }
}
