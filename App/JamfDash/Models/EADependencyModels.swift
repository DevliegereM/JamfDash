import Foundation

// MARK: - Extension attribute kinds

/// Which device type an extension attribute belongs to.
enum EAKind: String, CaseIterable, Identifiable, Sendable {
    case computer
    case mobileDevice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .computer:     return "Computers"
        case .mobileDevice: return "Mobile Devices"
        }
    }

    var singular: String {
        switch self {
        case .computer:     return "Computer extension attribute"
        case .mobileDevice: return "Mobile device extension attribute"
        }
    }

    /// Criterion name Jamf Pro uses for "member of group" in smart groups and searches.
    var groupCriterionName: String {
        switch self {
        case .computer:     return "Computer Group"
        case .mobileDevice: return "Mobile Device Group"
        }
    }

    /// The object types an extension attribute of this kind can affect.
    var objectTypes: [DependentObjectType] {
        DependentObjectType.allCases.filter { $0.kind == self }
    }
}

// MARK: - Object types

/// The nine Jamf Pro object types that can depend on an extension attribute.
enum DependentObjectType: String, CaseIterable, Identifiable, Sendable {
    case computerSmartGroup
    case computerAdvancedSearch
    case policy
    case macConfigProfile
    case restrictedSoftware
    case patchPolicy
    case mobileSmartGroup
    case mobileAdvancedSearch
    case mobileConfigProfile

    var id: String { rawValue }

    var kind: EAKind {
        switch self {
        case .mobileSmartGroup, .mobileAdvancedSearch, .mobileConfigProfile: return .mobileDevice
        default: return .computer
        }
    }

    var title: String {
        switch self {
        case .computerSmartGroup:     return "Smart Computer Groups"
        case .computerAdvancedSearch: return "Advanced Computer Searches"
        case .policy:                 return "Policies"
        case .macConfigProfile:       return "macOS Configuration Profiles"
        case .restrictedSoftware:     return "Restricted Software"
        case .patchPolicy:            return "Patch Policies"
        case .mobileSmartGroup:       return "Smart Mobile Device Groups"
        case .mobileAdvancedSearch:   return "Advanced Mobile Device Searches"
        case .mobileConfigProfile:    return "Mobile Device Configuration Profiles"
        }
    }

    var singular: String {
        switch self {
        case .computerSmartGroup:     return "Smart computer group"
        case .computerAdvancedSearch: return "Advanced computer search"
        case .policy:                 return "Policy"
        case .macConfigProfile:       return "macOS configuration profile"
        case .restrictedSoftware:     return "Restricted software"
        case .patchPolicy:            return "Patch policy"
        case .mobileSmartGroup:       return "Smart mobile device group"
        case .mobileAdvancedSearch:   return "Advanced mobile device search"
        case .mobileConfigProfile:    return "Mobile device configuration profile"
        }
    }

    var systemImage: String {
        switch self {
        case .computerSmartGroup, .mobileSmartGroup:         return "person.3"
        case .computerAdvancedSearch, .mobileAdvancedSearch: return "magnifyingglass"
        case .policy:                                        return "doc.badge.gearshape"
        case .macConfigProfile, .mobileConfigProfile:        return "gearshape.2"
        case .restrictedSoftware:                            return "nosign"
        case .patchPolicy:                                   return "bandage"
        }
    }

    /// Groups and searches evaluate the value; the rest are affected through their scope.
    var evaluatesCriteria: Bool {
        switch self {
        case .computerSmartGroup, .computerAdvancedSearch, .mobileSmartGroup, .mobileAdvancedSearch: return true
        default: return false
        }
    }
}

// MARK: - Scanned definitions

/// One criterion of a smart group or advanced search.
struct ClassicCriterion: Hashable, Sendable {
    let name: String
    let searchType: String
    let value: String
    let andOr: String

    /// "Department Code is ENG"
    var summary: String {
        let v = value.isEmpty ? "(empty)" : value
        return "\(name) \(searchType) \(v)"
    }

    var isNegated: Bool {
        let t = searchType.lowercased()
        return t.hasPrefix("not ") || t.contains(" not ") || t == "does not have"
    }
}

/// A smart or static group with its criteria.
struct GroupDefinition: Hashable, Sendable {
    let id: String
    let name: String
    let isSmart: Bool
    let criteria: [ClassicCriterion]
}

/// An advanced search with its criteria and the columns it shows.
struct SearchDefinition: Hashable, Sendable {
    let id: String
    let name: String
    let criteria: [ClassicCriterion]
    let displayFields: [String]
}

/// A group named in a scope, by ID and name (Classic scopes carry both).
struct ScopeGroupRef: Hashable, Sendable {
    let id: String
    let name: String
}

/// A policy, profile, restricted software entry or patch policy: what it's scoped to, and
/// for configuration profiles which extension attribute payload variables it uses.
struct ScopedObjectDefinition: Hashable, Sendable {
    let type: DependentObjectType
    let id: String
    let name: String
    let allDevices: Bool
    let includedGroups: [ScopeGroupRef]
    let excludedGroups: [ScopeGroupRef]
    /// IDs from `$EXTENSIONATTRIBUTE_<id>` in the payload.
    let payloadAttributeIDs: Set<String>
}

/// Something that couldn't be read during a scan.
struct DependencyScanFailure: Hashable, Sendable, Identifiable {
    /// Nil for the extension attribute lists themselves.
    let type: DependentObjectType?
    let kind: EAKind
    /// True when the whole list failed, so every object of this type is missing.
    let isListFailure: Bool
    let count: Int
    let message: String

    var id: String { "\(type?.rawValue ?? kind.rawValue)-\(isListFailure)" }

    var summary: String {
        let what = type?.title ?? "\(kind.title) extension attributes"
        if isListFailure { return "\(what) couldn't be read: \(message)" }
        return "\(count) \(what.lowercased()) couldn't be read: \(message)"
    }
}

/// Everything a scan read from Jamf Pro.
struct DependencyInventory: Sendable {
    var computerAttributes: [ExtensionAttribute] = []
    var mobileAttributes: [ExtensionAttribute] = []
    var computerGroups: [GroupDefinition] = []
    var mobileGroups: [GroupDefinition] = []
    var computerSearches: [SearchDefinition] = []
    var mobileSearches: [SearchDefinition] = []
    var scopedObjects: [ScopedObjectDefinition] = []
    var failures: [DependencyScanFailure] = []
    var scannedAt = Date()

    /// Number of objects read, for the scan summary.
    var objectCount: Int {
        computerGroups.count + mobileGroups.count + computerSearches.count + mobileSearches.count + scopedObjects.count
    }

    func attributes(_ kind: EAKind) -> [ExtensionAttribute] {
        kind == .computer ? computerAttributes : mobileAttributes
    }

    func groups(_ kind: EAKind) -> [GroupDefinition] {
        kind == .computer ? computerGroups : mobileGroups
    }

    func searches(_ kind: EAKind) -> [SearchDefinition] {
        kind == .computer ? computerSearches : mobileSearches
    }
}

// MARK: - Results

/// A Jamf Pro object that depends on an extension attribute.
struct DependentObject: Hashable, Sendable {
    let type: DependentObjectType
    let id: String
    let name: String
}

/// Why an object depends on an extension attribute.
enum DependencyReason: Hashable, Sendable {
    /// A criterion uses the attribute's value.
    case criterion(ClassicCriterion)
    /// An advanced search shows the attribute as a column.
    case displayField
    /// A criterion is "member of" a group that depends on the attribute. `chain` runs from
    /// the group that uses the attribute directly to `group`.
    case memberOf(group: String, negated: Bool, chain: [String])
    /// Scoped to (or excluded from) a group that depends on the attribute.
    case scope(group: String, excluded: Bool, chain: [String])
    /// A configuration profile payload inserts the value with `$EXTENSIONATTRIBUTE_<id>`.
    case payloadVariable(String)

    /// Uses the attribute itself, not through a group.
    var isDirect: Bool {
        switch self {
        case .criterion, .displayField, .payloadVariable: return true
        case .memberOf, .scope: return false
        }
    }

    var summary: String {
        switch self {
        case .criterion(let c):
            return "Criterion: \(c.summary)"
        case .displayField:
            return "Shows the value as a column"
        case .memberOf(let group, let negated, let chain):
            return "\(negated ? "Not member of" : "Member of") \(group)\(Self.via(chain, ending: group))"
        case .scope(let group, let excluded, let chain):
            return "\(excluded ? "Excludes" : "Scoped to") \(group)\(Self.via(chain, ending: group))"
        case .payloadVariable(let variable):
            return "Inserts the value into its payload with \(variable)"
        }
    }

    /// " (via A → B)" for the groups before `ending` in the chain.
    private static func via(_ chain: [String], ending: String) -> String {
        let before = chain.last == ending ? Array(chain.dropLast()) : chain
        return before.isEmpty ? "" : " (via \(before.joined(separator: " → ")))"
    }
}

struct EADependency: Identifiable, Hashable, Sendable {
    let object: DependentObject
    let reasons: [DependencyReason]

    var id: String { "\(object.type.rawValue)-\(object.id)" }
    var isDirect: Bool { reasons.contains(where: \.isDirect) }
    /// Only excluded through a dependent group: devices can start or stop getting it when
    /// the value changes, but in the opposite direction.
    var isExclusionOnly: Bool {
        reasons.allSatisfy { if case .scope(_, true, _) = $0 { return true } else { return false } }
    }
}

/// Something worth a look about one extension attribute.
struct EAFinding: Identifiable, Hashable, Sendable {
    enum Severity: Int, Sendable, Comparable {
        case info, warning
        static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
    }

    let severity: Severity
    let title: String
    let detail: String

    var id: String { title + detail }
}

/// Everything known about how one extension attribute is used.
struct EADependencyReport: Identifiable, Sendable {
    let attribute: ExtensionAttribute
    let kind: EAKind
    let dependencies: [EADependency]
    let findings: [EAFinding]

    var id: String { EADependencyReport.key(kind, attribute.id) }

    static func key(_ kind: EAKind, _ id: String) -> String { "\(kind.rawValue)-\(id)" }

    var isUnused: Bool { dependencies.isEmpty }
    var directCount: Int { dependencies.filter(\.isDirect).count }

    func dependencies(of type: DependentObjectType) -> [EADependency] {
        dependencies.filter { $0.object.type == type }
    }

    var hasWarnings: Bool { findings.contains { $0.severity == .warning } }
}
