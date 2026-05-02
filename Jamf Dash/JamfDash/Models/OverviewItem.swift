import Foundation

struct OverviewItem: Codable, Sendable, Hashable, Identifiable {
    var id: String { "\(section)-\(resource)" }
    let section: String
    let resource: String
    let value: String
    let status: String?  // not always present in jamf-cli output
}
