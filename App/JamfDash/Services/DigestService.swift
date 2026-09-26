import Foundation
import UserNotifications
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - DigestEntry

struct DigestEntry: Codable, Identifiable, Sendable {
    let id: UUID
    let date: Date
    let bullets: [String]
    let rawSummary: String
}

// MARK: - DigestService

@MainActor
final class DigestService {

    // MARK: Properties

    private let cli: any CLIRunning
    private let storageURL: URL
    private(set) var entries: [DigestEntry] = []
    private(set) var isRunning = false

    // MARK: Initialization

    init(cli: any CLIRunning) {
        self.cli = cli
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("JamfDash", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.storageURL = dir.appendingPathComponent("digests.json")
        self.entries = (try? JSONDecoder().decode([DigestEntry].self, from: Data(contentsOf: storageURL))) ?? []
    }

    // MARK: Public Methods

    func runIfNeeded() async {
        guard !isRunning else { return }
        if let last = entries.last, Date().timeIntervalSince(last.date) < 86400 { return }
        await run()
    }

    func run() async {
        isRunning = true
        defer { isRunning = false }

        let overviewData  = try? await cli.run(.overview)
        let securityData  = try? await cli.run(.securityReport)
        let patchData     = try? await cli.run(.reportPatchStatus)

        let context = buildContext(overview: overviewData, security: securityData, patch: patchData)
        let summary = await generateSummary(context: context)
        let bullets = parseBullets(from: summary)

        let entry = DigestEntry(id: UUID(), date: Date(), bullets: bullets, rawSummary: summary)
        entries.append(entry)
        persist()
        await notify(entry: entry)
    }

    // MARK: Private Methods

    private func buildContext(overview: Data?, security: Data?, patch: Data?) -> String {
        var parts: [String] = []
        if let d = overview, let s = String(data: d, encoding: .utf8) {
            parts.append("## Overview\n\(s.prefix(2000))")
        }
        if let d = security, let s = String(data: d, encoding: .utf8) {
            parts.append("## Security\n\(s.prefix(2000))")
        }
        if let d = patch, let s = String(data: d, encoding: .utf8) {
            parts.append("## Patches\n\(s.prefix(2000))")
        }
        return parts.joined(separator: "\n\n")
    }

    private func generateSummary(context: String) async -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            let session = LanguageModelSession(model: .default)
            let prompt = """
            You are a Jamf Pro admin assistant. Given the following JSON data from a Jamf Pro instance, write exactly 3 concise bullet points (each starting with "• ") summarizing the most important status or issues an admin should know today. Be direct and factual.

            \(context)
            """
            if let response = try? await session.respond(to: prompt) {
                return response.content
            }
        }
        #endif
        return "• Daily digest data collected (on-device AI unavailable)\n• Check the Security and Overview tabs for details\n• No automated summary generated"
    }

    private func parseBullets(from text: String) -> [String] {
        let lines = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("•") || $0.hasPrefix("-") || $0.hasPrefix("*") }
        let candidates = Array(lines.prefix(3))
        return candidates.isEmpty ? [text] : candidates
    }

    private func persist() {
        try? JSONEncoder().encode(entries).write(to: storageURL)
    }

    private func notify(entry: DigestEntry) async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound])

        let content = UNMutableNotificationContent()
        content.title = "Jamf Dash Daily Digest"
        content.body = entry.bullets.first ?? entry.rawSummary
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "digest-\(entry.id.uuidString)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }
}
