import Foundation

enum CLIError: Error, Sendable {
    case binaryMissing
    case launchFailed(String)
    case nonZeroExit(code: Int, stderr: String)
    case decodingFailed(String)
    case credentialsMissing
    case downloadFailed(String)
    case checksumMismatch(expected: String, actual: String)
    case versionNotFound(String)
    case timeout
    case untrustedBinary(String)
    case unexpectedPrompt(String)
    case cliTooOld(installed: String, minimum: String)
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
        case .checksumMismatch(let expected, let actual):
            return "jamf-cli download integrity check failed. Expected SHA256 \(expected.prefix(12))…, got \(actual.prefix(12))…"
        case .versionNotFound(let ver):
            return "jamf-cli version '\(ver)' was not found locally or in the release repository."
        case .timeout:
            return "The CLI command timed out."
        case .unexpectedPrompt(let question):
            return "jamf-cli asked a question Jamf Dash doesn't know how to answer (“\(question)”), so setup was stopped before answering it. Update Jamf Dash, or set up the profile in Terminal with jamf-cli."
        case .cliTooOld(let installed, let minimum):
            return "Jamf Dash needs jamf-cli \(minimum) or later (installed: \(installed)). Update it from Settings → CLI."
        case .untrustedBinary(let reason):
            return "jamf-cli failed its code signature check and was not run: \(reason). Reinstall it from Settings → CLI."
        }
    }
}
