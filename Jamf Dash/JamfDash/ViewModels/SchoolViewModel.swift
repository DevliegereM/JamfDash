import Foundation
import OSLog
import Observation

// MARK: - School data models

struct SchoolDevice: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String?
    let serialNumber: String?
    let model: String?
    let osVersion: String?
    let managed: Bool?

    private enum CodingKeys: String, CodingKey {
        case id, name, serialNumber, model, osVersion, managed
        case serial, deviceModel, version
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else { id = String(try c.decode(Int.self, forKey: .id)) }
        name         = try? c.decode(String.self, forKey: .name)
        serialNumber = (try? c.decode(String.self, forKey: .serialNumber)) ?? (try? c.decode(String.self, forKey: .serial))
        model        = (try? c.decode(String.self, forKey: .model))        ?? (try? c.decode(String.self, forKey: .deviceModel))
        osVersion    = (try? c.decode(String.self, forKey: .osVersion))    ?? (try? c.decode(String.self, forKey: .version))
        managed      = try? c.decode(Bool.self, forKey: .managed)
    }

    var displayName: String { name ?? serialNumber ?? id }
}

struct SchoolUser: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String?
    let email: String?
    let username: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, email, username
        case displayName, userPrincipalName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else { id = String(try c.decode(Int.self, forKey: .id)) }
        name     = (try? c.decode(String.self, forKey: .name))     ?? (try? c.decode(String.self, forKey: .displayName))
        email    = try? c.decode(String.self, forKey: .email)
        username = (try? c.decode(String.self, forKey: .username))  ?? (try? c.decode(String.self, forKey: .userPrincipalName))
    }

    var displayName: String { name ?? username ?? email ?? id }
}

struct SchoolNamedItem: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else { id = String(try c.decode(Int.self, forKey: .id)) }
        name = try c.decode(String.self, forKey: .name)
    }

    private enum CodingKeys: String, CodingKey { case id, name }
}

// MARK: - SchoolViewModel

@MainActor
@Observable
final class SchoolViewModel {
    private static let logger = Logger(subsystem: "com.jamfdash", category: "SchoolViewModel")
    private let cli: CLIRunning

    private(set) var overviewState:      LoadState<[OverviewItem]>      = .idle
    private(set) var devicesState:       LoadState<[SchoolDevice]>      = .idle
    private(set) var deviceGroupsState:  LoadState<[SchoolNamedItem]>   = .idle
    private(set) var usersState:         LoadState<[SchoolUser]>        = .idle
    private(set) var userGroupsState:    LoadState<[SchoolNamedItem]>   = .idle
    private(set) var classesState:       LoadState<[SchoolNamedItem]>   = .idle
    private(set) var appsState:          LoadState<[SchoolNamedItem]>   = .idle

    init(cli: CLIRunning) {
        self.cli = cli
    }

    // MARK: - Load all

    func load() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadOverview() }
            group.addTask { await self.loadDevices() }
            group.addTask { await self.loadDeviceGroups() }
            group.addTask { await self.loadUsers() }
            group.addTask { await self.loadUserGroups() }
            group.addTask { await self.loadClasses() }
            group.addTask { await self.loadApps() }
        }
    }

    // MARK: - Individual loaders

    func loadOverview(force: Bool = false) async {
        guard force || overviewState.value == nil else { return }
        guard force || !overviewState.isLoading else { return }
        Self.logger.debug("Loading school overview")
        overviewState = .loading
        do {
            let data  = try await cli.run(.schoolOverview)
            let items = try JSONDecoder().decode([OverviewItem].self, from: data)
            Self.logger.debug("Loaded \(items.count) school overview items")
            overviewState = .loaded(items)
        } catch {
            Self.logger.error("Failed to load school overview: \(error)")
            overviewState = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    func loadDevices(force: Bool = false) async {
        guard force || devicesState.value == nil else { return }
        guard force || !devicesState.isLoading else { return }
        Self.logger.debug("Loading school devices")
        devicesState = .loading
        do {
            let data  = try await cli.run(.schoolDevices)
            let items = try decodeList(SchoolDevice.self, from: data)
            Self.logger.debug("Loaded \(items.count) school devices")
            devicesState = .loaded(items)
        } catch {
            Self.logger.error("Failed to load school devices: \(error)")
            devicesState = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    func loadDeviceGroups(force: Bool = false) async {
        guard force || deviceGroupsState.value == nil else { return }
        guard force || !deviceGroupsState.isLoading else { return }
        Self.logger.debug("Loading school device groups")
        deviceGroupsState = .loading
        do {
            let data  = try await cli.run(.schoolDeviceGroups)
            let items = try decodeList(SchoolNamedItem.self, from: data)
            Self.logger.debug("Loaded \(items.count) school device groups")
            deviceGroupsState = .loaded(items)
        } catch {
            Self.logger.error("Failed to load school device groups: \(error)")
            deviceGroupsState = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    func loadUsers(force: Bool = false) async {
        guard force || usersState.value == nil else { return }
        guard force || !usersState.isLoading else { return }
        Self.logger.debug("Loading school users")
        usersState = .loading
        do {
            let data  = try await cli.run(.schoolUsers)
            let items = try decodeList(SchoolUser.self, from: data)
            Self.logger.debug("Loaded \(items.count) school users")
            usersState = .loaded(items)
        } catch {
            Self.logger.error("Failed to load school users: \(error)")
            usersState = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    func loadUserGroups(force: Bool = false) async {
        guard force || userGroupsState.value == nil else { return }
        guard force || !userGroupsState.isLoading else { return }
        Self.logger.debug("Loading school user groups")
        userGroupsState = .loading
        do {
            let data  = try await cli.run(.schoolUserGroups)
            let items = try decodeList(SchoolNamedItem.self, from: data)
            Self.logger.debug("Loaded \(items.count) school user groups")
            userGroupsState = .loaded(items)
        } catch {
            Self.logger.error("Failed to load school user groups: \(error)")
            userGroupsState = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    func loadClasses(force: Bool = false) async {
        guard force || classesState.value == nil else { return }
        guard force || !classesState.isLoading else { return }
        Self.logger.debug("Loading school classes")
        classesState = .loading
        do {
            let data  = try await cli.run(.schoolClasses)
            let items = try decodeList(SchoolNamedItem.self, from: data)
            Self.logger.debug("Loaded \(items.count) school classes")
            classesState = .loaded(items)
        } catch {
            Self.logger.error("Failed to load school classes: \(error)")
            classesState = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    func loadApps(force: Bool = false) async {
        guard force || appsState.value == nil else { return }
        guard force || !appsState.isLoading else { return }
        Self.logger.debug("Loading school apps")
        appsState = .loading
        do {
            let data  = try await cli.run(.schoolApps)
            let items = try decodeList(SchoolNamedItem.self, from: data)
            Self.logger.debug("Loaded \(items.count) school apps")
            appsState = .loaded(items)
        } catch {
            Self.logger.error("Failed to load school apps: \(error)")
            appsState = .failed(ErrorMessageFormatter.message(for: error))
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
        if let paged = try? decoder.decode(SchoolItemsPaged<T>.self, from: data) { return paged.items }
        if let paged = try? decoder.decode(SchoolResultsPaged<T>.self, from: data) { return paged.results }
        let preview = String(data: data.prefix(800), encoding: .utf8) ?? "<binary>"
        throw NSError(domain: "SchoolDecoding", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Unrecognized JSON shape — raw response: \(preview)"])
    }
}

private struct SchoolItemsPaged<T: Decodable>: Decodable { let items: [T] }
private struct SchoolResultsPaged<T: Decodable>: Decodable { let results: [T] }
