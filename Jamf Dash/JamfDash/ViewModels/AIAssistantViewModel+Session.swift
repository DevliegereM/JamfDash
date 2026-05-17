#if canImport(FoundationModels)
import Foundation
import FoundationModels

@available(macOS 26, *)
extension AIAssistantViewModel {

    // MARK: - Session

    private var languageModelSession: LanguageModelSession {
        if let existing = _session as? LanguageModelSession { return existing }
        let session = LanguageModelSession(
            model: .default,
            tools: Self.tools(cli: cli),
            instructions: Self.systemPrompt
        )
        _session = session
        return session
    }

    // Tools are a static factory so the availability-guarded types stay out of the
    // stored-property requirement on the ViewModel.
    private static func tools(cli: any CLIRunning) -> [any Tool] {
        [
            // Read
            ListComputersTool(cli: cli),
            GetComputerDetailTool(cli: cli),
            GetInstalledAppsTool(cli: cli),
            GetSecurityReportTool(cli: cli),
            GetComplianceTool(cli: cli),
            GetOverviewTool(cli: cli),
            GetPatchStatusTool(cli: cli),
            GetPoliciesTool(cli: cli),
            GetSmartGroupsTool(cli: cli),
            GetInventorySummaryTool(cli: cli),
            // Actions
            BlankPushTool(cli: cli),
            RenewMDMProfileTool(cli: cli),
            RedeployFrameworkTool(cli: cli),
            FlushFailedCommandsTool(cli: cli),
            RestartDeviceTool(cli: cli),
            ExecutePolicyTool(cli: cli),
            BulkEnablePoliciesTool(cli: cli),
            BulkDisablePoliciesTool(cli: cli),
        ]
    }

    // MARK: - Send

    func sendWithFoundationModels(prompt: String) async {
        // Verify the model is ready before even creating a session.
        switch SystemLanguageModel.default.availability {
        case .available:
            break
        case .unavailable(let reason):
            let msg: String
            switch reason {
            case .deviceNotEligible:
                msg = "This device does not support Apple Intelligence."
            case .appleIntelligenceNotEnabled:
                msg = "Apple Intelligence is not enabled. Go to System Settings → Apple Intelligence & Siri to turn it on."
            case .modelNotReady:
                msg = "The Apple Intelligence model is still downloading. Please wait and try again."
            @unknown default:
                msg = "Apple Intelligence is unavailable on this device."
            }
            messages.append(Message(role: .assistant, content: msg))
            return
        @unknown default:
            break
        }

        await compactContextIfNeeded()
        await stream(prompt: prompt, retrying: false)
    }

    // Lower temperature → more factual, deterministic answers for fleet management.
    private static let generationOptions = GenerationOptions(temperature: 0.4)

    private func stream(prompt: String, retrying: Bool) async {
        var assistantIdx: Int? = nil

        do {
            let stream = languageModelSession.streamResponse(
                to: prompt,
                options: Self.generationOptions
            )
            for try await snapshot in stream {
                if assistantIdx == nil {
                    messages.append(Message(role: .assistant, content: snapshot.content))
                    assistantIdx = messages.count - 1
                    messages[assistantIdx!].isStreaming = true
                    state = .talking
                } else {
                    messages[assistantIdx!].content = snapshot.content
                }
            }
        } catch let error as LanguageModelSession.GenerationError {
            if case .exceededContextWindowSize = error, !retrying {
                if let idx = assistantIdx { messages.remove(at: idx) }
                await performContextCompaction()
                await stream(prompt: prompt, retrying: true)
                return
            }
            appendError(generationErrorMessage(error), at: &assistantIdx)
        } catch let nsError as NSError
                where nsError.domain.contains("GenerationError") || nsError.domain.contains("FoundationModels") {
            // The framework sometimes bridges unknown error codes as NSError rather than the
            // typed Swift enum. Code -1 is a generic internal failure.
            let text: String
            switch nsError.code {
            case -1:
                text = "The model returned an internal error. This can happen when the request is too complex or the model is busy. Try rephrasing your question or starting a new chat."
            default:
                text = "The model returned an error (code \(nsError.code)). Try again or start a new chat."
            }
            appendError(text, at: &assistantIdx)
        } catch {
            appendError("Error: \(error.localizedDescription)", at: &assistantIdx)
        }

        if let idx = assistantIdx {
            messages[idx].isStreaming = false
        }
    }

    private func appendError(_ text: String, at idx: inout Int?) {
        if let i = idx {
            messages[i].content = text
        } else {
            messages.append(Message(role: .assistant, content: text))
            idx = messages.count - 1
        }
    }

    // MARK: - Context compaction

    // Rough threshold: ~10 000 chars ≈ 2 500 tokens, well below typical 4 096-token on-device limits.
    private static let contextCharacterThreshold = 10_000

    private func compactContextIfNeeded() async {
        let totalChars = messages.reduce(0) { $0 + $1.content.count }
        guard totalChars > Self.contextCharacterThreshold else { return }
        await performContextCompaction()
    }

    func performContextCompaction() async {
        let transcript = messages.map { msg -> String in
            let role = msg.role == .user ? "User" : "Assistant"
            return "\(role): \(msg.content)"
        }.joined(separator: "\n\n")

        let summarySession = LanguageModelSession(model: .default)
        let summaryPrompt = """
            Summarize this Jamf fleet management conversation as compact JSON. \
            Return ONLY valid JSON with no other text, using this exact structure:
            {
              "totalMessages": <int>,
              "keyTopics": [<string>],
              "devicesDiscussed": [<string>],
              "actionsPerformed": [<string>],
              "importantFindings": [<string with numbers where relevant>],
              "lastContext": "<brief description of the last discussion topic>"
            }

            Conversation:
            \(transcript)
            """

        var summaryContent = ""
        do {
            let stream = summarySession.streamResponse(to: summaryPrompt)
            for try await snapshot in stream {
                summaryContent = snapshot.content
            }
        } catch {
            // Summarisation failed — just reset the session without history.
            _session = nil
            messages = [Message(role: .assistant, content: "*(Conversation cleared to free up context window.)*")]
            return
        }

        let savedPath = saveConversationSummary(summaryContent)

        let enrichedInstructions = Self.systemPrompt
            + "\n\n## Previous conversation summary\n\(summaryContent)"
        let newSession = LanguageModelSession(
            model: .default,
            tools: Self.tools(cli: cli),
            instructions: enrichedInstructions
        )
        _session = newSession

        let notice: String
        if let path = savedPath {
            notice = "*(Conversation history compacted and saved to `\(path)`. Continuing with full context.)*"
        } else {
            notice = "*(Conversation history compacted. Continuing with full context.)*"
        }
        messages = [Message(role: .assistant, content: notice)]
    }

    @discardableResult
    private func saveConversationSummary(_ json: String) -> String? {
        let fm = FileManager.default
        guard let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = support.appendingPathComponent("JamfDash", isDirectory: true)
        guard (try? fm.createDirectory(at: dir, withIntermediateDirectories: true)) != nil else { return nil }
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let file = dir.appendingPathComponent("conversation-summary-\(timestamp).json")
        guard let data = json.data(using: .utf8), (try? data.write(to: file)) != nil else { return nil }
        return file.path
    }

    // MARK: - System prompt

    private static let systemPrompt = """
        You are Dashie, an AI assistant for Jamf Dash (Jamf Pro fleet management). \
        Help admins manage their fleet. You cannot create/update/delete Jamf Pro objects — \
        tell the user to do that in Jamf Pro instead.

        Tool routing:
        • Single-device hardware (CPU, RAM, disk, model, make): getComputerDetail
        • Single-device apps: getInstalledApps
        • Fleet-wide hardware breakdown (model counts, RAM distribution, disk sizes): getInventorySummary
        • Per-device filtering by OS, serial, or name: listComputers
        • Fleet-wide health/stats: getOverview
        • Patch status: getPatchStatus
        • Security posture: getSecurityReport
        • Compliance: getCompliance

        Rules: call tools only when needed; one tool per response. \
        Before any action tool, state exactly what you will do and ask "Shall I proceed?" — \
        only act after the user confirms.

        When a tool returns data, present the actual values — names, serials, \
        model names, CPU specs, RAM, disk sizes — as a bullet list. \
        Never summarise what you received without showing the data.

        Answer concisely.
        """

    // MARK: - Error helpers

    private func generationErrorMessage(_ error: LanguageModelSession.GenerationError) -> String {
        switch error {
        case .assetsUnavailable:
            return "Apple Intelligence is not available on this device or is still downloading."
        case .guardrailViolation:
            return "The response was blocked by content guardrails."
        case .exceededContextWindowSize:
            return "The conversation history is too long for the model. Use \"New Chat\" to start a fresh session."
        case .rateLimited:
            return "The model is being rate limited. Please wait a moment and try again."
        case .concurrentRequests:
            return "Another request is in progress. Please wait for it to finish."
        case .refusal:
            return "The model declined to answer this request."
        default:
            return "The model returned an unexpected error. Try rephrasing or starting a new chat."
        }
    }
}

#endif
