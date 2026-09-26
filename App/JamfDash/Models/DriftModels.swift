import Foundation
import SwiftUI

// MARK: - DriftItemType

enum DriftItemType: String, CaseIterable, Sendable {
    case policy
    case profile
    case script

    var displayName: String {
        switch self {
        case .policy: return "Policy"
        case .profile: return "Profile"
        case .script: return "Script"
        }
    }

    var icon: String {
        switch self {
        case .policy: return "checklist"
        case .profile: return "doc.badge.gearshape"
        case .script: return "terminal"
        }
    }
}

// MARK: - DriftChangeType

enum DriftChangeType: String, Sendable {
    case added
    case removed
    case modified

    var color: Color {
        switch self {
        case .added: return .green
        case .removed: return .red
        case .modified: return .yellow
        }
    }

    var icon: String {
        switch self {
        case .added: return "plus.circle.fill"
        case .removed: return "minus.circle.fill"
        case .modified: return "pencil.circle.fill"
        }
    }

    var label: String {
        switch self {
        case .added: return "Added"
        case .removed: return "Removed"
        case .modified: return "Modified"
        }
    }
}

// MARK: - SnapshotItemRow

struct SnapshotItemRow: Sendable {
    let itemId: String
    let name: String
    let category: String?
}

// MARK: - DriftEvent

struct DriftEvent: Identifiable, Sendable {
    let id: Int64
    let detectedAt: Date
    let itemType: DriftItemType
    let itemId: String
    let itemName: String
    let changeType: DriftChangeType
    let oldValue: String?
    let newValue: String?

    // MARK: Computed

    var detectedAtFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: detectedAt, relativeTo: Date())
    }

    var dayKey: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(detectedAt) {
            return "Today"
        } else if calendar.isDateInYesterday(detectedAt) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: detectedAt)
        }
    }
}
