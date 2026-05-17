import Foundation

enum ErrorMessageFormatter {
    static func message(for error: Error) -> String {
        if let cliError = error as? CLIError {
            return cliError.localizedDescription
        }
        return error.localizedDescription
    }
}
