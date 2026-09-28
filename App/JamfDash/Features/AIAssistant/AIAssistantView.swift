import FoundationModels
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Outer availability gate

struct AIAssistantView: View {
    var vm: AIAssistantViewModel

    var body: some View {
        if #available(macOS 26, *) {
            AIAssistantInnerView(vm: vm)
        } else {
            ContentUnavailableView(
                "Requires macOS 26",
                systemImage: "brain.head.profile",
                description: Text("The AI Assistant requires macOS 26 with Apple Intelligence.")
            )
        }
    }
}

// MARK: - Main chat view

@available(macOS 26, *)
struct AIAssistantInnerView: View {
    @Bindable var vm: AIAssistantViewModel
    @Environment(AppEnvironment.self) private var env
    @FocusState private var inputFocused: Bool
    @State private var showingHelp = false
    @State private var showingImagePicker = false
    @State private var showDigestHistory = false
    @State private var intelligence = AppleIntelligenceStatus()

    var body: some View {
        if intelligence.state == .ready {
            chat
        } else {
            AppleIntelligenceSetupView(status: intelligence)
                .navigationTitle("AI Assistant")
        }
    }

    private var chat: some View {
        VStack(spacing: 0) {
            compactHeader

            Divider()

            if vm.messages.isEmpty && !vm.isResponding {
                emptyState
            } else {
                messagesList
            }

            Divider()

            composer.padding(14)
        }
        .navigationTitle("AI Assistant")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Chat") { vm.clearHistory() }
                    .disabled(vm.messages.isEmpty && !vm.isResponding)
                    .help("Start a new conversation")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showDigestHistory = true
                } label: {
                    Label("Digest History", systemImage: "doc.text.magnifyingglass")
                }
                .help("View saved digest reports")
            }
        }
        .sheet(isPresented: $showDigestHistory) {
            DigestHistoryView(service: env.digestService)
        }
        .onAppear { inputFocused = true }
        .onChange(of: vm.isResponding) { _, responding in
            guard !responding else { return }
            // Defer by one run loop tick so SwiftUI finishes re-enabling the
            // TextField before we request focus — otherwise the field is still
            // disabled at the moment the focus change is processed.
            Task { @MainActor in inputFocused = true }
        }
    }

    // MARK: - Compact header (shown while chatting)

    private var compactHeader: some View {
        HStack(spacing: 10) {
            DashieMascot(state: vm.state, size: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Dashie").font(.system(size: 13, weight: .semibold))
                StatePill(state: vm.state, toolName: vm.activeToolName)
            }
            Spacer()
            Button {
                showingHelp.toggle()
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Prompting tips")
            .popover(isPresented: $showingHelp, arrowEdge: .top) {
                HelpPopover()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - Empty / welcome state

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 32)

                DashieMascot(state: .idle, size: 110)
                    .accessibilityHidden(true)

                VStack(spacing: 6) {
                    Text("Ask me about your fleet")
                        .font(.system(size: 17, weight: .semibold))
                    Text("I can look up device data, run reports, and take actions on your Jamf Pro fleet.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                }

                VStack(spacing: 8) {
                    ForEach([
                        ("Devices needing an OS update",   "laptopcomputer.trianglebadge.exclamationmark"),
                        ("Security posture summary",        "lock.shield"),
                        ("Which policies are failing?",     "doc.badge.exclamationmark"),
                        ("Devices running macOS 26",        "apple.logo"),
                        ("Show me non-compliant devices",   "exclamationmark.triangle"),
                    ], id: \.0) { prompt, icon in
                        quickPromptRow(prompt: prompt, icon: icon)
                    }
                }
                .frame(maxWidth: 440)

                Spacer(minLength: 32)
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity)
        }
    }

    private func quickPromptRow(prompt: String, icon: String) -> some View {
        Button {
            vm.inputText = prompt
            Task { await vm.send() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .frame(width: 20)
                    .foregroundStyle(.secondary)
                Text(prompt)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Messages list

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(vm.messages) { msg in
                        messageRow(for: msg).id(msg.id)
                    }
                    if vm.state == .thinking, vm.messages.last?.role == .user {
                        ThinkingBubble()
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 20)
            }
            .onChange(of: vm.messages.count) {
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: vm.state) {
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    @ViewBuilder
    private func messageRow(for message: AIAssistantViewModel.Message) -> some View {
        switch message.role {
        case .user:
            UserBubble(text: message.content, imageData: message.imageData)
        case .assistant:
            AssistantBubble(text: message.content, partial: message.isStreaming)
        }
    }

    // MARK: - Composer

    private var canAttachImages: Bool { AIAssistantViewModel.supportsImages }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let data = vm.pendingImage, let image = NSImage(data: data) {
                HStack(spacing: 8) {
                    Image(nsImage: image)
                        .resizable().scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Text("Image attached — read on this Mac").font(.caption).foregroundStyle(.secondary)
                    Button { vm.pendingImage = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove attached image")
                }
            }
            composerRow
        }
        .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
            guard canAttachImages else { return false }
            return attachImage(from: providers)
        }
        .onPasteCommand(of: [.image, .png, .tiff]) { providers in
            guard canAttachImages else { return }
            _ = attachImage(from: providers)
        }
        .fileImporter(isPresented: $showingImagePicker, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) { vm.pendingImage = ImageAttachmentLoader.png(from: data) }
            }
        }
    }

    private func attachImage(from providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSImage.self) }) else { return false }
        _ = provider.loadObject(ofClass: NSImage.self) { object, _ in
            guard let image = object as? NSImage, let tiff = image.tiffRepresentation else { return }
            let png = ImageAttachmentLoader.png(from: tiff)
            Task { @MainActor in vm.pendingImage = png }
        }
        return true
    }

    private var composerRow: some View {
        HStack(spacing: 10) {
            if canAttachImages {
                Button { showingImagePicker = true } label: {
                    Image(systemName: "paperclip").font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Attach a screenshot or image (or paste / drop one). Dashie reads it on this Mac.")
                .accessibilityLabel("Attach image")
            }
            TextField(vm.pendingImage == nil ? "Ask about your fleet…" : "Ask about the image…",
                      text: $vm.inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1...5)
                .focused($inputFocused)
                .onSubmit {
                    Task {
                        await vm.send()
                        inputFocused = true
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))

            Button {
                Task {
                    await vm.send()
                    inputFocused = true
                }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22))
            }
            .buttonStyle(.plain)
            .disabled(vm.isResponding || (vm.inputText.trimmingCharacters(in: .whitespaces).isEmpty && vm.pendingImage == nil))
            .accessibilityLabel("Send message")
        }
    }
}

/// Normalises attached images to a PNG no larger than 1 600 px on the long side.
enum ImageAttachmentLoader {
    static func png(from data: Data, maxDimension: CGFloat = 1_600) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:])
    }
}

// MARK: - State pill

@available(macOS 26, *)
private struct StatePill: View {
    let state: AssistantState
    var toolName: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
                .shadow(color: state == .idle ? .clear : dotColor, radius: 3)
                .modifier(PulseIfActive(active: state != .idle))
                .accessibilityHidden(true)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dashie: \(label)")
    }

    private var label: String {
        switch state {
        case .idle:     return "Ready"
        case .thinking: return "Thinking…"
        case .tool:     return toolName.map(Self.toolLabel) ?? "Looking things up…"
        case .talking:  return "Responding…"
        }
    }

    private var dotColor: Color {
        state == .idle ? .green : .accentColor
    }

    static func toolLabel(_ name: String) -> String {
        switch name {
        case "listComputers":        return "Looking up Macs…"
        case "getComputerDetail":    return "Reading device details…"
        case "getInstalledApps":     return "Reading installed apps…"
        case "getSecurityReport":    return "Checking security posture…"
        case "getCompliance":        return "Checking compliance…"
        case "getOverview":          return "Reading the fleet overview…"
        case "getPatchStatus":       return "Checking patch status…"
        case "getPolicies":          return "Reading policies…"
        case "getSmartGroups":       return "Reading smart groups…"
        case "getInventorySummary":  return "Summarising inventory…"
        case "searchFleetKnowledge": return "Searching the fleet index…"
        default:                     return "Waiting for confirmation…"
        }
    }
}

// MARK: - Bubbles

private struct UserBubble: View {
    let text: String
    var imageData: Data? = nil

    var body: some View {
        HStack {
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                if let imageData, let image = NSImage(data: imageData) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 260, maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .accessibilityLabel("Attached image")
                }
                if !text.isEmpty {
                    Text(text)
                        .font(.system(size: 13))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 9)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: 440, alignment: .trailing)
        }
    }
}

private struct AssistantBubble: View {
    let text: String
    let partial: Bool

    private var isLarge: Bool { !partial && text.count > 400 }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                if partial {
                    // Plain text + caret during streaming — avoids flickering from
                    // re-parsing incomplete markdown on every token.
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(text).font(.system(size: 13))
                        BlinkingCaret()
                    }
                } else {
                    MarkdownText(source: text)
                }

                if isLarge {
                    Button(action: exportJSON) {
                        Label("Export as JSON", systemImage: "arrow.down.circle")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 14))
            .frame(maxWidth: 460, alignment: .leading)
            .textSelection(.enabled)
            Spacer()
        }
    }

    private func exportJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "jamfdash-ai-response.json"
        panel.title = "Export AI Response"
        panel.message = "Save the AI response as a JSON file"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let payload: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "source": "Jamf Dash AI Assistant",
            "content": text
        ]
        guard let data = try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return }
        try? data.write(to: url)
    }
}

private struct ThinkingBubble: View {
    @State private var phase: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack {
            HStack(spacing: 5) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(.secondary)
                        .frame(width: 6, height: 6)
                        .opacity(reduceMotion ? 0.6 : (phase == i ? 1 : 0.3))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 14))
            Spacer()
        }
        .accessibilityLabel("Dashie is thinking")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: false)) {
                phase = (phase + 1) % 3
            }
        }
    }
}

private struct BlinkingCaret: View {
    @State private var on = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text("▎")
            .opacity(reduceMotion ? 1 : (on ? 1 : 0))
            .accessibilityHidden(true)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    on = false
                }
            }
    }
}

// MARK: - Markdown renderer

private struct MarkdownText: View {
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(parse(source).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .paragraph(let s):
            inlineText(s)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)

        case .heading(let level, let s):
            inlineText(s)
                .font(.system(size: level == 1 ? 15 : 14, weight: .semibold))
                .padding(.top, level == 1 ? 6 : 4)
                .fixedSize(horizontal: false, vertical: true)

        case .bullet(let s, let depth):
            HStack(alignment: .top, spacing: 5) {
                Text(depth == 0 ? "•" : "◦")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.leading, CGFloat(depth) * 14)
                inlineText(s)
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .numbered(let n, let s):
            HStack(alignment: .top, spacing: 5) {
                Text("\(n).")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 22, alignment: .trailing)
                inlineText(s)
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .code(let s, let lang):
            VStack(alignment: .leading, spacing: 0) {
                if !lang.isEmpty {
                    Text(lang)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.top, 6)
                }
                Text(s)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.vertical, 2)
        }
    }

    private func inlineText(_ s: String) -> Text {
        let opts = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        var attr = (try? AttributedString(markdown: s, options: opts)) ?? AttributedString(s)
        // Answers can repeat names from Jamf Pro, so links aren't clickable; the text stays.
        for run in attr.runs where run.link != nil {
            attr[run.range].link = nil
        }
        return Text(attr)
    }

    // MARK: Block parser

    private enum Block {
        case paragraph(String)
        case heading(Int, String)
        case bullet(String, depth: Int)
        case numbered(Int, String)
        case code(String, lang: String)
    }

    private func parse(_ text: String) -> [Block] {
        var blocks: [Block] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let raw = lines[i]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)

            // Code fence
            if trimmed.hasPrefix("```") {
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                i += 1
                var body: [String] = []
                while i < lines.count {
                    let fence = lines[i].trimmingCharacters(in: .whitespaces)
                    if fence.hasPrefix("```") { i += 1; break }
                    body.append(lines[i])
                    i += 1
                }
                blocks.append(.code(body.joined(separator: "\n"), lang: lang))
                continue
            }

            // Headings
            if trimmed.hasPrefix("### ") { blocks.append(.heading(3, String(trimmed.dropFirst(4)))); i += 1; continue }
            if trimmed.hasPrefix("## ")  { blocks.append(.heading(2, String(trimmed.dropFirst(3)))); i += 1; continue }
            if trimmed.hasPrefix("# ")   { blocks.append(.heading(1, String(trimmed.dropFirst(2)))); i += 1; continue }

            // Bullet
            let depth = raw.prefix(while: { $0 == " " }).count / 2
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") || trimmed.hasPrefix("• ") {
                blocks.append(.bullet(String(trimmed.dropFirst(2)), depth: depth))
                i += 1; continue
            }

            // Numbered list  (e.g. "1. text")
            if let (n, rest) = numberedPrefix(trimmed) {
                blocks.append(.numbered(n, rest))
                i += 1; continue
            }

            // Empty line — skip
            if trimmed.isEmpty { i += 1; continue }

            // Paragraph — consume consecutive non-special lines
            var para: [String] = [trimmed]
            i += 1
            while i < lines.count {
                let next = lines[i].trimmingCharacters(in: .whitespaces)
                if next.isEmpty
                    || next.hasPrefix("#")
                    || next.hasPrefix("```")
                    || next.hasPrefix("- ") || next.hasPrefix("* ")
                    || next.hasPrefix("+ ") || next.hasPrefix("• ")
                    || numberedPrefix(next) != nil {
                    break
                }
                para.append(next)
                i += 1
            }
            blocks.append(.paragraph(para.joined(separator: " ")))
        }

        return blocks
    }

    private func numberedPrefix(_ s: String) -> (Int, String)? {
        var rest = s[s.startIndex...]
        var digits = ""
        while let c = rest.first, c.isNumber { digits.append(c); rest = rest.dropFirst() }
        guard !digits.isEmpty, rest.hasPrefix(". "), let n = Int(digits) else { return nil }
        return (n, String(rest.dropFirst(2)))
    }
}

// MARK: - Help popover

@available(macOS 26, *)
@available(macOS 26, *)
private struct HelpPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Prompting Tips")
                .font(.headline)

            tipRow(icon: "text.bubble", title: "One task per message",
                   body: "Focused questions get better answers. \"Which devices are on macOS 14?\" instead of asking several things at once.")
            tipRow(icon: "magnifyingglass", title: "Use plain language",
                   body: "Ask in natural questions or commands: \"Send a blank push to C02XG2JCJG5J\" or \"Show non-compliant devices\".")
            tipRow(icon: "cpu", title: "Hardware lookups need a serial",
                   body: "For CPU, RAM, disk, or apps on a specific device, include the serial number. For fleet-wide breakdowns, just ask.")
            tipRow(icon: "arrow.counterclockwise", title: "Start a new chat when it slows down",
                   body: "The on-device model has a \(SystemLanguageModel.default.contextSize.formatted())-token context window. Dashie shortens older results automatically, but a fresh chat is fastest — use \"New Chat\".")
            tipRow(icon: "lock.shield", title: "Everything stays on your Mac",
                   body: "Dashie runs entirely on-device via Apple Intelligence. No data leaves your machine.")

            Divider()

            Text("Example prompts")
                .font(.subheadline)
                .fontWeight(.medium)

            VStack(alignment: .leading, spacing: 4) {
                ForEach([
                    "Devices that haven't checked in for 7 days",
                    "Security posture of the fleet",
                    "What apps are installed on C02XG2JCJG5J?",
                    "How much free disk space does FVMF1234ABCD have?",
                    "Show all policies in the Maintenance category",
                ], id: \.self) { example in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                        Text(example)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 340)
    }

    private func tipRow(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundStyle(Color.accentColor)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout).fontWeight(.medium)
                Text(body).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Dashie Mascot

struct DashieMascot: View {
    let state: AssistantState
    var size: CGFloat = 120
    /// Pauses the 60 fps animation while the window is in the background.
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !appearsActive)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                halos(t: t)
                base
                head(t: t)
            }
            .frame(width: size, height: size * 1.1)
        }
    }

    private var base: some View {
        ZStack {
            Ellipse()
                .fill(Color.accentColor.opacity(0.25))
                .frame(width: size * 0.52, height: size * 0.08)
                .offset(y: size * 0.44)
            RoundedRectangle(cornerRadius: size * 0.11, style: .continuous)
                .fill(Color.accentColor.opacity(0.35))
                .frame(width: size * 0.56, height: size * 0.22)
                .offset(y: size * 0.34)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.accentColor.opacity(0.45))
                .frame(width: size * 0.16, height: size * 0.06)
                .offset(y: size * 0.22)
        }
    }

    private func head(t: TimeInterval) -> some View {
        let breath = state == .idle ? sin(t * 1.8) * 1.2 : 0.0
        let tilt: Angle = {
            switch state {
            case .thinking, .tool: return .degrees(-3)
            case .talking:         return .degrees(2)
            default:               return .zero
            }
        }()

        return ZStack {
            Capsule()
                .fill(Color.accentColor)
                .frame(width: 2, height: size * 0.09)
                .offset(y: -size * 0.42)
            Circle()
                .fill(antennaColor)
                .frame(width: size * 0.06)
                .offset(y: -size * 0.46)
                .modifier(PulseIfActive(active: state != .idle))

            ZStack {
                RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                    .fill(headGradient)
                    .frame(width: size * 0.72, height: size * 0.6)
                RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                    .fill(LinearGradient(
                        colors: [.white.opacity(0.35), .white.opacity(0)],
                        startPoint: .top, endPoint: .center))
                    .frame(width: size * 0.72, height: size * 0.6)

                if state == .thinking || state == .tool {
                    let phase = (t.truncatingRemainder(dividingBy: 1.6)) / 1.6
                    Rectangle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: size * 0.72, height: size * 0.06)
                        .offset(y: size * (-0.26 + 0.52 * phase))
                        .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
                }

                HStack(spacing: size * 0.18) {
                    DashieEye(state: state, size: size, t: t)
                    DashieEye(state: state, size: size, t: t)
                }
                .offset(y: (state == .thinking || state == .tool) ? -size * 0.02 : 0)

                dashieMouth.offset(y: size * 0.13)
            }
            .rotationEffect(tilt)
            .offset(y: breath)
            .animation(.easeInOut(duration: 0.35), value: state)
        }
    }

    @ViewBuilder
    private var dashieMouth: some View {
        switch state {
        case .talking:
            DashieTalkingMouth(size: size)
        case .thinking, .tool:
            Capsule()
                .fill(Color.white)
                .frame(width: size * 0.12, height: 2.4)
        case .idle:
            DashieSmilePath()
                .stroke(Color.white, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                .frame(width: size * 0.14, height: size * 0.05)
        }
    }

    private var headGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(.displayP3, red: 0.30, green: 0.68, blue: 1.00, opacity: 1),
                Color(.displayP3, red: 0.14, green: 0.33, blue: 0.64, opacity: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    private var antennaColor: Color {
        switch state {
        case .idle:    return Color(.displayP3, red: 0.27, green: 0.63, blue: 0.29, opacity: 1)
        case .talking: return Color(.displayP3, red: 0.61, green: 1.00, blue: 0.49, opacity: 1)
        default:       return .accentColor
        }
    }

    @ViewBuilder
    private func halos(t: TimeInterval) -> some View {
        if state == .talking {
            ForEach(0..<2) { i in
                let phase = ((t + Double(i) * 0.4).truncatingRemainder(dividingBy: 1.6)) / 1.6
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.4 - Double(i) * 0.15), lineWidth: 1.2)
                    .frame(width: size * (0.78 + phase * 0.25),
                           height: size * (0.66 + phase * 0.25))
                    .opacity(1 - phase)
                    .offset(y: -size * 0.05)
            }
        }
    }
}

private struct DashieEye: View {
    let state: AssistantState
    let size: CGFloat
    let t: TimeInterval

    var body: some View {
        let blinkPhase = t.truncatingRemainder(dividingBy: 4.0)
        let blinking = state == .idle && blinkPhase > 3.76 && blinkPhase < 3.84
        let h: CGFloat = blinking ? 1.2 : (state == .thinking || state == .tool ? size * 0.032 : size * 0.08)

        return ZStack {
            Capsule()
                .fill(Color.white)
                .frame(width: size * 0.08, height: h)
            if !blinking && state != .thinking && state != .tool {
                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: size * 0.02)
                    .offset(x: size * 0.012, y: -size * 0.018)
            }
        }
        .animation(.easeInOut(duration: 0.12), value: state)
    }
}

private struct DashieTalkingMouth: View {
    let size: CGFloat
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Ellipse()
            .fill(Color.white)
            .frame(width: size * 0.14, height: size * 0.07)
            .scaleEffect(y: reduceMotion ? 0.7 : (on ? 1.0 : 0.4))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.22).repeatForever(autoreverses: true)) {
                    on = true
                }
            }
    }
}

private struct DashieSmilePath: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.maxY * 1.6)
        )
        return p
    }
}

private struct PulseIfActive: ViewModifier {
    let active: Bool
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(active && !reduceMotion ? (on ? 1 : 0.4) : 1)
            .onAppear {
                guard active && !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    on = true
                }
            }
    }
}

// MARK: - Preview

#Preview {
    AIAssistantView(vm: AIAssistantViewModel(cli: DemoCLIManager()))
}
