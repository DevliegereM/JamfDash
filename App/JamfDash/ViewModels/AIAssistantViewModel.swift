import Foundation
import Observation

/// Removes the setting older builds stored for the dropped Private Cloud Compute option.
enum AIAssistantSettings {
    static func removeLegacySettings() {
        UserDefaults.standard.removeObject(forKey: "jamfDash.aiUsePrivateCloudCompute")
    }
}

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
        /// PNG of an image the user attached (macOS 27 on-device vision).
        var imageData: Data? = nil
    }

    var messages: [Message] = []
    var state: AssistantState = .idle
    var isResponding: Bool { state != .idle }
    var inputText = ""

    /// Image to send with the next message (PNG).
    var pendingImage: Data?
    /// Tool Dashie is running right now, shown in the status pill (macOS 27 tool-call hooks).
    var activeToolName: String?

    // Stores a LanguageModelSession on macOS 26+ so conversation history is preserved
    // across sends within a single chat session.
    var _session: Any?

    /// Summary of the chat before the last compaction; carried into the new session's
    /// instructions and into the next summary. Kept in memory only.
    var conversationSummary: String?

    /// Number of `messages` already folded into `conversationSummary`.
    var compactedMessageCount = 0

    /// Bumped by "New Chat". A reply that started in an earlier chat checks this and stops
    /// touching `messages`; its session stays alive until the reply ends, because releasing a
    /// LanguageModelSession mid-generation crashes inside FoundationModels.
    private(set) var chatGeneration = 0

    let cli: any CLIRunning

    init(cli: any CLIRunning) {
        self.cli = cli
        AIAssistantSettings.removeLegacySettings()
    }

    func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let image = pendingImage
        guard !text.isEmpty || image != nil else { return }

        messages.append(Message(role: .user, content: text, imageData: image))
        let prompt = text.isEmpty ? "What does this image show? If it relates to Jamf or Mac management, explain it." : text
        inputText = ""
        pendingImage = nil
        let generation = chatGeneration

        state = .thinking

        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            await sendWithFoundationModels(prompt: prompt, imageData: image)
        } else {
            appendErrorMessage()
        }
        #else
        appendErrorMessage()
        #endif

        // A reply from a chat the user already cleared must not reset the new chat's state.
        if generation == chatGeneration { state = .idle }
    }

    func clearHistory() {
        chatGeneration += 1
        state = .idle
        activeToolName = nil
        pendingImage = nil
        messages = []
        inputText = ""
        _session = nil
        conversationSummary = nil
        compactedMessageCount = 0
    }

    private func appendErrorMessage() {
        messages.append(Message(
            role: .assistant,
            content: "The AI Assistant requires macOS 26 with Apple Intelligence."
        ))
    }
}
