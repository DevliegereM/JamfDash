import Foundation

struct JamfSecurityRepository: Sendable {
    let client: JamfSecurityClient

    func fetchDevices() async throws -> [JSCDevice] {
        try await client.fetchAllDevices()
    }

    func validateCredentials() async throws {
        try await client.validateCredentials()
    }
}
