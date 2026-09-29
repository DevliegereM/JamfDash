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

struct JamfScriptDetail: Decodable, Sendable, Identifiable {
    let id: String
    let name: String
    let categoryId: String?
    let categoryName: String?
    let filename: String?
    let info: String?
    let notes: String?
    let osRequirements: String?
    let priority: String?
    let scriptContents: String?
    let parameters: [String: String]?

    private enum CodingKeys: String, CodingKey {
        case id, name, categoryId, categoryName, filename, info, notes
        case osRequirements, priority, scriptContents, parameters
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = (try? c.decode(String.self, forKey: .id)) ?? ""
        name            = (try? c.decode(String.self, forKey: .name)) ?? ""
        categoryId      = try? c.decode(String.self, forKey: .categoryId)
        categoryName    = try? c.decode(String.self, forKey: .categoryName)
        filename        = try? c.decode(String.self, forKey: .filename)
        info            = try? c.decode(String.self, forKey: .info)
        notes           = try? c.decode(String.self, forKey: .notes)
        osRequirements  = try? c.decode(String.self, forKey: .osRequirements)
        priority        = try? c.decode(String.self, forKey: .priority)
        scriptContents  = try? c.decode(String.self, forKey: .scriptContents)
        parameters      = try? c.decode([String: String].self, forKey: .parameters)
    }
}

struct JamfPackage: Codable, Sendable, Hashable, Identifiable {
    let id: Int
    let name: String
}

struct JamfPackageDetail: Decodable, Sendable, Identifiable {
    let id: Int
    let name: String
    let category: String?
    let filename: String?
    let info: String?
    let notes: String?
    let priority: Int?
    let rebootRequired: Bool?
    let osRequirements: String?
    let fillUserTemplate: Bool?
    let allowUninstalled: Bool?
    let sendNotification: Bool?
    let switchWithPackage: String?
    let reinstallOption: String?
    let requiredProcessor: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, category, filename, info, notes, priority
        case rebootRequired = "reboot_required"
        case osRequirements = "os_requirements"
        case fillUserTemplate = "fill_user_template"
        case allowUninstalled = "allow_uninstalled"
        case sendNotification = "send_notification"
        case switchWithPackage = "switch_with_package"
        case reinstallOption = "reinstall_option"
        case requiredProcessor = "required_processor"
    }

    private struct Wrapper: Decodable {
        let package: JamfPackageDetail
    }

    init(from decoder: Decoder) throws {
        // Try unwrapping {"package": {...}} wrapper first, then fall back to flat object
        if let wrapped = try? Wrapper(from: decoder) {
            self = wrapped.package
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let intId = try? c.decode(Int.self, forKey: .id) {
            id = intId
        } else {
            id = Int((try? c.decode(String.self, forKey: .id)) ?? "0") ?? 0
        }
        name              = (try? c.decode(String.self, forKey: .name)) ?? ""
        category          = try? c.decode(String.self, forKey: .category)
        filename          = try? c.decode(String.self, forKey: .filename)
        info              = try? c.decode(String.self, forKey: .info)
        notes             = try? c.decode(String.self, forKey: .notes)
        priority          = try? c.decode(Int.self, forKey: .priority)
        rebootRequired    = try? c.decode(Bool.self, forKey: .rebootRequired)
        osRequirements    = try? c.decode(String.self, forKey: .osRequirements)
        fillUserTemplate  = try? c.decode(Bool.self, forKey: .fillUserTemplate)
        allowUninstalled  = try? c.decode(Bool.self, forKey: .allowUninstalled)
        sendNotification  = try? c.decode(Bool.self, forKey: .sendNotification)
        switchWithPackage = try? c.decode(String.self, forKey: .switchWithPackage)
        reinstallOption   = try? c.decode(String.self, forKey: .reinstallOption)
        requiredProcessor = try? c.decode(String.self, forKey: .requiredProcessor)
    }
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
    /// Choices of a pop-up menu attribute; empty for other input types.
    let popupMenuChoices: [String]

    private enum CodingKeys: String, CodingKey {
        case id, name, description, dataType, inputType, inventoryDisplayType, enabled, scriptContents, popupMenuChoices
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
        popupMenuChoices     = (try? c.decode([String].self, forKey: .popupMenuChoices)) ?? []
    }
}

// MARK: - Patch Management

struct PatchTitle: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let category: String?
    let currentVersion: String?

    /// Creates an enriched copy of a thin list item using detail data.
    /// Preserves the thin item's id and name; fills in category and currentVersion
    /// from the detail endpoint (which has the full record).
    init(thin: PatchTitle, detail: PatchTitleDetail) {
        self.id             = thin.id
        self.name           = thin.name.isEmpty ? detail.name : thin.name
        self.category       = detail.category       ?? thin.category
        self.currentVersion = detail.latestVersion  ?? thin.currentVersion
    }

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
    // UAPI v2 device counts (nil when using Classic API list)
    let installedCount: Int?
    let pendingCount: Int?
    let failedCount: Int?

    /// Creates an enriched copy of a thin list item using detail data.
    init(thin: PatchPolicy, detail: PatchPolicyDetail) {
        self.id             = thin.id
        self.name           = thin.name.isEmpty ? detail.name : thin.name
        self.enabled        = detail.enabled       ?? thin.enabled
        self.targetVersion  = detail.targetVersion ?? thin.targetVersion
        self.patchTitle     = detail.patchTitle    ?? thin.patchTitle
        self.installedCount = thin.installedCount
        self.pendingCount   = thin.pendingCount
        self.failedCount    = thin.failedCount
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, enabled
        case patchTitle, patch_title
        case softwareTitleName, software_title_name        // UAPI v2
        case targetVersion, target_version
        case targetPatchVersion, target_patch_version      // UAPI v2
        case installedDevicesCount, installed_devices_count
        case pendingDevicesCount, pending_devices_count
        case failedDevicesCount, failed_devices_count
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else { id = String(try c.decode(Int.self, forKey: .id)) }
        name    = (try? c.decode(String.self, forKey: .name))    ?? ""
        enabled = try? c.decode(Bool.self, forKey: .enabled)
        // target version: UAPI v2 uses targetPatchVersion; Classic uses target_version
        targetVersion = (try? c.decode(String.self, forKey: .targetPatchVersion))
                     ?? (try? c.decode(String.self, forKey: .target_patch_version))
                     ?? (try? c.decode(String.self, forKey: .target_version))
                     ?? (try? c.decode(String.self, forKey: .targetVersion))
        // patch title: UAPI v2 has softwareTitleName; Classic has nested {"id":N,"name":"..."}
        struct NamedObj: Decodable { let name: String? }
        var rawTitle: String? = (try? c.decode(String.self, forKey: .softwareTitleName))
                             ?? (try? c.decode(String.self, forKey: .software_title_name))
        if rawTitle == nil {
            rawTitle = (try? c.decode(String.self, forKey: .patch_title))
                    ?? (try? c.decode(String.self, forKey: .patchTitle))
        }
        if rawTitle == nil {
            rawTitle = (try? c.decode(NamedObj.self, forKey: .patch_title))?.name
                    ?? (try? c.decode(NamedObj.self, forKey: .patchTitle))?.name
        }
        patchTitle = rawTitle?.isEmpty == false ? rawTitle : nil
        // device counts (UAPI v2 only)
        installedCount = (try? c.decode(Int.self, forKey: .installedDevicesCount))
                      ?? (try? c.decode(Int.self, forKey: .installed_devices_count))
        pendingCount   = (try? c.decode(Int.self, forKey: .pendingDevicesCount))
                      ?? (try? c.decode(Int.self, forKey: .pending_devices_count))
        failedCount    = (try? c.decode(Int.self, forKey: .failedDevicesCount))
                      ?? (try? c.decode(Int.self, forKey: .failed_devices_count))
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
            // software_version can be a String ("26.3.1") or a Number (26, 26.5)
            if let s = (try? c.decode(String.self, forKey: .softwareVersion))
                    ?? (try? c.decode(String.self, forKey: .software_version)) {
                softwareVersion = s.isEmpty ? nil : s
            } else if let d = (try? c.decode(Double.self, forKey: .software_version))
                           ?? (try? c.decode(Double.self, forKey: .softwareVersion)) {
                softwareVersion = d.truncatingRemainder(dividingBy: 1) == 0
                    ? String(Int(d)) : String(d)
            } else {
                softwareVersion = nil
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, category, versions
    }

    /// The Classic API wraps versions as `{"version":[…]}` not a flat array.
    private struct VersionsWrapper: Decodable {
        let version: [PatchVersion]
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
        // Classic API: {"version":[…]}; UAPI / demo: flat [PatchVersion]
        if let wrapper = try? c.decode(VersionsWrapper.self, forKey: .versions) {
            versions = wrapper.version
        } else {
            versions = try? c.decode([PatchVersion].self, forKey: .versions)
        }
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

// MARK: - Modern Patch

struct ModernPatchTitle: Identifiable, Sendable {
    let id: String
    let name: String
    // Real API (patch-software-title-configurations)
    let publisher: String?          // softwareTitlePublisher
    let patchSource: String?        // patchSourceName ("Jamf", custom, …)
    let uiNotifications: Bool?      // uiNotifications
    let emailNotifications: Bool?   // emailNotifications
    // Legacy / demo fields (not in real list endpoint; kept for demo compatibility)
    let currentVersion: String?
    let categoryName: String?
    let onDashboard: Bool?
    let upToDate: Int?
    let outOfDate: Int?
    let unknown: Int?
    var total: Int { (upToDate ?? 0) + (outOfDate ?? 0) + (unknown ?? 0) }
    var compliantPct: Double? {
        guard total > 0, let u = upToDate else { return nil }
        return Double(u) / Double(total) * 100
    }
}

extension ModernPatchTitle: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, name, title, displayName, softwareTitleName, software_title_name, softwareTitle, software_title
        case publisher, softwareTitlePublisher, software_title_publisher
        case patchSource, patchSourceName, patch_source_name
        case uiNotifications, ui_notifications, uiNotification
        case emailNotifications, email_notifications
        case currentVersion, current_version, latestVersion, latest_version
        case categoryName, category_name
        case onDashboard, on_dashboard, dashboard, showOnDashboard, show_on_dashboard
        case notifications
        case upToDate, up_to_date, compliant
        case outOfDate, out_of_date, nonCompliant, non_compliant
        case unknown, pending
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else if let n = try? c.decode(Int.self, forKey: .id) { id = String(n) }
        else { id = UUID().uuidString }
        // Real API uses "softwareTitleName" or "displayName"; demo uses "name"
        name = (try? c.decode(String.self, forKey: .softwareTitleName))
            ?? (try? c.decode(String.self, forKey: .software_title_name))
            ?? (try? c.decode(String.self, forKey: .displayName))
            ?? (try? c.decode(String.self, forKey: .name))
            ?? (try? c.decode(String.self, forKey: .title))
            ?? (try? c.decode(String.self, forKey: .softwareTitle))
            ?? (try? c.decode(String.self, forKey: .software_title))
            ?? "Unknown"
        publisher = (try? c.decode(String.self, forKey: .softwareTitlePublisher))
                 ?? (try? c.decode(String.self, forKey: .software_title_publisher))
                 ?? (try? c.decode(String.self, forKey: .publisher))
        let rawSource = (try? c.decode(String.self, forKey: .patchSourceName))
                     ?? (try? c.decode(String.self, forKey: .patch_source_name))
                     ?? (try? c.decode(String.self, forKey: .patchSource))
        patchSource = rawSource?.isEmpty == false ? rawSource : nil
        uiNotifications = (try? c.decode(Bool.self, forKey: .uiNotifications))
            ?? (try? c.decode(Bool.self, forKey: .ui_notifications))
            ?? (try? c.decode(Bool.self, forKey: .uiNotification))
            ?? (try? c.decode(Bool.self, forKey: .notifications))
        emailNotifications = (try? c.decode(Bool.self, forKey: .emailNotifications))
            ?? (try? c.decode(Bool.self, forKey: .email_notifications))
        // Legacy / demo fields
        currentVersion = (try? c.decode(String.self, forKey: .currentVersion))
            ?? (try? c.decode(String.self, forKey: .current_version))
            ?? (try? c.decode(String.self, forKey: .latestVersion))
            ?? (try? c.decode(String.self, forKey: .latest_version))
        let rawCat = (try? c.decode(String.self, forKey: .categoryName))
                  ?? (try? c.decode(String.self, forKey: .category_name))
        categoryName = rawCat?.isEmpty == false ? rawCat : nil
        onDashboard = (try? c.decode(Bool.self, forKey: .onDashboard))
            ?? (try? c.decode(Bool.self, forKey: .on_dashboard))
            ?? (try? c.decode(Bool.self, forKey: .dashboard))
            ?? (try? c.decode(Bool.self, forKey: .showOnDashboard))
            ?? (try? c.decode(Bool.self, forKey: .show_on_dashboard))
        upToDate   = (try? c.decode(Int.self, forKey: .upToDate))   ?? (try? c.decode(Int.self, forKey: .up_to_date))   ?? (try? c.decode(Int.self, forKey: .compliant))
        outOfDate  = (try? c.decode(Int.self, forKey: .outOfDate))  ?? (try? c.decode(Int.self, forKey: .out_of_date))  ?? (try? c.decode(Int.self, forKey: .nonCompliant)) ?? (try? c.decode(Int.self, forKey: .non_compliant))
        unknown    = (try? c.decode(Int.self, forKey: .unknown))    ?? (try? c.decode(Int.self, forKey: .pending))
    }
}

// MARK: - App Installer

struct AppInstallerTitle: Identifiable, Sendable {
    let id: String
    let name: String
    let publisher: String?
    let currentVersion: String?
    let category: String?
}

extension AppInstallerTitle: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, name, title
        // Real API field name: "titleName"
        case titleName, title_name
        case publisher, vendor
        case currentVersion, current_version, latestVersion, latest_version, version
        case category
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else if let n = try? c.decode(Int.self, forKey: .id) { id = String(n) }
        else { id = UUID().uuidString }
        // Real API uses "titleName"; demo uses "name"
        name = (try? c.decode(String.self, forKey: .titleName))
            ?? (try? c.decode(String.self, forKey: .title_name))
            ?? (try? c.decode(String.self, forKey: .name))
            ?? (try? c.decode(String.self, forKey: .title))
            ?? "Unknown"
        publisher = (try? c.decode(String.self, forKey: .publisher))
            ?? (try? c.decode(String.self, forKey: .vendor))
        currentVersion = (try? c.decode(String.self, forKey: .currentVersion))
            ?? (try? c.decode(String.self, forKey: .current_version))
            ?? (try? c.decode(String.self, forKey: .latestVersion))
            ?? (try? c.decode(String.self, forKey: .latest_version))
            ?? (try? c.decode(String.self, forKey: .version))
        category = try? c.decode(String.self, forKey: .category)
    }
}

struct AppInstallerDeployment: Identifiable, Sendable {
    let id: String
    let name: String
    let categoryName: String?      // category.name
    let updateBehavior: String?    // top-level updateBehavior ("AUTOMATIC", "SPECIFIC_VERSION", …)
    let latestVersion: String?     // app.latestVersion
    let selectedVersion: String?   // app.selectedVersion (pinned; empty = latest)
    let deployedVersion: String?   // app.deployedVersion (currently deployed)
    let enabled: Bool?
    let deploymentType: String?    // "SELF_SERVICE" | "AUTOMATIC"
    let installedCount: Int?       // computerStatuses.installed
    let availableCount: Int?       // computerStatuses.available
    let inProgressCount: Int?      // computerStatuses.inProgress
    let failedCount: Int?          // computerStatuses.failed
    let smartGroupName: String?    // smartGroup.name (target)
    let iconURL: URL?              // app.iconUrl, only when served by Jamf over https

    /// Total devices targeted = installed + available + inProgress + failed + unqualified.
    var assignedCount: Int? {
        guard installedCount != nil || availableCount != nil else { return nil }
        return (installedCount ?? 0) + (availableCount ?? 0)
            + (inProgressCount ?? 0) + (failedCount ?? 0)
    }

    /// Version to display: pinned selected version, or latest if deploying latest.
    var displayVersion: String? {
        if let v = selectedVersion, !v.isEmpty { return v }
        return latestVersion
    }
}

extension AppInstallerDeployment: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, name, enabled
        case deploymentType, deployment_type
        case updateBehavior, update_behavior
        case site, smartGroup, smart_group
        case category
        case computerStatuses, computer_statuses
        case app
    }

    /// `{"id":"…","name":"…"}` nested helper.
    private struct NamedObj: Decodable { let name: String? }

    /// `app` sub-object returned by the App Installer Deployments API.
    private struct AppObj: Decodable {
        let latestVersion: String?
        let selectedVersion: String?
        let deployedVersion: String?
        let iconUrl: String?
        private enum CodingKeys: String, CodingKey {
            case iconUrl, icon_url
            case latestVersion, latest_version
            case selectedVersion, selected_version
            case deployedVersion, deployed_version
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            latestVersion  = (try? c.decode(String.self, forKey: .latestVersion))
                          ?? (try? c.decode(String.self, forKey: .latest_version))
            selectedVersion = (try? c.decode(String.self, forKey: .selectedVersion))
                           ?? (try? c.decode(String.self, forKey: .selected_version))
            deployedVersion = (try? c.decode(String.self, forKey: .deployedVersion))
                           ?? (try? c.decode(String.self, forKey: .deployed_version))
            iconUrl = (try? c.decode(String.self, forKey: .iconUrl))
                   ?? (try? c.decode(String.self, forKey: .icon_url))
        }
    }

    /// `computerStatuses` sub-object.
    private struct ComputerStatuses: Decodable {
        let installed:   Int?
        let available:   Int?
        let inProgress:  Int?
        let failed:      Int?
        let unqualified: Int?
        private enum CodingKeys: String, CodingKey {
            case installed, available
            case inProgress, in_progress
            case failed, unqualified
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            installed   = try? c.decode(Int.self, forKey: .installed)
            available   = try? c.decode(Int.self, forKey: .available)
            inProgress  = (try? c.decode(Int.self, forKey: .inProgress))
                       ?? (try? c.decode(Int.self, forKey: .in_progress))
            failed      = try? c.decode(Int.self, forKey: .failed)
            unqualified = try? c.decode(Int.self, forKey: .unqualified)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else if let n = try? c.decode(Int.self, forKey: .id) { id = String(n) }
        else { id = UUID().uuidString }

        name    = (try? c.decode(String.self, forKey: .name)) ?? "Unknown"
        enabled = try? c.decode(Bool.self, forKey: .enabled)

        deploymentType  = (try? c.decode(String.self, forKey: .deploymentType))
                       ?? (try? c.decode(String.self, forKey: .deployment_type))
        updateBehavior  = (try? c.decode(String.self, forKey: .updateBehavior))
                       ?? (try? c.decode(String.self, forKey: .update_behavior))

        // category: {"id":"6","name":"Browsers"}
        categoryName = (try? c.decode(NamedObj.self, forKey: .category))?.name

        // app sub-object
        let appObj      = try? c.decode(AppObj.self, forKey: .app)
        latestVersion   = appObj?.latestVersion
        selectedVersion = appObj?.selectedVersion
        deployedVersion = appObj?.deployedVersion
        iconURL         = appObj?.iconUrl.flatMap(Self.trustedIconURL)
        smartGroupName  = ((try? c.decode(NamedObj.self, forKey: .smartGroup))
                        ?? (try? c.decode(NamedObj.self, forKey: .smart_group)))?.name

        // computerStatuses sub-object
        let statuses     = (try? c.decode(ComputerStatuses.self, forKey: .computerStatuses))
                        ?? (try? c.decode(ComputerStatuses.self, forKey: .computer_statuses))
        installedCount   = statuses?.installed
        availableCount   = statuses?.available
        inProgressCount  = statuses?.inProgress
        failedCount      = statuses?.failed
    }

    /// Icons are fetched straight from the URL in the API response, so only https URLs
    /// on Jamf's own domains are used (e.g. appinstallers-packages.services.jamfcloud.com).
    static func trustedIconURL(_ string: String) -> URL? {
        guard let url = URL(string: string), url.scheme == "https",
              let host = url.host?.lowercased(),
              host == "jamfcloud.com" || host.hasSuffix(".jamfcloud.com") else { return nil }
        return url
    }
}

// MARK: - Restricted Software

struct RestrictedSoftware: Identifiable, Sendable {
    let id: String
    let name: String
    let processName: String?
    let matchExact: Bool?
    let killProcess: Bool?
    let deleteExecutable: Bool?
    let displayMessage: String?

    /// Memberwise init used by the enrichment path to preserve the thin item's
    /// id and name while merging detail fields from the Classic API "general" sub-object.
    init(id: String, name: String,
         processName: String?, matchExact: Bool?,
         killProcess: Bool?, deleteExecutable: Bool?, displayMessage: String?) {
        self.id = id; self.name = name
        self.processName = processName; self.matchExact = matchExact
        self.killProcess = killProcess; self.deleteExecutable = deleteExecutable
        self.displayMessage = displayMessage
    }
}

extension RestrictedSoftware: Decodable {
    // Top-level keys (id, name, and the Classic API "general" wrapper)
    private enum TopKeys: String, CodingKey {
        case id, name, general
    }
    // Fields inside the Classic API "general" sub-object (also tried flat)
    private enum GeneralKeys: String, CodingKey {
        case processName, process_name, process
        case matchExact, match_exact, exactMatch, exact_match, match_exact_process_name
        case killProcess, kill_process
        case deleteExecutable, delete_executable
        case displayMessage, display_message, message
    }

    init(from decoder: Decoder) throws {
        let top = try decoder.container(keyedBy: TopKeys.self)
        if let s = try? top.decode(String.self, forKey: .id) { id = s }
        else if let n = try? top.decode(Int.self, forKey: .id) { id = String(n) }
        else { id = UUID().uuidString }
        name = (try? top.decode(String.self, forKey: .name)) ?? "Unknown"

        // Classic API wraps detail fields in a "general" sub-object; fall back to flat keys
        let g: KeyedDecodingContainer<GeneralKeys>
        if let sub = try? top.nestedContainer(keyedBy: GeneralKeys.self, forKey: .general) {
            g = sub
        } else {
            g = try decoder.container(keyedBy: GeneralKeys.self)
        }

        let rawProcess = (try? g.decode(String.self, forKey: .processName))
            ?? (try? g.decode(String.self, forKey: .process_name))
            ?? (try? g.decode(String.self, forKey: .process))
        processName = rawProcess?.isEmpty == false ? rawProcess : nil

        matchExact = (try? g.decode(Bool.self, forKey: .match_exact_process_name))
            ?? (try? g.decode(Bool.self, forKey: .matchExact))
            ?? (try? g.decode(Bool.self, forKey: .match_exact))
            ?? (try? g.decode(Bool.self, forKey: .exactMatch))
            ?? (try? g.decode(Bool.self, forKey: .exact_match))
        killProcess = (try? g.decode(Bool.self, forKey: .killProcess))
            ?? (try? g.decode(Bool.self, forKey: .kill_process))
        deleteExecutable = (try? g.decode(Bool.self, forKey: .deleteExecutable))
            ?? (try? g.decode(Bool.self, forKey: .delete_executable))
        let rawMsg = (try? g.decode(String.self, forKey: .displayMessage))
            ?? (try? g.decode(String.self, forKey: .display_message))
            ?? (try? g.decode(String.self, forKey: .message))
        displayMessage = rawMsg?.isEmpty == false ? rawMsg : nil
    }
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
