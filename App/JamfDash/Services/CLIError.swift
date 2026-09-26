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
            if let readable = JamfCLIErrorPayload(output: stderr)?.readableMessage {
                return readable
            }
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

/// The JSON error jamf-cli prints on failure, e.g.
/// `{"error": "permission_denied", "exitCode": 5, "hint": "…", "message": "…"}`.
/// Anything before the JSON (prompts, progress lines) is ignored.
struct JamfCLIErrorPayload: Decodable, Equatable {
    let error: String?
    let exitCodeName: String?
    let message: String?
    let hint: String?

    init?(output: String) {
        guard let start = output.firstIndex(of: "{"), let end = output.lastIndex(of: "}"), start < end,
              let payload = try? JSONDecoder().decode(Self.self, from: Data(output[start...end].utf8)),
              payload.message != nil || payload.hint != nil
        else { return nil }
        self = payload
    }

    private var kind: String { exitCodeName ?? error ?? "" }

    var isPermissionDenied: Bool { kind == "permission_denied" }

    /// A sentence for the UI, with the hint on its own paragraph.
    var readableMessage: String {
        let detail = message.map(Self.clean) ?? ""
        var text: String
        switch kind {
        case "permission_denied":
            text = "The API client doesn't have permission for this."
            if hint == nil, !detail.isEmpty { text += "\n\n" + detail }
        case "unsupported":
            // jamf-cli refuses a command before sending it (exit 8) when the profile's API
            // doesn't offer it — in either direction.
            if detail.contains("gateway's published API") {
                return "This isn't available through the Jamf Platform API. Use a Jamf Pro connection (an API client or local admin account for your Jamf Pro instance) for this."
            }
            if detail.localizedCaseInsensitiveContains("platform setup") || (hint ?? "").localizedCaseInsensitiveContains("platform setup") {
                return "This needs a Jamf Platform API connection. Add one in Settings → Connection."
            }
            return detail.components(separatedBy: "\n\n").first ?? detail
        case "authentication":
            text = "Authentication failed" + (detail.isEmpty ? "." : ": " + detail)
        default:
            text = detail.isEmpty ? "jamf-cli failed (\(kind))." : detail
        }
        if let hint, !hint.isEmpty {
            text += "\n\n" + Self.capitalizedFirst(hint)
        }
        return text
    }

    /// Drops the request plumbing jamf-cli appends to API errors (trace IDs, method/URL).
    private static func clean(_ message: String) -> String {
        var m = message
        for pattern in [#",?\s*traceId [0-9a-f]+"#, #"\s*\(method=[A-Z]+, url=[^)]*\)"#] {
            m = m.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return m.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func capitalizedFirst(_ s: String) -> String {
        s.prefix(1).uppercased() + s.dropFirst()
    }
}
