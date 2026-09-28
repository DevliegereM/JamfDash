import Foundation

enum ErrorMessageFormatter {
    static func message(for error: Error) -> String {
        if let cliError = error as? CLIError {
            return cliError.localizedDescription
        }
        return error.localizedDescription
    }

    /// A description safe to log as public: the error's type and code, never its text,
    /// which for jamf-cli can contain server addresses, serials and names.
    static func logSummary(for error: Error) -> String {
        switch error {
        case CLIError.nonZeroExit(let code, let stderr):
            let kind = JamfCLIErrorPayload(output: stderr)?.exitCodeName ?? "unknown"
            return "jamf-cli exit \(code) (\(kind))"
        case let cliError as CLIError:
            return "CLIError.\(String(describing: cliError).prefix { $0 != "(" })"
        default:
            let ns = error as NSError
            return "\(ns.domain) \(ns.code)"
        }
    }
}
