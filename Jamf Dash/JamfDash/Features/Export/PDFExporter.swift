import SwiftUI
import AppKit

@MainActor
struct PDFExporter {

    // US Letter portrait at 72 pt/in (8.5" × 11")
    private static let pageWidth:  CGFloat = 612
    private static let pageHeight: CGFloat = 792

    // MARK: - Public

    static func export(
        overviewVM: OverviewViewModel,
        securityVM: SecurityViewModel
    ) async {
        let data = buildPDF(overviewVM: overviewVM, securityVM: securityVM)

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "JamfDash-Report-\(dateStamp()).pdf"
        panel.allowedContentTypes  = [.pdf]
        panel.message = "Choose where to save the Jamf Dash report"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
        } catch {
            let alert = NSAlert()
            alert.messageText     = "Export Failed"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    // MARK: - Build

    private static func buildPDF(
        overviewVM: OverviewViewModel,
        securityVM: SecurityViewModel
    ) -> Data {
        let output = NSMutableData()
        var box    = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        guard let consumer = CGDataConsumer(data: output),
              let pdf = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }

        // Page 1 — instance overview
        drawPage(pdf, box: box,
                 view: ReportCoverPage(timestamp: formattedDate(), overviewVM: overviewVM))

        // Page 2 — security posture
        if let summary = securityVM.summary {
            drawPage(pdf, box: box,
                     view: ReportSecurityPage(summary: summary, osVersions: securityVM.osVersions))
        }

        pdf.closePDF()
        return output as Data
    }

    // MARK: - Per-page rendering

    /// Renders a SwiftUI view into the next page of an already-open PDF context.
    private static func drawPage<V: View>(_ pdf: CGContext, box: CGRect, view: V) {
        let renderer = ImageRenderer(
            content: view.frame(width: box.width, height: box.height)
        )
        // Use 1.0 for PDF contexts — PDFs are resolution-independent and draw(pdf)
        // draws at the renderer's scale, so 2.0 would produce 2× overflow.
        // ImageRenderer already renders correctly oriented for CGPDFContext
        // (both macOS and PDF use bottom-left origin), so no manual flip is needed.
        renderer.scale = 1.0

        pdf.beginPDFPage(nil)
        renderer.render { _, draw in
            draw(pdf)
        }
        pdf.endPDFPage()
    }

    // MARK: - Helpers

    private static func dateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmm"
        return f.string(from: Date())
    }

    private static func formattedDate() -> String {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .short
        return f.string(from: Date())
    }
}

// MARK: - Page views
// These must NOT use ScrollView or LazyVStack — ImageRenderer only draws what
// the layout engine realises, and lazy/scrollable containers skip off-screen items.

private struct ReportCoverPage: View {
    let timestamp: String
    let overviewVM: OverviewViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ───────────────────────────────────────────────────────
            HStack(alignment: .center) {
                if let logo = BrandingService.logoImage {
                    Image(nsImage: logo)
                        .resizable().scaledToFit()
                        .frame(height: 36)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Jamf Pro Instance Report")
                        .font(.headline).bold()
                    Text(timestamp)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 28).padding(.vertical, 16)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // ── Sections ─────────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 12) {
                let sections = overviewVM.sections
                if sections.isEmpty {
                    Text("No overview data available.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ForEach(sections, id: \.title) { section in
                        SectionBlock(title: section.title, items: section.items)
                    }
                }
            }
            .padding(24)

            Spacer(minLength: 0)

            // ── Footer ───────────────────────────────────────────────────────
            Divider()
            Text("Generated by Jamf Dash · \(timestamp)")
                .font(.caption2).foregroundStyle(.tertiary)
                .padding(.horizontal, 28).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(width: 612, height: 792)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SectionBlock: View {
    let title: String
    let items: [OverviewItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.vertical, 4).padding(.horizontal, 10)
                .background(Color.accentColor.opacity(0.12))
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(items) { item in
                HStack {
                    Text(item.resource).font(.caption)
                    Spacer()
                    Text(item.value).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 3).padding(.horizontal, 10)
                Divider().padding(.horizontal, 10)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }
}

private struct ReportSecurityPage: View {
    let summary: SecuritySummary
    let osVersions: [OSVersionRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ───────────────────────────────────────────────────────
            Text("Security Posture")
                .font(.title2).bold()
                .padding(.horizontal, 28).padding(.top, 28).padding(.bottom, 16)

            Divider()

            VStack(alignment: .leading, spacing: 20) {

                // Compliance table
                VStack(spacing: 0) {
                    complianceRow("FileVault Encryption",
                                  count: summary.filevaultEncrypted,
                                  pct: summary.filevaultEncryptedPct)
                    complianceRow("Gatekeeper",
                                  count: summary.gatekeeperEnabled,
                                  pct: summary.gatekeeperEnabledPct)
                    complianceRow("System Integrity Protection",
                                  count: summary.sipEnabled,
                                  pct: summary.sipEnabledPct)
                    complianceRow("Firewall",
                                  count: summary.firewallEnabled,
                                  pct: summary.firewallEnabledPct)
                }
                .background(Color(nsColor: .controlBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5))

                // OS distribution table (plain — no Charts here to avoid render issues)
                if !osVersions.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("OS Version Distribution")
                            .font(.caption.weight(.semibold))
                            .padding(.vertical, 6).padding(.horizontal, 12)
                            .background(Color.accentColor.opacity(0.08))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        ForEach(osVersions.prefix(20), id: \.osVersion) { row in
                            VStack(spacing: 0) {
                                HStack {
                                    Text(row.osVersion).font(.caption)
                                    Spacer()
                                    Text("\(row.count) devices")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text(row.pct)
                                        .font(.caption.weight(.semibold))
                                        .frame(width: 48, alignment: .trailing)
                                }
                                .padding(.vertical, 4).padding(.horizontal, 12)
                                Divider().padding(.horizontal, 12)
                            }
                        }
                    }
                    .background(Color(nsColor: .controlBackgroundColor),
                                in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
                }
            }
            .padding(24)

            Spacer(minLength: 0)

            Divider()
            Text("Generated by Jamf Dash")
                .font(.caption2).foregroundStyle(.tertiary)
                .padding(.horizontal, 28).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(width: 612, height: 792)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func complianceRow(_ label: String, count: Int, pct: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label).font(.callout)
                Spacer()
                Text("\(count) devices").foregroundStyle(.secondary).font(.callout)
                Text(pct).fontWeight(.semibold).frame(width: 52, alignment: .trailing).font(.callout)
            }
            .padding(.vertical, 8).padding(.horizontal, 14)
            Divider().padding(.horizontal, 14)
        }
    }
}
