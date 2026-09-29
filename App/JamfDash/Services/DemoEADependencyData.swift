import Foundation

/// Demo data for the Extension Attributes dependency map. The group names match the scopes
/// in the demo policies and profiles, so the map shows nested groups, a disabled attribute
/// that's still used, a pop-up value that isn't a menu choice, exclusions and a payload variable.
enum DemoEADependencyData {

    static func json(for command: CLICommand) -> String? {
        switch command {
        case .computerExtensionAttributes:           return encode(computerAttributes)
        case .mobileDeviceExtensionAttributes:       return encode(mobileAttributes)
        case .classicComputerGroups:                 return encode(computerGroups.map(\.listRow))
        case .classicComputerGroupDetail(let id):    return computerGroups.first { $0.id == id }.map { encode($0.detail) }
        case .advancedComputerSearches:              return encode(computerSearches.map(\.listRow))
        case .advancedComputerSearchDetail(let id):  return computerSearches.first { $0.id == id }.map { encode($0.detail) }
        case .classicMobileDeviceGroups:             return encode(mobileGroups.map(\.listRow))
        case .classicMobileDeviceGroupDetail(let id): return mobileGroups.first { $0.id == id }.map { encode($0.detail) }
        case .advancedMobileDeviceSearches:          return encode(mobileSearches.map(\.listRow))
        case .advancedMobileDeviceSearchDetail(let id): return mobileSearches.first { $0.id == id }.map { encode($0.detail) }
        case .mobileConfigProfiles:                  return encode(mobileProfiles.map { ["id": $0.id, "name": $0.name] })
        case .mobileConfigProfileDetail(let id):     return mobileProfiles.first { $0.id == id }.map { encode($0.detail) }
        default:                                     return nil
        }
    }

    // MARK: - Attributes

    private static var computerAttributes: [[String: Any]] { [
        attribute("1", "Last Reboot", "DATE", "SCRIPT", script: "#!/bin/zsh\necho \"<result>$(date -r $(sysctl -n kern.boottime | awk '{print $4}' | tr -d ,) '+%Y-%m-%d %H:%M:%S')</result>\""),
        attribute("2", "Battery Cycle Count", "INTEGER", "SCRIPT", script: "#!/bin/zsh\necho \"<result>$(system_profiler SPPowerDataType | awk '/Cycle Count/{print $3}')</result>\""),
        attribute("3", "Encryption Status", "STRING", "SCRIPT", script: "#!/bin/zsh\nfdesetup isactive >/dev/null && echo '<result>FileVault On</result>' || echo '<result>FileVault Off</result>'"),
        attribute("4", "Local Admin Present", "STRING", "SCRIPT", enabled: false,
                  description: "Replaced by Jamf Connect privilege elevation; kept for the audit search.",
                  script: "#!/bin/zsh\ndscl . -read /Groups/admin GroupMembership | wc -w | awk '{print ($1>2)?\"<result>Yes</result>\":\"<result>No</result>\"}'"),
        attribute("5", "SIP Status", "STRING", "SCRIPT", script: "#!/bin/zsh\ncsrutil status | grep -q enabled && echo '<result>Enabled</result>' || echo '<result>Disabled</result>'"),
        attribute("6", "VPN Client Version", "STRING", "SCRIPT", script: "#!/bin/zsh\ndefaults read /Applications/VPN.app/Contents/Info CFBundleShortVersionString 2>/dev/null | sed 's/.*/<result>&<\\/result>/'"),
        attribute("7", "Asset Tag", "STRING", "TEXT"),
        attribute("8", "Purchase Date", "DATE", "TEXT"),
        attribute("9", "Department Code", "STRING", "POPUP", choices: ["ENG", "FIN", "MKT", "HR"],
                  description: "Set by the provisioning team."),
        attribute("10", "Warranty Expiry", "DATE", "TEXT"),
    ] }

    private static var mobileAttributes: [[String: Any]] { [
        attribute("1", "Cart Number", "STRING", "TEXT"),
        attribute("2", "Classroom", "STRING", "POPUP", choices: ["Room 101", "Room 102", "Library"]),
        attribute("3", "Lost Device Flag", "STRING", "POPUP", choices: ["Yes", "No"]),
        attribute("4", "Legacy Tag", "STRING", "TEXT"),
    ] }

    private static func attribute(_ id: String, _ name: String, _ dataType: String, _ inputType: String,
                                  enabled: Bool = true, choices: [String] = [], description: String = "",
                                  script: String? = nil) -> [String: Any] {
        var row: [String: Any] = ["id": id, "name": name, "description": description, "dataType": dataType,
                                  "inputType": inputType, "inventoryDisplayType": "EXTENSION_ATTRIBUTES",
                                  "enabled": enabled, "popupMenuChoices": choices]
        if let script { row["scriptContents"] = script }
        return row
    }

    // MARK: - Groups and searches

    private struct Group {
        let id: String
        let name: String
        var smart = true
        let criteria: [(String, String, String)]

        var listRow: [String: Any] { ["id": Int(id) ?? 0, "name": name, "is_smart": smart] }
        var detail: [String: Any] {
            ["id": Int(id) ?? 0, "name": name, "is_smart": smart,
             "criteria": criteria.enumerated().map { i, c in
                 ["name": c.0, "priority": i, "and_or": "and", "search_type": c.1, "value": c.2,
                  "opening_paren": false, "closing_paren": false] as [String: Any]
             }]
        }
    }

    private struct Search {
        let id: String
        let name: String
        let criteria: [(String, String, String)]
        let columns: [String]

        var listRow: [String: Any] { ["id": Int(id) ?? 0, "name": name] }
        var detail: [String: Any] {
            ["id": Int(id) ?? 0, "name": name,
             "criteria": ["size": criteria.count, "criterion": criteria.enumerated().map { i, c in
                 ["name": c.0, "priority": i, "and_or": "and", "search_type": c.1, "value": c.2] as [String: Any]
             }],
             "display_fields": columns.map { ["name": $0] }]
        }
    }

    private static let computerGroups: [Group] = [
        Group(id: "1", name: "All Managed Macs", criteria: [("Last Check-in", "less than x days ago", "90")]),
        Group(id: "2", name: "All Intel Macs", criteria: [("Architecture Type", "is", "x86_64")]),
        Group(id: "3", name: "All Apple Silicon Macs", criteria: [("Architecture Type", "is", "arm64")]),
        Group(id: "4", name: "macOS 15 - Current", criteria: [("Operating System Version", "like", "15.")]),
        Group(id: "5", name: "Security Baseline Required", criteria: [("Encryption Status", "is not", "FileVault On"),
                                                                     ("SIP Status", "is", "Disabled")]),
        Group(id: "7", name: "FileVault Disabled", criteria: [("Encryption Status", "is", "FileVault Off")]),
        Group(id: "8", name: "SIP Disabled", criteria: [("SIP Status", "is", "Disabled")]),
        Group(id: "11", name: "Stale - Not Checked In 30d", criteria: [("Last Check-in", "more than x days ago", "30"),
                                                                     ("Last Reboot", "more than x days ago", "30")]),
        Group(id: "12", name: "Finance Department", criteria: [("Department Code", "is", "FIN")]),
        Group(id: "13", name: "Engineering Department", criteria: [("Department Code", "is", "ENG")]),
        Group(id: "14", name: "Marketing Department", criteria: [("Department Code", "is", "MKTG")]),
        Group(id: "15", name: "Executives", criteria: [("Computer Group", "member of", "Finance Department"),
                                                      ("Asset Tag", "like", "EXEC")]),
        Group(id: "21", name: "Engineering VPN Users", criteria: [("Computer Group", "member of", "Engineering Department"),
                                                                 ("VPN Client Version", "is not", "")]),
        Group(id: "22", name: "Beta Testers", criteria: [("Asset Tag", "like", "BETA")]),
        Group(id: "30", name: "Loaner Pool", smart: false, criteria: []),
    ]

    private static let computerSearches: [Search] = [
        Search(id: "1", name: "Warranty & Purchase Report",
               criteria: [("Computer Group", "member of", "All Managed Macs")],
               columns: ["Computer Name", "Asset Tag", "Purchase Date", "Warranty Expiry"]),
        Search(id: "2", name: "Local Admins Audit",
               criteria: [("Local Admin Present", "is", "Yes")],
               columns: ["Computer Name", "Local Admin Present", "Department Code"]),
        Search(id: "3", name: "Engineering VPN Inventory",
               criteria: [("Computer Group", "member of", "Engineering VPN Users")],
               columns: ["Computer Name", "VPN Client Version"]),
    ]

    private static let mobileGroups: [Group] = [
        Group(id: "1", name: "Library iPads", criteria: [("Classroom", "is", "Library")]),
        Group(id: "2", name: "Cart A iPads", criteria: [("Cart Number", "is", "A")]),
        Group(id: "3", name: "Lost iPads", criteria: [("Lost Device Flag", "is", "Yes")]),
        Group(id: "4", name: "Library Cart iPads", criteria: [("Mobile Device Group", "member of", "Library iPads"),
                                                             ("Cart Number", "like", "L")]),
        Group(id: "5", name: "iPadOS 17", criteria: [("OS Version", "like", "17.")]),
    ]

    private static let mobileSearches: [Search] = [
        Search(id: "1", name: "Cart Inventory", criteria: [("Cart Number", "is not", "")],
               columns: ["Device Name", "Cart Number", "Classroom"]),
    ]

    // MARK: - Mobile profiles

    private struct MobileProfile {
        let id: String
        let name: String
        let groups: [(Int, String)]
        let excluded: [(Int, String)]
        var payload = "<dict><key>PayloadType</key><string>com.apple.applicationaccess</string></dict>"

        var detail: [String: Any] {
            ["general": ["id": Int(id) ?? 0, "name": name, "payloads": payload],
             "scope": ["all_mobile_devices": false,
                       "mobile_device_groups": groups.map { ["id": $0.0, "name": $0.1] },
                       "exclusions": ["mobile_device_groups": excluded.map { ["id": $0.0, "name": $0.1] }]]]
        }
    }

    private static let mobileProfiles: [MobileProfile] = [
        MobileProfile(id: "1", name: "Library Restrictions", groups: [(1, "Library iPads")], excluded: []),
        MobileProfile(id: "2", name: "Lock Screen Message", groups: [(5, "iPadOS 17")], excluded: [],
                      payload: "<dict><key>PayloadType</key><string>com.apple.shareddeviceconfiguration</string><key>LockScreenFootnote</key><string>Cart $EXTENSIONATTRIBUTE_1 · Return to the library desk</string></dict>"),
        MobileProfile(id: "3", name: "Wi-Fi (Classroom)", groups: [(2, "Cart A iPads"), (4, "Library Cart iPads")],
                      excluded: [(3, "Lost iPads")]),
    ]

    private static func encode(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }
}
