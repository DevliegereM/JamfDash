import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Help → Report a Problem…: describe the problem, review exactly what's sent, then send it
/// by email, open a GitHub issue (text only), or save a zip.
struct ReportProblemView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var model = ProblemReportModel()
    @State private var reviewing = false
    @State private var info = ReportEnvironment()
    @State private var selectedFile: ReportFile.ID?

    var body: some View {
        Group {
            if reviewing {
                reviewStep
            } else {
                describeStep
            }
        }
        .frame(minWidth: 720, minHeight: 560)
        .task {
            info = await env.reportEnvironment()
            takeContext()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openReportProblem)) { _ in takeContext() }
    }

    private func takeContext() {
        if let summary = ReportProblem.pendingSummary {
            if model.summary.isEmpty { model.summary = String(summary.prefix(200)) }
            ReportProblem.pendingSummary = nil
        }
        if let context = ReportProblem.pendingContext {
            model.context = context
            if model.actual.isEmpty { model.actual = context }
            ReportProblem.pendingContext = nil
        }
    }

    // MARK: Describe

    private var describeStep: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Text("Tell us what went wrong. Nothing is sent until you choose how to send it in the next step.")
                        .foregroundStyle(.secondary)
                    TextField("Summary", text: $model.summary, prompt: Text("e.g. Security view shows “permission denied”"))
                    Picker("Area", selection: $model.area) {
                        ForEach(ReportArea.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("How often", selection: $model.frequency) {
                        ForEach(ReportFrequency.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                Section("Steps to reproduce") {
                    TextEditor(text: $model.steps)
                        .font(.body)
                        .frame(minHeight: 70)
                        .accessibilityLabel("Steps to reproduce")
                }
                Section {
                    TextField("What did you expect?", text: $model.expected, axis: .vertical)
                    TextField("What happened?", text: $model.actual, axis: .vertical)
                }
                Section {
                    LabeledContent("App, macOS and jamf-cli versions") { Text("Always included").foregroundStyle(.secondary) }
                    HStack {
                        Toggle("Recent logs", isOn: $model.includeLogs)
                        Spacer()
                        Picker("Period", selection: $model.logHours) {
                            Text("Last hour").tag(1)
                            Text("Last 2 hours").tag(2)
                            Text("Last 8 hours").tag(8)
                            Text("Last 24 hours").tag(24)
                        }
                        .labelsHidden()
                        .fixedSize()
                        .disabled(!model.includeLogs)
                    }
                    Toggle("Recent jamf-cli commands (names only, no values)", isOn: $model.includeCommands)
                    Toggle(crashLabel, isOn: $model.includeCrashReports)
                        .disabled(model.crashReportCount == 0)
                    Toggle("Server address", isOn: $model.includeServerAddress)
                    HStack {
                        Text(model.attachments.isEmpty ? "Screenshots or other files"
                             : model.attachments.map(\.lastPathComponent).joined(separator: ", "))
                            .foregroundStyle(model.attachments.isEmpty ? .secondary : .primary)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        if !model.attachments.isEmpty {
                            Button("Remove") { model.attachments = [] }
                        }
                        Button("Add…") { addAttachments() }
                    }
                } header: {
                    Text("Include")
                } footer: {
                    Text("Server addresses, serial numbers, names, email and IP addresses, IDs and tokens are replaced with placeholders. Passwords, client secrets, the jamf-cli configuration and your Dashie conversation are never included.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if let context = model.context {
                    Label("Started from an error: \(context)", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Review…") {
                    reviewing = true
                    Task {
                        await model.prepare(environment: info)
                        selectedFile = model.files.first?.id
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canReview)
            }
            .padding(12)
        }
        .navigationTitle("Report a Problem")
    }

    private var crashLabel: String {
        let n = model.crashReportCount
        return n == 0 ? "Crash reports (none found)" : "Crash reports (\(n) found)"
    }

    private func addAttachments() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image, .pdf, .plainText, .movie]
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        model.attachments += panel.urls
    }

    // MARK: Review

    private var reviewStep: some View {
        VStack(spacing: 0) {
            if model.isPreparing {
                ProgressView("Collecting and redacting…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    fileList.frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
                    fileDetail.frame(minWidth: 380)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                if let note = model.preparationNote {
                    Label(note, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                }
                Text(redactionLine).font(.caption).foregroundStyle(.secondary)
                Toggle("I reviewed this report and it contains nothing I can't share", isOn: $model.reviewed)
                if let status = model.statusMessage {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Back") { reviewing = false; model.reviewed = false }
                    Spacer()
                    Button("Save as Zip…") { model.saveZip() }
                    Button("Open GitHub Issue") { model.openGitHubIssue(environment: info) }
                        .help("Text only: the description and versions. Logs stay on your Mac.")
                    Button("Email") { model.email(); CrashReports.markSeen() }
                        .keyboardShortcut(.defaultAction)
                        .help("Opens an email to \(ProblemReportModel.recipient) with the report attached")
                }
                .disabled(!model.reviewed || model.isPreparing)
            }
            .padding(12)
        }
        .navigationTitle("Review Report \(model.reportID)")
    }

    private var redactionLine: String {
        let counts = model.totalRedactions
        return counts.total == 0 ? "Nothing needed redacting." : "Redacted: \(counts.summary)"
    }

    private var fileList: some View {
        List(selection: $selectedFile) {
            ForEach(model.files) { file in
                HStack(alignment: .top, spacing: 8) {
                    Toggle("", isOn: Binding(get: { file.included },
                                             set: { model.setIncluded($0, for: file.id) }))
                        .labelsHidden()
                        .disabled(file.name == "report.md")
                        .accessibilityLabel("Include \(file.name)")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.name).lineLimit(1).truncationMode(.middle)
                        Text("\(ByteCountFormatter.string(fromByteCount: Int64(file.byteCount), countStyle: .file)) · \(file.note)")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        if file.redactions.total > 0 {
                            Text("\(file.redactions.total) redactions").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .tag(file.id)
            }
        }
    }

    @ViewBuilder
    private var fileDetail: some View {
        if let id = selectedFile, let file = model.files.first(where: { $0.id == id }) {
            if let text = file.text {
                VStack(alignment: .leading, spacing: 4) {
                    Text("You can edit this text before sending. Placeholders like ‹host-1› replace what was removed.")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding([.top, .horizontal], 8)
                    TextEditor(text: Binding(get: { text }, set: { model.setText($0, for: id) }))
                        .font(.system(.caption, design: .monospaced))
                        .accessibilityLabel("Contents of \(file.name)")
                }
            } else {
                ContentUnavailableView("\(file.name)", systemImage: "doc",
                                       description: Text("Added by you. Files you add aren't redacted: check them before sending."))
            }
        } else {
            ContentUnavailableView("Select a File", systemImage: "doc.text.magnifyingglass")
        }
    }
}

/// Shown at the top of the main window after Jamf Dash quit unexpectedly.
struct CrashReportBanner: View {
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.octagon.fill").foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("Jamf Dash quit unexpectedly last time.")
            Spacer()
            Button("Report This Problem…") {
                ReportProblem.open(context: "Jamf Dash quit unexpectedly.")
                onDismiss()
            }
            Button("Dismiss") { onDismiss() }
                .buttonStyle(.borderless)
        }
        .font(.callout)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
        .accessibilityElement(children: .contain)
    }
}
