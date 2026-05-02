import Foundation

struct SecurityRepository: Sendable {
    let cli: any CLIRunning

    func fetch() async throws -> SecurityReport {
        let data = try await cli.run(.securityReport)
        do {
            let envelopes = try JSONDecoder().decode([SecurityEnvelope].self, from: data)
            return SecurityReport(from: envelopes)
        } catch {
            throw CLIError.decodingFailed(error.localizedDescription)
        }
    }
}
