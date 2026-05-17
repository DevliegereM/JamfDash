import Foundation
import Observation

enum AssistantState: Sendable {
    case idle, thinking, tool, talking
}

@MainActor
@Observable
final class AIAssistantViewModel {
    struct Message: Identifiable, Sendable {
        enum Role: Sendable { case user, assistant }
        let id = UUID()
        let role: Role
        var content: String
        var isStreaming: Bool = false
    }

    var messages: [Message] = []
    var state: AssistantState = .idle
    var isResponding: Bool { state != .idle }
    var inputText = ""

    // Stores a LanguageModelSession on macOS 26+ so conversation history is preserved
    // across sends within a single chat session.
    var _session: Any?

    let cli: any CLIRunning

    init(cli: any CLIRunning) {
        self.cli = cli
    }

    func send() async {
        guard !inputText.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let userMessage = Message(role: .user, content: inputText)
        messages.append(userMessage)
        let prompt = inputText
        inputText = ""

        state = .thinking

        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            await sendWithFoundationModels(prompt: prompt)
        } else {
            appendErrorMessage()
        }
        #else
        appendErrorMessage()
        #endif

        state = .idle
    }

    func clearHistory() {
        messages = []
        inputText = ""
        _session = nil
    }

    private func appendErrorMessage() {
        messages.append(Message(
            role: .assistant,
            content: "The AI Assistant requires macOS 26 with Apple Intelligence."
        ))
    }
}
