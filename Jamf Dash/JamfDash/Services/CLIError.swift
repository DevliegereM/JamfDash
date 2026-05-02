import Foundation

enum CLIError: Error, Sendable {
    case binaryMissing
    case launchFailed(String)
    case nonZeroExit(code: Int, stderr: String)
    case decodingFailed(String)
    case credentialsMissing
    case downloadFailed(String)
    case timeout
}

extension CLIError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .binaryMissing:
            return "jamf-cli binary is not installed. Open Settings to download it."
        case .launchFailed(let msg):
            return "Failed to launch jamf-cli: \(msg)"
        case .nonZeroExit(let code, let stderr):
            return "jamf-cli exited with code \(code): \(stderr.isEmpty ? "no output" : stderr)"
        case .decodingFailed(let msg):
            return "Failed to parse CLI output: \(msg)"
        case .credentialsMissing:
            return "Jamf Pro credentials are not configured. Open Settings to add them."
        case .downloadFailed(let msg):
            return "Failed to download jamf-cli: \(msg)"
        case .timeout:
            return "The CLI command timed out."
        }
    }
}
