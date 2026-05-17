import Foundation

// MARK: - Device (from computers-inventory GENERAL section)

struct DDMDevice: Sendable, Identifiable, Hashable {
    let id: String            // Jamf Pro computer ID
    let managementId: String  // UUID used for ddm-statuss calls
    let name: String
    let serialNumber: String?
}

extension DDMDevice: Decodable {
    private struct GeneralSection: Decodable {
        let name: String?
        let managementId: String?
        let serialNumber: String?
        let declarativeDeviceManagementEnabled: Bool?
    }

    private enum CodingKeys: String, CodingKey {
        case id, general, serialNumber
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let strID = try? c.decode(String.self, forKey: .id) {
            id = strID
        } else if let intID = try? c.decode(Int.self, forKey: .id) {
            id = String(intID)
        } else {
            id = UUID().uuidString
        }
        let general = try? c.decode(GeneralSection.self, forKey: .general)
        managementId = general?.managementId ?? ""
        name = general?.name ?? id
        serialNumber = (try? c.decode(String.self, forKey: .serialNumber)) ?? general?.serialNumber
    }
}

// MARK: - Status items response

struct DDMStatusItemResponse: Decodable {
    let statusItems: [DDMStatusItem]
}

struct DDMStatusItem: Sendable, Hashable, Identifiable {
    let key: String
    let value: String?
    let lastUpdateTime: String?

    var id: String { key }
}

extension DDMStatusItem: Decodable {
    private enum CodingKeys: String, CodingKey {
        case key, value, lastUpdateTime
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = (try? c.decode(String.self, forKey: .key)) ?? ""
        value = try? c.decode(String.self, forKey: .value)
        lastUpdateTime = try? c.decode(String.self, forKey: .lastUpdateTime)
    }
}

// MARK: - Status

enum DDMStatus: String, Sendable, Hashable {
    case active, pending, error, unknown
}
