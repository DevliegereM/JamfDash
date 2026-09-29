import Foundation

// MARK: - Classic API parsing

/// Turns jamf-cli's Classic API output into the definitions the dependency graph needs.
///
/// jamf-cli usually returns the object without its root key (`{"general": …}` instead of
/// `{"policy": {"general": …}}`), and Classic lists come as `[…]`, `{"size": n, "item": […]}`
/// or `{"item": {…}}` for a single entry. Every form is accepted.
enum ClassicDefinitionParser {

    // MARK: Lists

    /// Rows of a Classic or Jamf Pro API list: `[…]`, `{"results": […]}` or `{"<plural>": […]}`.
    static func listRows(_ data: Data) -> [[String: Any]] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        if let rows = json as? [[String: Any]] { return rows }
        guard let dict = json as? [String: Any] else { return [] }
        if let rows = dict["results"] as? [[String: Any]] { return rows }
        for value in dict.values {
            if let rows = value as? [[String: Any]] { return rows }
            if let inner = value as? [String: Any] {
                for innerValue in inner.values {
                    if let rows = innerValue as? [[String: Any]] { return rows }
                    if let row = innerValue as? [String: Any], row["id"] != nil { return [row] }
                }
            }
        }
        return []
    }

    /// ID and name of each list row; rows without an ID are skipped.
    static func idsAndNames(_ data: Data) -> [(id: String, name: String, isSmart: Bool?)] {
        listRows(data).compactMap { row in
            guard let id = string(row["id"]), !id.isEmpty else { return nil }
            return (id, string(row["name"]) ?? "", bool(row["is_smart"] ?? row["isSmart"] ?? row["smart"]))
        }
    }

    // MARK: Definitions

    static func group(_ data: Data, fallbackID: String, fallbackName: String) -> GroupDefinition? {
        guard let root = object(data, wrappers: ["computer_group", "mobile_device_group"]) else { return nil }
        let general = root["general"] as? [String: Any] ?? root
        return GroupDefinition(
            id: string(general["id"]) ?? fallbackID,
            name: nonEmpty(string(general["name"])) ?? fallbackName,
            isSmart: bool(general["is_smart"] ?? general["isSmart"]) ?? true,
            criteria: criteria(root["criteria"] ?? general["criteria"])
        )
    }

    static func search(_ data: Data, fallbackID: String, fallbackName: String) -> SearchDefinition? {
        guard let root = object(data, wrappers: ["advanced_computer_search", "advanced_mobile_device_search"]) else { return nil }
        return SearchDefinition(
            id: string(root["id"]) ?? fallbackID,
            name: nonEmpty(string(root["name"])) ?? fallbackName,
            criteria: criteria(root["criteria"]),
            displayFields: items(root["display_fields"] ?? root["displayFields"], singular: "display_field")
                .compactMap { nonEmpty(string($0["name"])) }
        )
    }

    /// A policy, profile, restricted software entry or patch policy. The list's ID and name
    /// are kept: some detail responses leave them out.
    static func scopedObject(_ data: Data, type: DependentObjectType, id: String, name: String) -> ScopedObjectDefinition? {
        let wrappers = ["policy", "os_x_configuration_profile", "configuration_profile",
                        "restricted_software", "patch_policy"]
        guard let root = object(data, wrappers: wrappers) else { return nil }
        let general = root["general"] as? [String: Any] ?? [:]
        let scope = root["scope"] as? [String: Any] ?? [:]
        let exclusions = scope["exclusions"] as? [String: Any] ?? [:]
        let mobile = type.kind == .mobileDevice
        let groupsKey = mobile ? "mobile_device_groups" : "computer_groups"
        let groupKey  = mobile ? "mobile_device_group" : "computer_group"
        let allKey    = mobile ? "all_mobile_devices" : "all_computers"

        let payloads = string(general["payloads"]) ?? string(root["payloads"]) ?? ""
        return ScopedObjectDefinition(
            type: type,
            id: id,
            name: nonEmpty(name) ?? nonEmpty(string(general["name"])) ?? "ID \(id)",
            allDevices: bool(scope[allKey]) ?? false,
            includedGroups: groupRefs(scope[groupsKey], singular: groupKey),
            excludedGroups: groupRefs(exclusions[groupsKey], singular: groupKey),
            payloadAttributeIDs: payloadAttributeIDs(in: payloads)
        )
    }

    /// IDs used as `$EXTENSIONATTRIBUTE_<id>` in a configuration profile payload.
    static func payloadAttributeIDs(in payload: String) -> Set<String> {
        guard payload.contains("EXTENSIONATTRIBUTE_") else { return [] }
        let regex = #/\$EXTENSIONATTRIBUTE_(\d+)/#
        return Set(payload.matches(of: regex).map { String($0.output.1) })
    }

    // MARK: Helpers

    /// The JSON object, unwrapped from its Classic root key when present.
    private static func object(_ data: Data, wrappers: [String]) -> [String: Any]? {
        guard let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        for key in wrappers {
            if let inner = dict[key] as? [String: Any] { return inner }
        }
        return dict
    }

    static func criteria(_ value: Any?) -> [ClassicCriterion] {
        items(value, singular: "criterion").compactMap { row in
            guard let name = nonEmpty(string(row["name"])) else { return nil }
            return ClassicCriterion(
                name: name,
                searchType: string(row["search_type"] ?? row["searchType"]) ?? "is",
                value: string(row["value"]) ?? "",
                andOr: string(row["and_or"] ?? row["andOr"]) ?? "and"
            )
        }
    }

    private static func groupRefs(_ value: Any?, singular: String) -> [ScopeGroupRef] {
        items(value, singular: singular).compactMap { row in
            let name = string(row["name"]) ?? ""
            let id = string(row["id"]) ?? ""
            guard !name.isEmpty || !id.isEmpty else { return nil }
            return ScopeGroupRef(id: id, name: name)
        }
    }

    /// `[…]`, `{"<singular>": […]}` or `{"<singular>": {…}}`; anything else is empty.
    private static func items(_ value: Any?, singular: String) -> [[String: Any]] {
        if let rows = value as? [[String: Any]] { return rows }
        guard let dict = value as? [String: Any], let inner = dict[singular] else { return [] }
        if let rows = inner as? [[String: Any]] { return rows }
        if let row = inner as? [String: Any] { return [row] }
        return []
    }

    static func string(_ value: Any?) -> String? {
        switch value {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }

    private static func bool(_ value: Any?) -> Bool? {
        switch value {
        case let b as Bool: return b
        case let s as String: return ["true", "yes", "1"].contains(s.lowercased())
        default: return nil
        }
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return s
    }
}

// MARK: - Graph

/// Works out, from a scan, which objects depend on each extension attribute.
///
/// Smart groups and advanced searches depend on an attribute when a criterion uses it, or
/// when a criterion is "member of" a group that depends on it (followed through any number
/// of nested groups). Searches also depend on it when they show it as a column. Policies,
/// configuration profiles, restricted software and patch policies depend on it through the
/// groups in their scope, including exclusions; configuration profiles also when their
/// payload inserts the value with `$EXTENSIONATTRIBUTE_<id>`.
struct EADependencyGraph: Sendable {
    let inventory: DependencyInventory
    /// Every attribute's report, keyed by `EADependencyReport.key`.
    let reports: [String: EADependencyReport]

    init(inventory: DependencyInventory) {
        self.inventory = inventory
        var reports: [String: EADependencyReport] = [:]
        for kind in EAKind.allCases {
            for attribute in inventory.attributes(kind) {
                let report = Self.report(for: attribute, kind: kind, in: inventory)
                reports[report.id] = report
            }
        }
        self.reports = reports
    }

    func report(for attribute: ExtensionAttribute, kind: EAKind) -> EADependencyReport? {
        reports[EADependencyReport.key(kind, attribute.id)]
    }

    // MARK: Building

    static func report(for attribute: ExtensionAttribute, kind: EAKind, in inventory: DependencyInventory) -> EADependencyReport {
        let groups = inventory.groups(kind).filter(\.isSmart)
        let usesAttribute: (ClassicCriterion) -> Bool = { namesMatch($0.name, attribute.name) }
        let groupCriterion = kind.groupCriterionName

        // 1. Groups: direct criteria first, then "member of" a dependent group, until nothing
        //    new is found. `chains` holds the path from a direct group to each dependent group.
        var reasons: [String: [DependencyReason]] = [:]          // group ID → reasons
        var chains: [String: [String]] = [:]                      // lowercased group name → chain
        for group in groups {
            let direct = group.criteria.filter(usesAttribute).map(DependencyReason.criterion)
            if !direct.isEmpty {
                reasons[group.id] = direct
                chains[key(group.name)] = [group.name]
            }
        }
        var changed = true
        while changed {
            changed = false
            for group in groups where reasons[group.id] == nil {
                let nested = memberOfReasons(group.criteria, groupCriterion: groupCriterion, chains: chains)
                guard let first = nested.first, case .memberOf(_, _, let chain) = first else { continue }
                reasons[group.id] = nested
                chains[key(group.name)] = chain + [group.name]
                changed = true
            }
        }
        // Now that every chain is known, record all of each group's reasons.
        for group in groups where reasons[group.id] != nil {
            reasons[group.id] = group.criteria.filter(usesAttribute).map(DependencyReason.criterion)
                + memberOfReasons(group.criteria, groupCriterion: groupCriterion, chains: chains)
                    .filter { if case .memberOf(let g, _, _) = $0 { return !namesMatch(g, group.name) } else { return true } }
        }

        var dependencies: [EADependency] = []
        let groupType: DependentObjectType = kind == .computer ? .computerSmartGroup : .mobileSmartGroup
        for group in groups {
            guard let r = reasons[group.id], !r.isEmpty else { continue }
            dependencies.append(EADependency(object: DependentObject(type: groupType, id: group.id, name: group.name), reasons: r))
        }

        // 2. Advanced searches.
        let searchType: DependentObjectType = kind == .computer ? .computerAdvancedSearch : .mobileAdvancedSearch
        for search in inventory.searches(kind) {
            var r = search.criteria.filter(usesAttribute).map(DependencyReason.criterion)
            r += memberOfReasons(search.criteria, groupCriterion: groupCriterion, chains: chains)
            if search.displayFields.contains(where: { namesMatch($0, attribute.name) }) { r.append(.displayField) }
            guard !r.isEmpty else { continue }
            dependencies.append(EADependency(object: DependentObject(type: searchType, id: search.id, name: search.name), reasons: r))
        }

        // 3. Scoped objects.
        let groupNamesByID = Dictionary(inventory.groups(kind).map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        func chain(for ref: ScopeGroupRef) -> [String]? {
            let name = ref.name.isEmpty ? (groupNamesByID[ref.id] ?? "") : ref.name
            return chains[key(name)] ?? groupNamesByID[ref.id].flatMap { chains[key($0)] }
        }
        for object in inventory.scopedObjects where object.type.kind == kind {
            var r: [DependencyReason] = []
            if object.type == .macConfigProfile || object.type == .mobileConfigProfile,
               object.payloadAttributeIDs.contains(attribute.id) {
                r.append(.payloadVariable("$EXTENSIONATTRIBUTE_\(attribute.id)"))
            }
            for ref in object.includedGroups {
                if let c = chain(for: ref) { r.append(.scope(group: c.last ?? ref.name, excluded: false, chain: c)) }
            }
            for ref in object.excludedGroups {
                if let c = chain(for: ref) { r.append(.scope(group: c.last ?? ref.name, excluded: true, chain: c)) }
            }
            guard !r.isEmpty else { continue }
            dependencies.append(EADependency(object: DependentObject(type: object.type, id: object.id, name: object.name), reasons: r))
        }

        let order = Dictionary(uniqueKeysWithValues: DependentObjectType.allCases.enumerated().map { ($1, $0) })
        dependencies.sort {
            let a = order[$0.object.type] ?? 0, b = order[$1.object.type] ?? 0
            if a != b { return a < b }
            return $0.object.name.localizedStandardCompare($1.object.name) == .orderedAscending
        }

        return EADependencyReport(
            attribute: attribute,
            kind: kind,
            dependencies: dependencies,
            findings: findings(for: attribute, kind: kind, dependencies: dependencies, inventory: inventory)
        )
    }

    /// "member of" / "not member of" criteria naming a group that depends on the attribute.
    private static func memberOfReasons(_ criteria: [ClassicCriterion], groupCriterion: String,
                                        chains: [String: [String]]) -> [DependencyReason] {
        criteria.compactMap { c in
            guard namesMatch(c.name, groupCriterion), let chain = chains[key(c.value)] else { return nil }
            return .memberOf(group: chain.last ?? c.value, negated: c.isNegated, chain: chain)
        }
    }

    // MARK: Findings

    static func findings(for attribute: ExtensionAttribute, kind: EAKind, dependencies: [EADependency],
                         inventory: DependencyInventory) -> [EAFinding] {
        var findings: [EAFinding] = []
        let evaluating = dependencies.filter { $0.object.type.evaluatesCriteria && $0.isDirect }

        if attribute.enabled == false, !dependencies.isEmpty {
            findings.append(EAFinding(
                severity: .warning,
                title: "Disabled, but still in use",
                detail: "Jamf Pro no longer collects this value, so \(count(dependencies.count, "object")) "
                    + "work with the last value each device reported."
            ))
        }

        // Pop-up menu criteria with a value that isn't one of the choices never match
        // ("is") or always match ("is not").
        if !attribute.popupMenuChoices.isEmpty {
            let choices = Set(attribute.popupMenuChoices.map(key))
            for dependency in evaluating {
                for case .criterion(let c) in dependency.reasons
                where ["is", "is not"].contains(c.searchType.lowercased()) && !c.value.isEmpty && !choices.contains(key(c.value)) {
                    findings.append(EAFinding(
                        severity: .warning,
                        title: "Value isn't a menu choice",
                        detail: "\(dependency.object.name) looks for “\(c.value)”, which isn't one of this pop-up menu's choices, "
                            + "so the criterion \(c.searchType.lowercased() == "is" ? "never matches" : "matches every device")."
                    ))
                }
            }
        }

        let exclusionOnly = dependencies.filter(\.isExclusionOnly)
        if !exclusionOnly.isEmpty {
            findings.append(EAFinding(
                severity: .info,
                title: "Used in exclusions",
                detail: "\(count(exclusionOnly.count, "object")) exclude a group based on this value. "
                    + "When a device's value changes, it can start receiving them."
            ))
        }

        if dependencies.isEmpty {
            let script = kind == .computer && (attribute.inputType ?? "").lowercased().contains("script")
            findings.append(EAFinding(
                severity: .info,
                title: "Not used anywhere",
                detail: "No smart group, advanced search, scope or profile payload uses this attribute."
                    + (script ? " Its script still runs on every inventory update." : "")
                    + " It may still be used in reports, webhooks or API integrations."
            ))
        }
        return findings
    }

    // MARK: Matching

    static func namesMatch(_ a: String, _ b: String) -> Bool { key(a) == key(b) }

    private static func key(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func count(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }
}
