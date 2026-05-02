import Foundation

struct Policy: Codable, Sendable, Hashable, Identifiable {
    let id: Int
    let name: String
    let category: PolicyCategory?

    private enum CodingKeys: String, CodingKey { case id, name, category }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        // Classic API returns category as a bare string; Pro API returns an {id,name} object
        if let obj = try? c.decode(PolicyCategory.self, forKey: .category) {
            category = obj.name.isEmpty ? nil : obj
        } else if let str = try? c.decode(String.self, forKey: .category), !str.isEmpty {
            category = PolicyCategory(id: 0, name: str)
        } else {
            category = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(category, forKey: .category)
    }
}

struct PolicyCategory: Codable, Sendable, Hashable, Identifiable {
    let id: Int
    let name: String

    init(id: Int, name: String) { self.id = id; self.name = name }

    private enum CodingKeys: String, CodingKey { case id, name }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let intId = try? c.decode(Int.self, forKey: .id) {
            id = intId
        } else {
            id = Int((try? c.decode(String.self, forKey: .id)) ?? "0") ?? 0
        }
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
    }
}

struct SmartComputerGroup: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String
}

struct JamfCategory: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String
}

struct JamfScript: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let category: PolicyCategory?
}

struct JamfPackage: Codable, Sendable, Hashable, Identifiable {
    let id: Int
    let name: String
}

struct ConfigProfile: Codable, Sendable, Hashable, Identifiable {
    let id: Int
    let name: String
}

// MARK: - Smart Group Detail (Pro API returns criteria, not members)

struct SmartGroupDetail: Decodable, Sendable, Identifiable {
    var id: String { name }
    let name: String
    let criteria: [SmartGroupCriterion]

    private enum CodingKeys: String, CodingKey { case name, criteria }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        criteria = (try? c.decode([SmartGroupCriterion].self, forKey: .criteria)) ?? []
    }
}

struct SmartGroupCriterion: Decodable, Sendable, Identifiable {
    var id: String { "\(priority)-\(name)" }
    let name: String
    let priority: Int
    let andOr: String
    let searchType: String
    let value: String
    let openingParen: Bool
    let closingParen: Bool

    private enum CodingKeys: String, CodingKey {
        case name, priority, andOr, searchType, value, openingParen, closingParen
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name     = (try? c.decode(String.self, forKey: .name))       ?? ""
        priority = (try? c.decode(Int.self,    forKey: .priority))   ?? 0
        andOr    = (try? c.decode(String.self, forKey: .andOr))      ?? "and"
        searchType = (try? c.decode(String.self, forKey: .searchType)) ?? ""
        value    = (try? c.decode(String.self, forKey: .value))      ?? ""
        openingParen = (try? c.decode(Bool.self, forKey: .openingParen)) ?? false
        closingParen = (try? c.decode(Bool.self, forKey: .closingParen)) ?? false
    }
}

// MARK: - Jamf Scope (returned by dedicated scope commands)

struct JamfScope: Decodable, Sendable {
    let allComputers: Bool
    let computers: [JamfScopeItem]
    let computerGroups: [JamfScopeItem]
    let departments: [JamfScopeItem]
    let buildings: [JamfScopeItem]
    let limitations: JamfScopeLimitations
    let exclusions: JamfScopeExclusions

    var isEmpty: Bool {
        !allComputers && computers.isEmpty && computerGroups.isEmpty
            && departments.isEmpty && buildings.isEmpty
    }

    init(allComputers: Bool = false, computers: [JamfScopeItem] = [],
         computerGroups: [JamfScopeItem] = [], departments: [JamfScopeItem] = [],
         buildings: [JamfScopeItem] = [], limitations: JamfScopeLimitations = JamfScopeLimitations(),
         exclusions: JamfScopeExclusions = JamfScopeExclusions()) {
        self.allComputers = allComputers; self.computers = computers
        self.computerGroups = computerGroups; self.departments = departments
        self.buildings = buildings; self.limitations = limitations
        self.exclusions = exclusions
    }

    private enum CodingKeys: String, CodingKey {
        case allComputers, computers, computerGroups, departments, buildings, limitations, exclusions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        allComputers   = (try? c.decode(Bool.self,                    forKey: .allComputers))  ?? false
        computers      = (try? c.decode([JamfScopeItem].self,         forKey: .computers))     ?? []
        computerGroups = (try? c.decode([JamfScopeItem].self,         forKey: .computerGroups)) ?? []
        departments    = (try? c.decode([JamfScopeItem].self,         forKey: .departments))   ?? []
        buildings      = (try? c.decode([JamfScopeItem].self,         forKey: .buildings))     ?? []
        limitations    = (try? c.decode(JamfScopeLimitations.self,    forKey: .limitations))   ?? JamfScopeLimitations()
        exclusions     = (try? c.decode(JamfScopeExclusions.self,     forKey: .exclusions))    ?? JamfScopeExclusions()
    }
}

struct JamfScopeItem: Decodable, Sendable, Identifiable {
    let id: Int
    let name: String

    init(id: Int, name: String) { self.id = id; self.name = name }

    private enum CodingKeys: String, CodingKey { case id, name }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let intId = try? c.decode(Int.self, forKey: .id) { id = intId }
        else { id = Int((try? c.decode(String.self, forKey: .id)) ?? "0") ?? 0 }
        name = (try? c.decode(String.self, forKey: .name)) ?? "Unknown"
    }
}

struct JamfScopeLimitations: Decodable, Sendable {
    let users: [JamfScopeItem]
    let userGroups: [JamfScopeItem]
    let networkSegments: [JamfScopeItem]
    let ibeacons: [JamfScopeItem]

    var hasAny: Bool {
        !users.isEmpty || !userGroups.isEmpty || !networkSegments.isEmpty || !ibeacons.isEmpty
    }

    init(users: [JamfScopeItem] = [], userGroups: [JamfScopeItem] = [],
         networkSegments: [JamfScopeItem] = [], ibeacons: [JamfScopeItem] = []) {
        self.users = users; self.userGroups = userGroups
        self.networkSegments = networkSegments; self.ibeacons = ibeacons
    }

    private enum CodingKeys: String, CodingKey {
        case users, userGroups, networkSegments, ibeacons
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        users           = (try? c.decode([JamfScopeItem].self, forKey: .users))           ?? []
        userGroups      = (try? c.decode([JamfScopeItem].self, forKey: .userGroups))      ?? []
        networkSegments = (try? c.decode([JamfScopeItem].self, forKey: .networkSegments)) ?? []
        ibeacons        = (try? c.decode([JamfScopeItem].self, forKey: .ibeacons))        ?? []
    }
}

struct JamfScopeExclusions: Decodable, Sendable {
    let computers: [JamfScopeItem]
    let computerGroups: [JamfScopeItem]
    let departments: [JamfScopeItem]
    let buildings: [JamfScopeItem]
    let users: [JamfScopeItem]
    let userGroups: [JamfScopeItem]
    let networkSegments: [JamfScopeItem]

    var hasAny: Bool {
        !computers.isEmpty || !computerGroups.isEmpty || !departments.isEmpty || !buildings.isEmpty
            || !users.isEmpty || !userGroups.isEmpty || !networkSegments.isEmpty
    }

    init(computers: [JamfScopeItem] = [], computerGroups: [JamfScopeItem] = [],
         departments: [JamfScopeItem] = [], buildings: [JamfScopeItem] = [],
         users: [JamfScopeItem] = [], userGroups: [JamfScopeItem] = [],
         networkSegments: [JamfScopeItem] = []) {
        self.computers = computers; self.computerGroups = computerGroups
        self.departments = departments; self.buildings = buildings
        self.users = users; self.userGroups = userGroups
        self.networkSegments = networkSegments
    }

    private enum CodingKeys: String, CodingKey {
        case computers, computerGroups, departments, buildings, users, userGroups, networkSegments
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        computers       = (try? c.decode([JamfScopeItem].self, forKey: .computers))       ?? []
        computerGroups  = (try? c.decode([JamfScopeItem].self, forKey: .computerGroups))  ?? []
        departments     = (try? c.decode([JamfScopeItem].self, forKey: .departments))     ?? []
        buildings       = (try? c.decode([JamfScopeItem].self, forKey: .buildings))       ?? []
        users           = (try? c.decode([JamfScopeItem].self, forKey: .users))           ?? []
        userGroups      = (try? c.decode([JamfScopeItem].self, forKey: .userGroups))      ?? []
        networkSegments = (try? c.decode([JamfScopeItem].self, forKey: .networkSegments)) ?? []
    }
}

// MARK: - Org objects

struct Building: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String

    private enum CodingKeys: String, CodingKey { case id, name }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else { id = String(try c.decode(Int.self, forKey: .id)) }
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
    }
}

struct Department: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String

    private enum CodingKeys: String, CodingKey { case id, name }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else { id = String(try c.decode(Int.self, forKey: .id)) }
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
    }
}

struct NetworkSegment: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let startingAddress: String?
    let endingAddress: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, startingAddress, endingAddress
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else { id = String(try c.decode(Int.self, forKey: .id)) }
        name            = (try? c.decode(String.self, forKey: .name))            ?? ""
        startingAddress = try? c.decode(String.self, forKey: .startingAddress)
        endingAddress   = try? c.decode(String.self, forKey: .endingAddress)
    }
}

// MARK: - Extension Attributes

struct ExtensionAttribute: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let dataType: String?
    let inputType: String?
    let inventoryDisplayType: String?
    let enabled: Bool?
    let scriptContents: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, description, dataType, inputType, inventoryDisplayType, enabled, scriptContents
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else { id = String(try c.decode(Int.self, forKey: .id)) }
        name                 = (try? c.decode(String.self, forKey: .name))                 ?? ""
        description          = try? c.decode(String.self, forKey: .description)
        dataType             = try? c.decode(String.self, forKey: .dataType)
        inputType            = try? c.decode(String.self, forKey: .inputType)
        inventoryDisplayType = try? c.decode(String.self, forKey: .inventoryDisplayType)
        enabled              = try? c.decode(Bool.self,   forKey: .enabled)
        scriptContents       = try? c.decode(String.self, forKey: .scriptContents)
    }
}

// MARK: - Patch Management

struct PatchTitle: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let category: String?
    let currentVersion: String?

    private enum CodingKeys: String, CodingKey {
        // Classic API returns snake_case; also handle camelCase and demo variants
        case id, name, category
        case currentVersion = "currentVersion"
        case current_version = "current_version"
        case latestVersion = "latestVersion"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else { id = String(try c.decode(Int.self, forKey: .id)) }
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        // Classic API returns category as {"id":N,"name":"..."};
        // uncategorised titles use id -1 and an empty or placeholder name
        if let s = try? c.decode(String.self, forKey: .category) {
            category = s.isEmpty ? nil : s
        } else {
            struct NamedObj: Decodable { let id: Int?; let name: String? }
            let obj = try? c.decode(NamedObj.self, forKey: .category)
            let catName = obj?.name ?? ""
            let catId   = obj?.id ?? -1
            category = (catId == -1 || catName.isEmpty) ? nil : catName
        }
        // Classic API uses snake_case current_version; camelCase and latestVersion are fallbacks
        currentVersion = (try? c.decode(String.self, forKey: .current_version))
                      ?? (try? c.decode(String.self, forKey: .currentVersion))
                      ?? (try? c.decode(String.self, forKey: .latestVersion))
    }
}

struct PatchPolicy: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let enabled: Bool?
    let patchTitle: String?
    let targetVersion: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, enabled
        case patchTitle = "patchTitle"
        case patch_title = "patch_title"
        case targetVersion = "targetVersion"
        case target_version = "target_version"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else { id = String(try c.decode(Int.self, forKey: .id)) }
        name    = (try? c.decode(String.self, forKey: .name))    ?? ""
        enabled = try? c.decode(Bool.self, forKey: .enabled)
        // Classic API uses snake_case; camelCase is the fallback
        targetVersion = (try? c.decode(String.self, forKey: .target_version))
                     ?? (try? c.decode(String.self, forKey: .targetVersion))
        // patch_title may be a plain string or a nested {"id":N,"name":"..."} object
        if let s = try? c.decode(String.self, forKey: .patch_title) {
            patchTitle = s.isEmpty ? nil : s
        } else if let s = try? c.decode(String.self, forKey: .patchTitle) {
            patchTitle = s.isEmpty ? nil : s
        } else {
            struct NamedObj: Decodable { let name: String? }
            patchTitle = (try? c.decode(NamedObj.self, forKey: .patch_title))?.name
                      ?? (try? c.decode(NamedObj.self, forKey: .patchTitle))?.name
        }
    }
}

// MARK: - Patch Detail models

struct PatchTitleDetail: Decodable, Sendable {
    let id: String
    let name: String
    let category: String?
    let versions: [PatchVersion]?

    struct PatchVersion: Decodable, Sendable {
        let softwareVersion: String?
        private enum CodingKeys: String, CodingKey {
            case softwareVersion, software_version
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            softwareVersion = (try? c.decode(String.self, forKey: .softwareVersion))
                           ?? (try? c.decode(String.self, forKey: .software_version))
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, category, versions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else { id = String(try c.decode(Int.self, forKey: .id)) }
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        if let s = try? c.decode(String.self, forKey: .category) {
            category = s.isEmpty ? nil : s
        } else {
            struct NamedObj: Decodable { let id: Int?; let name: String? }
            let obj = try? c.decode(NamedObj.self, forKey: .category)
            let catName = obj?.name ?? ""
            let catId   = obj?.id ?? -1
            category = (catId == -1 || catName.isEmpty) ? nil : catName
        }
        versions = try? c.decode([PatchVersion].self, forKey: .versions)
    }

    var latestVersion: String? { versions?.compactMap(\.softwareVersion).first }
}

struct PatchPolicyDetail: Decodable, Sendable {
    let id: String
    let name: String
    let enabled: Bool?
    let targetVersion: String?
    let patchTitle: String?

    private enum GeneralKeys: String, CodingKey {
        case id, name, enabled
        case targetVersion, target_version
        case patchTitle, patch_title
    }
    private struct PatchTitleNested: Decodable { let name: String? }

    init(from decoder: Decoder) throws {
        let top = try decoder.container(keyedBy: DynamicKey.self)
        let c: KeyedDecodingContainer<GeneralKeys>
        if let general = try? top.nestedContainer(keyedBy: GeneralKeys.self, forKey: DynamicKey("general")) {
            c = general
        } else {
            c = try decoder.container(keyedBy: GeneralKeys.self)
        }
        if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else { id = String((try? c.decode(Int.self, forKey: .id)) ?? 0) }
        name    = (try? c.decode(String.self, forKey: .name)) ?? ""
        enabled = try? c.decode(Bool.self, forKey: .enabled)
        targetVersion = (try? c.decode(String.self, forKey: .targetVersion))
                     ?? (try? c.decode(String.self, forKey: .target_version))
        if let s = try? c.decode(String.self, forKey: .patchTitle) {
            patchTitle = s
        } else if let s = try? c.decode(String.self, forKey: .patch_title) {
            patchTitle = s
        } else {
            patchTitle = (try? c.decode(PatchTitleNested.self, forKey: .patchTitle))?.name
                      ?? (try? c.decode(PatchTitleNested.self, forKey: .patch_title))?.name
        }
    }
}

private struct DynamicKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

// MARK: - Enrollment & Prestages

struct DEPToken: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let tokenExpiration: String?
    let orgName: String?

    private enum CodingKeys: String, CodingKey {
        case id, uuid, tokenExpiration, expiration, tokenExpirationDate, expirationDate,
             orgName, organizationName, name
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .uuid) { id = s }
        else if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else { id = String(try c.decode(Int.self, forKey: .id)) }
        tokenExpiration = (try? c.decode(String.self, forKey: .tokenExpiration))
                       ?? (try? c.decode(String.self, forKey: .tokenExpirationDate))
                       ?? (try? c.decode(String.self, forKey: .expiration))
                       ?? (try? c.decode(String.self, forKey: .expirationDate))
        orgName = (try? c.decode(String.self, forKey: .orgName))
               ?? (try? c.decode(String.self, forKey: .organizationName))
               ?? (try? c.decode(String.self, forKey: .name))
    }
}

struct ComputerPrestage: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let displayName: String
    let enrollmentSiteId: String?
    let mdmRemovable: Bool?

    private enum CodingKeys: String, CodingKey {
        case id, uuid, displayName, name, enrollmentSiteId, mdmRemovable
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .uuid) { id = s }
        else if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else { id = String(try c.decode(Int.self, forKey: .id)) }
        displayName     = (try? c.decode(String.self, forKey: .displayName))
                       ?? (try? c.decode(String.self, forKey: .name)) ?? id
        enrollmentSiteId = try? c.decode(String.self, forKey: .enrollmentSiteId)
        mdmRemovable     = try? c.decode(Bool.self,   forKey: .mdmRemovable)
    }
}

struct MobileDevicePrestage: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let displayName: String
    let enrollmentSiteId: String?

    private enum CodingKeys: String, CodingKey {
        case id, uuid, displayName, name, enrollmentSiteId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .uuid) { id = s }
        else if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else { id = String(try c.decode(Int.self, forKey: .id)) }
        displayName      = (try? c.decode(String.self, forKey: .displayName))
                        ?? (try? c.decode(String.self, forKey: .name)) ?? id
        enrollmentSiteId = try? c.decode(String.self, forKey: .enrollmentSiteId)
    }
}

// MARK: - Webhooks

struct JamfWebhook: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let enabled: Bool?
    let event: String?
    let url: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, enabled, event, url, webhookUrl, webHookUrl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else { id = String(try c.decode(Int.self, forKey: .id)) }
        name    = (try? c.decode(String.self, forKey: .name))    ?? ""
        enabled = try? c.decode(Bool.self,   forKey: .enabled)
        event   = try? c.decode(String.self, forKey: .event)
        url     = (try? c.decode(String.self, forKey: .url))
               ?? (try? c.decode(String.self, forKey: .webhookUrl))
               ?? (try? c.decode(String.self, forKey: .webHookUrl))
    }
}

// MARK: - Computer inventory

struct Computer: Codable, Sendable, Hashable, Identifiable {
    let id: String  // Pro API returns id as either String ("1") or Int (1) depending on endpoint/version
    let name: String
    let serialNumber: String?
    let osVersion: String?
    let lastContactTime: String?   // ISO 8601 or human-readable string from jamf-cli
    let managed: Bool?

    // Nested sub-objects used by Pro API v1/v2 responses
    private struct NestedOS: Decodable {
        let version: String?
        let name: String?   // e.g. "macOS"
    }
    private struct NestedGeneral: Decodable {
        let name: String?
        let lastContactTime: String?
        let lastContact: String?
        var effectiveContactTime: String? { lastContactTime ?? lastContact }
    }
    private struct NestedManagementState: Decodable {
        let managed: Bool?
    }
    private struct NestedHardware: Decodable {
        let serialNumber: String?
        let serial: String?
        var effectiveSerial: String? { serialNumber ?? serial }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, managed
        case serialNumber, osVersion, lastContactTime
        // alternative flat-field spellings
        case serial, osname, lastContact
        // nested section keys (Pro API v1/v2)
        case operatingSystem, general, managementState, hardware
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // id may be a String ("1") or an Int (1) depending on endpoint/version
        if let strID = try? c.decode(String.self, forKey: .id) {
            id = strID
        } else {
            id = String(try c.decode(Int.self, forKey: .id))
        }
        // Name may be top-level or nested inside the "general" section (Pro API v2)
        let nestedGeneral = try? c.decode(NestedGeneral.self, forKey: .general)
        name = (try? c.decode(String.self, forKey: .name)) ?? nestedGeneral?.name ?? id

        // managed: flat bool, or nested in managementState
        managed = (try? c.decode(Bool.self, forKey: .managed))
               ?? (try? c.decode(NestedManagementState.self, forKey: .managementState))?.managed

        // serialNumber: flat keys, or nested in hardware section (Pro API v2)
        serialNumber = (try? c.decode(String.self, forKey: .serialNumber))
                    ?? (try? c.decode(String.self, forKey: .serial))
                    ?? (try? c.decode(NestedHardware.self, forKey: .hardware))?.effectiveSerial

        // osVersion: flat key, alternate "osname", or nested operatingSystem.version
        osVersion = (try? c.decode(String.self, forKey: .osVersion))
                 ?? (try? c.decode(String.self, forKey: .osname))
                 ?? (try? c.decode(NestedOS.self, forKey: .operatingSystem))?.version

        // lastContactTime: flat, alternate "lastContact", or nested in general section
        lastContactTime = (try? c.decode(String.self, forKey: .lastContactTime))
                       ?? (try? c.decode(String.self, forKey: .lastContact))
                       ?? nestedGeneral?.effectiveContactTime
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(managed, forKey: .managed)
        try c.encodeIfPresent(serialNumber, forKey: .serialNumber)
        try c.encodeIfPresent(osVersion, forKey: .osVersion)
        try c.encodeIfPresent(lastContactTime, forKey: .lastContactTime)
    }

    /// Returns the number of days since last contact, or nil if the date cannot be parsed.
    var daysSinceContact: Int? {
        guard let str = lastContactTime else { return nil }
        let fmts = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd"
        ]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        for fmt in fmts {
            df.dateFormat = fmt
            if let date = df.date(from: str) {
                return Calendar.current.dateComponents([.day], from: date, to: Date()).day
            }
        }
        return nil
    }
}
