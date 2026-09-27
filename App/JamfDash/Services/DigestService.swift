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

    /// Older digests stored the model's own bullet markers; newer ones store plain text.
    static func stripBullet(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        while let c = t.first, c == "•" || c == "-" || c == "*" {
            t = String(t.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return t
    }
}

#if canImport(FoundationModels)
@available(macOS 26, *)
@Generable
struct DigestSummary {
    @Guide(description: "Exactly three short, factual points an admin should know today, most important first. No bullet characters.", .count(3))
    let bullets: [String]
}
#endif

// MARK: - DigestService

@MainActor
final class DigestService {

    // MARK: Properties

    private let cli: any CLIRunning
    private var storageURL: URL
    private let notifies: Bool
    private(set) var entries: [DigestEntry] = []
    private(set) var isRunning = false

    // MARK: Initialization

    /// The app passes `InstanceStorage.directory(forProfile:)/digests.json`; demo mode
    /// a temporary file.
    init(cli: any CLIRunning, storageURL: URL, notifies: Bool = true) {
        self.cli = cli
        self.notifies = notifies
        self.storageURL = storageURL
        self.entries = Self.read(storageURL)
    }

    /// Switches to another instance's digests.
    func use(storageURL: URL) {
        self.storageURL = storageURL
        entries = Self.read(storageURL)
    }

    private static func read(_ url: URL) -> [DigestEntry] {
        (try? JSONDecoder().decode([DigestEntry].self, from: Data(contentsOf: url))) ?? []
    }

    // MARK: Public Methods

    /// Digests kept on disk; older ones are dropped.
    static let maxStoredEntries = 60

    func runIfNeeded() async {
        guard !isRunning else { return }
        if let last = entries.last, Date().timeIntervalSince(last.date) < 86400 { return }
        await run()
    }

    /// Collects today's data and saves a digest. Nothing is saved when no data could be
    /// fetched or the model couldn't summarise it, so the next launch tries again.
    func run() async {
        isRunning = true
        defer { isRunning = false }
        let target = storageURL

        let overviewData  = try? await cli.run(.overview)
        let securityData  = try? await cli.run(.securityReport)
        let patchData     = try? await cli.run(.reportPatchStatus)

        let context = Self.buildContext(overview: overviewData, security: securityData, patch: patchData)
        guard !context.isEmpty else { return }
        guard let bullets = await generateBullets(context: context), !bullets.isEmpty else { return }
        // The instance changed while this ran; the digest belongs to the previous one.
        guard target == storageURL else { return }

        let entry = DigestEntry(id: UUID(), date: Date(), bullets: bullets,
                                rawSummary: bullets.map { "• \($0)" }.joined(separator: "\n"))
        entries.append(entry)
        if entries.count > Self.maxStoredEntries {
            entries.removeFirst(entries.count - Self.maxStoredEntries)
        }
        persist()
        if notifies { await notify(entry: entry) }
    }

    // MARK: Private Methods

    /// Compact, readable facts for the model — the same summaries Dashie's tools produce,
    /// instead of raw JSON cut off mid-object.
    static func buildContext(overview: Data?, security: Data?, patch: Data?) -> String {
        var parts: [String] = []
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            if let d = overview { parts.append("## Overview\n" + GetOverviewTool.summarize(d)) }
            if let d = security { parts.append("## Security\n" + GetSecurityReportTool.summarize(d)) }
            if let d = patch    { parts.append("## Patches\n" + GetPatchStatusTool.summarize(d)) }
        }
        #endif
        return parts.joined(separator: "\n\n")
    }

    private func generateBullets(context: String) async -> [String]? {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            guard case .available = SystemLanguageModel.default.availability else { return nil }
            let session = LanguageModelSession(
                model: .default,
                instructions: "You are a Jamf Pro admin assistant. Be direct and factual; keep numbers exact."
            )
            do {
                let response = try await session.respond(
                    to: "Summarise the most important status or issues an admin should know today.\n\n\(context)",
                    generating: DigestSummary.self
                )
                return response.content.bullets
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }

    private func persist() {
        try? JSONEncoder().encode(entries).write(to: storageURL, options: .atomic)
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
