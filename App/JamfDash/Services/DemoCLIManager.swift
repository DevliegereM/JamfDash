import Foundation

/// A mock implementation of CLIRunning that returns realistic-looking demo data
/// without requiring a real Jamf instance or a jamf-cli binary.
struct DemoCLIManager: SimulatedCLI, Sendable {

    func run(_ command: CLICommand) async throws -> Data {
        // Brief simulated latency so loading states are visible
        try await Task.sleep(nanoseconds: 350_000_000)
        let json = try demoJSON(for: command)
        guard let data = json.data(using: .utf8) else {
            throw CLIError.decodingFailed("Failed to encode demo payload")
        }
        return data
    }

    func run(_ command: CLICommand, outputFormat: ReportOutputFormat) async throws -> Data {
        try await Task.sleep(nanoseconds: 350_000_000)
        if outputFormat == .json {
            let json = try demoJSON(for: command)
            guard let data = json.data(using: .utf8) else {
                throw CLIError.decodingFailed("Failed to encode demo payload")
            }
            return data
        }
        let text = demoRawText(for: command, format: outputFormat)
        guard let data = text.data(using: .utf8) else {
            throw CLIError.decodingFailed("Failed to encode demo payload")
        }
        return data
    }

    // MARK: - Route

    private func demoJSON(for command: CLICommand) throws -> String {
        if let enrollment = DemoEnrollmentData.json(for: command) { return enrollment }
        switch command {
        // Jamf Pro
        case .overview:              return proOverviewJSON
        case .securityReport:        return securityReportJSON
        case .policies:              return policiesJSON
        case .smartComputerGroups:   return smartGroupsJSON
        case .categories:            return categoriesJSON
        case .scripts:               return scriptsJSON
        case .packages:              return packagesJSON
        case .configProfiles:        return configProfilesJSON
        case .policyDetail(let id):        return demoPolicyDetailJSON(id: id)
        case .configProfileDetail(let id): return demoConfigProfileDetailJSON(id: id)
        case .computers:             return computersJSON
        case .computerDetail:        return computerDetailJSON
        case .ddmStatusItems(let managementId):
            return ddmStatusItemsJSON(for: managementId)
        case .ddmComputers:          return ddmComputersJSON
        case .smartGroupDetail:      return smartGroupDetailJSON
        case .mobileDeviceList:      return mobileDevicesJSON
        case .computerExtensionAttributes: return extensionAttributesJSON
        case .patchTitles:           return patchTitlesJSON
        case .patchPolicies:         return patchPoliciesJSON
        case .depTokens:             return depTokensJSON
        case .computerPrestages:     return computerPrestagesJSON
        case .mobileDevicePrestages: return mobileDevicePrestagesJSON
        // Jamf Protect
        case .protectOverview:       return protectOverviewJSON
        case .protectEvents:         return protectEventsJSON
        case .protectComputers:          return protectComputersJSON
        case .protectComputerDetail:     return protectComputerDetailJSON
        case .protectPlans:          return protectPlansJSON
        case .protectAlerts:         return protectAlertsJSON
        case .protectInsights:       return protectAnalyticSetsJSON
        case .protectAuditLogs:          return protectAuditLogsJSON
        case .protectExceptionSets:      return protectExceptionSetsJSON
        case .protectExceptionSetDetail: return protectExceptionSetDetailJSON
        case .protectAnalyticSets:   return protectAnalyticSetsJSON
        case .protectRemovableStorage:    return protectRemovableStorageJSON
        case .protectUnifiedLogging:      return protectUnifiedLoggingJSON
        case .protectActionConfigs:       return protectActionConfigsJSON
        case .protectTelemetryConfigs:    return protectTelemetryConfigsJSON
        case .protectCustomPreventLists:  return protectCustomPreventListsJSON
        case .protectRoles:               return protectRolesJSON
        case .protectUsers:               return protectUsersJSON
        case .protectGroups:              return protectGroupsJSON
        case .protectAPIClients:              return protectAPIClientsJSON
        case .protectUnifiedLoggingDetail:    return protectULFDetailJSON
        case .protectAnalyticDetail:          return protectAnalyticDetailJSON
        case .patchTitleDetail:               return patchTitleDetailJSON
        case .patchPolicyDetail:              return patchPolicyDetailJSON
        case .restrictedSoftware:             return restrictedSoftwareListJSON
        case .restrictedSoftwareDetail:       return restrictedSoftwareDetailJSON
        case .patchSoftwareTitleConfigurations: return modernPatchTitlesJSON
        case .appInstallerTitles:             return appInstallerTitlesJSON
        case .appInstallerDeployments:        return appInstallerDeploymentsJSON
        // Jamf School
        case .schoolOverview:        return schoolOverviewJSON
        case .schoolDevices:         return schoolDevicesJSON
        case .schoolDeviceGroups:    return schoolDeviceGroupsJSON
        case .schoolUsers:           return schoolUsersJSON
        case .schoolUserGroups:      return schoolUserGroupsJSON
        case .schoolClasses:         return schoolClassesJSON
        case .schoolApps:            return schoolAppsJSON
        // Reports
        case .reportPatchStatus:     return reportPatchStatusJSON
        case .reportPolicyStatus:    return reportPolicyStatusJSON
        case .reportProfileStatus:   return reportProfileStatusJSON
        case .reportAppStatus:       return reportAppStatusJSON
        case .reportUpdateStatus:    return reportUpdateStatusJSON
        case .reportDeviceCompliance:    return reportDeviceComplianceJSON
        case .reportInventorySummary:    return reportInventorySummaryJSON
        case .reportSoftwareInstalls:    return reportSoftwareInstallsJSON
        case .reportDDMStatus:           return reportDDMStatusJSON
        // macOS 27 readiness
        case .softwareUpdatePlans:       return softwareUpdatePlansJSON
        case .softwareUpdatePlansForComputer(let id): return softwareUpdatePlansJSON(forComputer: id)
        case .softwareUpdateStatuses:    return softwareUpdateStatusesJSON
        case .computersUpdateReadiness:  return computersUpdateReadinessJSON
        case .installedApps:             return installedAppsJSON
        case .deviceIdentity(let serial):
            let clean = CLICommand.sanitizedSerial(serial)
            return #"{"totalCount":1,"results":[{"id":"1","general":{"name":"Demo Mac \#(clean)","lastContactTime":"2026-09-27T08:12:00Z"},"hardware":{"model":"MacBook Pro (14-inch, 2024)","serialNumber":"\#(clean)"}}]}"#
        case .blueprints:                return blueprintsJSON
        case .complianceBenchmarks:      return complianceBenchmarksJSON
        case .buildings:                 return buildingsJSON
        case .departments:               return departmentsJSON
        case .networkSegments:           return networkSegmentsJSON
        case .webhooks:                  return webhooksJSON
        case .schoolProfiles:            return schoolProfilesJSON
        case .schoolDepDevices:          return schoolDepDevicesJSON
        default:
            // Actions are simulated; reads without sample data say so instead of
            // returning a payload the caller can't decode.
            guard command.risk != .read else { throw CLIError.notInDemo }
            return #"{"status":"success","message":"Action simulated in demo mode"}"#
        }
    }

    private func demoRawText(for command: CLICommand, format: ReportOutputFormat) -> String {
        switch format {
        case .csv:
            return "name,status,count,updated\nPatch Status,healthy,45,2025-05-03\nPolicy Deployment,warning,3,2025-05-02"
        case .yaml:
            return "reports:\n- name: Patch Status\n  status: healthy\n  count: 45\n- name: Policy Deployment\n  status: warning\n  count: 3"
        case .table:
            return "NAME                STATUS    COUNT   UPDATED\nPatch Status        Healthy   45      2025-05-03\nPolicy Deployment   Warning   3       2025-05-02"
        case .plain:
            return "Patch Status: 45 devices healthy\nPolicy Deployment: 3 devices with warnings"
        case .json:
            return "{}"
        }
    }
}

// MARK: - Jamf Pro Overview

private let proOverviewJSON = """
[
  {"section":"Health & Alerts","resource":"Health Check","value":"OK","status":"ok"},
  {"section":"Health & Alerts","resource":"Expiring Certificates","value":"0","status":"ok"},
  {"section":"Instance","resource":"Jamf Pro Version","value":"11.14.2"},
  {"section":"Instance","resource":"Database Size","value":"4.2 GB"},
  {"section":"Fleet","resource":"Total Computers","value":"247"},
  {"section":"Fleet","resource":"Managed Computers","value":"231"},
  {"section":"Fleet","resource":"Unmanaged Computers","value":"16"},
  {"section":"Fleet","resource":"Total Mobile Devices","value":"83"},
  {"section":"Fleet","resource":"Managed Mobile Devices","value":"79"},
  {"section":"Configuration","resource":"Policies","value":"64"},
  {"section":"Configuration","resource":"Config Profiles (macOS)","value":"28"},
  {"section":"Configuration","resource":"Smart Computer Groups","value":"42"},
  {"section":"Configuration","resource":"Scripts","value":"31"},
  {"section":"Configuration","resource":"Packages","value":"19"},
  {"section":"Organization","resource":"Departments","value":"8"},
  {"section":"Organization","resource":"Buildings","value":"3"},
  {"section":"Organization","resource":"Categories","value":"12"},
  {"section":"Enrollment & Certificates","resource":"Enrollment Invitations","value":"4"},
  {"section":"Enrollment & Certificates","resource":"Push Certificate Expiry","value":"324 days"},
  {"section":"Features","resource":"Self Service","value":"Enabled"},
  {"section":"Features","resource":"Patch Management","value":"Enabled"},
  {"section":"Security","resource":"Two-Factor Auth","value":"Enabled"}
]
"""

// MARK: - Security Report

private let securityReportJSON = """
[
  {"section":"summary","data":{"total_devices":231,"filevault_encrypted":218,"filevault_encrypted_pct":"94.4%","gatekeeper_enabled":229,"gatekeeper_enabled_pct":"99.1%","sip_enabled":225,"sip_enabled_pct":"97.4%","firewall_enabled":214,"firewall_enabled_pct":"92.6%"}},
  {"section":"os_version","os_version":"15.4","count":142,"pct":"61.5%"},
  {"section":"os_version","os_version":"15.3.2","count":49,"pct":"21.2%"},
  {"section":"os_version","os_version":"15.2","count":22,"pct":"9.5%"},
  {"section":"os_version","os_version":"14.7.4","count":12,"pct":"5.2%"},
  {"section":"os_version","os_version":"13.7.2","count":6,"pct":"2.6%"},
  {"section":"device","name":"Alice's MacBook Pro","serial":"C02XA001DEMO","os_version":"15.4","filevault":"ENCRYPTED","gatekeeper":"ENABLED","sip":"ENABLED","firewall":true},
  {"section":"device","name":"Bob's MacBook Air","serial":"C02XA002DEMO","os_version":"15.4","filevault":"ENCRYPTED","gatekeeper":"ENABLED","sip":"ENABLED","firewall":true},
  {"section":"device","name":"Charlie's MacBook Pro","serial":"C02XA003DEMO","os_version":"15.3.2","filevault":"ENCRYPTED","gatekeeper":"ENABLED","sip":"ENABLED","firewall":false},
  {"section":"device","name":"Diana's MacBook Air","serial":"C02XA004DEMO","os_version":"15.4","filevault":"ENCRYPTED","gatekeeper":"ENABLED","sip":"ENABLED","firewall":true},
  {"section":"device","name":"Evan's Mac mini","serial":"C02XA005DEMO","os_version":"15.3.2","filevault":"NOT ENCRYPTED","gatekeeper":"ENABLED","sip":"ENABLED","firewall":true},
  {"section":"device","name":"Frank's MacBook Pro","serial":"C02XA006DEMO","os_version":"14.7.4","filevault":"ENCRYPTED","gatekeeper":"ENABLED","sip":"DISABLED","firewall":true},
  {"section":"device","name":"Grace's MacBook Air","serial":"C02XA007DEMO","os_version":"15.2","filevault":"ENCRYPTED","gatekeeper":"ENABLED","sip":"ENABLED","firewall":true},
  {"section":"device","name":"Henry's Mac Studio","serial":"C02XA008DEMO","os_version":"15.4","filevault":"ENCRYPTED","gatekeeper":"ENABLED","sip":"ENABLED","firewall":true},
  {"section":"device","name":"Iris's MacBook Pro","serial":"C02XA009DEMO","os_version":"15.4","filevault":"ENCRYPTED","gatekeeper":"DISABLED","sip":"ENABLED","firewall":true},
  {"section":"device","name":"Jake's MacBook Air","serial":"C02XA010DEMO","os_version":"13.7.2","filevault":"ENCRYPTED","gatekeeper":"ENABLED","sip":"ENABLED","firewall":false}
]
"""

// MARK: - Fleet

private let policiesJSON = """
[
  {"id":1,"name":"Install Zoom","category":{"id":1,"name":"Productivity"}},
  {"id":2,"name":"Install Microsoft Office","category":{"id":1,"name":"Productivity"}},
  {"id":3,"name":"Install Slack","category":{"id":1,"name":"Productivity"}},
  {"id":4,"name":"Install Google Chrome","category":{"id":1,"name":"Productivity"}},
  {"id":5,"name":"Install 1Password","category":{"id":2,"name":"Security"}},
  {"id":6,"name":"Enable Firewall","category":{"id":2,"name":"Security"}},
  {"id":7,"name":"Configure Login Window","category":{"id":3,"name":"Configuration"}},
  {"id":8,"name":"Set Energy Saver Settings","category":{"id":3,"name":"Configuration"}},
  {"id":9,"name":"Install Printer Drivers","category":{"id":4,"name":"Printing"}},
  {"id":10,"name":"Map Network Drives","category":{"id":3,"name":"Configuration"}},
  {"id":11,"name":"Install Rosetta 2","category":{"id":5,"name":"System"}},
  {"id":12,"name":"Install Jamf Connect","category":{"id":2,"name":"Security"}},
  {"id":13,"name":"Install Sophos","category":{"id":2,"name":"Security"}},
  {"id":14,"name":"Configure Dock","category":{"id":3,"name":"Configuration"}},
  {"id":15,"name":"Install VPN Client","category":{"id":2,"name":"Security"}},
  {"id":16,"name":"macOS Sequoia Upgrade","category":{"id":5,"name":"System"}},
  {"id":17,"name":"Collect Inventory","category":{"id":5,"name":"System"}},
  {"id":18,"name":"Update Jamf Agent","category":{"id":5,"name":"System"}},
  {"id":19,"name":"Install Developer Tools","category":{"id":6,"name":"Development"}},
  {"id":20,"name":"Configure SSH","category":{"id":6,"name":"Development"}}
]
"""

private let smartGroupsJSON = """
[
  {"id":"1","name":"All Managed Macs"},
  {"id":"2","name":"All Intel Macs"},
  {"id":"3","name":"All Apple Silicon Macs"},
  {"id":"4","name":"macOS 15 - Current"},
  {"id":"5","name":"macOS 14 - Supported"},
  {"id":"6","name":"macOS 13 - Legacy"},
  {"id":"7","name":"FileVault Disabled"},
  {"id":"8","name":"SIP Disabled"},
  {"id":"9","name":"Firewall Disabled"},
  {"id":"10","name":"No 1Password"},
  {"id":"11","name":"Stale - Not Checked In 30d"},
  {"id":"12","name":"Finance Department"},
  {"id":"13","name":"Engineering Department"},
  {"id":"14","name":"Marketing Department"},
  {"id":"15","name":"Executives"}
]
"""

private let categoriesJSON = """
[
  {"id":"1","name":"Productivity"},
  {"id":"2","name":"Security"},
  {"id":"3","name":"Configuration"},
  {"id":"4","name":"Printing"},
  {"id":"5","name":"System"},
  {"id":"6","name":"Development"},
  {"id":"7","name":"Creative"},
  {"id":"8","name":"Finance"},
  {"id":"9","name":"HR"},
  {"id":"10","name":"No Category"},
  {"id":"11","name":"Testing"},
  {"id":"12","name":"Deprecated"}
]
"""

private let scriptsJSON = """
[
  {"id":"1","name":"Configure DNS Servers","category":{"id":1,"name":"Configuration"}},
  {"id":"2","name":"Remove Rosetta","category":{"id":1,"name":"System"}},
  {"id":"3","name":"Flush DNS Cache","category":{"id":1,"name":"System"}},
  {"id":"4","name":"Enable FileVault","category":{"id":1,"name":"Security"}},
  {"id":"5","name":"Rotate FileVault Key","category":{"id":1,"name":"Security"}},
  {"id":"6","name":"Set Desktop Wallpaper","category":{"id":1,"name":"Configuration"}},
  {"id":"7","name":"Check Disk Health","category":{"id":1,"name":"System"}},
  {"id":"8","name":"Configure NTP","category":{"id":1,"name":"Configuration"}},
  {"id":"9","name":"Map Shared Drive","category":{"id":1,"name":"Configuration"}},
  {"id":"10","name":"Remove Old VPN Profiles","category":{"id":1,"name":"Security"}},
  {"id":"11","name":"Enable SSH","category":{"id":1,"name":"Development"}},
  {"id":"12","name":"Collect Hardware Info","category":{"id":1,"name":"System"}}
]
"""

private let packagesJSON = """
[
  {"id":1,"name":"Zoom-5.17.0.pkg"},
  {"id":2,"name":"MicrosoftOffice365-16.87.pkg"},
  {"id":3,"name":"Slack-4.38.125.pkg"},
  {"id":4,"name":"GoogleChrome-124.0.6367.pkg"},
  {"id":5,"name":"1Password-8.10.36.pkg"},
  {"id":6,"name":"JamfConnect-2.38.0.pkg"},
  {"id":7,"name":"Sophos-10.3.9.pkg"},
  {"id":8,"name":"VPN-GlobalProtect-6.3.pkg"},
  {"id":9,"name":"Rosetta2-runtime.pkg"},
  {"id":10,"name":"XcodeCommandLineTools-15.3.pkg"}
]
"""

private let configProfilesJSON = """
[
  {"id":1,"name":"Security Baseline"},
  {"id":2,"name":"FileVault Enforcement"},
  {"id":3,"name":"Firewall Configuration"},
  {"id":4,"name":"Energy Saver"},
  {"id":5,"name":"Wi-Fi (Corporate)"},
  {"id":6,"name":"VPN Settings"},
  {"id":7,"name":"Login Window"},
  {"id":8,"name":"System Preferences Restrictions"},
  {"id":9,"name":"Password Policy"},
  {"id":10,"name":"Certificates - Internal CA"},
  {"id":11,"name":"Software Update Deferrals"},
  {"id":12,"name":"Privacy Preferences (PPPC)"},
  {"id":13,"name":"Jamf Setup Manager"}
]
"""

// MARK: - Devices

private let computersJSON = """
[
  {"id":"1","name":"Alice's MacBook Pro","serialNumber":"C02XA001DEMO","osVersion":"15.4","lastContactTime":"2026-04-18T08:14:22Z","managed":true},
  {"id":"2","name":"Bob's MacBook Air","serialNumber":"C02XA002DEMO","osVersion":"15.4","lastContactTime":"2026-04-18T07:55:10Z","managed":true},
  {"id":"3","name":"Charlie's MacBook Pro","serialNumber":"C02XA003DEMO","osVersion":"15.3.2","lastContactTime":"2026-04-17T16:22:05Z","managed":true},
  {"id":"4","name":"Diana's MacBook Air","serialNumber":"C02XA004DEMO","osVersion":"15.4","lastContactTime":"2026-04-18T09:01:47Z","managed":true},
  {"id":"5","name":"Evan's Mac mini","serialNumber":"C02XA005DEMO","osVersion":"15.3.2","lastContactTime":"2026-04-15T11:30:00Z","managed":true},
  {"id":"6","name":"Frank's MacBook Pro","serialNumber":"C02XA006DEMO","osVersion":"14.7.4","lastContactTime":"2026-03-10T09:00:00Z","managed":true},
  {"id":"7","name":"Grace's MacBook Air","serialNumber":"C02XA007DEMO","osVersion":"15.2","lastContactTime":"2026-04-17T14:45:30Z","managed":true},
  {"id":"8","name":"Henry's Mac Studio","serialNumber":"C02XA008DEMO","osVersion":"15.4","lastContactTime":"2026-04-18T08:30:00Z","managed":true},
  {"id":"9","name":"Iris's MacBook Pro","serialNumber":"C02XA009DEMO","osVersion":"15.4","lastContactTime":"2026-04-18T07:00:15Z","managed":true},
  {"id":"10","name":"Jake's MacBook Air","serialNumber":"C02XA010DEMO","osVersion":"13.7.2","lastContactTime":"2026-02-14T10:00:00Z","managed":true},
  {"id":"11","name":"Karen's MacBook Pro","serialNumber":"C02XA011DEMO","osVersion":"15.4","lastContactTime":"2026-04-18T08:55:00Z","managed":true},
  {"id":"12","name":"Liam's Mac Pro","serialNumber":"C02XA012DEMO","osVersion":"15.4","lastContactTime":"2026-04-17T18:00:00Z","managed":true},
  {"id":"13","name":"Mona's MacBook Air","serialNumber":"C02XA013DEMO","osVersion":"15.3.2","lastContactTime":"2026-04-16T10:20:00Z","managed":true},
  {"id":"14","name":"Nate's MacBook Pro","serialNumber":"C02XA014DEMO","osVersion":"15.4","lastContactTime":"2026-04-18T06:45:00Z","managed":true},
  {"id":"15","name":"Olivia's MacBook Air","serialNumber":"C02XA015DEMO","osVersion":"15.2","lastContactTime":"2026-04-11T09:30:00Z","managed":true},
  {"id":"16","name":"Paul's Mac mini","serialNumber":"C02XA016DEMO","osVersion":"14.7.4","lastContactTime":"2026-04-18T08:10:00Z","managed":true},
  {"id":"17","name":"Quinn's MacBook Pro","serialNumber":"C02XA017DEMO","osVersion":"15.4","lastContactTime":"2026-04-17T17:00:00Z","managed":true},
  {"id":"18","name":"Rachel's MacBook Air","serialNumber":"C02XA018DEMO","osVersion":"15.3.2","lastContactTime":"2026-04-18T09:10:00Z","managed":true},
  {"id":"19","name":"Sam's MacBook Pro","serialNumber":"C02XA019DEMO","osVersion":"15.4","lastContactTime":"2026-04-18T08:00:00Z","managed":true},
  {"id":"20","name":"Tina's Mac Studio","serialNumber":"C02XA020DEMO","osVersion":"15.4","lastContactTime":"2026-04-18T09:05:00Z","managed":true},
  {"id":"21","name":"Uma's MacBook Pro","serialNumber":"C02XA021DEMO","osVersion":"13.7.2","lastContactTime":"2026-01-20T14:00:00Z","managed":false},
  {"id":"22","name":"Conference Room Mac mini","serialNumber":"C02XA022DEMO","osVersion":"15.4","lastContactTime":"2026-04-17T19:00:00Z","managed":true},
  {"id":"23","name":"IT Loaner MBP","serialNumber":"C02XA023DEMO","osVersion":"15.4","lastContactTime":"2026-04-18T08:20:00Z","managed":true}
]
"""

private let computerDetailJSON = """
{
  "id": "1",
  "name": "Alice's MacBook Pro",
  "serialNumber": "C02XA001DEMO",
  "udid": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
  "managed": true,
  "platform": "Mac",
  "general": {
    "name": "Alice's MacBook Pro",
    "lastIpAddress": "192.168.1.42",
    "jamfBinaryVersion": "11.14.2",
    "assetTag": "IT-2024-042",
    "supervised": true,
    "mdmCapable": true,
    "userApprovedMdm": true,
    "enrollmentMethod": "PreStage",
    "declarativeDeviceManagementEnabled": true,
    "managementId": "aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb",
    "lastContactTime": "2026-04-18T08:14:22Z",
    "lastEnrolledDate": "2024-03-15T10:00:00Z",
    "remoteManagement": {"managed": true, "managementUsername": "jamfadmin"}
  },
  "hardware": {
    "make": "Apple",
    "model": "MacBook Pro 14-inch (M3 Pro, 2023)",
    "serialNumber": "C02XA001DEMO",
    "cpuType": "Apple M3 Pro",
    "ramMegabytes": 36864,
    "batteryCapacityPercent": 87,
    "isAppleSilicon": true
  },
  "operatingSystem": {
    "name": "macOS",
    "version": "27.0",
    "build": "27A5320",
    "fileVault2Status": "ENCRYPTED"
  },
  "security": {
    "sipStatus": "ENABLED",
    "gatekeeperStatus": "ENABLED",
    "xprotectVersion": "5271",
    "autoLoginDisabled": true,
    "remoteDesktopEnabled": false,
    "firewallEnabled": true,
    "secureBootLevel": "FULL_SECURITY",
    "bootstrapTokenAllowed": true,
    "bootstrapTokenEscrowedStatus": "ESCROWED"
  },
  "location": {
    "username": "alice.smith",
    "realName": "Alice Smith",
    "email": "alice.smith@acme.example.com",
    "departmentName": "Engineering"
  },
  "diskEncryption": {
    "bootPartitionEncryptionDetails": {
      "partitionName": "Macintosh HD",
      "partitionFileVault2State": "ENCRYPTED",
      "partitionFileVault2Percent": 100
    },
    "individualRecoveryKeyValidityStatus": "VALID"
  },
  "network": {
    "lastIpAddress": "192.168.1.42",
    "networkAdapters": [
      {"displayName": "Wi-Fi", "macAddress": "A1:B2:C3:D4:E5:F6", "ipAddress": "192.168.1.42", "type": "Wireless"}
    ]
  },
  "purchasing": {
    "purchased": true,
    "vendor": "Apple",
    "warrantyDate": "2026-03-15",
    "purchasePrice": "$2,499.00"
  },
  "storage": {
    "bootDriveAvailableSpaceMegabytes": 312000,
    "disks": [
      {"device": "disk0", "model": "Apple SSD", "sizeMegabytes": 524288, "smartStatus": "Verified", "type": "SSD",
       "partitions": [
         {"name": "Macintosh HD", "sizeMegabytes": 524000, "availableMegabytes": 312000, "percentUsed": 40, "fileVault2State": "ENCRYPTED", "fileVault2Percent": 100}
       ]}
    ]
  },
  "groupMemberships": [
    {"groupId": "1", "groupName": "All Managed Macs", "smartGroup": true},
    {"groupId": "3", "groupName": "All Apple Silicon Macs", "smartGroup": true},
    {"groupId": "4", "groupName": "macOS 15 - Current", "smartGroup": true},
    {"groupId": "13", "groupName": "Engineering Department", "smartGroup": true}
  ],
  "localUserAccounts": [
    {"uid": "501", "username": "alice.smith", "fullName": "Alice Smith", "admin": false, "fileVault2Enabled": true},
    {"uid": "502", "username": "jamfadmin", "fullName": "Jamf Admin", "admin": true, "fileVault2Enabled": false}
  ],
  "softwareUpdates": [],
  "configurationProfiles": [
    {"profileId": "1", "displayName": "Security Baseline", "state": "Installed"},
    {"profileId": "2", "displayName": "FileVault Enforcement", "state": "Installed"},
    {"profileId": "3", "displayName": "Firewall Configuration", "state": "Installed"},
    {"profileId": "10", "displayName": "Certificates - Internal CA", "state": "Installed"},
    {"profileId": "11", "displayName": "Software Update Deferrals", "state": "Installed"}
  ]
}
"""

private let smartGroupDetailJSON = """
{
  "name": "All Managed Macs",
  "criteria": [
    {"name": "Operating System", "priority": 0, "andOr": "and", "searchType": "like", "value": "macOS", "openingParen": false, "closingParen": false},
    {"name": "Managed", "priority": 1, "andOr": "and", "searchType": "is", "value": "true", "openingParen": false, "closingParen": false}
  ]
}
"""

private func demoPolicyDetailJSON(id: Int) -> String {
    let cats: [Int: (Int, String)] = [
        1: (1,"Productivity"), 2: (1,"Productivity"), 3: (1,"Productivity"), 4: (1,"Productivity"),
        5: (2,"Security"), 6: (2,"Security"), 12: (2,"Security"), 13: (2,"Security"), 15: (2,"Security"),
        7: (3,"Configuration"), 8: (3,"Configuration"), 10: (3,"Configuration"), 14: (3,"Configuration"),
        9: (4,"Printing"), 11: (5,"System"), 16: (5,"System"), 17: (5,"System"), 18: (5,"System"),
        19: (6,"Development"), 20: (6,"Development")
    ]
    let (catId, catName) = cats[id] ?? (-1, "No category assigned")
    // Enrollment Complete policies for the Enrollment section's flow (Dock only for Engineering).
    let enrollmentTrigger = [7, 8, 11, 14, 17].contains(id)
    let allComputers = [7, 8, 11, 17, 4, 5, 12, 13].contains(id)
    // Custom triggers that the demo Setup Manager profile runs.
    let customTrigger = [4: "EnrollChrome", 5: "Enroll1Password", 11: "EnrollRosetta2", 12: "EnrollJamfConnect", 13: "EnrollSophos"][id] ?? ""
    return """
    {
      "general": {"id": \(id), "name": "Policy \(id)", "enabled": true, "trigger_enrollment_complete": \(enrollmentTrigger), "trigger_other": "\(customTrigger)", "category": {"id": \(catId), "name": "\(catName)"}},
      "scope": {
        "all_computers": \(allComputers),
        "computers": [],
        "computer_groups": [{"id": 1, "name": "All Managed Macs"}, {"id": 13, "name": "Engineering Department"}],
        "departments": [],
        "buildings": [],
        "limitations": {
          "users": [], "user_groups": [], "network_segments": [], "ibeacons": []
        },
        "exclusions": {
          "computers": [], "computer_groups": [{"id": 11, "name": "Stale - Not Checked In 30d"}],
          "departments": [], "buildings": [], "users": [], "user_groups": [], "network_segments": []
        }
      }
    }
    """
}

private func demoConfigProfileDetailJSON(id: Int) -> String {
    let cats: [Int: (Int, String)] = [
        1: (2,"Security"), 2: (2,"Security"), 3: (2,"Security"), 10: (2,"Security"), 12: (2,"Security"),
        4: (3,"Configuration"), 5: (3,"Configuration"), 6: (3,"Configuration"),
        7: (3,"Configuration"), 8: (3,"Configuration"), 9: (3,"Configuration"),
        11: (5,"System")
    ]
    let (catId, catName) = cats[id] ?? (-1, "No category assigned")
    let payloads = demoProfilePayloadsPlist(id: id)
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
    // Scopes for the Enrollment section's flow: most profiles go to All Computers, a few to groups.
    let allComputers = [1, 2, 3, 5, 7, 9, 10, 12, 13].contains(id)
    let groups: String
    switch id {
    case 6:  groups = #"[{"id": 21, "name": "Engineering VPN Users"}]"#
    case 11: groups = #"[{"id": 22, "name": "Beta Testers"}]"#
    default: groups = #"[{"id": 1, "name": "All Managed Macs"}, {"id": 5, "name": "Security Baseline Required"}]"#
    }
    return """
    {
      "general": {"id": \(id), "name": "\(demoProfileName(id: id))", "uuid": "demo-profile-\(id)", "category": {"id": \(catId), "name": "\(catName)"}, "payloads": "\(payloads)"},
      "scope": {
        "all_computers": \(allComputers),
        "computers": [],
        "computer_groups": \(groups),
        "departments": \([6, 11].contains(id) ? "[]" : #"[{"id": 2, "name": "Engineering"}, {"id": 3, "name": "IT"}]"#),
        "buildings": [],
        "limitations": {
          "users": [], "user_groups": [], "network_segments": [], "ibeacons": []
        },
        "exclusions": {
          "computers": [], "computer_groups": [{"id": 11, "name": "Dev Machines - Exception"}],
          "departments": [], "buildings": [], "users": [], "user_groups": [], "network_segments": []
        }
      }
    }
    """
}


// MARK: - Jamf Protect Events

private let protectEventsJSON = """
[
  {"uuid":"evt001","analyticName":"EICAR Test File Detected","hostName":"Frank's MacBook Pro","timestamp":"2026-04-18T07:22:15Z","severity":"High","status":"open"},
  {"uuid":"evt002","analyticName":"Outbound Connection to Threat Intel IP","hostName":"Jake's MacBook Air","timestamp":"2026-04-17T23:05:42Z","severity":"High","status":"open"},
  {"uuid":"evt003","analyticName":"Suspicious Shell Command","hostName":"Charlie's MacBook Pro","timestamp":"2026-04-17T14:33:07Z","severity":"Medium","status":"open"},
  {"uuid":"evt004","analyticName":"LaunchDaemon Added by Non-Admin","hostName":"Evan's Mac mini","timestamp":"2026-04-17T09:11:55Z","severity":"Medium","status":"resolved"},
  {"uuid":"evt005","analyticName":"Root Process Spawned by App","hostName":"Grace's MacBook Air","timestamp":"2026-04-16T16:47:30Z","severity":"Medium","status":"resolved"},
  {"uuid":"evt006","analyticName":"Disk Image Mounted from Web","hostName":"Bob's MacBook Air","timestamp":"2026-04-16T11:02:18Z","severity":"Medium","status":"resolved"},
  {"uuid":"evt007","analyticName":"Login Item Added","hostName":"Diana's MacBook Air","timestamp":"2026-04-15T15:28:44Z","severity":"Low","status":"resolved"},
  {"uuid":"evt008","analyticName":"Clipboard Access by Background App","hostName":"Henry's Mac Studio","timestamp":"2026-04-15T10:55:01Z","severity":"Low","status":"resolved"},
  {"uuid":"evt009","analyticName":"Auto-Login Enabled","hostName":"Iris's MacBook Pro","timestamp":"2026-04-14T08:30:12Z","severity":"Low","status":"resolved"},
  {"uuid":"evt010","analyticName":"Unusual Process Tree","hostName":"Karen's MacBook Pro","timestamp":"2026-04-13T19:44:59Z","severity":"Medium","status":"resolved"},
  {"uuid":"evt011","analyticName":"Unsigned Kernel Extension Loaded","hostName":"Sam's MacBook Pro","timestamp":"2026-04-12T12:00:00Z","severity":"High","status":"resolved"},
  {"uuid":"evt012","analyticName":"SSH Brute Force Attempt","hostName":"Liam's Mac Pro","timestamp":"2026-04-11T03:14:07Z","severity":"High","status":"resolved"}
]
"""

// MARK: - Jamf Protect

private let protectOverviewJSON = """
[
  {"section":"Deployment","resource":"Total Computers","value":"189"},
  {"section":"Deployment","resource":"Enrolled This Month","value":"7"},
  {"section":"Deployment","resource":"Plans Configured","value":"3"},
  {"section":"Threat Summary","resource":"Alerts (Last 30d)","value":"12"},
  {"section":"Threat Summary","resource":"High Severity","value":"2"},
  {"section":"Threat Summary","resource":"Medium Severity","value":"5"},
  {"section":"Threat Summary","resource":"Low Severity","value":"5"},
  {"section":"Compliance","resource":"Analytic Sets","value":"4"},
  {"section":"Compliance","resource":"Exception Sets","value":"2"},
  {"section":"Version","resource":"Protect Agent Version","value":"5.4.1"}
]
"""

private let protectComputersJSON = """
[
  {"uuid":"pc001","hostname":"alice-mbp","serial":"C02XA001DEMO","osString":"Version 15.4 (Build 24E5209a)","plan":"Standard Security","checkin":"2026-04-18T08:14:22Z","connectionStatus":"Connected","fullDiskAccess":"Authorized","modelName":"MacBookPro18,3","version":"8.11.0.3","webProtectionActive":true},
  {"uuid":"pc002","hostname":"bob-mba","serial":"C02XA002DEMO","osString":"Version 15.4 (Build 24E5209a)","plan":"Standard Security","checkin":"2026-04-18T07:55:10Z","connectionStatus":"Disconnected","fullDiskAccess":"Authorized","modelName":"MacBookAir10,1","version":"8.11.0.3","webProtectionActive":true},
  {"uuid":"pc003","hostname":"charlie-mbp","serial":"C02XA003DEMO","osString":"Version 15.3.2 (Build 24D81)","plan":"Developer Security","checkin":"2026-04-17T16:22:05Z","connectionStatus":"Connected","fullDiskAccess":"Authorized","modelName":"MacBookPro18,4","version":"8.11.0.3","webProtectionActive":false},
  {"uuid":"pc004","hostname":"diana-mba","serial":"C02XA004DEMO","osString":"Version 15.4 (Build 24E5209a)","plan":"Standard Security","checkin":"2026-04-18T09:01:47Z","connectionStatus":"Connected","fullDiskAccess":"Unauthorized","modelName":"MacBookAir10,1","version":"8.10.1.0","webProtectionActive":true},
  {"uuid":"pc005","hostname":"evan-mini","serial":"C02XA005DEMO","osString":"Version 15.3.2 (Build 24D81)","plan":"Standard Security","checkin":"2026-04-15T11:30:00Z","connectionStatus":"Disconnected","fullDiskAccess":"Authorized","modelName":"Macmini9,1","version":"8.11.0.3","webProtectionActive":true},
  {"uuid":"pc006","hostname":"frank-mbp","serial":"C02XA006DEMO","osString":"Version 14.7.4 (Build 23H420)","plan":"Legacy Plan","checkin":"2026-03-10T09:00:00Z","connectionStatus":"Disconnected","fullDiskAccess":"Authorized","modelName":"MacBookPro17,1","version":"8.9.0.0","webProtectionActive":false},
  {"uuid":"pc007","hostname":"grace-mba","serial":"C02XA007DEMO","osString":"Version 15.2 (Build 24C101)","plan":"Standard Security","checkin":"2026-04-17T14:45:30Z","connectionStatus":"Connected","fullDiskAccess":"Authorized","modelName":"MacBookAir10,1","version":"8.11.0.3","webProtectionActive":true},
  {"uuid":"pc008","hostname":"henry-studio","serial":"C02XA008DEMO","osString":"Version 15.4 (Build 24E5209a)","plan":"Developer Security","checkin":"2026-04-18T08:30:00Z","connectionStatus":"Connected","fullDiskAccess":"Authorized","modelName":"Mac13,2","version":"8.11.0.3","webProtectionActive":false},
  {"uuid":"pc009","hostname":"iris-mbp","serial":"C02XA009DEMO","osString":"Version 15.4 (Build 24E5209a)","plan":"Standard Security","checkin":"2026-04-18T07:00:15Z","connectionStatus":"Connected","fullDiskAccess":"Authorized","modelName":"MacBookPro18,3","version":"8.11.0.3","webProtectionActive":true},
  {"uuid":"pc010","hostname":"jake-mba","serial":"C02XA010DEMO","osString":"Version 13.7.2 (Build 22G620)","plan":"Legacy Plan","checkin":"2026-02-14T10:00:00Z","connectionStatus":"Disconnected","fullDiskAccess":"Authorized","modelName":"MacBookAir8,2","version":"8.7.0.0","webProtectionActive":false}
]
"""

private let protectComputerDetailJSON = """
{
  "uuid": "pc001",
  "hostName": "Alice's MacBook Pro",
  "serial": "C02XA001DEMO",
  "modelName": "MacBookPro18,3",
  "arch": "arm64",
  "osString": "Version 15.4 (Build 24E5209a)",
  "version": "8.11.0.3",
  "checkin": "2026-04-18T08:14:22Z",
  "connectionStatus": "Connected",
  "fullDiskAccess": "Authorized",
  "lastConnectionIp": "192.168.1.42",
  "signaturesVersion": 21567,
  "webProtectionActive": true,
  "plan": "Standard Security"
}
"""

private let protectPlansJSON = """
[
  {"name":"Standard Security","actionConfig":"Prevent","autoUpdate":true,"logLevel":"Info","telemetry":"Full"},
  {"name":"Developer Security","actionConfig":"Alert","autoUpdate":true,"logLevel":"Debug","telemetry":"Full"},
  {"name":"Legacy Plan","actionConfig":"Alert","autoUpdate":false,"logLevel":"Warning","telemetry":"Minimal"}
]
"""

private let protectAlertsJSON = """
[
  {"name":"EICAR Test File Detected","severity":"High","categories":"Malware","inputType":"UnifiedLog","jamf":true},
  {"name":"Unsigned Kernel Extension Loaded","severity":"High","categories":"Kernel","inputType":"UnifiedLog","jamf":true},
  {"name":"LaunchDaemon Added by Non-Admin","severity":"Medium","categories":"Persistence","inputType":"UnifiedLog","jamf":true},
  {"name":"Suspicious Shell Command","severity":"Medium","categories":"Execution","inputType":"ESF","jamf":true},
  {"name":"Login Item Added","severity":"Low","categories":"Persistence","inputType":"UnifiedLog","jamf":true},
  {"name":"Outbound Connection to Threat Intel IP","severity":"High","categories":"Network","inputType":"NetworkFilter","jamf":true},
  {"name":"Root Process Spawned by App","severity":"Medium","categories":"Privilege Escalation","inputType":"ESF","jamf":true},
  {"name":"Disk Image Mounted from Web","severity":"Medium","categories":"Initial Access","inputType":"UnifiedLog","jamf":true},
  {"name":"SSH Brute Force Attempt","severity":"High","categories":"Network","inputType":"NetworkFilter","jamf":false},
  {"name":"Unusual Process Tree","severity":"Medium","categories":"Execution","inputType":"ESF","jamf":false},
  {"name":"Clipboard Access by Background App","severity":"Low","categories":"Collection","inputType":"ESF","jamf":true},
  {"name":"Auto-Login Enabled","severity":"Low","categories":"Configuration","inputType":"UnifiedLog","jamf":true}
]
"""

private let protectAnalyticSetsJSON = """
[
  {"name":"macOS Threat Defense","description":"Core detection rules for macOS endpoint threats","analyticsCount":24,"managed":true,"plans":"Standard Security, Developer Security","types":"Behavioral, IOC"},
  {"name":"Privilege Escalation","description":"Detects privilege escalation and lateral movement","analyticsCount":8,"managed":true,"plans":"Standard Security","types":"Behavioral"},
  {"name":"Network Threats","description":"Outbound connection monitoring and threat intelligence","analyticsCount":6,"managed":false,"plans":"Standard Security, Developer Security, Legacy Plan","types":"Network"},
  {"name":"Developer Tools Policy","description":"Monitors developer tooling usage across fleet","analyticsCount":4,"managed":false,"plans":"Developer Security","types":"Behavioral, IOC"}
]
"""

private let protectAuditLogsJSON = """
[
  {
    "uuid": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "action": "policy.update",
    "actor": "admin@example.com",
    "timestamp": "2026-05-30T09:14:22Z",
    "resource": "Endpoint Security Policy",
    "details": "Updated threat response actions"
  },
  {
    "uuid": "b2c3d4e5-f6a7-8901-bcde-f01234567891",
    "action": "user.login",
    "actor": "jdoe@example.com",
    "timestamp": "2026-05-30T08:55:10Z",
    "resource": "Jamf Protect Console",
    "details": "Successful login from 192.168.1.42"
  },
  {
    "uuid": "c3d4e5f6-a7b8-9012-cdef-012345678902",
    "action": "plan.assign",
    "actor": "admin@example.com",
    "timestamp": "2026-05-29T17:33:00Z",
    "resource": "macOS Baseline Plan",
    "details": "Assigned to 24 computers"
  },
  {
    "uuid": "d4e5f6a7-b8c9-0123-defa-123456789013",
    "action": "analytic.disable",
    "actor": "security@example.com",
    "timestamp": "2026-05-29T14:12:45Z",
    "resource": "Suspicious Script Execution",
    "details": "Temporarily disabled for maintenance window"
  },
  {
    "uuid": "e5f6a7b8-c9d0-1234-efab-234567890124",
    "action": "exception_set.create",
    "actor": "itops@example.com",
    "timestamp": "2026-05-28T11:05:37Z",
    "resource": "Approved Security Tools",
    "details": "Created new exception set with 3 entries"
  }
]
"""

private let protectExceptionSetsJSON = """
[
  {"uuid":"4722390a-f279-4fbe-9dad-b922e9c92289","name":"Approved Security Tools"},
  {"uuid":"8b3c1d2e-a4f5-6789-bcde-f01234567890","name":"Developer Exceptions"}
]
"""

private let protectExceptionSetDetailJSON = """
{
  "uuid": "4722390a-f279-4fbe-9dad-b922e9c92289",
  "name": "Approved Security Tools",
  "description": "Whitelisted internal security and IT tooling - reviewed quarterly by Security team."
}
"""

private let protectRemovableStorageJSON = """
[
  {"name":"USB - read-only and allow write encrypted","defaultMountAction":"ReadOnly","rulesCount":1},
  {"name":"USB - read-only","defaultMountAction":"ReadOnly","rulesCount":0},
  {"name":"USB - allow write unencrypted","defaultMountAction":"ReadWrite","rulesCount":0}
]
"""

private let protectUnifiedLoggingJSON = """
[
  {"name":"Airdrop Transfer Outbound","enabled":true,"filter":"subsystem == \"com.apple.sharing\" AND process == \"AirDrop\""},
  {"name":"Application Firewall Logging","enabled":true,"filter":"subsystem == \"com.apple.alf\""},
  {"name":"Jamf Connect Login monitoring","enabled":false,"filter":"subsystem == \"com.jamf.connect.login\""}
]
"""

private let protectActionConfigsJSON = """
[
  {"name":"Default"},
  {"name":"Alert and Block"},
  {"name":"Alert Only"}
]
"""

private let protectTelemetryConfigsJSON = """
[
  {"name":"Telemetry general - 20250110","fileHashing":true,"logFileCollection":true,"performanceMetrics":true},
  {"name":"Minimal Telemetry","fileHashing":false,"logFileCollection":false,"performanceMetrics":false}
]
"""

private let protectCustomPreventListsJSON = """
[
  {"uuid":"cpl001","name":"Approved Developer Tools","description":"Excludes known-good developer binaries from malware detections","enabled":true},
  {"uuid":"cpl002","name":"Security Scanner Exceptions","description":"Prevents false positives from internal vulnerability scanners","enabled":true},
  {"uuid":"cpl003","name":"Legacy App Exceptions","description":"Temporary exceptions for legacy line-of-business applications","enabled":false}
]
"""

private let protectRolesJSON = """
[
  {"name":"Administrator","permissions":"R: 5 resources, W: 5 resources"},
  {"name":"Security Analyst","permissions":"R: 3 resources, W: 2 resources"},
  {"name":"Read Only","permissions":"R: 1 resource, W: none"}
]
"""

private let protectUsersJSON = """
[
  {"email":"alice.smith@acme.example.com","assignedRoles":"Administrator","assignedGroups":"Security Team, IT Admins"},
  {"email":"bob.johnson@acme.example.com","assignedRoles":"Security Analyst","assignedGroups":"Security Team"},
  {"email":"charlie.brown@acme.example.com","assignedRoles":"Security Analyst","assignedGroups":"Security Team"},
  {"email":"diana.prince@acme.example.com","assignedRoles":"Read Only","assignedGroups":"Management"},
  {"email":"evan.rogers@acme.example.com","assignedRoles":"Read Only","assignedGroups":"Management"}
]
"""

private let protectGroupsJSON = """
[
  {"name":"Security Team","accessGroup":false,"assignedRoles":"Security Analyst"},
  {"name":"IT Admins","accessGroup":false,"assignedRoles":"Administrator"},
  {"name":"Management","accessGroup":false,"assignedRoles":"Read Only"},
  {"name":"External Auditors","accessGroup":true,"assignedRoles":"Read Only"}
]
"""

private let protectULFDetailJSON = """
{
  "uuid": "0d3b2c1d-e426-475c-b8e7-d987efe27ad0",
  "name": "Airdrop Transfer Outbound",
  "description": "This Unified Log filter may be used to report on outbound AirDrop file transfers from the Mac. It monitors logging from an AirDrop process spawning from a valid location and a logged string known to indicate an outbound file transfer was offered.",
  "created": "2025-08-20T12:48:13.263724Z",
  "updated": "2025-08-20T12:48:13.263724Z",
  "filter": "subsystem == \\"com.apple.sharing\\" AND process == \\"AirDrop\\" AND processImagePath BEGINSWITH \\"/System/Library\\" AND eventMessage BEGINSWITH \\"Successfully issued sandbox extension for\\"",
  "tags": ["visibility", "DataLossPrevention"],
  "enabled": true
}
"""

private let protectAnalyticDetailJSON = """
{
  "uuid": "0eb4ca4e-e883-49d5-8160-edf17527152e",
  "name": "PeriodicScript",
  "label": "Periodic Script",
  "inputType": "GPFSEvent",
  "filter": "$event.type in {0, 3, 4} AND ($event.path MATCHES[cd] \\"(/usr/local)?/etc/periodic/(daily|weekly|monthly)/.*\\" OR $event.path MATCHES[cd] \\"/etc/(daily|weekly|monthly)\\\\.local\\") AND NOT $event.process.responsible.signingInfo.teamid == \\"483DWKW443\\"",
  "description": "A script was added for execution by periodic.",
  "longDescription": "Scripts located in /etc/periodic or /usr/local/etc/periodic/ are executed by the operating system on a periodic basis for routine system tasks. Persistence may be achieved by adding scripts to this directory.",
  "created": "2023-10-05T09:09:28.313620Z",
  "updated": "2026-01-15T16:32:58.753208Z",
  "analyticActions": [{"name": "Report"}],
  "tags": ["MITREattack", "Execution", "ScheduledTaskJob", "T1053", "Persistence"],
  "severity": "Low",
  "categories": ["Persistence"],
  "jamf": true,
  "remediation": "This analytic is primarily for visibility purposes. If you've determined that the created persistence item is malicious, remove the persistence item and the associated malicious binary."
}
"""

private let protectAPIClientsJSON = """
[
  {"uuid":"cli001","name":"SIEM Integration","role":"Security Analyst","createdAt":"2024-01-15T10:00:00Z"},
  {"uuid":"cli002","name":"Jamf Pro Sync","role":"Read Only","createdAt":"2024-02-01T09:30:00Z"},
  {"uuid":"cli003","name":"Automation Pipeline","role":"Administrator","createdAt":"2024-03-10T14:00:00Z"}
]
"""

// MARK: - Jamf School

private let schoolOverviewJSON = """
[
  {"section":"Devices","resource":"Total Devices","value":"312"},
  {"section":"Devices","resource":"Managed Devices","value":"305"},
  {"section":"Devices","resource":"iPads","value":"280"},
  {"section":"Devices","resource":"MacBooks","value":"32"},
  {"section":"Users","resource":"Total Users","value":"487"},
  {"section":"Users","resource":"Students","value":"432"},
  {"section":"Users","resource":"Staff","value":"55"},
  {"section":"Organisation","resource":"Device Groups","value":"18"},
  {"section":"Organisation","resource":"User Groups","value":"12"},
  {"section":"Organisation","resource":"Classes","value":"24"},
  {"section":"Content","resource":"Apps Deployed","value":"14"}
]
"""

private let schoolDevicesJSON = """
[
  {"id":"1","name":"iPad Year 7 - 001","serialNumber":"F7TK2001DEMO","model":"iPad (10th gen)","osVersion":"18.4","managed":true},
  {"id":"2","name":"iPad Year 7 - 002","serialNumber":"F7TK2002DEMO","model":"iPad (10th gen)","osVersion":"18.4","managed":true},
  {"id":"3","name":"iPad Year 7 - 003","serialNumber":"F7TK2003DEMO","model":"iPad (10th gen)","osVersion":"18.3.2","managed":true},
  {"id":"4","name":"iPad Year 8 - 001","serialNumber":"F8TK2001DEMO","model":"iPad (10th gen)","osVersion":"18.4","managed":true},
  {"id":"5","name":"iPad Year 8 - 002","serialNumber":"F8TK2002DEMO","model":"iPad (10th gen)","osVersion":"18.4","managed":true},
  {"id":"6","name":"iPad Year 9 - 001","serialNumber":"F9TK2001DEMO","model":"iPad (10th gen)","osVersion":"18.4","managed":true},
  {"id":"7","name":"iPad Staff - 001","serialNumber":"FSTK2001DEMO","model":"iPad Pro 12.9-inch (M2)","osVersion":"18.4","managed":true},
  {"id":"8","name":"iPad Staff - 002","serialNumber":"FSTK2002DEMO","model":"iPad Pro 12.9-inch (M2)","osVersion":"18.3.2","managed":true},
  {"id":"9","name":"MacBook Air Lab - 001","serialNumber":"FLBK2001DEMO","model":"MacBook Air 13-inch (M2)","osVersion":"15.4","managed":true},
  {"id":"10","name":"MacBook Air Lab - 002","serialNumber":"FLBK2002DEMO","model":"MacBook Air 13-inch (M2)","osVersion":"15.4","managed":true},
  {"id":"11","name":"MacBook Air Lab - 003","serialNumber":"FLBK2003DEMO","model":"MacBook Air 13-inch (M2)","osVersion":"15.4","managed":true},
  {"id":"12","name":"MacBook Air Lab - 004","serialNumber":"FLBK2004DEMO","model":"MacBook Air 13-inch (M2)","osVersion":"15.3.2","managed":true}
]
"""

private let schoolDeviceGroupsJSON = """
[
  {"id":"1","name":"Year 7 iPads"},
  {"id":"2","name":"Year 8 iPads"},
  {"id":"3","name":"Year 9 iPads"},
  {"id":"4","name":"Year 10 iPads"},
  {"id":"5","name":"Staff iPads"},
  {"id":"6","name":"Computer Lab MacBooks"},
  {"id":"7","name":"Shared Devices"},
  {"id":"8","name":"Not Supervised"}
]
"""

private let schoolUsersJSON = """
[
  {"id":"1","name":"Alice Smith","email":"alice.smith@school.example.com","username":"alice.smith"},
  {"id":"2","name":"Bob Johnson","email":"bob.johnson@school.example.com","username":"bob.johnson"},
  {"id":"3","name":"Charlie Brown","email":"charlie.brown@school.example.com","username":"charlie.brown"},
  {"id":"4","name":"Diana Prince","email":"diana.prince@school.example.com","username":"diana.prince"},
  {"id":"5","name":"Evan Rogers","email":"evan.rogers@school.example.com","username":"evan.rogers"},
  {"id":"6","name":"Ms. Sarah Thompson","email":"s.thompson@school.example.com","username":"s.thompson"},
  {"id":"7","name":"Mr. James Williams","email":"j.williams@school.example.com","username":"j.williams"},
  {"id":"8","name":"Mrs. Emily Davis","email":"e.davis@school.example.com","username":"e.davis"}
]
"""

private let schoolUserGroupsJSON = """
[
  {"id":"1","name":"Year 7 Students"},
  {"id":"2","name":"Year 8 Students"},
  {"id":"3","name":"Year 9 Students"},
  {"id":"4","name":"Year 10 Students"},
  {"id":"5","name":"Teaching Staff"},
  {"id":"6","name":"IT Staff"},
  {"id":"7","name":"Leadership"}
]
"""

private let schoolClassesJSON = """
[
  {"id":"1","name":"7A - Mathematics"},
  {"id":"2","name":"7A - English"},
  {"id":"3","name":"7A - Science"},
  {"id":"4","name":"8B - Mathematics"},
  {"id":"5","name":"8B - History"},
  {"id":"6","name":"9C - Computer Science"},
  {"id":"7","name":"9C - Art & Design"},
  {"id":"8","name":"10D - Physics"},
  {"id":"9","name":"10D - Chemistry"},
  {"id":"10","name":"Computer Lab - Open Access"}
]
"""

private let schoolAppsJSON = """
[
  {"id":"1","name":"Minecraft Education Edition"},
  {"id":"2","name":"GoodNotes 6"},
  {"id":"3","name":"Keynote"},
  {"id":"4","name":"Pages"},
  {"id":"5","name":"Numbers"},
  {"id":"6","name":"Clips"},
  {"id":"7","name":"Google Classroom"},
  {"id":"8","name":"Kahoot!"},
  {"id":"9","name":"Khan Academy"},
  {"id":"10","name":"Explain Everything"},
  {"id":"11","name":"Swift Playgrounds"},
  {"id":"12","name":"Notability"},
  {"id":"13","name":"Duolingo"},
  {"id":"14","name":"Canva"}
]
"""

// MARK: - Mobile Devices

private let mobileDevicesJSON = """
[
  {"id":"1","name":"iPad-ClassroomA-01","serialNumber":"DMPXXXXXXXX1","model":"iPad (10th generation)","osVersion":"17.4.1","lastContactTime":"2024-04-20T09:15:00Z","managed":true,"supervised":true,"enrolled":true},
  {"id":"2","name":"iPad-ClassroomA-02","serialNumber":"DMPXXXXXXXX2","model":"iPad (10th generation)","osVersion":"17.4.1","lastContactTime":"2024-04-20T09:16:00Z","managed":true,"supervised":true,"enrolled":true},
  {"id":"3","name":"iPhone-Exec-01","serialNumber":"F2LXXXXXXXX1","model":"iPhone 15 Pro","osVersion":"17.4","lastContactTime":"2024-04-19T18:30:00Z","managed":true,"supervised":false,"enrolled":true},
  {"id":"4","name":"iPhone-Exec-02","serialNumber":"F2LXXXXXXXX2","model":"iPhone 15","osVersion":"17.3.1","lastContactTime":"2024-04-18T10:00:00Z","managed":true,"supervised":false,"enrolled":true},
  {"id":"5","name":"iPad-Lab-01","serialNumber":"DMPXXXXXXXX3","model":"iPad Air (5th generation)","osVersion":"16.7.7","lastContactTime":"2024-03-15T14:00:00Z","managed":true,"supervised":true,"enrolled":true},
  {"id":"6","name":"iPad-Lab-02","serialNumber":"DMPXXXXXXXX4","model":"iPad Air (5th generation)","osVersion":"17.4.1","lastContactTime":"2024-04-20T08:45:00Z","managed":true,"supervised":true,"enrolled":true},
  {"id":"7","name":"iPad-Unmanaged","serialNumber":"DMPXXXXXXXX5","model":"iPad (9th generation)","osVersion":"15.8","lastContactTime":"2023-11-01T12:00:00Z","managed":false,"supervised":false,"enrolled":false}
]
"""

// MARK: - Extension Attributes

private let extensionAttributesJSON = """
[
  {"id":"1","name":"Last Reboot","dataType":"Date","inputType":"Script"},
  {"id":"2","name":"Battery Cycle Count","dataType":"Integer","inputType":"Script"},
  {"id":"3","name":"Encryption Status","dataType":"String","inputType":"Script"},
  {"id":"4","name":"Local Admin Present","dataType":"String","inputType":"Script"},
  {"id":"5","name":"SIP Status","dataType":"String","inputType":"Script"},
  {"id":"6","name":"VPN Client Version","dataType":"String","inputType":"Script"},
  {"id":"7","name":"Asset Tag","dataType":"String","inputType":"Text Field"},
  {"id":"8","name":"Purchase Date","dataType":"Date","inputType":"Text Field"},
  {"id":"9","name":"Department Code","dataType":"String","inputType":"Pop-up Menu"},
  {"id":"10","name":"Warranty Expiry","dataType":"Date","inputType":"Text Field"}
]
"""

// MARK: - Patch Management

private let patchTitlesJSON = """
[
  {"id":"1","name":"macOS Sonoma","category":{"id":1,"name":"Operating Systems"},"current_version":"14.4.1"},
  {"id":"2","name":"macOS Ventura","category":{"id":1,"name":"Operating Systems"},"current_version":"13.6.6"},
  {"id":"3","name":"Google Chrome","category":{"id":2,"name":"Browsers"},"current_version":"124.0.6367.60"},
  {"id":"4","name":"Mozilla Firefox","category":{"id":2,"name":"Browsers"},"current_version":"125.0.2"},
  {"id":"5","name":"Microsoft Office 365","category":{"id":3,"name":"Productivity"},"current_version":"16.84.0"},
  {"id":"6","name":"Zoom","category":{"id":4,"name":"Communication"},"current_version":"6.0.2"},
  {"id":"7","name":"Slack","category":{"id":4,"name":"Communication"},"current_version":"4.38.125"},
  {"id":"8","name":"Adobe Acrobat","category":{"id":5,"name":"Creative"},"current_version":"24.002.20736"},
  {"id":"9","name":"1Password 8","category":{"id":6,"name":"Security"},"current_version":"8.10.28"},
  {"id":"10","name":"Jamf Connect","category":{"id":6,"name":"Security"},"current_version":"2.34.0"}
]
"""

private let patchPoliciesJSON = """
[
  {"id":"1","name":"Sonoma Auto-Update","enabled":true,"target_version":"14.4.1","patch_title":{"id":1,"name":"macOS Sonoma"}},
  {"id":"2","name":"Chrome - Latest","enabled":true,"target_version":"124.0.6367.60","patch_title":{"id":3,"name":"Google Chrome"}},
  {"id":"3","name":"Firefox - Latest","enabled":true,"target_version":"125.0.2","patch_title":{"id":4,"name":"Mozilla Firefox"}},
  {"id":"4","name":"Office 365 Quarterly","enabled":true,"target_version":"16.84.0","patch_title":{"id":5,"name":"Microsoft Office 365"}},
  {"id":"5","name":"Zoom - Latest","enabled":true,"target_version":"6.0.2","patch_title":{"id":6,"name":"Zoom"}},
  {"id":"6","name":"Slack - Latest","enabled":false,"target_version":"4.38.125","patch_title":{"id":7,"name":"Slack"}},
  {"id":"7","name":"Acrobat - Latest","enabled":true,"target_version":"24.002.20736","patch_title":{"id":8,"name":"Adobe Acrobat"}},
  {"id":"8","name":"1Password - Latest","enabled":true,"target_version":"8.10.28","patch_title":{"id":9,"name":"1Password 8"}}
]
"""

private let patchTitleDetailJSON = """
{
  "id": 3,
  "name": "Google Chrome",
  "name_id": "Jamf_Chrome",
  "category": {"id": 5, "name": "Browsers"},
  "versions": [
    {"software_version": "124.0.6367.60"},
    {"software_version": "123.0.6312.86"},
    {"software_version": "122.0.6261.128"}
  ]
}
"""

private let patchPolicyDetailJSON = """
{
  "general": {
    "id": 2,
    "name": "Chrome - Latest",
    "enabled": true,
    "target_version": "124.0.6367.60",
    "patch_title": {"id": 3, "name": "Google Chrome"}
  }
}
"""

// MARK: - Restricted Software
// The list is returned pre-enriched (flat format) so the VM's "thin list" enrichment
// guard never fires — all detail fields are present right in the list response.

private let restrictedSoftwareListJSON = """
[
  {"id":"1","name":"Safari Extensions Helper","process_name":"SafariExtensionsHelper","match_exact_process_name":true,"kill_process":false,"delete_executable":false,"display_message":""},
  {"id":"2","name":"Unauthorized VPN Clients","process_name":"openvpn","match_exact_process_name":false,"kill_process":true,"delete_executable":false,"display_message":"Unauthorized VPN software detected. Please contact IT."},
  {"id":"3","name":"BitTorrent Clients","process_name":"Transmission","match_exact_process_name":true,"kill_process":true,"delete_executable":true,"display_message":"Peer-to-peer file sharing is prohibited on corporate devices."},
  {"id":"4","name":"Cryptomining Software","process_name":"xmrig","match_exact_process_name":false,"kill_process":true,"delete_executable":true,"display_message":"Cryptomining software is not permitted."},
  {"id":"5","name":"Remote Access Tools (Unauthorized)","process_name":"TeamViewer","match_exact_process_name":true,"kill_process":true,"delete_executable":false,"display_message":"Unauthorized remote access tools are not permitted. Use approved solutions."},
  {"id":"6","name":"Hacking Utilities","process_name":"nmap","match_exact_process_name":false,"kill_process":true,"delete_executable":true,"display_message":"Network scanning tools are restricted on this device."},
  {"id":"7","name":"Screen Recording (Unapproved)","process_name":"Screenium","match_exact_process_name":true,"kill_process":false,"delete_executable":false,"display_message":""},
  {"id":"8","name":"Ad-hoc Gaming","process_name":"Steam","match_exact_process_name":true,"kill_process":false,"delete_executable":false,"display_message":"Gaming applications are not permitted on work devices during business hours."}
]
"""

// Fallback for individual detail calls (not triggered in demo mode since the list is pre-enriched)
private let restrictedSoftwareDetailJSON = """
{
  "restricted_software": {
    "id": 1,
    "name": "Safari Extensions Helper",
    "general": {
      "process_name": "SafariExtensionsHelper",
      "match_exact_process_name": true,
      "kill_process": false,
      "delete_executable": false,
      "display_message": ""
    }
  }
}
"""

// MARK: - Modern Patch Titles (UAPI v2 / patchSoftwareTitleConfigurations)

private let modernPatchTitlesJSON = """
[
  {"id":"mpt-001","softwareTitleName":"Google Chrome","current_version":"124.0.6367.60","categoryName":"Browsers","onDashboard":true,"uiNotifications":true},
  {"id":"mpt-002","softwareTitleName":"Mozilla Firefox","current_version":"125.0.2","categoryName":"Browsers","onDashboard":true,"uiNotifications":false},
  {"id":"mpt-003","softwareTitleName":"Microsoft Office 365","current_version":"16.84.0","categoryName":"Productivity","onDashboard":true,"uiNotifications":true},
  {"id":"mpt-004","softwareTitleName":"Zoom","current_version":"6.0.2","categoryName":"Communication","onDashboard":false,"uiNotifications":true},
  {"id":"mpt-005","softwareTitleName":"Slack","current_version":"4.38.125","categoryName":"Communication","onDashboard":false,"uiNotifications":false},
  {"id":"mpt-006","softwareTitleName":"Adobe Acrobat","current_version":"24.002.20736","categoryName":"Creative","onDashboard":true,"uiNotifications":false},
  {"id":"mpt-007","softwareTitleName":"1Password 8","current_version":"8.10.28","categoryName":"Security","onDashboard":true,"uiNotifications":true},
  {"id":"mpt-008","softwareTitleName":"Jamf Connect","current_version":"2.34.0","categoryName":"Security","onDashboard":true,"uiNotifications":true},
  {"id":"mpt-009","softwareTitleName":"Jamf Protect","current_version":"5.4.1","categoryName":"Security","onDashboard":true,"uiNotifications":false},
  {"id":"mpt-010","softwareTitleName":"Visual Studio Code","current_version":"1.89.0","categoryName":"Development","onDashboard":false,"uiNotifications":false}
]
"""

// MARK: - App Installer Titles

private let appInstallerTitlesJSON = """
[
  {"id":"ait-001","name":"1Password 7 – Password Manager","publisher":"AgileBits Inc.","currentVersion":"7.9.11","category":"Productivity"},
  {"id":"ait-002","name":"Google Chrome","publisher":"Google LLC","currentVersion":"124.0.6367.60","category":"Browsers"},
  {"id":"ait-003","name":"Zoom","publisher":"Zoom Video Communications, Inc.","currentVersion":"6.0.2","category":"Communication"},
  {"id":"ait-004","name":"Slack","publisher":"Slack Technologies, LLC","currentVersion":"4.38.125","category":"Communication"},
  {"id":"ait-005","name":"Visual Studio Code","publisher":"Microsoft Corporation","currentVersion":"1.89.0","category":"Development"},
  {"id":"ait-006","name":"Figma","publisher":"Figma, Inc.","currentVersion":"116.14.8","category":"Design"},
  {"id":"ait-007","name":"Notion","publisher":"Notion Labs, Inc.","currentVersion":"3.8.4","category":"Productivity"},
  {"id":"ait-008","name":"Spotify","publisher":"Spotify AB","currentVersion":"1.2.31","category":"Media"},
  {"id":"ait-009","name":"Docker Desktop","publisher":"Docker Inc.","currentVersion":"4.29.0","category":"Development"},
  {"id":"ait-010","name":"TablePlus","publisher":"TablePlus, Inc.","currentVersion":"5.9.2","category":"Development"}
]
"""

// MARK: - App Installer Deployments

private let appInstallerDeploymentsJSON = """
[
  {"id":"dep-001","name":"Chrome - All Staff","appTitleName":"Google Chrome","targetVersion":"124.0.6367.60","latestVersion":"124.0.6367.60","versionSelection":"LATEST_MAJOR","enabled":true,"assignedDevicesCount":180,"installedDevicesCount":175},
  {"id":"dep-002","name":"Zoom - All Staff","appTitleName":"Zoom","targetVersion":"6.0.2","latestVersion":"6.0.2","versionSelection":"LATEST_MAJOR","enabled":true,"assignedDevicesCount":165,"installedDevicesCount":162},
  {"id":"dep-003","name":"Slack - Engineering","appTitleName":"Slack","targetVersion":"4.38.125","latestVersion":"4.38.125","versionSelection":"LATEST_MINOR","enabled":true,"assignedDevicesCount":52,"installedDevicesCount":48},
  {"id":"dep-004","name":"VS Code - Developers","appTitleName":"Visual Studio Code","targetVersion":"1.89.0","latestVersion":"1.89.0","versionSelection":"LATEST_MAJOR","enabled":true,"assignedDevicesCount":38,"installedDevicesCount":36},
  {"id":"dep-005","name":"Figma - Design Team","appTitleName":"Figma","targetVersion":"116.14.8","latestVersion":"116.14.8","versionSelection":"SPECIFIC_VERSION","enabled":true,"assignedDevicesCount":14,"installedDevicesCount":14},
  {"id":"dep-006","name":"Docker Desktop - Developers","appTitleName":"Docker Desktop","targetVersion":"4.29.0","latestVersion":"4.29.0","versionSelection":"LATEST_MAJOR","enabled":false,"assignedDevicesCount":22,"installedDevicesCount":18},
  {"id":"dep-007","name":"1Password - All Staff","appTitleName":"1Password 7 – Password Manager","targetVersion":"7.9.11","latestVersion":"7.9.11","versionSelection":"LATEST_MINOR","enabled":true,"assignedDevicesCount":180,"installedDevicesCount":180},
  {"id":"dep-008","name":"Notion - Operations","appTitleName":"Notion","targetVersion":"3.8.4","latestVersion":"3.8.4","versionSelection":"LATEST_MAJOR","enabled":true,"assignedDevicesCount":28,"installedDevicesCount":25}
]
"""

// MARK: - Enrollment & Prestages

private let depTokensJSON = """
[
  {"id":"A1B2C3D4-E5F6-7890-ABCD-EF1234567890","orgName":"Acme Corporation","tokenExpiration":"2025-06-15T00:00:00Z"},
  {"id":"B2C3D4E5-F6A7-8901-BCDE-F12345678901","orgName":"Acme Corp - Education","tokenExpiration":"2025-09-30T00:00:00Z"}
]
"""

private let computerPrestagesJSON = """
[
  {"id":"1","displayName":"MacBook Pro - Standard","mdmRemovable":false,"enrollmentSiteId":"-1"},
  {"id":"2","displayName":"MacBook Air - Education","mdmRemovable":false,"enrollmentSiteId":"-1"},
  {"id":"3","displayName":"Mac mini - Lab","mdmRemovable":true,"enrollmentSiteId":"-1"},
  {"id":"4","displayName":"iMac - Creative","mdmRemovable":false,"enrollmentSiteId":"-1"}
]
"""

private let mobileDevicePrestagesJSON = """
[
  {"id":"1","displayName":"iPad - Classroom Shared","enrollmentSiteId":"-1"},
  {"id":"2","displayName":"iPhone - Corporate Standard","enrollmentSiteId":"-1"},
  {"id":"3","displayName":"iPad - Lab Shared","enrollmentSiteId":"-1"}
]
"""

// MARK: - Reports

private let reportPatchStatusJSON = """
[
  {"device_id":"ABC123","device_name":"MacBook Pro - Alice","patch_title":"macOS Sonoma","current_version":"14.2.0","target_version":"14.4.1","status":"Pending"},
  {"device_id":"XYZ789","device_name":"iMac - Bob","patch_title":"macOS Sonoma","current_version":"14.4.1","target_version":"14.4.1","status":"Completed"},
  {"device_id":"PQR345","device_name":"Mac mini - Chris","patch_title":"Google Chrome","current_version":"123.0","target_version":"124.0.6367.60","status":"Failed"},
  {"device_id":"MNO901","device_name":"MacBook Air - Diana","patch_title":"macOS Sonoma","current_version":"14.4.1","target_version":"14.4.1","status":"Completed"},
  {"device_id":"DEF567","device_name":"Mac Studio - Eve","patch_title":"Microsoft Office 365","current_version":"16.83","target_version":"16.84.0","status":"Pending"}
]
"""

private let reportPolicyStatusJSON = """
[
  {"policy_id":"1","policy_name":"MacBook Pro Baseline","enabled":true,"assigned_count":45,"failed_count":2,"success_rate":95.6},
  {"policy_id":"2","policy_name":"Security Posture Update","enabled":true,"assigned_count":120,"failed_count":5,"success_rate":95.8},
  {"policy_id":"3","policy_name":"Office 365 Configuration","enabled":true,"assigned_count":89,"failed_count":1,"success_rate":98.9},
  {"policy_id":"4","policy_name":"VPN Deployment","enabled":true,"assigned_count":150,"failed_count":12,"success_rate":92.0},
  {"policy_id":"5","policy_name":"Nightly Maintenance","enabled":false,"assigned_count":200,"failed_count":0,"success_rate":0.0}
]
"""

private let reportProfileStatusJSON = """
[
  {"profile_id":"1","profile_name":"WiFi - Corporate","assigned_count":180,"installed_count":175,"failure_count":5,"compliance":97.2},
  {"profile_id":"2","profile_name":"VPN Settings","assigned_count":150,"installed_count":148,"failure_count":2,"compliance":98.7},
  {"profile_id":"3","profile_name":"Certificate Authority","assigned_count":200,"installed_count":198,"failure_count":2,"compliance":99.0},
  {"profile_id":"4","profile_name":"Email Configuration","assigned_count":120,"installed_count":115,"failure_count":5,"compliance":95.8},
  {"profile_id":"5","profile_name":"Restrictions & Parental Controls","assigned_count":50,"installed_count":48,"failure_count":2,"compliance":96.0}
]
"""

private let reportAppStatusJSON = """
[
  {"app_id":"1","app_name":"Microsoft Teams","version":"24.01.35","assigned_count":200,"installed_count":195,"latest_version":"24.02.10"},
  {"app_id":"2","app_name":"Google Chrome","version":"124.0.6367.60","assigned_count":180,"installed_count":180,"latest_version":"124.0.6367.60"},
  {"app_id":"3","app_name":"Zoom","version":"6.0.1","assigned_count":150,"installed_count":145,"latest_version":"6.0.2"},
  {"app_id":"4","app_name":"Slack","version":"4.37.125","assigned_count":120,"installed_count":110,"latest_version":"4.38.125"},
  {"app_id":"5","app_name":"Adobe Acrobat Reader","version":"24.001.20629","assigned_count":100,"installed_count":98,"latest_version":"24.002.20736"}
]
"""

private let reportUpdateStatusJSON = """
[
  {"device_id":"ABC123","device_name":"MacBook Pro - Alice","os":"macOS","current_version":"14.2.0","latest_version":"14.4.1","days_behind":10,"status":"Pending"},
  {"device_id":"XYZ789","device_name":"iMac - Bob","os":"macOS","current_version":"14.4.1","latest_version":"14.4.1","days_behind":0,"status":"Current"},
  {"device_id":"PQR345","device_name":"Mac mini - Chris","os":"macOS","current_version":"13.6.5","latest_version":"14.4.1","days_behind":45,"status":"Failed"},
  {"device_id":"MNO901","device_name":"MacBook Air - Diana","os":"macOS","current_version":"14.4.0","latest_version":"14.4.1","days_behind":1,"status":"Pending"},
  {"device_id":"DEF567","device_name":"Mac Studio - Eve","os":"macOS","current_version":"14.4.1","latest_version":"14.4.1","days_behind":0,"status":"Current"}
]
"""

private let reportDeviceComplianceJSON = """
[
  {"device_id":"ABC123","device_name":"MacBook Pro - Alice","device_type":"Mac","compliance_status":"Compliant","last_checkin":"2025-05-03T10:30:00Z","os_version":"14.4.1"},
  {"device_id":"XYZ789","device_name":"iMac - Bob","device_type":"Mac","compliance_status":"Compliant","last_checkin":"2025-05-03T09:15:00Z","os_version":"14.4.1"},
  {"device_id":"PQR345","device_name":"Mac mini - Chris","device_type":"Mac","compliance_status":"Non-Compliant","last_checkin":"2025-05-02T14:45:00Z","os_version":"13.6.5"},
  {"device_id":"MNO901","device_name":"MacBook Air - Diana","device_type":"Mac","compliance_status":"Compliant","last_checkin":"2025-05-03T08:20:00Z","os_version":"14.4.0"},
  {"device_id":"DEF567","device_name":"Mac Studio - Eve","device_type":"Mac","compliance_status":"Compliant","last_checkin":"2025-05-03T11:00:00Z","os_version":"14.4.1"}
]
"""

private let reportInventorySummaryJSON = """
[
  {"category":"macOS Versions","macOS Sonoma":45,"macOS Ventura":28,"macOS Monterey":12,"Total":85},
  {"category":"Device Models","MacBook Pro":38,"iMac":15,"Mac mini":18,"MacBook Air":10,"Mac Studio":4,"Total":85},
  {"category":"Memory","8GB":10,"16GB":35,"32GB":30,"64GB":10,"Total":85},
  {"category":"Storage","256GB":15,"512GB":40,"1TB":25,"2TB":5,"Total":85},
  {"category":"Network Status","WiFi":"78","Ethernet":"5","Offline":"2","Total":"85"}
]
"""

private let reportSoftwareInstallsJSON = """
[
  {"app_name":"Microsoft Teams","installed_count":195,"failed_count":5,"success_rate":97.5,"last_updated":"2025-05-03T10:30:00Z"},
  {"app_name":"Google Chrome","installed_count":180,"failed_count":0,"success_rate":100.0,"last_updated":"2025-05-03T09:45:00Z"},
  {"app_name":"Zoom","installed_count":145,"failed_count":5,"success_rate":96.7,"last_updated":"2025-05-02T14:20:00Z"},
  {"app_name":"Slack","installed_count":110,"failed_count":10,"success_rate":91.7,"last_updated":"2025-05-02T11:15:00Z"},
  {"app_name":"Adobe Acrobat Reader","installed_count":98,"failed_count":2,"success_rate":98.0,"last_updated":"2025-05-01T16:40:00Z"},
  {"app_name":"1Password","installed_count":75,"failed_count":0,"success_rate":100.0,"last_updated":"2025-04-30T13:25:00Z"}
]
"""

// Returns computers-inventory GENERAL section; only DDM-enabled devices have a managementId
private let ddmComputersJSON = """
{
  "totalCount": 4,
  "results": [
    {"id":"1","general":{"name":"Alice's MacBook Pro","managementId":"aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb","serialNumber":"C02XA001DEMO","declarativeDeviceManagementEnabled":true}},
    {"id":"2","general":{"name":"Bob's MacBook Air","managementId":"bbbbbbbb-2222-3333-4444-cccccccccccc","serialNumber":"C02XA002DEMO","declarativeDeviceManagementEnabled":true}},
    {"id":"3","general":{"name":"Charlie's MacBook Pro","managementId":"cccccccc-3333-4444-5555-dddddddddddd","serialNumber":"C02XA003DEMO","declarativeDeviceManagementEnabled":true}},
    {"id":"8","general":{"name":"Henry's Mac Studio","managementId":"dddddddd-4444-5555-6666-eeeeeeeeeeee","serialNumber":"C02XA008DEMO","declarativeDeviceManagementEnabled":true}}
  ]
}
"""

private let ddmAllStatusItems: [(managementId: String, key: String, value: String)] = [
    ("aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb", "device.identifier.serial-number",         "C02XA001DEMO"),
    ("aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb", "management.declarations.activations",      "{active=true, valid=valid, identifier=e537799f-aaaa-bbbb-cccc-dddddddddddd}"),
    ("aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb", "device.operating-system.version",          "27.0"),
    ("aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb", "device.operating-system.build-version",    "27A5320"),
    ("aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb", "mdm.enrollment-type",                      "supervised"),
    ("aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb", "mdm.is-awaiting-configuration",            "false"),
    ("aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb", "security.lockdown-mode",                   "false"),
    ("aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb", "softwareupdate.install-state",             "prepared"),
    ("aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb", "softwareupdate.pending-version",           "{os-version=27.0.1, build-version=27A5340, target-local-date-time=2026-10-03T18:00:00}"),
    ("aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb", "softwareupdate.failure-reason",            "{count=0}"),
    ("bbbbbbbb-2222-3333-4444-cccccccccccc", "device.identifier.serial-number",         "C02XA002DEMO"),
    ("bbbbbbbb-2222-3333-4444-cccccccccccc", "management.declarations.activations",      "{active=true, valid=valid, identifier=f648800e-bbbb-cccc-dddd-eeeeeeeeeeee}"),
    ("bbbbbbbb-2222-3333-4444-cccccccccccc", "device.operating-system.version",          "15.4"),
    ("cccccccc-3333-4444-5555-dddddddddddd", "device.identifier.serial-number",         "C02XA003DEMO"),
    ("cccccccc-3333-4444-5555-dddddddddddd", "management.declarations.activations",      "{active=true, valid=valid, identifier=a759911d-cccc-dddd-eeee-ffffffffffff}"),
    ("dddddddd-4444-5555-6666-eeeeeeeeeeee", "device.identifier.serial-number",         "C02XA008DEMO"),
    ("dddddddd-4444-5555-6666-eeeeeeeeeeee", "management.declarations.activations",      "{active=true, valid=valid, identifier=b860022c-dddd-eeee-ffff-000000000000}"),
    ("dddddddd-4444-5555-6666-eeeeeeeeeeee", "device.operating-system.version",          "27.0"),
    ("dddddddd-4444-5555-6666-eeeeeeeeeeee", "mdm.enrollment-type",                      "supervised"),
    ("dddddddd-4444-5555-6666-eeeeeeeeeeee", "mdm.is-awaiting-configuration",            "false"),
    ("dddddddd-4444-5555-6666-eeeeeeeeeeee", "security.lockdown-mode",                   "true"),
    ("dddddddd-4444-5555-6666-eeeeeeeeeeee", "softwareupdate.install-state",             "failed"),
    ("dddddddd-4444-5555-6666-eeeeeeeeeeee", "softwareupdate.pending-version",           "{os-version=27.0.1, build-version=27A5340}"),
    ("dddddddd-4444-5555-6666-eeeeeeeeeeee", "softwareupdate.failure-reason",            "{count=2, reason=Insufficient disk space, timestamp=2026-09-24T09:12:00Z}"),
]

private func ddmStatusItemsJSON(for managementId: String) -> String {
    let items = ddmAllStatusItems
        .filter { $0.managementId == managementId }
        .map { item in
            """
            {"key":"\(item.key)","value":"\(item.value)","lastUpdateTime":"2026-04-24T15:56:17.198"}
            """
        }
        .joined(separator: ",\n    ")
    return "{\n  \"statusItems\": [\n    \(items)\n  ]\n}"
}

// MARK: - macOS 27 readiness demo data

private let demoProfileNames: [Int: String] = [
    1: "Security Baseline", 2: "FileVault Enforcement", 3: "Firewall Configuration",
    4: "Energy Saver", 5: "Wi-Fi (Corporate)", 6: "VPN Settings", 7: "Login Window",
    8: "System Preferences Restrictions", 9: "Password Policy", 10: "Certificates - Internal CA",
    11: "Software Update Deferrals", 12: "Privacy Preferences (PPPC)", 13: "Jamf Setup Manager",
]

private func demoProfileName(id: Int) -> String {
    demoProfileNames[id] ?? "Profile \(id)"
}

/// Jamf Setup Manager settings as Jamf Pro stores them (Application & Custom Settings).
private let demoSetupManagerPayload = """
<dict><key>PayloadType</key><string>com.apple.ManagedClient.preferences</string><key>PayloadContent</key><dict>\
<key>com.jamf.setupmanager</key><dict><key>Forced</key><array><dict><key>mcx_preference_settings</key><dict>\
<key>title</key><string>Welcome to Acme</string><key>finalAction</key><string>restart</string>\
<key>enrollmentActions</key><array>\
<dict><key>label</key><string>Rosetta 2</string><key>policy</key><string>EnrollRosetta2</string></dict>\
<dict><key>label</key><string>Google Chrome</string><key>policy</key><string>EnrollChrome</string></dict>\
<dict><key>label</key><string>Jamf Connect</string><key>policy</key><string>EnrollJamfConnect</string></dict>\
<dict><key>label</key><string>Sophos</string><key>policy</key><string>EnrollSophos</string></dict>\
<dict><key>label</key><string>1Password</string><key>policy</key><string>Enroll1Password</string></dict>\
<dict><key>label</key><string>Microsoft Teams</string><key>installomator</key><string>microsoftteams</string></dict>\
<dict><key>label</key><string>Inventory</string><key>recon</key><true/></dict>\
</array></dict></dict></array></dict></dict></dict>
"""

/// Minimal profile plists so the deprecation audit rules have something to find in Demo Mode.
private func demoProfilePayloadsPlist(id: Int) -> String {
    let payload: String
    switch id {
    case 3:  payload = "<dict><key>PayloadType</key><string>com.apple.security.firewall</string><key>EnableFirewall</key><true/></dict>"
    case 6:  payload = "<dict><key>PayloadType</key><string>com.apple.vpn.managed</string><key>VPNType</key><string>IKEv2</string></dict>"
    case 8:  payload = "<dict><key>PayloadType</key><string>com.apple.applicationaccess.new</string><key>familyControlsEnabled</key><true/></dict>"
    case 10: payload = "<dict><key>PayloadType</key><string>com.apple.AssetCache.managed</string><key>AllowSharedCaching</key><true/></dict>"
    case 11: payload = "<dict><key>PayloadType</key><string>com.apple.applicationaccess</string><key>forceDelayedSoftwareUpdates</key><true/><key>enforcedSoftwareUpdateDelay</key><integer>30</integer></dict>"
    case 12: payload = "<dict><key>PayloadType</key><string>com.apple.TCC.configuration-profile-policy</string><key>Services</key><dict/></dict>"
    case 13: payload = demoSetupManagerPayload
    default: payload = "<dict><key>PayloadType</key><string>com.apple.loginwindow</string><key>SHOWFULLNAME</key><true/></dict>"
    }
    return """
    <?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>PayloadContent</key><array>\(payload)</array><key>PayloadType</key><string>Configuration</string></dict></plist>
    """
}

private let reportDDMStatusJSON = """
[
  {"declaration":"Software Update Enforcement — macOS 27.0","succeededCount":14,"failedCount":2,"pendingCount":3},
  {"declaration":"Passcode Settings","succeededCount":20,"failedCount":0,"pendingCount":1},
  {"declaration":"Status Subscriptions","succeededCount":21,"failedCount":0,"pendingCount":0},
  {"declaration":"Content Cache Settings","succeededCount":3,"failedCount":1,"pendingCount":0},
  {"declaration":"Background Tasks","succeededCount":18,"failedCount":0,"pendingCount":2}
]
"""

private let softwareUpdatePlansJSON = """
{"totalCount":3,"results":[
  {"planUuid":"6f3c0001-demo","device":{"deviceId":"1","objectType":"COMPUTER"},"updateAction":"DOWNLOAD_INSTALL_SCHEDULE","versionType":"SPECIFIC_VERSION","specificVersion":"27.0.1","forceInstallLocalDateTime":"2026-10-03T18:00:00","status":{"state":"PlanAccepted","errorReasons":[]}},
  {"planUuid":"6f3c0002-demo","device":{"deviceId":"2","objectType":"COMPUTER"},"updateAction":"DOWNLOAD_INSTALL_SCHEDULE","versionType":"LATEST_MINOR","specificVersion":"NO_SPECIFIC_VERSION","status":{"state":"PlanCompleted","errorReasons":[]}},
  {"planUuid":"6f3c0003-demo","device":{"deviceId":"8","objectType":"COMPUTER"},"updateAction":"DOWNLOAD_INSTALL_SCHEDULE","versionType":"SPECIFIC_VERSION","specificVersion":"27.0.1","status":{"state":"PlanFailed","errorReasons":["SPECIFIED_VERSION_NOT_AVAILABLE"]}}
]}
"""

private func softwareUpdatePlansJSON(forComputer id: String) -> String {
    let all: [String: String] = [
        "1": #"{"planUuid":"6f3c0001-demo","device":{"deviceId":"1","objectType":"COMPUTER"},"updateAction":"DOWNLOAD_INSTALL_SCHEDULE","versionType":"SPECIFIC_VERSION","specificVersion":"27.0.1","forceInstallLocalDateTime":"2026-10-03T18:00:00","status":{"state":"PlanAccepted","errorReasons":[]}}"#,
    ]
    return "{\"totalCount\":\(all[id] == nil ? 0 : 1),\"results\":[\(all[id] ?? "")]}"
}

private let softwareUpdateStatusesJSON = """
{"totalCount":3,"results":[
  {"osUpdatesStatusId":"1","device":{"deviceId":"1","objectType":"COMPUTER"},"downloaded":true,"downloadPercentComplete":1.0,"productKey":"macOS 27.0.1","status":"DOWNLOADED","nextScheduledInstall":"2026-10-03T18:00:00"},
  {"osUpdatesStatusId":"2","device":{"deviceId":"2","objectType":"COMPUTER"},"downloaded":false,"downloadPercentComplete":0.0,"productKey":"","status":"IDLE"},
  {"osUpdatesStatusId":"3","device":{"deviceId":"8","objectType":"COMPUTER"},"downloaded":false,"downloadPercentComplete":0.0,"productKey":"macOS 27.0.1","status":"DOWNLOAD_FAILED"}
]}
"""

private let computersUpdateReadinessJSON = """
{"totalCount":8,"results":[
  {"id":"1","general":{"name":"Alice's MacBook Pro","managementId":"aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb","declarativeDeviceManagementEnabled":true},"hardware":{"serialNumber":"C02XA001DEMO"},"operatingSystem":{"version":"27.0"},"configurationProfiles":[{"id":"1","displayName":"Security Baseline"},{"id":"11","displayName":"Software Update Deferrals"}]},
  {"id":"2","general":{"name":"Bob's MacBook Air","managementId":"bbbbbbbb-2222-3333-4444-cccccccccccc","declarativeDeviceManagementEnabled":true},"hardware":{"serialNumber":"C02XA002DEMO"},"operatingSystem":{"version":"27.0"},"configurationProfiles":[{"id":"1","displayName":"Security Baseline"}]},
  {"id":"3","general":{"name":"Charlie's MacBook Pro","managementId":"cccccccc-3333-4444-5555-dddddddddddd","declarativeDeviceManagementEnabled":true},"hardware":{"serialNumber":"C02XA003DEMO"},"operatingSystem":{"version":"27.0"},"configurationProfiles":[]},
  {"id":"4","general":{"name":"Diana's MacBook Air","managementId":"","declarativeDeviceManagementEnabled":false},"hardware":{"serialNumber":"C02XA004DEMO"},"operatingSystem":{"version":"27.0"},"configurationProfiles":[{"id":"11","displayName":"Software Update Deferrals"}]},
  {"id":"6","general":{"name":"Frank's MacBook Pro","declarativeDeviceManagementEnabled":true},"hardware":{"serialNumber":"C02XA006DEMO"},"operatingSystem":{"version":"14.7.4"},"configurationProfiles":[{"id":"11","displayName":"Software Update Deferrals"}]},
  {"id":"8","general":{"name":"Henry's Mac Studio","managementId":"dddddddd-4444-5555-6666-eeeeeeeeeeee","declarativeDeviceManagementEnabled":true},"hardware":{"serialNumber":"C02XA008DEMO"},"operatingSystem":{"version":"27.0"},"configurationProfiles":[]},
  {"id":"10","general":{"name":"Jake's MacBook Air","declarativeDeviceManagementEnabled":false},"hardware":{"serialNumber":"C02XA010DEMO"},"operatingSystem":{"version":"13.7.2"},"configurationProfiles":[]},
  {"id":"11","general":{"name":"Karen's MacBook Pro","declarativeDeviceManagementEnabled":true},"hardware":{"serialNumber":"C02XA011DEMO"},"operatingSystem":{"version":"15.4"},"configurationProfiles":[]}
]}
"""

// MARK: - Release 1.0 additions

private let installedAppsJSON = """
{"totalCount":1,"results":[{"id":"1","general":{"name":"Frank's MacBook Pro"},"applications":[
  {"name":"Google Chrome.app","version":"129.0.6668.90","bundleId":"com.google.Chrome"},
  {"name":"Microsoft Outlook.app","version":"16.89","bundleId":"com.microsoft.Outlook"},
  {"name":"Slack.app","version":"4.40.128","bundleId":"com.tinyspeck.slackmacgap"},
  {"name":"Zoom.us.app","version":"6.2.5","bundleId":"us.zoom.xos"},
  {"name":"Self Service.app","version":"11.10.0","bundleId":"com.jamfsoftware.selfservice.mac"},
  {"name":"Safari.app","version":"26.0","bundleId":"com.apple.Safari"},
  {"name":"Xcode.app","version":"26.0","bundleId":"com.apple.dt.Xcode"}
]}]}
"""

private let blueprintsJSON = """
[
  {"id":"bp-001","name":"Baseline Security"},
  {"id":"bp-002","name":"Wi-Fi and Certificates"},
  {"id":"bp-003","name":"Software Update Deadlines"}
]
"""

private let complianceBenchmarksJSON = """
[
  {"id":"cb-001","name":"CIS macOS Level 1"},
  {"id":"cb-002","name":"NIST 800-53 Moderate"}
]
"""

private let buildingsJSON = """
{"totalCount":3,"results":[{"id":"1","name":"Headquarters"},{"id":"2","name":"Ghent Office"},{"id":"3","name":"Remote"}]}
"""

private let departmentsJSON = """
{"totalCount":4,"results":[{"id":"1","name":"Engineering"},{"id":"2","name":"Finance"},{"id":"3","name":"Marketing"},{"id":"4","name":"IT"}]}
"""

private let networkSegmentsJSON = """
[
  {"id":1,"name":"HQ Wired","startingAddress":"10.10.0.1","endingAddress":"10.10.255.254"},
  {"id":2,"name":"Ghent Wi-Fi","startingAddress":"10.20.0.1","endingAddress":"10.20.15.254"}
]
"""

private let webhooksJSON = """
[
  {"id":1,"name":"Computer Added → Slack","enabled":true,"event":"ComputerAdded"},
  {"id":2,"name":"Policy Finished → SIEM","enabled":false,"event":"ComputerPolicyFinished"}
]
"""

private let schoolProfilesJSON = """
[
  {"id":1,"name":"Classroom Wi-Fi","scope":"All Devices","payloadCount":1,"enabled":true},
  {"id":2,"name":"Restrictions — Grade 5","scope":"Grade 5 iPads","payloadCount":3,"enabled":true},
  {"id":3,"name":"Exam Mode","scope":"Exam Group","payloadCount":2,"enabled":false}
]
"""

private let schoolDepDevicesJSON = """
[
  {"serialNumber":"DMPXK1A2B3C4","model":"iPad (10th generation)","profileName":"Students","status":"Enrolled"},
  {"serialNumber":"DMPXK1A2B3C5","model":"iPad (10th generation)","profileName":"Students","status":"Pending"},
  {"serialNumber":"DMPXK1A2B3C6","model":"iPad Air (M2)","profileName":"Teachers","status":"Enrolled"}
]
"""
