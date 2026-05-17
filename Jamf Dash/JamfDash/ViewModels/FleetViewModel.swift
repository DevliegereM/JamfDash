import Foundation
import OSLog
import Observation

@MainActor
@Observable
final class FleetViewModel {
    private static let logger = Logger(subsystem: "com.jamfdash", category: "FleetViewModel")
    private(set) var policiesState:       LoadState<[Policy]> = .idle
    private(set) var groupsState:         LoadState<[SmartComputerGroup]> = .idle
    private(set) var scriptsState:        LoadState<[JamfScript]> = .idle
    private(set) var packagesState:       LoadState<[JamfPackage]> = .idle
    private(set) var configProfilesState: LoadState<[ConfigProfile]> = .idle
    private(set) var smartGroupDetailState:    LoadState<SmartGroupDetail>  = .idle
    private(set) var policyDetailState:        LoadState<JamfScope>         = .idle
    private(set) var configProfileDetailState: LoadState<JamfScope>         = .idle
    private(set) var scriptDetailState:        LoadState<JamfScriptDetail>  = .idle
    private(set) var packageDetailState:       LoadState<JamfPackageDetail> = .idle

    // MARK: New Pro resources
    private(set) var buildingsState:              LoadState<[Building]>              = .idle
    private(set) var departmentsState:            LoadState<[Department]>            = .idle
    private(set) var networkSegmentsState:        LoadState<[NetworkSegment]>        = .idle
    private(set) var extensionAttributesState:    LoadState<[ExtensionAttribute]>    = .idle
    private(set) var patchTitlesState:            LoadState<[PatchTitle]>            = .idle
    private(set) var patchPoliciesState:          LoadState<[PatchPolicy]>           = .idle
    private(set) var patchTitleDetailState:       LoadState<PatchTitleDetail>        = .idle
    private(set) var patchPolicyDetailState:      LoadState<PatchPolicyDetail>       = .idle
    private(set) var depTokensState:              LoadState<[DEPToken]>              = .idle
    private(set) var computerPrestagesState:      LoadState<[ComputerPrestage]>      = .idle
    private(set) var mobileDevicePrestagesState:  LoadState<[MobileDevicePrestage]>  = .idle
    private(set) var webhooksState:               LoadState<[JamfWebhook]>           = .idle

    var searchText = ""

    private(set) var policyCategoryMap:       [Int: String] = [:]
    private(set) var configProfileCategoryMap: [Int: String] = [:]

    private let repository: FleetRepository

    init(repository: FleetRepository) {
        self.repository = repository
    }

    func loadAll(force: Bool = false) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadPolicies(force: force) }
            group.addTask { await self.loadGroups(force: force) }
            group.addTask { await self.loadScripts(force: force) }
            group.addTask { await self.loadPackages(force: force) }
            group.addTask { await self.loadConfigProfiles(force: force) }
        }
    }

    func loadPolicies(force: Bool = false) async {
        guard force || policiesState.value == nil else { return }
        guard force || !policiesState.isLoading else { return }
        Self.logger.debug("Loading policies")
        policiesState = .loading
        do {
            let policies = try await repository.fetchPolicies()
            Self.logger.debug("Loaded \(policies.count) policies")
            policiesState = .loaded(policies)
            let uncategorized = policies.filter { $0.category == nil }
            if !uncategorized.isEmpty {
                Task { policyCategoryMap = await repository.fetchPolicyCategoryMap(for: uncategorized) }
            }
        }
        catch {
            Self.logger.error("Failed to load policies: \(error)")
            policiesState = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    func loadGroups(force: Bool = false) async {
        guard force || groupsState.value == nil else { return }
        guard force || !groupsState.isLoading else { return }
        Self.logger.debug("Loading smart groups")
        groupsState = .loading
        do {
            let groups = try await repository.fetchSmartGroups()
            Self.logger.debug("Loaded \(groups.count) smart groups")
            groupsState = .loaded(groups)
        }
        catch {
            Self.logger.error("Failed to load smart groups: \(error)")
            groupsState = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    func loadScripts(force: Bool = false) async {
        guard force || scriptsState.value == nil else { return }
        guard force || !scriptsState.isLoading else { return }
        Self.logger.debug("Loading scripts")
        scriptsState = .loading
        do {
            let scripts = try await repository.fetchScripts()
            Self.logger.debug("Loaded \(scripts.count) scripts")
            scriptsState = .loaded(scripts)
        }
        catch {
            Self.logger.error("Failed to load scripts: \(error)")
            scriptsState = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    func loadPackages(force: Bool = false) async {
        guard force || packagesState.value == nil else { return }
        guard force || !packagesState.isLoading else { return }
        Self.logger.debug("Loading packages")
        packagesState = .loading
        do {
            let packages = try await repository.fetchPackages()
            Self.logger.debug("Loaded \(packages.count) packages")
            packagesState = .loaded(packages)
        }
        catch {
            Self.logger.error("Failed to load packages: \(error)")
            packagesState = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    func loadConfigProfiles(force: Bool = false) async {
        guard force || configProfilesState.value == nil else { return }
        guard force || !configProfilesState.isLoading else { return }
        Self.logger.debug("Loading config profiles")
        configProfilesState = .loading
        do {
            let profiles = try await repository.fetchConfigProfiles()
            Self.logger.debug("Loaded \(profiles.count) config profiles")
            configProfilesState = .loaded(profiles)
            Task { configProfileCategoryMap = await repository.fetchConfigProfileCategoryMap(for: profiles) }
        }
        catch {
            Self.logger.error("Failed to load config profiles: \(error)")
            configProfilesState = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    func loadSmartGroupDetail(id: String) async {
        smartGroupDetailState = .loading
        do { smartGroupDetailState = .loaded(try await repository.fetchSmartGroupDetail(id: id)) }
        catch {
            Self.logger.error("Failed to load smart group detail (\(id)): \(error)")
            smartGroupDetailState = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    func loadPolicyScope(id: Int) async {
        policyDetailState = .loading
        do { policyDetailState = .loaded(try await repository.fetchPolicyScope(id: id)) }
        catch {
            Self.logger.error("Failed to load policy scope (\(id)): \(error)")
            policyDetailState = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    func loadConfigProfileScope(id: Int) async {
        configProfileDetailState = .loading
        do { configProfileDetailState = .loaded(try await repository.fetchConfigProfileScope(id: id)) }
        catch {
            Self.logger.error("Failed to load config profile scope (\(id)): \(error)")
            configProfileDetailState = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    func loadScriptDetail(id: String) async {
        scriptDetailState = .loading
        do {
            let data = try await repository.cli.run(.scriptDetail(id: id))
            scriptDetailState = .loaded(try JSONDecoder().decode(JamfScriptDetail.self, from: data))
        } catch {
            Self.logger.error("Failed to load script detail (\(id)): \(error)")
            scriptDetailState = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    func loadPackageDetail(id: Int) async {
        packageDetailState = .loading
        do {
            let data = try await repository.cli.run(.packageDetail(id: id))
            packageDetailState = .loaded(try JSONDecoder().decode(JamfPackageDetail.self, from: data))
        } catch {
            Self.logger.error("Failed to load package detail (\(id)): \(error)")
            packageDetailState = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    // MARK: - New Pro resource loaders

    func loadBuildings(force: Bool = false) async {
        guard force || buildingsState.value == nil else { return }
        guard force || !buildingsState.isLoading else { return }
        buildingsState = .loading
        do { buildingsState = .loaded(try await repository.fetchList(Building.self, command: .buildings)) }
        catch { Self.logger.error("Failed to load buildings: \(error)"); buildingsState = .failed(ErrorMessageFormatter.message(for: error)) }
    }

    func loadDepartments(force: Bool = false) async {
        guard force || departmentsState.value == nil else { return }
        guard force || !departmentsState.isLoading else { return }
        departmentsState = .loading
        do { departmentsState = .loaded(try await repository.fetchList(Department.self, command: .departments)) }
        catch { Self.logger.error("Failed to load departments: \(error)"); departmentsState = .failed(ErrorMessageFormatter.message(for: error)) }
    }

    func loadNetworkSegments(force: Bool = false) async {
        guard force || networkSegmentsState.value == nil else { return }
        guard force || !networkSegmentsState.isLoading else { return }
        networkSegmentsState = .loading
        do { networkSegmentsState = .loaded(try await repository.fetchList(NetworkSegment.self, command: .networkSegments)) }
        catch { Self.logger.error("Failed to load network segments: \(error)"); networkSegmentsState = .failed(ErrorMessageFormatter.message(for: error)) }
    }

    func loadExtensionAttributes(force: Bool = false) async {
        guard force || extensionAttributesState.value == nil else { return }
        guard force || !extensionAttributesState.isLoading else { return }
        extensionAttributesState = .loading
        do { extensionAttributesState = .loaded(try await repository.fetchList(ExtensionAttribute.self, command: .computerExtensionAttributes)) }
        catch { Self.logger.error("Failed to load extension attributes: \(error)"); extensionAttributesState = .failed(ErrorMessageFormatter.message(for: error)) }
    }

    func loadPatchTitles(force: Bool = false) async {
        guard force || patchTitlesState.value == nil else { return }
        guard force || !patchTitlesState.isLoading else { return }
        patchTitlesState = .loading
        do { patchTitlesState = .loaded(try await repository.fetchList(PatchTitle.self, command: .patchTitles)) }
        catch { Self.logger.error("Failed to load patch titles: \(error)"); patchTitlesState = .failed(ErrorMessageFormatter.message(for: error)) }
    }

    func loadPatchPolicies(force: Bool = false) async {
        guard force || patchPoliciesState.value == nil else { return }
        guard force || !patchPoliciesState.isLoading else { return }
        patchPoliciesState = .loading
        do { patchPoliciesState = .loaded(try await repository.fetchList(PatchPolicy.self, command: .patchPolicies)) }
        catch { Self.logger.error("Failed to load patch policies: \(error)"); patchPoliciesState = .failed(ErrorMessageFormatter.message(for: error)) }
    }

    func loadPatchTitleDetail(id: String) async {
        patchTitleDetailState = .loading
        do {
            let data   = try await repository.cli.run(.patchTitleDetail(id: id))
            let detail = try JSONDecoder().decode(PatchTitleDetail.self, from: data)
            patchTitleDetailState = .loaded(detail)
        } catch {
            Self.logger.error("Failed to load patch title detail (\(id)): \(error)")
            patchTitleDetailState = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    func loadPatchPolicyDetail(id: String) async {
        patchPolicyDetailState = .loading
        do {
            let data   = try await repository.cli.run(.patchPolicyDetail(id: id))
            let detail = try JSONDecoder().decode(PatchPolicyDetail.self, from: data)
            patchPolicyDetailState = .loaded(detail)
        } catch {
            Self.logger.error("Failed to load patch policy detail (\(id)): \(error)")
            patchPolicyDetailState = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    func loadDepTokens(force: Bool = false) async {
        guard force || depTokensState.value == nil else { return }
        guard force || !depTokensState.isLoading else { return }
        depTokensState = .loading
        do { depTokensState = .loaded(try await repository.fetchList(DEPToken.self, command: .depTokens)) }
        catch { Self.logger.error("Failed to load DEP tokens: \(error)"); depTokensState = .failed(ErrorMessageFormatter.message(for: error)) }
    }

    func loadComputerPrestages(force: Bool = false) async {
        guard force || computerPrestagesState.value == nil else { return }
        guard force || !computerPrestagesState.isLoading else { return }
        computerPrestagesState = .loading
        do { computerPrestagesState = .loaded(try await repository.fetchList(ComputerPrestage.self, command: .computerPrestages)) }
        catch { Self.logger.error("Failed to load computer prestages: \(error)"); computerPrestagesState = .failed(ErrorMessageFormatter.message(for: error)) }
    }

    func loadMobileDevicePrestages(force: Bool = false) async {
        guard force || mobileDevicePrestagesState.value == nil else { return }
        guard force || !mobileDevicePrestagesState.isLoading else { return }
        mobileDevicePrestagesState = .loading
        do { mobileDevicePrestagesState = .loaded(try await repository.fetchList(MobileDevicePrestage.self, command: .mobileDevicePrestages)) }
        catch { Self.logger.error("Failed to load mobile device prestages: \(error)"); mobileDevicePrestagesState = .failed(ErrorMessageFormatter.message(for: error)) }
    }

    func loadWebhooks(force: Bool = false) async {
        guard force || webhooksState.value == nil else { return }
        guard force || !webhooksState.isLoading else { return }
        webhooksState = .loading
        do { webhooksState = .loaded(try await repository.fetchList(JamfWebhook.self, command: .webhooks)) }
        catch { Self.logger.error("Failed to load webhooks: \(error)"); webhooksState = .failed(ErrorMessageFormatter.message(for: error)) }
    }

    @discardableResult
    func runCLI(_ command: CLICommand) async throws -> Data {
        try await repository.run(command)
    }

    // MARK: - Filtered accessors

    private var q: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private func matches(_ name: String) -> Bool {
        q.isEmpty || name.localizedCaseInsensitiveContains(q)
    }

    var policies: [Policy] {
        (policiesState.value ?? []).filter { matches($0.name) }
    }
    var smartGroups: [SmartComputerGroup] {
        (groupsState.value ?? []).filter { matches($0.name) }
    }
    var scripts: [JamfScript] {
        (scriptsState.value ?? []).filter { matches($0.name) }
    }
    var packages: [JamfPackage] {
        (packagesState.value ?? []).filter { matches($0.name) }
    }
    var configProfiles: [ConfigProfile] {
        (configProfilesState.value ?? []).filter { matches($0.name) }
    }

    var policiesByCategory: [(name: String, policies: [Policy])] {
        let grouped = Dictionary(grouping: policies, by: {
            $0.category?.name ?? policyCategoryMap[$0.id] ?? "Uncategorised"
        })
        return grouped.map { (name: $0.key, policies: $0.value) }
            .sorted { lhs, rhs in
                if lhs.name == "Uncategorised" { return false }
                if rhs.name == "Uncategorised" { return true }
                return lhs.name < rhs.name
            }
    }

    var configProfilesByCategory: [(name: String, profiles: [ConfigProfile])] {
        let grouped = Dictionary(grouping: configProfiles, by: {
            configProfileCategoryMap[$0.id] ?? "Uncategorised"
        })
        return grouped.map { (name: $0.key, profiles: $0.value) }
            .sorted { lhs, rhs in
                if lhs.name == "Uncategorised" { return false }
                if rhs.name == "Uncategorised" { return true }
                return lhs.name < rhs.name
            }
    }

}
