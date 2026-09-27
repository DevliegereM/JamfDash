import SwiftUI

// MARK: - Score Component

struct ScoreComponent: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let systemImage: String
    let color: Color
    let earned: Double
    let maxPoints: Double

    var percentage: Double { maxPoints > 0 ? earned / maxPoints : 0 }
}

// MARK: - Fleet Health Score

struct FleetHealthScore: Sendable {
    let score: Int
    let grade: String
    let gradeColor: Color
    /// True when patch compliance data was unavailable; score is calculated over the remaining weight.
    let isPartial: Bool
    let breakdown: [ScoreComponent]
    /// False when there's no security data to score. The score is then meaningless and
    /// must not be shown, badged or compared.
    let isAvailable: Bool

    // MARK: - Init

    /// Computes the fleet health score from security summary, stale-device counts, and optional patch compliance.
    ///
    /// Weights: FileVault=25, SIP=20, Gatekeeper=15, Firewall=15, Device Freshness=10, Patch Compliance=15.
    /// When patch compliance is unavailable, the score is normalised over the remaining 85 pts.
    init(
        summary: SecuritySummary?,
        staleCount: Int,
        totalCount: Int,
        patchCompliancePct: Double?
    ) {
        var components: [ScoreComponent] = []
        isAvailable = (summary?.totalDevices ?? 0) > 0

        if let s = summary, s.totalDevices > 0 {
            let total  = Double(s.totalDevices)
            let fvPct  = Double(s.filevaultEncrypted) / total
            let sipPct = Double(s.sipEnabled)         / total
            let gkPct  = Double(s.gatekeeperEnabled)  / total
            let fwPct  = Double(s.firewallEnabled)    / total

            components.append(ScoreComponent(
                name: "FileVault",
                systemImage: "lock.fill",
                color: .blue,
                earned: fvPct * 25,
                maxPoints: 25
            ))
            components.append(ScoreComponent(
                name: "SIP",
                systemImage: "shield.fill",
                color: .purple,
                earned: sipPct * 20,
                maxPoints: 20
            ))
            components.append(ScoreComponent(
                name: "Gatekeeper",
                systemImage: "checkmark.seal.fill",
                color: .green,
                earned: gkPct * 15,
                maxPoints: 15
            ))
            components.append(ScoreComponent(
                name: "Firewall",
                systemImage: "flame.fill",
                color: .orange,
                earned: fwPct * 15,
                maxPoints: 15
            ))
        }

        if totalCount > 0 {
            let freshPct = 1 - Double(staleCount) / Double(totalCount)
            components.append(ScoreComponent(
                name: "Device Freshness",
                systemImage: "clock.fill",
                color: .cyan,
                earned: freshPct * 10,
                maxPoints: 10
            ))
        }

        if let patch = patchCompliancePct {
            components.append(ScoreComponent(
                name: "Patch Compliance",
                systemImage: "bandage.fill",
                color: .teal,
                earned: (patch / 100) * 15,
                maxPoints: 15
            ))
        }

        let totalEarned = components.reduce(0) { $0 + $1.earned }
        let totalMax    = components.reduce(0) { $0 + $1.maxPoints }

        let raw = totalMax > 0 ? Int((totalEarned / totalMax) * 100) : 0
        self.score     = max(0, min(100, raw))
        self.isPartial = patchCompliancePct == nil
        self.breakdown = components

        switch score {
        case 90...: grade = "A"; gradeColor = .green
        case 75...: grade = "B"; gradeColor = .green
        case 60...: grade = "C"; gradeColor = .yellow
        case 45...: grade = "D"; gradeColor = .orange
        default:    grade = "F"; gradeColor = .red
        }
    }
}
