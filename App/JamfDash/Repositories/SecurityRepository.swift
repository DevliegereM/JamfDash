import Foundation
import OSLog

struct SecurityRepository: Sendable {
    private static let logger = Logger(subsystem: "com.jamfdash", category: "SecurityRepository")
    let cli: any CLIRunning

    func fetch() async throws -> SecurityReport {
        let data: Data
        do {
            data = try await cli.run(.securityReport)
        } catch CLIError.nonZeroExit(_, let stderr) where Self.isMissingInventoryEndpoint(stderr) {
            // jamf-cli's security report asks for /v4/computers-inventory without the /v1
            // fallback its generated commands have; some Platform gateways answer 404.
            Self.logger.notice("Security report endpoint not served — building the report from inventory")
            let inventory = try await cli.run(.securityInventory)
            do {
                return try SecurityReport(inventory: inventory)
            } catch {
                throw CLIError.decodingFailed(error.localizedDescription)
            }
        }
        do {
            let envelopes = try JSONDecoder().decode([SecurityEnvelope].self, from: data)
            let report = SecurityReport(from: envelopes)
            if report.summary == nil {
                Self.logger.warning("Security report is missing its summary section — CLI schema may have changed")
            }
            if report.devices.isEmpty {
                Self.logger.warning("Security report contains no device records — fleet may be empty or CLI schema may have changed")
            }
            return report
        } catch {
            throw CLIError.decodingFailed(error.localizedDescription)
        }
    }

    static func isMissingInventoryEndpoint(_ stderr: String) -> Bool {
        guard let payload = JamfCLIErrorPayload(output: stderr),
              (payload.exitCodeName ?? payload.error) == "not_found" else { return false }
        return payload.message?.contains("computers-inventory") == true
    }
}
