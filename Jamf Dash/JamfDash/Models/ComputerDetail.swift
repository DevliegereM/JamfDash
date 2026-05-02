import Foundation

/// Rich device inventory record returned by `jamf-cli pro comp get <serial>`.
/// All nested sections and most leaf fields are optional so the model degrades
/// gracefully across different jamf-cli / Jamf Pro API versions.
struct ComputerDetail: Decodable, Sendable, Identifiable {

    let id: String
    let name: String

    // Top-level flat fields (present in simpler CLI output)
    let serialNumber: String?
    let udid: String?
    let managed: Bool?
    let platform: String?

    // Nested sections (present in full Pro API v1 response)
    let general: GeneralInfo?
    let hardware: HardwareInfo?
    let operatingSystem: OSInfo?
    let security: SecurityInfo?
    let location: LocationInfo?
    let diskEncryption: DiskEncryptionInfo?
    let network: NetworkInfo?
    let purchasing: PurchasingInfo?
    let storage: StorageInfo?
    let groupMemberships: [GroupMembership]?
    let localUserAccounts: [LocalUserAccount]?
    let softwareUpdates: [SoftwareUpdate]?
    let extensionAttributes: [ExtensionAttribute]?
    let configurationProfiles: [AssignedConfigProfile]?

    // MARK: - CodingKeys

    private enum CodingKeys: String, CodingKey {
        case id, name, managed, platform, udid
        case serialNumber, serial
        case general, hardware, operatingSystem, security
        case location, diskEncryption, network
        case purchasing, storage
        case groupMemberships, localUserAccounts
        case softwareUpdates, extensionAttributes
        case configurationProfiles
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let strID = try? c.decode(String.self, forKey: .id) {
            id = strID
        } else {
            id = String(try c.decode(Int.self, forKey: .id))
        }

        // Decode general first so we can fall back to general.name for Pro API v2 responses
        let gen = try? c.decode(GeneralInfo.self, forKey: .general)
        name = (try? c.decode(String.self, forKey: .name)) ?? gen?.name ?? id

        managed  = try? c.decode(Bool.self,   forKey: .managed)
        platform = try? c.decode(String.self, forKey: .platform)
        udid     = try? c.decode(String.self, forKey: .udid)
        serialNumber = (try? c.decode(String.self, forKey: .serialNumber))
                    ?? (try? c.decode(String.self, forKey: .serial))

        general              = gen
        hardware             = try? c.decode(HardwareInfo.self,          forKey: .hardware)
        operatingSystem      = try? c.decode(OSInfo.self,                forKey: .operatingSystem)
        security             = try? c.decode(SecurityInfo.self,          forKey: .security)
        location             = try? c.decode(LocationInfo.self,          forKey: .location)
        diskEncryption       = try? c.decode(DiskEncryptionInfo.self,    forKey: .diskEncryption)
        network              = try? c.decode(NetworkInfo.self,           forKey: .network)
        purchasing           = try? c.decode(PurchasingInfo.self,        forKey: .purchasing)
        storage              = try? c.decode(StorageInfo.self,           forKey: .storage)
        groupMemberships     = try? c.decode([GroupMembership].self,     forKey: .groupMemberships)
        localUserAccounts    = try? c.decode([LocalUserAccount].self,    forKey: .localUserAccounts)
        softwareUpdates      = try? c.decode([SoftwareUpdate].self,      forKey: .softwareUpdates)
        extensionAttributes  = try? c.decode([ExtensionAttribute].self,  forKey: .extensionAttributes)
        configurationProfiles = try? c.decode([AssignedConfigProfile].self, forKey: .configurationProfiles)
    }

    // MARK: - Nested types

    struct GeneralInfo: Decodable, Sendable {
        let name: String?
        let lastIpAddress: String?
        let jamfBinaryVersion: String?
        let assetTag: String?
        let barcode1: String?
        let barcode2: String?
        let supervised: Bool?
        let mdmCapable: Bool?
        let userApprovedMdm: Bool?
        let enrollmentMethod: String?
        let declarativeDeviceManagementEnabled: Bool?
        let lastContactTime: String?
        let lastEnrolledDate: String?
        let initialEntryDate: String?
        let remoteManagement: RemoteManagement?

        struct RemoteManagement: Decodable, Sendable {
            let managed: Bool?
            let managementUsername: String?
        }
    }

    struct HardwareInfo: Decodable, Sendable {
        let make: String?
        let model: String?
        let modelId: String?
        let serialNumber: String?
        let cpuType: String?
        let cpuSpeedMHz: Int?
        let ramMegabytes: Int?
        let batteryCapacityPercent: Int?
        let storageSizeBytes: Int?
        let macAddress: String?
        let altMacAddress: String?
        let bluetoothMacAddress: String?
        let processorCount: Int?
        let coreCount: Int?
        let busSpeedMHz: Int?
        let cacheKilobytes: Int?
        let availableRamSlots: Int?
        let opticalDrive: String?
        let nicSpeed: String?
        let smcVersion: String?
        let openFirmwarePasswordStatus: String?
        let supportsIosAppInstalls: Bool?
        let isAppleSilicon: Bool?
    }

    struct OSInfo: Decodable, Sendable {
        let name: String?
        let version: String?
        let build: String?
        let supplementalBuildVersion: String?
        let rapidSecurityResponse: String?
        let activeDirectoryStatus: String?
        let fileVault2Status: String?
        let softwareUpdateDeviceId: String?
    }

    struct SecurityInfo: Decodable, Sendable {
        let sipStatus: String?
        let gatekeeperStatus: String?
        let xprotectVersion: String?
        let autoLoginDisabled: Bool?
        let remoteDesktopEnabled: Bool?
        let activationLockEnabled: Bool?
        let recoveryLockEnabled: Bool?
        let firewallEnabled: Bool?
        let secureBootLevel: String?
        let externalBootLevel: String?
        let bootstrapTokenAllowed: Bool?
        let bootstrapTokenEscrowedStatus: String?
        let isActivationLockManageable: Bool?
    }

    struct LocationInfo: Decodable, Sendable {
        let username: String?
        let realName: String?
        let email: String?
        let position: String?
        let phone: String?
        let departmentName: String?
        let buildingName: String?
        let room: String?
    }

    struct DiskEncryptionInfo: Decodable, Sendable {
        let bootPartitionEncryptionDetails: BootPartition?
        let individualRecoveryKeyValidityStatus: String?
        let institutionalRecoveryKeyPresent: Bool?
        let diskEncryptionConfigurationName: String?

        struct BootPartition: Decodable, Sendable {
            let partitionName: String?
            let partitionFileVault2State: String?
            let partitionFileVault2Percent: Int?
        }
    }

    struct NetworkInfo: Decodable, Sendable {
        let boundIpAddress: String?
        let lastIpAddress: String?
        let networkAdapters: [NetworkAdapter]?

        struct NetworkAdapter: Decodable, Sendable, Identifiable {
            var id: String { macAddress ?? displayName ?? UUID().uuidString }
            let displayName: String?
            let macAddress: String?
            let ipAddress: String?
            let type: String?
        }
    }

    struct PurchasingInfo: Decodable, Sendable {
        let leased: Bool?
        let purchased: Bool?
        let poNumber: String?
        let poDate: String?
        let vendor: String?
        let warrantyDate: String?
        let appleCareId: String?
        let leaseDate: String?
        let purchasePrice: String?
        let purchasingAccount: String?
        let purchasingContact: String?
        let lifeExpectancy: Int?
    }

    struct StorageInfo: Decodable, Sendable {
        let bootDriveAvailableSpaceMegabytes: Int?
        let disks: [Disk]?

        struct Disk: Decodable, Sendable, Identifiable {
            var id: String { device ?? serialNumber ?? UUID().uuidString }
            let device: String?
            let model: String?
            let serialNumber: String?
            let sizeMegabytes: Int?
            let smartStatus: String?
            let type: String?
            let partitions: [Partition]?

            struct Partition: Decodable, Sendable, Identifiable {
                var id: String { name ?? UUID().uuidString }
                let name: String?
                let sizeMegabytes: Int?
                let availableMegabytes: Int?
                let percentUsed: Int?
                let fileVault2State: String?
                let fileVault2Percent: Int?
                let lvgUUID: String?
                let lvUUID: String?
                let pvUUID: String?
                let isEncrypted: Bool?
                let type: String?
            }
        }
    }

    struct GroupMembership: Decodable, Sendable, Identifiable {
        var id: String { groupId ?? groupName ?? UUID().uuidString }
        let groupId: String?
        let groupName: String?
        let smartGroup: Bool?
    }

    struct LocalUserAccount: Decodable, Sendable, Identifiable {
        var id: String { uid ?? username ?? UUID().uuidString }
        let uid: String?
        let username: String?
        let fullName: String?
        let home: String?
        let homeSize: String?
        let admin: Bool?
        let fileVault2Enabled: Bool?
        let azureActiveDirectoryId: String?
        let userAccountType: String?
        let passwordMinLength: Int?
        let passwordMaxAge: Int?
        let passwordMinComplexCharacters: Int?
        let passwordHistoryDepth: Int?
        let passwordRequireAlphanumeric: Bool?
        let computerAzureActiveDirectoryId: String?
    }

    struct SoftwareUpdate: Decodable, Sendable, Identifiable {
        var id: String { name ?? UUID().uuidString }
        let name: String?
        let version: String?
        let packageName: String?
    }

    struct ExtensionAttribute: Decodable, Sendable, Identifiable {
        var id: String { definitionId ?? name ?? UUID().uuidString }
        let definitionId: String?
        let name: String?
        let description: String?
        let enabled: Bool?
        let multiValue: Bool?
        let values: [String]?
        let dataType: String?
        let inputType: String?
    }

    struct AssignedConfigProfile: Decodable, Sendable, Identifiable {
        var id: String { profileId ?? displayName ?? UUID().uuidString }
        let profileId: String?
        let displayName: String?
        let version: String?
        let removable: Bool?
        let lastInstalled: String?
        let state: String?
    }

    // MARK: - Computed convenience

    var effectiveSerial: String   { serialNumber ?? hardware?.serialNumber ?? "—" }
    var effectiveIP: String?      { general?.lastIpAddress ?? network?.lastIpAddress ?? network?.boundIpAddress }
    var effectiveOS: String?      { operatingSystem?.version }
    var effectiveOSBuild: String? { operatingSystem?.build }
    var effectiveModel: String?   { hardware?.model }

    var effectiveRAM: String? {
        guard let mb = hardware?.ramMegabytes else { return nil }
        return mb >= 1024 ? "\(mb / 1024) GB" : "\(mb) MB"
    }

    var effectiveBattery: String? {
        hardware?.batteryCapacityPercent.map { "\($0)%" }
    }

    var effectiveDiskFree: String? {
        guard let mb = storage?.bootDriveAvailableSpaceMegabytes else { return nil }
        return mb >= 1024 ? "\(mb / 1024) GB free" : "\(mb) MB free"
    }

    var isManaged: Bool {
        managed ?? general?.remoteManagement?.managed ?? false
    }

    var isSIPEnabled: Bool? {
        security?.sipStatus.map { $0.uppercased() == "ENABLED" }
    }

    var isGatekeeperEnabled: Bool? {
        security?.gatekeeperStatus.map { !$0.uppercased().contains("DISABLED") }
    }

    var isFileVaultEnabled: Bool? {
        diskEncryption?.bootPartitionEncryptionDetails?.partitionFileVault2State
            .map { $0.uppercased().contains("ENCRYPT") }
    }

    var isFirewallEnabled: Bool? { security?.firewallEnabled }

    var pendingSoftwareUpdateCount: Int { softwareUpdates?.count ?? 0 }

    var smartGroupNames: [String] {
        (groupMemberships ?? []).filter { $0.smartGroup == true }.compactMap { $0.groupName }
    }

    var staticGroupNames: [String] {
        (groupMemberships ?? []).filter { $0.smartGroup != true }.compactMap { $0.groupName }
    }
}
