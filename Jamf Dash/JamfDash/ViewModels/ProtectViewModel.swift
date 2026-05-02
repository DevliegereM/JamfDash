import Foundation
import Observation

// MARK: - Protect data models

struct ProtectComputer: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let hostName: String?
    let serialNumber: String?
    let osVersion: String?
    let planName: String?
    let checkinTime: String?
    let connectionStatus: String?
    let fullDiskAccess: String?
    let modelName: String?
    let lastConnectionIp: String?
    let agentVersion: String?
    let webProtectionActive: Bool?
    let signaturesVersion: Int?
    let arch: String?

    private enum CodingKeys: String, CodingKey {
        case id, uuid
        case hostName, hostname
        case serialNumber, serial
        case osVersion, osString
        case planName, plan
        case checkinTime, checkin, lastCheckin, lastSeen
        case connectionStatus, fullDiskAccess, modelName
        case lastConnectionIp, version, webProtectionActive
        case signaturesVersion, arch
    }

    private struct NestedPlan: Decodable { let name: String? }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .uuid) { id = s }
        else if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else { id = String(try c.decode(Int.self, forKey: .id)) }

        hostName     = (try? c.decode(String.self, forKey: .hostName)) ?? (try? c.decode(String.self, forKey: .hostname))
        serialNumber = (try? c.decode(String.self, forKey: .serialNumber)) ?? (try? c.decode(String.self, forKey: .serial))
        osVersion    = (try? c.decode(String.self, forKey: .osVersion)) ?? (try? c.decode(String.self, forKey: .osString))
        planName     = (try? c.decode(String.self, forKey: .planName))
                    ?? (try? c.decode(String.self, forKey: .plan))
                    ?? (try? c.decode(NestedPlan.self, forKey: .plan))?.name
        checkinTime  = (try? c.decode(String.self, forKey: .checkinTime))
                    ?? (try? c.decode(String.self, forKey: .checkin))
                    ?? (try? c.decode(String.self, forKey: .lastCheckin))
                    ?? (try? c.decode(String.self, forKey: .lastSeen))
        connectionStatus  = try? c.decode(String.self, forKey: .connectionStatus)
        fullDiskAccess    = try? c.decode(String.self, forKey: .fullDiskAccess)
        modelName         = try? c.decode(String.self, forKey: .modelName)
        lastConnectionIp  = try? c.decode(String.self, forKey: .lastConnectionIp)
        agentVersion      = try? c.decode(String.self, forKey: .version)
        webProtectionActive = try? c.decode(Bool.self, forKey: .webProtectionActive)
        signaturesVersion = try? c.decode(Int.self, forKey: .signaturesVersion)
        arch              = try? c.decode(String.self, forKey: .arch)
    }

    var displayName: String { hostName ?? serialNumber ?? id }

    var formattedCheckinTime: String? { formatDate(checkinTime) }

    private func formatDate(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
        guard let d = date else { return raw }
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        fmt.timeStyle = .short
        return fmt.string(from: d)
    }
}

/// An individual analytic (alert rule).
/// List response: flat array with name, severity, categories, inputType, jamf.
struct ProtectAnalytic: Decodable, Sendable, Hashable, Identifiable {
    let name: String
    let categories: String?
    let inputType: String?
    let severity: String?
    let jamf: Bool?

    // Name is the natural key — no uuid/id in this response
    var id: String { name }
}

/// An analytic set (collection of analytics).
/// List response: flat array with name, description, analyticsCount, managed, plans, types.
struct ProtectAnalyticSet: Decodable, Sendable, Hashable, Identifiable {
    let name: String
    let description: String?
    let analyticsCount: Int?
    let managed: Bool?
    let plans: String?
    let types: String?

    var id: String { name }
}

/// A Protect plan.
/// List response: flat array with name, actionConfig, autoUpdate, logLevel, telemetry.
struct ProtectPlan: Decodable, Sendable, Hashable, Identifiable {
    let name: String
    let actionConfig: String?
    let autoUpdate: Bool?
    let logLevel: String?
    let telemetry: String?

    var id: String { name }
}

/// A triggered Protect alert event (from `protect alerts list`).
struct ProtectEvent: Decodable, Sendable, Identifiable {
    let id: String
    let analyticName: String?
    let hostName: String?
    let timestamp: String?
    let severity: String?
    let status: String?

    private enum CodingKeys: String, CodingKey {
        case id, uuid
        case analyticName, analytic, ruleName, name
        case hostName, hostname, deviceName
        case timestamp, createdAt, created, date
        case severity
        case status, state
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .uuid) { id = s }
        else if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else { id = String(try c.decode(Int.self, forKey: .id)) }
        analyticName = (try? c.decode(String.self, forKey: .analyticName))
                    ?? (try? c.decode(String.self, forKey: .analytic))
                    ?? (try? c.decode(String.self, forKey: .ruleName))
                    ?? (try? c.decode(String.self, forKey: .name))
        hostName     = (try? c.decode(String.self, forKey: .hostName))
                    ?? (try? c.decode(String.self, forKey: .hostname))
                    ?? (try? c.decode(String.self, forKey: .deviceName))
        timestamp    = (try? c.decode(String.self, forKey: .timestamp))
                    ?? (try? c.decode(String.self, forKey: .createdAt))
                    ?? (try? c.decode(String.self, forKey: .created))
                    ?? (try? c.decode(String.self, forKey: .date))
        severity     = try? c.decode(String.self, forKey: .severity)
        status       = (try? c.decode(String.self, forKey: .status))
                    ?? (try? c.decode(String.self, forKey: .state))
    }

    var formattedTimestamp: String? {
        guard let raw = timestamp else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
        guard let d = date else { return raw }
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        fmt.timeStyle = .short
        return fmt.string(from: d)
    }
}

/// An exception set (returned by exception-sets list, which does have uuid + name).
struct ProtectNamedItem: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String

    private enum CodingKeys: String, CodingKey { case id, uuid, name }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .uuid) { id = s }
        else if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else { id = String(try c.decode(Int.self, forKey: .id)) }
        name = try c.decode(String.self, forKey: .name)
    }
}

/// Detail returned by `protect exception-sets get <name>`.
struct ProtectExceptionSetDetail: Decodable, Sendable {
    let id: String
    let name: String
    let description: String?

    private enum CodingKeys: String, CodingKey { case id, uuid, name, description }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .uuid) { id = s }
        else if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else { id = "" }
        name        = (try? c.decode(String.self, forKey: .name)) ?? ""
        description = try? c.decode(String.self, forKey: .description)
    }
}

// MARK: - New Protect resource models

struct ProtectNamedEntry: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let enabled: Bool?

    private enum CodingKeys: String, CodingKey {
        case id, uuid, name, description, enabled, active
        case filter, defaultMountAction
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let nameVal = (try? c.decode(String.self, forKey: .name)) ?? ""
        if let s = try? c.decode(String.self, forKey: .uuid) { id = s }
        else if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else { id = nameVal }
        name        = nameVal.isEmpty ? id : nameVal
        description = (try? c.decode(String.self, forKey: .description))
                   ?? (try? c.decode(String.self, forKey: .filter))
                   ?? (try? c.decode(String.self, forKey: .defaultMountAction))
        enabled     = (try? c.decode(Bool.self, forKey: .enabled))
                   ?? (try? c.decode(Bool.self, forKey: .active))
    }
}

struct ProtectRole: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let permissions: String

    private enum CodingKeys: String, CodingKey {
        case id, uuid, name, description, permissions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let nameVal = (try? c.decode(String.self, forKey: .name)) ?? ""
        if let s = try? c.decode(String.self, forKey: .uuid) { id = s }
        else if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else { id = nameVal }
        name        = nameVal.isEmpty ? id : nameVal
        description = try? c.decode(String.self, forKey: .description)
        permissions = (try? c.decode(String.self, forKey: .permissions)) ?? ""
    }
}

struct ProtectUser: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let email: String
    let role: String?
    let groups: String?

    private enum CodingKeys: String, CodingKey {
        case id, uuid, email, role, roleName, assignedRoles, groups, assignedGroups
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let emailVal = (try? c.decode(String.self, forKey: .email)) ?? ""
        if let s = try? c.decode(String.self, forKey: .uuid) { id = s }
        else if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else { id = emailVal }
        email  = emailVal
        role   = (try? c.decode(String.self, forKey: .role))
              ?? (try? c.decode(String.self, forKey: .roleName))
              ?? (try? c.decode(String.self, forKey: .assignedRoles))
        groups = (try? c.decode(String.self, forKey: .groups))
              ?? (try? c.decode(String.self, forKey: .assignedGroups))
    }
}

struct ProtectGroup: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let accessGroup: Bool?
    let assignedRoles: String?

    private enum CodingKeys: String, CodingKey {
        case id, uuid, name, accessGroup, assignedRoles
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let nameVal = (try? c.decode(String.self, forKey: .name)) ?? ""
        if let s = try? c.decode(String.self, forKey: .uuid) { id = s }
        else if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else { id = nameVal }
        name         = nameVal.isEmpty ? id : nameVal
        accessGroup  = try? c.decode(Bool.self,   forKey: .accessGroup)
        assignedRoles = try? c.decode(String.self, forKey: .assignedRoles)
    }
}

struct ProtectAPIClient: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let role: String?
    let createdAt: String?

    private enum CodingKeys: String, CodingKey {
        case id, uuid, clientId, name, role, assignedRoles, createdAt, created
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .uuid) { id = s }
        else if let s = try? c.decode(String.self, forKey: .clientId) { id = s }
        else if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else { id = (try? c.decode(String.self, forKey: .name)) ?? "" }
        name      = (try? c.decode(String.self, forKey: .name)) ?? id
        role      = (try? c.decode(String.self, forKey: .role))
                 ?? (try? c.decode(String.self, forKey: .assignedRoles))
        createdAt = (try? c.decode(String.self, forKey: .createdAt))
                 ?? (try? c.decode(String.self, forKey: .created))
    }
}

// MARK: - Rich detail models

struct ProtectULFDetail: Decodable, Sendable {
    let uuid: String?
    let name: String
    let description: String?
    let filter: String?
    let tags: [String]?
    let enabled: Bool?
    let created: String?
    let updated: String?
}

struct ProtectAnalyticDetail: Decodable, Sendable {
    let uuid: String?
    let name: String
    let label: String?
    let inputType: String?
    let filter: String?
    let description: String?
    let longDescription: String?
    let severity: String?
    let tags: [String]?
    let categories: [String]?
    let jamf: Bool?
    let remediation: String?
    let created: String?
    let updated: String?

    struct AnalyticAction: Decodable, Sendable { let name: String? }
    let analyticActions: [AnalyticAction]?
}

// MARK: - ProtectViewModel

@MainActor
@Observable
final class ProtectViewModel {
    private let cli: CLIRunning

    private(set) var overviewState:           LoadState<[OverviewItem]>            = .idle
    private(set) var eventsState:             LoadState<[ProtectEvent]>            = .idle
    private(set) var computersState:          LoadState<[ProtectComputer]>         = .idle
    private(set) var plansState:              LoadState<[ProtectPlan]>             = .idle
    private(set) var analyticsState:          LoadState<[ProtectAnalytic]>         = .idle
    private(set) var analyticSetsState:       LoadState<[ProtectAnalyticSet]>      = .idle
    private(set) var exceptionSetsState:      LoadState<[ProtectNamedItem]>        = .idle
    private(set) var exceptionSetDetailState: LoadState<ProtectExceptionSetDetail> = .idle

    // New Protect resources (Part 2)
    private(set) var computerDetailState:    LoadState<ProtectComputer>       = .idle
    private(set) var ulfDetailState:         LoadState<ProtectULFDetail>      = .idle
    private(set) var analyticDetailState:    LoadState<ProtectAnalyticDetail> = .idle
    private(set) var removableStorageState: LoadState<[ProtectNamedEntry]> = .idle
    private(set) var unifiedLoggingState:   LoadState<[ProtectNamedEntry]> = .idle
    private(set) var actionConfigsState:    LoadState<[ProtectNamedEntry]> = .idle
    private(set) var telemetryState:        LoadState<[ProtectNamedEntry]> = .idle
    private(set) var preventListsState:     LoadState<[ProtectNamedEntry]> = .idle
    private(set) var rolesState:            LoadState<[ProtectRole]>       = .idle
    private(set) var usersState:            LoadState<[ProtectUser]>       = .idle
    private(set) var groupsState:           LoadState<[ProtectGroup]>      = .idle
    private(set) var apiClientsState:       LoadState<[ProtectAPIClient]>  = .idle
    private(set) var dataForwardingState:   LoadState<Data>                = .idle
    private(set) var dataRetentionState:    LoadState<Data>                = .idle
    private(set) var configFreezeState:     LoadState<Data>                = .idle
    private(set) var downloadsState:        LoadState<Data>                = .idle

    init(cli: CLIRunning) {
        self.cli = cli
    }

    // MARK: - Load all

    func load() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadOverview() }
            group.addTask { await self.loadEvents() }
            group.addTask { await self.loadComputers() }
            group.addTask { await self.loadPlans() }
            group.addTask { await self.loadAnalytics() }
            group.addTask { await self.loadAnalyticSets() }
            group.addTask { await self.loadExceptionSets() }
        }
    }

    // MARK: - Individual loaders

    func loadEvents(force: Bool = false) async {
        guard force || eventsState.value == nil else { return }
        guard force || !eventsState.isLoading else { return }
        eventsState = .loading
        do {
            let data  = try await cli.run(.protectEvents)
            let items = try decodeList(ProtectEvent.self, from: data)
            eventsState = .loaded(items)
        } catch {
            eventsState = .failed(error.localizedDescription)
        }
    }

    func loadOverview(force: Bool = false) async {
        guard force || overviewState.value == nil else { return }
        guard force || !overviewState.isLoading else { return }
        overviewState = .loading
        do {
            let data  = try await cli.run(.protectOverview)
            let items = try JSONDecoder().decode([OverviewItem].self, from: data)
            overviewState = .loaded(items)
        } catch {
            overviewState = .failed(error.localizedDescription)
        }
    }

    func loadComputers(force: Bool = false) async {
        guard force || computersState.value == nil else { return }
        guard force || !computersState.isLoading else { return }
        computersState = .loading
        do {
            let data  = try await cli.run(.protectComputers)
            let items = try decodeList(ProtectComputer.self, from: data)
            computersState = .loaded(items)
        } catch {
            computersState = .failed(error.localizedDescription)
        }
    }

    func loadPlans(force: Bool = false) async {
        guard force || plansState.value == nil else { return }
        guard force || !plansState.isLoading else { return }
        plansState = .loading
        do {
            let data  = try await cli.run(.protectPlans)
            let items = try decodeList(ProtectPlan.self, from: data)
            plansState = .loaded(items)
        } catch {
            plansState = .failed(error.localizedDescription)
        }
    }

    func loadAnalytics(force: Bool = false) async {
        guard force || analyticsState.value == nil else { return }
        guard force || !analyticsState.isLoading else { return }
        analyticsState = .loading
        do {
            let data  = try await cli.run(.protectAlerts)
            let items = try decodeList(ProtectAnalytic.self, from: data)
            analyticsState = .loaded(items)
        } catch {
            analyticsState = .failed(error.localizedDescription)
        }
    }

    func loadAnalyticSets(force: Bool = false) async {
        guard force || analyticSetsState.value == nil else { return }
        guard force || !analyticSetsState.isLoading else { return }
        analyticSetsState = .loading
        do {
            let data  = try await cli.run(.protectInsights)
            let items = try decodeList(ProtectAnalyticSet.self, from: data)
            analyticSetsState = .loaded(items)
        } catch {
            analyticSetsState = .failed(error.localizedDescription)
        }
    }

    func loadExceptionSets(force: Bool = false) async {
        guard force || exceptionSetsState.value == nil else { return }
        guard force || !exceptionSetsState.isLoading else { return }
        exceptionSetsState = .loading
        do {
            let data  = try await cli.run(.protectAuditLogs)
            let items = try decodeList(ProtectNamedItem.self, from: data)
            exceptionSetsState = .loaded(items)
        } catch {
            exceptionSetsState = .failed(error.localizedDescription)
        }
    }

    func loadULFDetail(name: String) async {
        ulfDetailState = .loading
        do {
            let data   = try await cli.run(.protectUnifiedLoggingDetail(name: name))
            let detail = try JSONDecoder().decode(ProtectULFDetail.self, from: data)
            ulfDetailState = .loaded(detail)
        } catch {
            ulfDetailState = .failed(error.localizedDescription)
        }
    }

    func loadAnalyticDetail(name: String) async {
        analyticDetailState = .loading
        do {
            let data   = try await cli.run(.protectAnalyticDetail(name: name))
            let detail = try JSONDecoder().decode(ProtectAnalyticDetail.self, from: data)
            analyticDetailState = .loaded(detail)
        } catch {
            analyticDetailState = .failed(error.localizedDescription)
        }
    }

    func loadComputerDetail(name: String) async {
        computerDetailState = .loading
        do {
            let data   = try await cli.run(.protectComputerDetail(name: name))
            let detail = try JSONDecoder().decode(ProtectComputer.self, from: data)
            computerDetailState = .loaded(detail)
        } catch {
            computerDetailState = .failed(error.localizedDescription)
        }
    }

    func loadRemovableStorage(force: Bool = false) async {
        guard force || removableStorageState.value == nil else { return }
        guard force || !removableStorageState.isLoading else { return }
        removableStorageState = .loading
        do { removableStorageState = .loaded(try decodeList(ProtectNamedEntry.self, from: try await cli.run(.protectRemovableStorage))) }
        catch { removableStorageState = .failed(error.localizedDescription) }
    }

    func loadUnifiedLogging(force: Bool = false) async {
        guard force || unifiedLoggingState.value == nil else { return }
        guard force || !unifiedLoggingState.isLoading else { return }
        unifiedLoggingState = .loading
        do { unifiedLoggingState = .loaded(try decodeList(ProtectNamedEntry.self, from: try await cli.run(.protectUnifiedLogging))) }
        catch { unifiedLoggingState = .failed(error.localizedDescription) }
    }

    func loadActionConfigs(force: Bool = false) async {
        guard force || actionConfigsState.value == nil else { return }
        guard force || !actionConfigsState.isLoading else { return }
        actionConfigsState = .loading
        do { actionConfigsState = .loaded(try decodeList(ProtectNamedEntry.self, from: try await cli.run(.protectActionConfigs))) }
        catch { actionConfigsState = .failed(error.localizedDescription) }
    }

    func loadTelemetry(force: Bool = false) async {
        guard force || telemetryState.value == nil else { return }
        guard force || !telemetryState.isLoading else { return }
        telemetryState = .loading
        do { telemetryState = .loaded(try decodeList(ProtectNamedEntry.self, from: try await cli.run(.protectTelemetryConfigs))) }
        catch { telemetryState = .failed(error.localizedDescription) }
    }

    func loadPreventLists(force: Bool = false) async {
        guard force || preventListsState.value == nil else { return }
        guard force || !preventListsState.isLoading else { return }
        preventListsState = .loading
        do { preventListsState = .loaded(try decodeList(ProtectNamedEntry.self, from: try await cli.run(.protectCustomPreventLists))) }
        catch { preventListsState = .failed(error.localizedDescription) }
    }

    func loadRoles(force: Bool = false) async {
        guard force || rolesState.value == nil else { return }
        guard force || !rolesState.isLoading else { return }
        rolesState = .loading
        do { rolesState = .loaded(try decodeList(ProtectRole.self, from: try await cli.run(.protectRoles))) }
        catch { rolesState = .failed(error.localizedDescription) }
    }

    func loadUsers(force: Bool = false) async {
        guard force || usersState.value == nil else { return }
        guard force || !usersState.isLoading else { return }
        usersState = .loading
        do { usersState = .loaded(try decodeList(ProtectUser.self, from: try await cli.run(.protectUsers))) }
        catch { usersState = .failed(error.localizedDescription) }
    }

    func loadGroups(force: Bool = false) async {
        guard force || groupsState.value == nil else { return }
        guard force || !groupsState.isLoading else { return }
        groupsState = .loading
        do { groupsState = .loaded(try decodeList(ProtectGroup.self, from: try await cli.run(.protectGroups))) }
        catch { groupsState = .failed(error.localizedDescription) }
    }

    func loadAPIClients(force: Bool = false) async {
        guard force || apiClientsState.value == nil else { return }
        guard force || !apiClientsState.isLoading else { return }
        apiClientsState = .loading
        do { apiClientsState = .loaded(try decodeList(ProtectAPIClient.self, from: try await cli.run(.protectAPIClients))) }
        catch { apiClientsState = .failed(error.localizedDescription) }
    }

    func loadDataForwarding(force: Bool = false) async {
        guard force || dataForwardingState.value == nil else { return }
        guard force || !dataForwardingState.isLoading else { return }
        dataForwardingState = .loading
        do { dataForwardingState = .loaded(try await cli.run(.protectDataForwarding)) }
        catch { dataForwardingState = .failed(error.localizedDescription) }
    }

    func loadDataRetention(force: Bool = false) async {
        guard force || dataRetentionState.value == nil else { return }
        guard force || !dataRetentionState.isLoading else { return }
        dataRetentionState = .loading
        do { dataRetentionState = .loaded(try await cli.run(.protectDataRetention)) }
        catch { dataRetentionState = .failed(error.localizedDescription) }
    }

    func loadConfigFreeze(force: Bool = false) async {
        guard force || configFreezeState.value == nil else { return }
        guard force || !configFreezeState.isLoading else { return }
        configFreezeState = .loading
        do { configFreezeState = .loaded(try await cli.run(.protectConfigFreeze)) }
        catch { configFreezeState = .failed(error.localizedDescription) }
    }

    func loadDownloads(force: Bool = false) async {
        guard force || downloadsState.value == nil else { return }
        guard force || !downloadsState.isLoading else { return }
        downloadsState = .loading
        do { downloadsState = .loaded(try await cli.run(.protectDownloadsSummary)) }
        catch { downloadsState = .failed(error.localizedDescription) }
    }

    func loadExceptionSetDetail(name: String) async {
        exceptionSetDetailState = .loading
        do {
            let data   = try await cli.run(.protectExceptionSetDetail(name: name))
            let detail = try JSONDecoder().decode(ProtectExceptionSetDetail.self, from: data)
            exceptionSetDetailState = .loaded(detail)
        } catch {
            exceptionSetDetailState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Overview derived

    var overviewSections: [(title: String, items: [OverviewItem])] {
        guard case .loaded(let items) = overviewState else { return [] }
        let grouped = Dictionary(grouping: items, by: \.section)
        return grouped.keys.sorted().compactMap { section in
            guard let group = grouped[section], !group.isEmpty else { return nil }
            return (title: section, items: group)
        }
    }

    // MARK: - Helpers

    private func decodeList<T: Decodable>(_ type: T.Type, from data: Data) throws -> [T] {
        let decoder = JSONDecoder()
        if let items = try? decoder.decode([T].self, from: data) { return items }
        if let paged = try? decoder.decode(ProtectItemsPaged<T>.self, from: data) { return paged.items }
        if let paged = try? decoder.decode(ProtectResultsPaged<T>.self, from: data) { return paged.results }
        let preview = String(data: data.prefix(800), encoding: .utf8) ?? "<binary>"
        throw NSError(domain: "ProtectDecoding", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Unrecognized JSON shape — raw response: \(preview)"])
    }
}

private struct ProtectItemsPaged<T: Decodable>: Decodable { let items: [T] }
private struct ProtectResultsPaged<T: Decodable>: Decodable { let results: [T] }
