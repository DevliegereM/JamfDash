import SwiftUI

// MARK: - Report types

private enum ReportType: String, CaseIterable, Identifiable {
    case patchStatus      = "Patch Status"
    case policyStatus     = "Policy Status"
    case profileStatus    = "Profile Status"
    case appStatus        = "App Status"
    case updateStatus     = "Update Status"
    case deviceCompliance = "Device Compliance"
    case inventorySummary = "Inventory Summary"
    case softwareInstalls = "Software Installs"
    case pdfExport        = "PDF Export"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .patchStatus:      return "bandage"
        case .policyStatus:     return "list.bullet.rectangle"
        case .profileStatus:    return "gearshape.2"
        case .appStatus:        return "app.badge"
        case .updateStatus:     return "arrow.triangle.2.circlepath"
        case .deviceCompliance: return "checkmark.shield"
        case .inventorySummary: return "laptopcomputer.and.iphone"
        case .softwareInstalls: return "square.and.arrow.down"
        case .pdfExport:        return "doc.richtext.fill"
        }
    }
}

// MARK: - Generic report row for table display

private struct ReportRow: Decodable, Sendable, Identifiable {
    let id: String
    let fields: [String: String]

    var sortedFields: [(key: String, value: String)] {
        fields.sorted { $0.key < $1.key }
    }
}

// MARK: - ReportView

struct ReportView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var selectedReport = ReportType.patchStatus
    @State private var includeFailures = false
    @State private var reportState: LoadState<[[String: String]]> = .idle
    @State private var columnKeys: [String] = []
    @State private var overviewVM: OverviewViewModel?
    @State private var securityVM: SecurityViewModel?
    @State private var isExporting = false

    var body: some View {
        VStack(spacing: 0) {
            // Report picker toolbar
            HStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(ReportType.allCases) { type in
                            Button {
                                selectedReport = type
                                if type != .pdfExport { Task { await loadReport(type) } }
                            } label: {
                                Label(type.rawValue, systemImage: type.icon)
                                    .labelStyle(.titleAndIcon)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(selectedReport == type
                                                ? Color.accentColor.opacity(0.15)
                                                : Color.clear, in: Capsule())
                                    .foregroundStyle(selectedReport == type ? Color.accentColor : Color.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                Spacer()
                if selectedReport == .updateStatus {
                    Toggle("Failures only", isOn: $includeFailures)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                        .padding(.trailing, 16)
                        .onChange(of: includeFailures) { _, _ in Task { await loadReport(.updateStatus) } }
                }
                Button { Task { await loadReport(selectedReport) } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .padding(.trailing, 16)
            }
            .padding(.vertical, 8)
            .background(.regularMaterial)

            Divider()

            if selectedReport == .pdfExport {
                pdfExportPanel
            } else {
                reportContentPanel
            }
        }
        .navigationTitle("Reports")
        .task {
            let ovm = env.makeReportOverviewVM()
            let svm = env.makeReportSecurityVM()
            overviewVM = ovm
            securityVM = svm
            await ovm.load()
            await svm.load()
            await loadReport(selectedReport)
        }
    }

    // MARK: - Report content

    @ViewBuilder
    private var reportContentPanel: some View {
        switch reportState {
        case .idle:
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loading:
            SyncingIndicator()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let msg):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 36)).foregroundStyle(.orange)
                Text("Report failed").font(.headline)
                Text(msg).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 400)
                Button("Retry") { Task { await loadReport(selectedReport) } }.buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let rows):
            if rows.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle").font(.system(size: 36)).foregroundStyle(.green)
                    Text("No data returned for this report.").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("\(rows.count) row\(rows.count == 1 ? "" : "s")")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button { exportCSV(rows) } label: {
                            Label("Export CSV", systemImage: "doc.text")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)

                    Divider()

                    reportTable(rows)
                }
            }
        }
    }

    @ViewBuilder
    private func reportTable(_ rows: [[String: String]]) -> some View {
        let cols = columnKeys.isEmpty ? Array(rows.first?.keys.sorted() ?? []) : columnKeys
        GeometryReader { geo in
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    // Header
                    HStack(spacing: 0) {
                        ForEach(cols, id: \.self) { key in
                            Text(key)
                                .font(.caption.weight(.semibold))
                                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                            if key != cols.last {
                                Divider()
                            }
                        }
                    }
                    .frame(width: geo.size.width)
                    .background(Color.primary.opacity(0.05))

                    Divider()

                    // Rows
                    LazyVStack(spacing: 0) {
                        ForEach(rows.indices, id: \.self) { idx in
                            let row = rows[idx]
                            HStack(spacing: 0) {
                                ForEach(cols, id: \.self) { key in
                                    Text(row[key] ?? "—")
                                        .font(.caption)
                                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                    if key != cols.last {
                                        Divider()
                                    }
                                }
                            }
                            .frame(width: geo.size.width)
                            .background(idx.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.02))
                            Divider()
                        }
                    }
                }
            }
        }
    }

    // MARK: - PDF panel (existing behavior)

    @ViewBuilder
    private var pdfExportPanel: some View {
        VStack(spacing: 24) {
            Image(systemName: "doc.richtext.fill").font(.system(size: 56)).foregroundStyle(.secondary)
            Text("Export PDF Report").font(.title2).bold()
            Text("Generate a PDF containing your Jamf Pro overview and security posture data.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 400)

            VStack(alignment: .leading, spacing: 8) {
                DataReadyRow(label: "Instance Overview",
                             stateDescription: stateInfo(overviewVM?.state))
                DataReadyRow(label: "Security Report",
                             stateDescription: stateInfo(securityVM?.state))
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))

            Button {
                Task { await exportPDF() }
            } label: {
                Label(isExporting ? "Preparing…" : "Export PDF Report…",
                      systemImage: "arrow.down.doc")
                .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isExporting || overviewVM?.state.value == nil || securityVM?.state.value == nil)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - Load helpers

    private func loadReport(_ type: ReportType) async {
        guard type != .pdfExport else { return }
        reportState = .loading
        do {
            let cmd: CLICommand
            switch type {
            case .patchStatus:      cmd = .reportPatchStatus
            case .policyStatus:     cmd = .reportPolicyStatus
            case .profileStatus:    cmd = .reportProfileStatus
            case .appStatus:        cmd = .reportAppStatus
            case .updateStatus:     cmd = .reportUpdateStatus(includeFailures: includeFailures)
            case .deviceCompliance: cmd = .reportDeviceCompliance
            case .inventorySummary: cmd = .reportInventorySummary
            case .softwareInstalls: cmd = .reportSoftwareInstalls
            case .pdfExport:        return
            }
            let data = try await env.cliManager.run(cmd)
            let rows = try parseReportData(data)
            columnKeys = rows.first.map { Array($0.keys.sorted()) } ?? []
            reportState = .loaded(rows)
        } catch {
            reportState = .failed(error.localizedDescription)
        }
    }

    private func parseReportData(_ data: Data) throws -> [[String: String]] {
        let decoder = JSONDecoder()
        if let flat = try? decoder.decode([[String: String]].self, from: data) { return flat }
        if let flat = try? decoder.decode([[String: AnyCodable]].self, from: data) {
            return flat.map { $0.mapValues { $0.stringValue } }
        }
        struct Paged: Decodable { let results: [[String: AnyCodable]] }
        if let paged = try? decoder.decode(Paged.self, from: data) {
            return paged.results.map { $0.mapValues { $0.stringValue } }
        }
        let preview = String(data: data.prefix(400), encoding: .utf8) ?? "<binary>"
        throw NSError(domain: "ReportDecoding", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Unexpected response format: \(preview)"])
    }

    private func exportCSV(_ rows: [[String: String]]) {
        guard !rows.isEmpty else { return }
        let cols = columnKeys.isEmpty ? Array(rows.first?.keys.sorted() ?? []) : columnKeys
        var csv = cols.map { "\"\($0)\"" }.joined(separator: ",") + "\n"
        for row in rows {
            csv += cols.map { key in
                let v = (row[key] ?? "").replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(v)\""
            }.joined(separator: ",") + "\n"
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(selectedReport.rawValue.replacingOccurrences(of: " ", with: "_")).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? csv.write(to: url, atomically: true, encoding: .utf8)
    }

    private func exportPDF() async {
        guard let ovm = overviewVM, let svm = securityVM else { return }
        isExporting = true
        await PDFExporter.export(overviewVM: ovm, securityVM: svm)
        isExporting = false
    }

    private func stateInfo<T: Sendable>(_ state: LoadState<T>?) -> (icon: String, color: Color, label: String) {
        guard let state else { return ("circle", .secondary, "Not loaded") }
        switch state {
        case .idle:   return ("circle", .secondary, "Not loaded")
        case .loading: return ("arrow.clockwise", .secondary, "Loading…")
        case .loaded: return ("checkmark.circle.fill", .green, "Ready")
        case .failed: return ("xmark.circle.fill", .red, "Failed")
        }
    }
}

// MARK: - AnyCodable helper for mixed-type JSON

private struct AnyCodable: Decodable, Sendable {
    enum Value: Sendable { case bool(Bool), int(Int), double(Double), string(String) }
    let value: Value

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self)   { value = .bool(b);   return }
        if let i = try? c.decode(Int.self)    { value = .int(i);    return }
        if let d = try? c.decode(Double.self) { value = .double(d); return }
        if let s = try? c.decode(String.self) { value = .string(s); return }
        value = .string("")
    }

    var stringValue: String {
        switch value {
        case .bool(let b):   return b ? "true" : "false"
        case .int(let i):    return String(i)
        case .double(let d): return String(d)
        case .string(let s): return s
        }
    }
}

// MARK: - Status row (reused by PDF panel)

private struct DataReadyRow: View {
    let label: String
    let stateDescription: (icon: String, color: Color, label: String)

    var body: some View {
        HStack {
            Image(systemName: stateDescription.icon).foregroundStyle(stateDescription.color).frame(width: 20)
            Text(label)
            Spacer()
            Text(stateDescription.label).font(.caption).foregroundStyle(.secondary)
        }
    }
}
