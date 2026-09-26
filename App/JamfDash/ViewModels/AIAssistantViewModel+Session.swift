#if canImport(FoundationModels)
import Foundation
import FoundationModels
import OSLog

private let sessionLogger = Logger(subsystem: "com.jamfdash", category: "AIAssistant")

@available(macOS 26, *)
extension AIAssistantViewModel {

    // MARK: - Session

    private var languageModelSession: LanguageModelSession {
        if let existing = _session as? LanguageModelSession { return existing }
        let session = makeSession(instructions: Self.systemPrompt)
        _session = session
        return session
    }

    /// Creates the chat session. On macOS 27+ with the opt-in setting on (default off) and
    /// Private Cloud Compute available, uses the PCC model; otherwise the on-device model
    /// exactly as on macOS 26.
    private func makeSession(instructions: String, allowPrivateCloudCompute: Bool = true) -> LanguageModelSession {
        let tools = Self.tools(cli: cli)
        if #available(macOS 27, *), allowPrivateCloudCompute, AIAssistantSettings.usePrivateCloudCompute {
            let pcc = PrivateCloudComputeLanguageModel()
            if pcc.isAvailable {
                usesPrivateCloudCompute = true
                return LanguageModelSession(model: pcc, tools: tools, instructions: instructions)
            }
        }
        usesPrivateCloudCompute = false
        return LanguageModelSession(model: .default, tools: tools, instructions: instructions)
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

        await compactContextIfNeeded(prompt: prompt)
        await stream(prompt: prompt, retrying: false)
    }

    // Lower temperature → more factual, deterministic answers for fleet management.
    private static let generationOptions = GenerationOptions(temperature: 0.4)

    /// If a reply fails while Private Cloud Compute is in use, switches this chat to the
    /// on-device model and asks again once. Returns true when it did so.
    private func fallBackToOnDevice(prompt: String, error: Error, assistantIdx: Int?) async -> Bool {
        guard usesPrivateCloudCompute else { return false }
        let ns = error as NSError
        sessionLogger.error("Private Cloud Compute request failed — \(String(describing: error), privacy: .public) [domain \(ns.domain, privacy: .public), code \(ns.code, privacy: .public), userInfo \(String(describing: ns.userInfo), privacy: .private)] — falling back to the on-device model")
        if let idx = assistantIdx { messages.remove(at: idx) }
        _session = makeSession(instructions: Self.systemPrompt, allowPrivateCloudCompute: false)
        messages.append(Message(role: .assistant,
            content: "Private Cloud Compute didn't respond, so this chat now uses the on-device model."))
        await stream(prompt: prompt, retrying: true)
        return true
    }

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
        } catch where !retrying && Self.isOS27ContextOverflow(error) {
            // macOS 27 reports context overflow as LanguageModelError.contextSizeExceeded.
            if let idx = assistantIdx { messages.remove(at: idx) }
            await performContextCompaction()
            await stream(prompt: prompt, retrying: true)
            return
        } catch where Self.os27ErrorMessage(for: error) != nil {
            if await fallBackToOnDevice(prompt: prompt, error: error, assistantIdx: assistantIdx) { return }
            appendError(Self.os27ErrorMessage(for: error) ?? "", at: &assistantIdx)
        } catch let error as LanguageModelSession.GenerationError {
            if case .exceededContextWindowSize = error, !retrying {
                if let idx = assistantIdx { messages.remove(at: idx) }
                await performContextCompaction()
                await stream(prompt: prompt, retrying: true)
                return
            }
            if await fallBackToOnDevice(prompt: prompt, error: error, assistantIdx: assistantIdx) { return }
            appendError(generationErrorMessage(error), at: &assistantIdx)
        } catch let nsError as NSError
                where nsError.domain.contains("GenerationError") || nsError.domain.contains("FoundationModels") {
            // The framework sometimes bridges unknown error codes as NSError rather than the
            // typed Swift enum. Code -1 is a generic internal failure.
            if await fallBackToOnDevice(prompt: prompt, error: nsError, assistantIdx: assistantIdx) { return }
            sessionLogger.error("Foundation Models error — domain \(nsError.domain, privacy: .public), code \(nsError.code, privacy: .public)")
            let text: String
            switch nsError.code {
            case -1:
                text = "The model returned an internal error. This can happen when the request is too complex or the model is busy. Try rephrasing your question or starting a new chat."
            default:
                text = "The model returned an error (code \(nsError.code)). Try again or start a new chat."
            }
            appendError(text, at: &assistantIdx)
        } catch {
            if await fallBackToOnDevice(prompt: prompt, error: error, assistantIdx: assistantIdx) { return }
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

    private func compactContextIfNeeded(prompt: String) async {
        if #available(macOS 27, *) {
            // Measure the real transcript against the model's context size instead of
            // guessing from character counts (and instead of only reacting to overflow).
            if let decision = await tokenBasedCompactionDecision(prompt: prompt) {
                if decision { await performContextCompaction() }
                return
            }
        }
        let totalChars = messages.reduce(0) { $0 + $1.content.count }
        guard totalChars > Self.contextCharacterThreshold else { return }
        await performContextCompaction()
    }

    /// Compact once transcript + next prompt would use more than this share of the context,
    /// leaving room for tool output and the reply.
    private static let contextFillRatio = 0.7

    /// Returns true/false when token counting worked, nil to fall back to the heuristic.
    @available(macOS 27, *)
    private func tokenBasedCompactionDecision(prompt: String) async -> Bool? {
        guard let session = _session as? LanguageModelSession else { return false }
        let model = SystemLanguageModel.default
        do {
            let used = try await model.tokenCount(for: session.transcript)
            let next = try await model.tokenCount(for: prompt)
            var contextSize = model.contextSize
            if usesPrivateCloudCompute, let pccSize = try? await PrivateCloudComputeLanguageModel().contextSize {
                contextSize = pccSize
            }
            guard contextSize > 0 else { return nil }
            return Double(used + next) > Double(contextSize) * Self.contextFillRatio
        } catch {
            return nil
        }
    }

    @available(macOS 27, *)
    private static func contextOverflow(_ error: any Error) -> Bool {
        if let e = error as? LanguageModelError, case .contextSizeExceeded = e { return true }
        return false
    }

    private static func isOS27ContextOverflow(_ error: any Error) -> Bool {
        if #available(macOS 27, *) { return contextOverflow(error) }
        return false
    }

    /// User-facing text for the macOS 27 error types; nil on macOS 26 or for other errors.
    private static func os27ErrorMessage(for error: any Error) -> String? {
        guard #available(macOS 27, *) else { return nil }
        if let e = error as? LanguageModelError {
            switch e {
            case .contextSizeExceeded:
                return "The conversation history is too long for the model. Use \"New Chat\" to start a fresh session."
            case .rateLimited:
                return "The model is being rate limited. Please wait a moment and try again."
            case .guardrailViolation:
                return "The response was blocked by content guardrails."
            case .refusal:
                return "The model declined to answer this request."
            case .timeout:
                return "The model took too long to respond. Try again or rephrase your question."
            default:
                return "The model couldn't handle this request (\(e.localizedDescription)). Try rephrasing or starting a new chat."
            }
        }
        if let e = error as? PrivateCloudComputeLanguageModel.Error {
            switch e {
            case .quotaLimitReached:
                return "The Private Cloud Compute quota has been reached. Turn off Private Cloud Compute in Settings › AI Assistant to keep using the on-device model."
            case .networkFailure, .serviceUnavailable:
                return "Private Cloud Compute is unreachable right now. Try again, or turn it off in Settings › AI Assistant."
            @unknown default:
                return "Private Cloud Compute returned an error. Turn it off in Settings › AI Assistant to use the on-device model."
            }
        }
        return nil
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
        _session = makeSession(instructions: enrichedInstructions)

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
