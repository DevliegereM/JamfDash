import Foundation

/// Demo data for the Enrollment section: a handful of recently enrolled Macs with dates
/// relative to now, so "recent" stays recent. One Mac has a failed Wi-Fi profile and a
/// stuck app install, one has a waiting command, one has a failed policy.
enum DemoEnrollmentData {

    static func json(for command: CLICommand, now: Date = Date()) -> String? {
        switch command {
        case .recentEnrollments:
            return encode(["totalCount": macs.count, "results": macs.map { $0.inventoryRow(now: now, detailed: false) }])
        case .enrollmentInventory(let serial):
            guard let mac = mac(serial: serial) else { return encode(["totalCount": 0, "results": []]) }
            return encode(["totalCount": 1, "results": [mac.inventoryRow(now: now, detailed: true)]])
        case .mdmCommandsForDevice(let managementId):
            guard let mac = macs.first(where: { $0.managementId == managementId }) else { return encode(["totalCount": 0, "results": []]) }
            return encode(["totalCount": mac.apiCommands.count, "results": mac.apiCommands.map { $0.apiRow(mac: mac, now: now) }])
        case .computerHistory(let serial, let subset):
            guard let mac = mac(serial: serial) else { return encode(["computer_history": [:]]) }
            switch subset {
            case .commands:   return encode(["computer_history": ["commands": mac.historyCommands(now: now)]])
            case .policyLogs: return encode(["computer_history": ["policy_logs": mac.policyLogs(now: now)]])
            }
        case .computerPrestageDetail(let id):
            return encode(prestage(id: id))
        case .logFlushingSettings:
            return encode(["hourOfDay": 2, "retentionPolicies": [
                ["displayName": "Computer Management History", "retentionPeriod": 3, "retentionPeriodUnit": "MONTH"],
                ["displayName": "Policy Logs", "retentionPeriod": 6, "retentionPeriodUnit": "MONTH"],
            ]])
        default:
            return nil
        }
    }

    // MARK: - Macs

    fileprivate struct Command {
        let offset: TimeInterval           // after enrollment; negative = before now instead (see `fromNow`)
        let type: String                   // API spelling, e.g. INSTALL_PROFILE
        let state: String                  // ACKNOWLEDGED, PENDING, ERROR
        var profileID: Int? = nil
        var error: String? = nil
        var fromNow = false
        var historyOnly = false

        func date(_ mac: DemoMac, now: Date) -> Date {
            fromNow ? now.addingTimeInterval(-offset) : mac.enrolledAt(now).addingTimeInterval(offset)
        }

        func apiRow(mac: DemoMac, now: Date) -> [String: Any] {
            let sent = date(mac, now: now)
            var row: [String: Any] = [
                "uuid": "demo-\(mac.serial)-\(Int(offset))-\(type)",
                "commandType": type, "commandState": state,
                "dateSent": iso(sent),
                "client": ["managementId": mac.managementId, "clientType": "COMPUTER"],
            ]
            if state == "ACKNOWLEDGED" { row["dateCompleted"] = iso(sent.addingTimeInterval(4)) }
            if let id = profileID { row["profileIdentifier"] = "demo-profile-\(id)"; row["profileId"] = id }
            if let error { row["errorMessage"] = error }
            return row
        }
    }

    fileprivate struct PolicyRun {
        let offset: TimeInterval
        let id: Int
        let name: String
        var status = "Completed"
    }

    fileprivate struct DemoMac {
        let id: String
        let name: String
        let serial: String
        let managementId: String
        let enrolledDaysAgo: Double
        let method: String
        let methodID: String?
        let ade: Bool
        let lastContactAgo: TimeInterval
        let groups: [String]
        let department: String
        let commands: [Command]
        let policies: [PolicyRun]

        func enrolledAt(_ now: Date) -> Date { now.addingTimeInterval(-enrolledDaysAgo * 86_400) }

        var apiCommands: [Command] { commands.filter { !$0.historyOnly } }

        func inventoryRow(now: Date, detailed: Bool) -> [String: Any] {
            let enrolled = enrolledAt(now)
            var general: [String: Any] = [
                "name": name,
                "lastEnrolledDate": iso(enrolled),
                "initialEntryDate": iso(enrolled),
                "lastContactTime": iso(now.addingTimeInterval(-lastContactAgo)),
                "managementId": managementId,
                "supervised": ade,
                "userApprovedMdm": true,
                "enrolledViaAutomatedDeviceEnrollment": ade,
                "enrollmentMethod": ["id": methodID ?? "", "objectName": method,
                                     "objectType": methodID == nil ? "User-initiated" : "Computer PreStage"],
            ]
            if !detailed { general["remoteManagement"] = ["managed": true] }
            var row: [String: Any] = ["id": id, "general": general, "hardware": ["serialNumber": serial]]
            if detailed {
                row["location"] = ["departmentName": department, "buildingName": "HQ"]
                row["groupMemberships"] = groups.enumerated().map { ["groupId": "\($0.offset + 1)", "groupName": $0.element, "smartGroup": true] }
                row["configurationProfiles"] = installedProfiles(now: now)
            }
            return row
        }

        func installedProfiles(now: Date) -> [[String: Any]] {
            var out: [[String: Any]] = [["displayName": "MDM Profile", "profileIdentifier": "com.jamfsoftware.tcc.management",
                                         "lastInstalled": iso(enrolledAt(now))]]
            for c in commands where c.type == "INSTALL_PROFILE" && c.state == "ACKNOWLEDGED" {
                guard let id = c.profileID else { continue }
                out.append(["id": "\(id)", "displayName": DemoEnrollmentData.profileNames[id] ?? "Profile \(id)",
                            "profileIdentifier": "demo-profile-\(id)",
                            "lastInstalled": iso(c.date(self, now: now).addingTimeInterval(4)), "username": ""])
            }
            return out
        }

        func historyCommands(now: Date) -> [String: Any] {
            func classicName(_ type: String) -> String {
                type.split(separator: "_").map { $0.lowercased().capitalized }.joined()
            }
            var completed: [[String: Any]] = [], pending: [[String: Any]] = [], failed: [[String: Any]] = []
            for c in commands {
                let d = c.date(self, now: now)
                let ms = Int(d.timeIntervalSince1970 * 1000)
                switch c.state {
                case "ACKNOWLEDGED":
                    completed.append(["name": classicName(c.type), "completed_epoch": ms + 4000, "issued_epoch": ms])
                case "PENDING":
                    pending.append(["name": classicName(c.type), "status": "Pending", "issued_epoch": ms,
                                    "last_push_epoch": Int(now.addingTimeInterval(-600).timeIntervalSince1970 * 1000)])
                default:
                    failed.append(["name": classicName(c.type), "status": c.error ?? "Error", "issued_epoch": ms,
                                   "failed_epoch": ms + 5000])
                }
            }
            return ["completed": completed, "pending": pending, "failed": failed]
        }

        func policyLogs(now: Date) -> [[String: Any]] {
            policies.map { p in
                ["policy_id": p.id, "policy_name": p.name, "username": "",
                 "date_completed_epoch": Int(enrolledAt(now).addingTimeInterval(p.offset).timeIntervalSince1970 * 1000),
                 "status": p.status]
            }
        }
    }

    fileprivate static let profileNames: [Int: String] = [
        1: "Security Baseline", 2: "FileVault Enforcement", 3: "Firewall Configuration", 4: "Energy Saver",
        5: "Wi-Fi (Corporate)", 6: "VPN Settings", 7: "Login Window", 8: "System Preferences Restrictions",
        9: "Password Policy", 10: "Certificates - Internal CA", 11: "Software Update Deferrals",
        12: "Privacy Preferences (PPPC)",
    ]

    /// Profiles every demo Mac gets (scoped to All Computers in the demo profile details).
    private static func standardProfiles(start: TimeInterval, failing: Int? = nil) -> [Command] {
        [2, 1, 3, 5, 7, 9, 12].enumerated().map { i, id in
            id == failing
                ? Command(offset: start + Double(i) * 3, type: "INSTALL_PROFILE", state: "ERROR", profileID: id,
                          error: "The certificate payload couldn't be installed (MDMErrorDomain 12021).")
                : Command(offset: start + Double(i) * 3, type: "INSTALL_PROFILE", state: "ACKNOWLEDGED", profileID: id)
        }
    }

    private static func setup(prestagePackage: Bool) -> [Command] {
        var out = [Command(offset: 37, type: "INSTALL_PROFILE", state: "ACKNOWLEDGED", profileID: 10)]
        if prestagePackage { out.append(Command(offset: 62, type: "INSTALL_ENTERPRISE_APPLICATION", state: "ACKNOWLEDGED", historyOnly: true)) }
        out.append(Command(offset: 199, type: "DEVICE_CONFIGURED", state: "ACKNOWLEDGED", historyOnly: true))
        out.append(Command(offset: 120, type: "DECLARATIVE_MANAGEMENT", state: "ACKNOWLEDGED"))
        out.append(Command(offset: 900, type: "DEVICE_INFORMATION", state: "ACKNOWLEDGED", historyOnly: true))
        return out
    }

    private static let enrollmentPolicies: [PolicyRun] = [
        PolicyRun(offset: 359, id: 7, name: "Configure Login Window"),
        PolicyRun(offset: 397, id: 8, name: "Set Energy Saver Settings"),
        PolicyRun(offset: 420, id: 11, name: "Install Rosetta 2"),
        PolicyRun(offset: 470, id: 17, name: "Collect Inventory"),
    ]

    fileprivate static let macs: [DemoMac] = [
        DemoMac(id: "1", name: "Alice's MacBook Pro", serial: "C02XA001DEMO",
                managementId: "aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb", enrolledDaysAgo: 2.1,
                method: "MacBook Pro - Standard", methodID: "1", ade: true, lastContactAgo: 600,
                groups: ["All Managed Macs", "Engineering Department"], department: "Engineering",
                commands: setup(prestagePackage: true) + standardProfiles(start: 239, failing: 5) + [
                    Command(offset: 1500, type: "INSTALL_PROFILE", state: "ACKNOWLEDGED", profileID: 4),
                    Command(offset: 1504, type: "INSTALL_PROFILE", state: "ACKNOWLEDGED", profileID: 8),
                    Command(offset: 447, type: "INSTALL_APPLICATION", state: "PENDING"),
                ],
                policies: enrollmentPolicies + [PolicyRun(offset: 530, id: 14, name: "Configure Dock")]),
        DemoMac(id: "2", name: "Bob's MacBook Air", serial: "C02XA002DEMO",
                managementId: "bbbbbbbb-2222-3333-4444-cccccccccccc", enrolledDaysAgo: 3.2,
                method: "MacBook Air - Education", methodID: "2", ade: true, lastContactAgo: 1800,
                groups: ["All Managed Macs"], department: "Sales",
                commands: setup(prestagePackage: false) + standardProfiles(start: 210) + [
                    Command(offset: 1400, type: "INSTALL_PROFILE", state: "ACKNOWLEDGED", profileID: 4),
                    Command(offset: 1403, type: "INSTALL_PROFILE", state: "ACKNOWLEDGED", profileID: 8),
                ],
                policies: enrollmentPolicies),
        DemoMac(id: "21", name: "Lab-Mini-07", serial: "C02XLAB07DEMO",
                managementId: "eeeeeeee-5555-6666-7777-ffffffffffff", enrolledDaysAgo: 4.4,
                method: "User-initiated - no invitation", methodID: nil, ade: false, lastContactAgo: 3 * 3600,
                groups: ["All Managed Macs", "Lab Macs"], department: "IT",
                commands: [Command(offset: 120, type: "DECLARATIVE_MANAGEMENT", state: "ACKNOWLEDGED")]
                    + standardProfiles(start: 60) + [
                    Command(offset: 2 * 3600, type: "INSTALL_PROFILE", state: "PENDING", profileID: 4, fromNow: true),
                ],
                policies: enrollmentPolicies),
        DemoMac(id: "22", name: "Design-Studio-12", serial: "C02XDS12DEMO",
                managementId: "ffffffff-6666-7777-8888-000000000000", enrolledDaysAgo: 5.3,
                method: "iMac - Creative", methodID: "4", ade: true, lastContactAgo: 900,
                groups: ["All Managed Macs"], department: "Design",
                commands: setup(prestagePackage: true) + standardProfiles(start: 230) + [
                    Command(offset: 1600, type: "INSTALL_PROFILE", state: "ACKNOWLEDGED", profileID: 4),
                    Command(offset: 1603, type: "INSTALL_PROFILE", state: "ACKNOWLEDGED", profileID: 8),
                ],
                policies: enrollmentPolicies),
        DemoMac(id: "23", name: "Reception-iMac", serial: "C02XREC1DEMO",
                managementId: "12345678-7777-8888-9999-aaaaaaaaaaaa", enrolledDaysAgo: 6.2,
                method: "iMac - Creative", methodID: "4", ade: true, lastContactAgo: 1200,
                groups: ["All Managed Macs"], department: "Facilities",
                commands: setup(prestagePackage: true) + standardProfiles(start: 225) + [
                    Command(offset: 1550, type: "INSTALL_PROFILE", state: "ACKNOWLEDGED", profileID: 4),
                    Command(offset: 1553, type: "INSTALL_PROFILE", state: "ACKNOWLEDGED", profileID: 8),
                ],
                policies: enrollmentPolicies + [PolicyRun(offset: 610, id: 9, name: "Install Printer Drivers", status: "Failed")]),
        DemoMac(id: "8", name: "Henry's Mac Studio", serial: "C02XA008DEMO",
                managementId: "dddddddd-4444-5555-6666-eeeeeeeeeeee", enrolledDaysAgo: 45,
                method: "MacBook Pro - Standard", methodID: "1", ade: true, lastContactAgo: 2400,
                groups: ["All Managed Macs"], department: "Engineering",
                commands: setup(prestagePackage: true) + standardProfiles(start: 240),
                policies: enrollmentPolicies),
    ]

    private static func mac(serial: String) -> DemoMac? {
        macs.first { $0.serial.caseInsensitiveCompare(serial) == .orderedSame }
    }

    // MARK: - PreStages

    private static func prestage(id: String) -> [String: Any] {
        let names = ["1": "MacBook Pro - Standard", "2": "MacBook Air - Education", "3": "Mac mini - Lab", "4": "iMac - Creative"]
        var skip: [String: Bool] = [:]
        for pane in ["Biometric", "TermsOfAddress", "FileVault", "iCloudDiagnostics", "Diagnostics", "Accessibility",
                     "AppleID", "ScreenTime", "Siri", "DisplayTone", "Restore", "Appearance", "Privacy", "Payment",
                     "Registration", "TOS", "iCloudStorage", "Location", "Intelligence", "Wallpaper"] {
            skip[pane] = !["Location", "Accessibility", "TermsOfAddress"].contains(pane)
        }
        return [
            "id": id, "displayName": names[id] ?? "PreStage \(id)",
            "isMandatory": true, "isMdmRemovable": id == "3", "autoAdvanceSetup": false,
            "installProfilesDuringSetup": true, "enableRecoveryLock": id != "3",
            "skipSetupItems": skip,
            "prestageInstalledProfileIds": id == "3" ? [] : ["10"],
            "customPackageIds": ["1": ["1"], "4": ["2"]][id] ?? [],
            "enrollmentCustomizationId": id == "1" ? "1" : "0",
            "deviceEnrollmentProgramInstanceId": id == "3" ? "" : "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
            "accountSettings": ["userAccountType": "STANDARD"],
        ]
    }

    // MARK: - Helpers

    private static func encode(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

private func iso(_ date: Date) -> String {
    date.formatted(Date.ISO8601FormatStyle())
}
