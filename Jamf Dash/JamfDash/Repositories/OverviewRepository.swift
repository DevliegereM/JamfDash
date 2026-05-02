import Foundation

struct OverviewRepository: Sendable {
    let cli: any CLIRunning

    func fetch() async throws -> [OverviewItem] {
        let data = try await cli.run(.overview)
        do {
            return try JSONDecoder().decode([OverviewItem].self, from: data)
        } catch {
            throw CLIError.decodingFailed(error.localizedDescription)
        }
    }
}
