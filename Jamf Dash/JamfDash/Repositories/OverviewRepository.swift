import Foundation
import OSLog

struct OverviewRepository: Sendable {
    private static let logger = Logger(subsystem: "com.jamfdash", category: "OverviewRepository")
    let cli: any CLIRunning

    func fetch() async throws -> [OverviewItem] {
        let data = try await cli.run(.overview)
        do {
            let items = try JSONDecoder().decode([OverviewItem].self, from: data)
            if items.isEmpty {
                Self.logger.warning("Overview response decoded to an empty array — jamf-cli may have returned no data")
            }
            let malformed = items.filter { $0.section.isEmpty || $0.resource.isEmpty }
            if !malformed.isEmpty {
                Self.logger.warning("Overview response contains \(malformed.count) item(s) with empty section or resource — CLI schema may have changed")
            }
            return items
        } catch {
            throw CLIError.decodingFailed(error.localizedDescription)
        }
    }
}
