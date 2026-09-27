#if canImport(FoundationModels)
import CoreGraphics
import Foundation
import FoundationModels
import ImageIO
import OSLog

private let sessionLogger = Logger(subsystem: "com.jamfdash", category: "AIAssistant")

@available(macOS 26, *)
extension AIAssistantViewModel {

    // MARK: - Session

    private var languageModelSession: LanguageModelSession {
        if let existing = _session as? LanguageModelSession { return existing }
        let session = makeSession(instructions: currentInstructions)
        _session = session
        return session
    }

    /// Creates the chat session on the on-device model. On macOS 27 it uses a session profile:
    /// older tool output is shortened before each turn (so long chats fit the context), and
    /// tool calls are reported to the UI as they happen.
    private func makeSession(instructions: String) -> LanguageModelSession {
        if #available(macOS 27, *) {
            return Self.makeProfileSession(
                instructions: instructions, cli: cli,
                onToolCall: { [weak self] name in await self?.toolStarted(name) },
                onToolOutput: { [weak self] in await self?.toolFinished() })
        }
        return LanguageModelSession(model: .default, tools: Self.tools(cli: cli), instructions: instructions)
    }

    /// Built outside the main actor so the profile (tools + hooks) can be handed to the session.
    @available(macOS 27, *)
    nonisolated private static func makeProfileSession(
        instructions: String,
        cli: any CLIRunning,
        onToolCall: @escaping @Sendable (String) async -> Void,
        onToolOutput: @escaping @Sendable () async -> Void
    ) -> LanguageModelSession {
        let tools = toolList(cli: cli)
        return LanguageModelSession(profile: LanguageModelSession.Profile {
            Instructions(instructions)
            tools
        }
        .historyTransform(DashieHistory.trim)
        .onToolCall { call in await onToolCall(call.toolName) }
        .onToolOutput { _, _ in await onToolOutput() })
    }

    private func toolStarted(_ name: String) {
        activeToolName = name
        if state != .talking { state = .tool }
    }

    private func toolFinished() {
        activeToolName = nil
        if state == .tool { state = .thinking }
    }

    /// True when the on-device model can read images (macOS 27 vision capability).
    static var supportsImages: Bool {
        if #available(macOS 27, *) {
            let model = SystemLanguageModel.default
            guard case .available = model.availability else { return false }
            return model.capabilities.contains(.vision)
        }
        return false
    }

    // Tools are a static factory so the availability-guarded types stay out of the
    // stored-property requirement on the ViewModel.
    static func tools(cli: any CLIRunning) -> [any Tool] { toolList(cli: cli) }

    nonisolated static func toolList(cli: any CLIRunning) -> [any Tool] {
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
            SearchFleetKnowledgeTool(),
            SearchHelpTool(),
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

    func sendWithFoundationModels(prompt: String, imageData: Data? = nil) async {
        let generation = chatGeneration
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
        guard generation == chatGeneration else { return }
        await stream(prompt: prompt, image: imageData.flatMap(Self.cgImage), retrying: false)
    }

    private static func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Text, plus the image when one is attached and the model can read it.
    private func makePrompt(_ text: String, image: CGImage?) -> Prompt {
        if #available(macOS 27, *), let image, Self.supportsImages {
            return Prompt {
                text
                Attachment(image)
            }
        }
        return Prompt(text)
    }

    // Lower temperature → more factual, deterministic answers for fleet management.
    private static let generationOptions = GenerationOptions(temperature: 0.4)

    private func stream(prompt: String, image: CGImage? = nil, retrying: Bool) async {
        var assistantIdx: Int? = nil
        // Held for the whole reply: "New Chat" clears `_session`, and a session released
        // while generating trips an assertion in FoundationModels.
        let session = languageModelSession
        let generation = chatGeneration
        var isCurrentChat: Bool { generation == chatGeneration }

        do {
            let stream = session.streamResponse(
                to: makePrompt(prompt, image: image),
                options: Self.generationOptions
            )
            for try await snapshot in stream {
                // Drain a reply from a cleared chat without showing it; breaking out of the
                // loop would cancel generation mid-flight.
                guard isCurrentChat else { continue }
                if assistantIdx == nil {
                    messages.append(Message(role: .assistant, content: snapshot.content))
                    assistantIdx = messages.count - 1
                    messages[assistantIdx!].isStreaming = true
                    state = .talking
                } else {
                    messages[assistantIdx!].content = snapshot.content
                }
            }
        } catch where !isCurrentChat {
            return
        } catch where !retrying && Self.isOS27ContextOverflow(error) {
            // macOS 27 reports context overflow as LanguageModelError.contextSizeExceeded.
            if let idx = assistantIdx { messages.remove(at: idx) }
            await performContextCompaction()
            await stream(prompt: prompt, image: image, retrying: true)
            return
        } catch where Self.os27ErrorMessage(for: error) != nil {
            appendError(Self.os27ErrorMessage(for: error) ?? "", at: &assistantIdx)
        } catch let error as LanguageModelSession.GenerationError {
            if case .exceededContextWindowSize = error, !retrying {
                if let idx = assistantIdx { messages.remove(at: idx) }
                await performContextCompaction()
                await stream(prompt: prompt, image: image, retrying: true)
                return
            }
            appendError(generationErrorMessage(error), at: &assistantIdx)
        } catch let nsError as NSError
                where nsError.domain.contains("GenerationError") || nsError.domain.contains("FoundationModels") {
            // The framework sometimes bridges unknown error codes as NSError rather than the
            // typed Swift enum. Code -1 is a generic internal failure.
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
            appendError("Error: \(error.localizedDescription)", at: &assistantIdx)
        }

        if isCurrentChat, let idx = assistantIdx, messages.indices.contains(idx) {
            messages[idx].isStreaming = false
        }
        if isCurrentChat { activeToolName = nil }
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
        let totalChars = messages.dropFirst(compactedMessageCount).reduce(0) { $0 + $1.content.count }
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
            let contextSize = model.contextSize
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
        return nil
    }

    /// Instructions for a new session: the system prompt plus the summary of earlier turns.
    private var currentInstructions: String {
        guard let summary = conversationSummary, !summary.isEmpty else { return Self.systemPrompt }
        return Self.systemPrompt + "\n\n## Earlier in this conversation\n" + summary
    }

    /// Transcript text handed to the summariser. Kept well inside the on-device context
    /// (≈ 2 000 tokens) so summarising a long chat can't overflow the summariser itself.
    private static var summaryInputCharacterBudget: Int { DashieBudget.characters(7_000) }
    /// Tool output is the data the model actually used; keep a slice of each one.
    private static let toolOutputCharacterLimit = 500

    /// Replaces the session with a fresh one whose instructions carry a summary of the chat
    /// so far. The visible messages stay; a notice marks where the model's memory was compacted.
    func performContextCompaction() async {
        let generation = chatGeneration
        let recent = transcriptText(budget: Self.summaryInputCharacterBudget)
        var summary: String?
        if !recent.isEmpty {
            summary = await summarize(recent)
        }
        // "New Chat" was pressed while summarising: leave the new chat alone.
        guard generation == chatGeneration else { return }

        let notice: String
        if let summary {
            conversationSummary = summary
            notice = "*(Earlier messages were summarised to free up the model's memory. Dashie keeps the key facts.)*"
        } else {
            // The summariser failed: carry the last exchange over verbatim so the next
            // answer still has the immediate context.
            let tail = String(recent.suffix(1_500))
            let carried = [conversationSummary, tail.isEmpty ? nil : "Most recent exchange:\n\(tail)"]
                .compactMap { $0 }.joined(separator: "\n\n")
            conversationSummary = String(carried.suffix(3_000))
            notice = "*(The model's memory was full, so Dashie kept only the most recent exchange.)*"
        }
        _session = makeSession(instructions: currentInstructions)
        messages.append(Message(role: .assistant, content: notice))
        compactedMessageCount = messages.count
    }

    /// The conversation as plain text, newest entries kept when over budget. Uses the session
    /// transcript (so tool output is included); falls back to the visible messages.
    private func transcriptText(budget: Int) -> String {
        var lines: [String] = []
        if let session = _session as? LanguageModelSession {
            for entry in session.transcript {
                switch entry {
                case .prompt(let p):
                    lines.append("User: " + Self.text(of: p.segments))
                case .response(let r):
                    lines.append("Assistant: " + Self.text(of: r.segments))
                case .toolOutput(let o):
                    let out = Self.text(of: o.segments)
                    let clipped = out.count > Self.toolOutputCharacterLimit
                        ? String(out.prefix(Self.toolOutputCharacterLimit)) + " …" : out
                    lines.append("Tool \(o.toolName) returned: " + clipped)
                default:
                    continue
                }
            }
        }
        if lines.isEmpty {
            lines = messages.dropFirst(compactedMessageCount).map {
                ($0.role == .user ? "User: " : "Assistant: ") + $0.content
            }
        }
        // Keep the newest lines that fit.
        var kept: [String] = []
        var used = 0
        for line in lines.reversed() {
            let cost = line.count + 2
            if used + cost > budget {
                if kept.isEmpty { kept.append(String(line.suffix(budget))) }
                break
            }
            kept.append(line)
            used += cost
        }
        return kept.reversed().joined(separator: "\n\n")
    }

    private static func text(of segments: [Transcript.Segment]) -> String {
        segments.compactMap { segment -> String? in
            if case .text(let t) = segment { return t.content }
            return nil
        }.joined(separator: " ")
    }

    /// Summarises with the on-device model into a typed structure; nil on failure.
    private func summarize(_ transcript: String) async -> String? {
        let session = LanguageModelSession(
            model: .default,
            instructions: "You summarise Jamf fleet management chats so the assistant can continue them. Keep names, serial numbers and numbers exact."
        )
        let previous = conversationSummary.map { "Summary of the chat before this part:\n\($0)\n\n" } ?? ""
        do {
            let response = try await session.respond(
                to: "\(previous)Conversation:\n\(transcript)",
                generating: ConversationSummary.self
            )
            return response.content.rendered
        } catch {
            sessionLogger.error("Conversation summary failed — \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    // MARK: - System prompt

    static let systemPrompt = """
        You are Dashie, an AI assistant for Jamf Dash (Jamf Pro fleet management). \
        Help admins manage their fleet. You cannot create/update/delete Jamf Pro objects — \
        tell the user to do that in Jamf Pro instead.

        Tool routing:
        • One Mac's hardware, security or details: getComputerDetail (needs the serial)
        • One Mac's installed apps: getInstalledApps (needs the serial)
        • Find Macs by name, macOS version or days since check-in: listComputers with its filters
        • Fleet hardware breakdown (models, RAM, disks): getInventorySummary
        • Fleet health and stats: getOverview
        • Patch status: getPatchStatus
        • Security posture: getSecurityReport
        • Compliance: getCompliance
        • Policies: getPolicies — Smart groups: getSmartGroups
        • Find anything by name or keyword (policies, profiles, scripts, packages, groups, Macs, \
        blueprints, compliance rules, past digests), e.g. "what do we have for FileVault?": \
        searchFleetKnowledge
        • How to use Jamf Dash, where something is, setup, permissions or errors in the app: \
        searchHelp — answer from its result and name where to find it (e.g. Settings → Updates)
        • Actions, only when the user asks for them: blankPush, renewMDMProfile, \
        redeployFramework, flushFailedCommands, restartDevice, executePolicy, \
        bulkEnablePolicies, bulkDisablePolicies

        Rules: call tools only when needed, at most two per answer — for example \
        listComputers with nameContains to find a serial, then getComputerDetail. \
        When the user gives a serial number, use it as given; never ask them to confirm it. \
        When the user asks for an action, call the action tool straight away — do not ask \
        "shall I proceed" yourself: the app shows its own confirmation dialog before anything \
        runs. Then report what the tool returned, including when the user cancelled.

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

// MARK: - History trimming (macOS 27)

/// Keeps long chats inside the on-device context: before each turn, tool output older than
/// the most recent few is shortened. The data was already used for earlier answers; the
/// model only needs a reminder of it.
@available(macOS 27, *)
enum DashieHistory {
    static let fullToolOutputsKept = 2
    static let shortenedLength = 300

    static func trim(_ entries: [Transcript.Entry]) -> [Transcript.Entry] {
        let outputIndices = entries.indices.filter {
            if case .toolOutput = entries[$0] { return true }
            return false
        }
        let keep = Set(outputIndices.suffix(fullToolOutputsKept))
        return entries.enumerated().map { index, entry in
            guard case .toolOutput(let output) = entry, !keep.contains(index) else { return entry }
            let text = output.segments.compactMap { segment -> String? in
                if case .text(let t) = segment { return t.content }
                return nil
            }.joined(separator: " ")
            guard text.count > shortenedLength else { return entry }
            let short = String(text.prefix(shortenedLength)) + " …(older result shortened — call the tool again for details)"
            return .toolOutput(Transcript.ToolOutput(id: output.id, toolName: output.toolName,
                                                     segments: [.text(Transcript.TextSegment(content: short))]))
        }
    }
}

// MARK: - Conversation summary

@available(macOS 26, *)
@Generable
struct ConversationSummary {
    @Guide(description: "Main topics discussed, oldest first", .maximumCount(6))
    let keyTopics: [String]
    @Guide(description: "Mac names or serial numbers discussed", .maximumCount(10))
    let devicesDiscussed: [String]
    @Guide(description: "Actions performed or requested, with their outcome", .maximumCount(6))
    let actionsPerformed: [String]
    @Guide(description: "Important facts found, with exact numbers, e.g. '12 Macs lack FileVault'", .maximumCount(8))
    let importantFindings: [String]
    @Guide(description: "One sentence on what the user was working on last")
    let lastContext: String
}

@available(macOS 26, *)
extension ConversationSummary {
    /// Plain text for the next session's instructions.
    var rendered: String {
        var parts: [String] = []
        func section(_ title: String, _ items: [String]) {
            let items = items.filter { !$0.isEmpty }
            guard !items.isEmpty else { return }
            parts.append("\(title):\n" + items.map { "- \($0)" }.joined(separator: "\n"))
        }
        section("Topics", keyTopics)
        section("Devices", devicesDiscussed)
        section("Actions", actionsPerformed)
        section("Findings", importantFindings)
        if !lastContext.isEmpty { parts.append("Last topic: \(lastContext)") }
        return parts.joined(separator: "\n")
    }
}

#endif
