import Foundation
import OSLog

struct SecurityRepository: Sendable {
    private static let logger = Logger(subsystem: "com.jamfdash", category: "SecurityRepository")
    let cli: any CLIRunning

    func fetch() async throws -> SecurityReport {
        let data = try await cli.run(.securityReport)
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
}
