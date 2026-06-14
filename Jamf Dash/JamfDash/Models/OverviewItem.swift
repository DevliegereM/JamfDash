import Foundation

struct OverviewItem: Codable, Sendable, Hashable, Identifiable {
    /// Stable unique ID. Uses section+resource when both are present; falls back to a
    /// UUID so that items with empty keys don't collide in SwiftUI ForEach.
    let id: String
    let section: String
    let resource: String
    let value: String
    let status: String?  // not always present in jamf-cli output

    private enum CodingKeys: String, CodingKey {
        case id, section, resource, value, status
        // Alternate key names some jamf-cli builds use
        case key, name, label, category, group
        case val, data
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        // Section: "section" > "category" > "group" > ""
        let rawSection = (try? c.decode(String.self, forKey: .section))
                      ?? (try? c.decode(String.self, forKey: .category))
                      ?? (try? c.decode(String.self, forKey: .group))
                      ?? ""
        section = rawSection

        // Resource: "resource" > "key" > "name" > "label" > ""
        let rawResource = (try? c.decode(String.self, forKey: .resource))
                       ?? (try? c.decode(String.self, forKey: .key))
                       ?? (try? c.decode(String.self, forKey: .name))
                       ?? (try? c.decode(String.self, forKey: .label))
                       ?? ""
        resource = rawResource

        // Value: "value" > "val" > "data" > ""
        value = (try? c.decode(String.self, forKey: .value))
             ?? (try? c.decode(String.self, forKey: .val))
             ?? (try? c.decode(String.self, forKey: .data))
             ?? ""

        status = try? c.decode(String.self, forKey: .status)

        // Build a stable ID: prefer section+resource when meaningful, else a UUID.
        if !rawSection.isEmpty || !rawResource.isEmpty {
            id = "\(rawSection)-\(rawResource)"
        } else {
            id = UUID().uuidString
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(section,  forKey: .section)
        try c.encode(resource, forKey: .resource)
        try c.encode(value,    forKey: .value)
        try c.encodeIfPresent(status, forKey: .status)
    }
}
