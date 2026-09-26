import SwiftUI

// MARK: - Match State

enum MatchState: String, CaseIterable {
    case matched      = "Matched"
    case proOnly      = "Pro Only"
    case protectOnly  = "Protect Only"

    var icon: String {
        switch self {
        case .matched:     return "link.circle.fill"
        case .proOnly:     return "laptopcomputer"
        case .protectOnly: return "shield.fill"
        }
    }

    var color: Color {
        switch self {
        case .matched:     return .green
        case .proOnly:     return .blue
        case .protectOnly: return .orange
        }
    }
}

// MARK: - Filter

enum CorrelationFilter: String, CaseIterable {
    case all          = "All"
    case matched      = "Matched"
    case proOnly      = "Pro Only"
    case protectOnly  = "Protect Only"
}

// MARK: - Correlated Device

struct CorrelatedDevice: Identifiable, Sendable {
    // id is the serial number; fall back to a synthetic key if serial is missing
    var id: String
    let serial: String?
    let proComputer: Computer?
    let protectComputer: ProtectComputer?
    let matchState: MatchState

    // MARK: Convenience display properties

    var displayName: String {
        proComputer?.name ?? protectComputer?.displayName ?? serial ?? id
    }

    var displayOS: String? {
        proComputer?.osVersion ?? protectComputer?.osVersion
    }

    var displaySerial: String {
        serial ?? "—"
    }
}
