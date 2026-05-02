import Foundation
import Observation

@MainActor
@Observable
final class FleetViewModel {
    private(set) var policiesState:       LoadState<[Policy]> = .idle
    private(set) var groupsState:         LoadState<[SmartComputerGroup]> = .idle
    private(set) var scriptsState:        LoadState<[JamfScript]> = .idle
    private(set) var packagesState:       LoadState<[JamfPackage]> = .idle
    private(set) var configProfilesState: LoadState<[ConfigProfile]> = .idle
    private(set) var smartGroupDetailState:    LoadState<SmartGroupDetail> = .idle
    private(set) var policyDetailState:        LoadState<JamfScope>        = .idle
    private(set) var configProfileDetailState: LoadState<JamfScope>        = .idle

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
        policiesState = .loading
        do {
            let policies = try await repository.fetchPolicies()
            policiesState = .loaded(policies)
            let uncategorized = policies.filter { $0.category == nil }
            if !uncategorized.isEmpty {
                Task { policyCategoryMap = await repository.fetchPolicyCategoryMap(for: uncategorized) }
            }
        }
        catch { policiesState = .failed(error.localizedDescription) }
    }

    func loadGroups(force: Bool = false) async {
        guard force || groupsState.value == nil else { return }
        guard force || !groupsState.isLoading else { return }
        groupsState = .loading
        do { groupsState = .loaded(try await repository.fetchSmartGroups()) }
        catch { groupsState = .failed(error.localizedDescription) }
    }

    func loadScripts(force: Bool = false) async {
        guard force || scriptsState.value == nil else { return }
        guard force || !scriptsState.isLoading else { return }
        scriptsState = .loading
        do { scriptsState = .loaded(try await repository.fetchScripts()) }
        catch { scriptsState = .failed(error.localizedDescription) }
    }

    func loadPackages(force: Bool = false) async {
        guard force || packagesState.value == nil else { return }
        guard force || !packagesState.isLoading else { return }
        packagesState = .loading
        do { packagesState = .loaded(try await repository.fetchPackages()) }
        catch { packagesState = .failed(error.localizedDescription) }
    }

    func loadConfigProfiles(force: Bool = false) async {
        guard force || configProfilesState.value == nil else { return }
        guard force || !configProfilesState.isLoading else { return }
        configProfilesState = .loading
        do {
            let profiles = try await repository.fetchConfigProfiles()
            configProfilesState = .loaded(profiles)
            Task { configProfileCategoryMap = await repository.fetchConfigProfileCategoryMap(for: profiles) }
        }
        catch { configProfilesState = .failed(error.localizedDescription) }
    }

    func loadSmartGroupDetail(id: String) async {
        smartGroupDetailState = .loading
        do { smartGroupDetailState = .loaded(try await repository.fetchSmartGroupDetail(id: id)) }
        catch { smartGroupDetailState = .failed(error.localizedDescription) }
    }

    func loadPolicyScope(id: Int) async {
        policyDetailState = .loading
        do { policyDetailState = .loaded(try await repository.fetchPolicyScope(id: id)) }
        catch { policyDetailState = .failed(error.localizedDescription) }
    }

    func loadConfigProfileScope(id: Int) async {
        configProfileDetailState = .loading
        do { configProfileDetailState = .loaded(try await repository.fetchConfigProfileScope(id: id)) }
        catch { configProfileDetailState = .failed(error.localizedDescription) }
    }

    // MARK: - New Pro resource loaders

    func loadBuildings(force: Bool = false) async {
        guard force || buildingsState.value == nil else { return }
        guard force || !buildingsState.isLoading else { return }
        buildingsState = .loading
        do { buildingsState = .loaded(try await repository.fetchList(Building.self, command: .buildings)) }
        catch { buildingsState = .failed(error.localizedDescription) }
    }

    func loadDepartments(force: Bool = false) async {
        guard force || departmentsState.value == nil else { return }
        guard force || !departmentsState.isLoading else { return }
        departmentsState = .loading
        do { departmentsState = .loaded(try await repository.fetchList(Department.self, command: .departments)) }
        catch { departmentsState = .failed(error.localizedDescription) }
    }

    func loadNetworkSegments(force: Bool = false) async {
        guard force || networkSegmentsState.value == nil else { return }
        guard force || !networkSegmentsState.isLoading else { return }
        networkSegmentsState = .loading
        do { networkSegmentsState = .loaded(try await repository.fetchList(NetworkSegment.self, command: .networkSegments)) }
        catch { networkSegmentsState = .failed(error.localizedDescription) }
    }

    func loadExtensionAttributes(force: Bool = false) async {
        guard force || extensionAttributesState.value == nil else { return }
        guard force || !extensionAttributesState.isLoading else { return }
        extensionAttributesState = .loading
        do { extensionAttributesState = .loaded(try await repository.fetchList(ExtensionAttribute.self, command: .computerExtensionAttributes)) }
        catch { extensionAttributesState = .failed(error.localizedDescription) }
    }

    func loadPatchTitles(force: Bool = false) async {
        guard force || patchTitlesState.value == nil else { return }
        guard force || !patchTitlesState.isLoading else { return }
        patchTitlesState = .loading
        do { patchTitlesState = .loaded(try await repository.fetchList(PatchTitle.self, command: .patchTitles)) }
        catch { patchTitlesState = .failed(error.localizedDescription) }
    }

    func loadPatchPolicies(force: Bool = false) async {
        guard force || patchPoliciesState.value == nil else { return }
        guard force || !patchPoliciesState.isLoading else { return }
        patchPoliciesState = .loading
        do { patchPoliciesState = .loaded(try await repository.fetchList(PatchPolicy.self, command: .patchPolicies)) }
        catch { patchPoliciesState = .failed(error.localizedDescription) }
    }

    func loadPatchTitleDetail(id: String) async {
        patchTitleDetailState = .loading
        do {
            let data   = try await repository.cli.run(.patchTitleDetail(id: id))
            let detail = try JSONDecoder().decode(PatchTitleDetail.self, from: data)
            patchTitleDetailState = .loaded(detail)
        } catch {
            patchTitleDetailState = .failed(error.localizedDescription)
        }
    }

    func loadPatchPolicyDetail(id: String) async {
        patchPolicyDetailState = .loading
        do {
            let data   = try await repository.cli.run(.patchPolicyDetail(id: id))
            let detail = try JSONDecoder().decode(PatchPolicyDetail.self, from: data)
            patchPolicyDetailState = .loaded(detail)
        } catch {
            patchPolicyDetailState = .failed(error.localizedDescription)
        }
    }

    func loadDepTokens(force: Bool = false) async {
        guard force || depTokensState.value == nil else { return }
        guard force || !depTokensState.isLoading else { return }
        depTokensState = .loading
        do { depTokensState = .loaded(try await repository.fetchList(DEPToken.self, command: .depTokens)) }
        catch { depTokensState = .failed(error.localizedDescription) }
    }

    func loadComputerPrestages(force: Bool = false) async {
        guard force || computerPrestagesState.value == nil else { return }
        guard force || !computerPrestagesState.isLoading else { return }
        computerPrestagesState = .loading
        do { computerPrestagesState = .loaded(try await repository.fetchList(ComputerPrestage.self, command: .computerPrestages)) }
        catch { computerPrestagesState = .failed(error.localizedDescription) }
    }

    func loadMobileDevicePrestages(force: Bool = false) async {
        guard force || mobileDevicePrestagesState.value == nil else { return }
        guard force || !mobileDevicePrestagesState.isLoading else { return }
        mobileDevicePrestagesState = .loading
        do { mobileDevicePrestagesState = .loaded(try await repository.fetchList(MobileDevicePrestage.self, command: .mobileDevicePrestages)) }
        catch { mobileDevicePrestagesState = .failed(error.localizedDescription) }
    }

    func loadWebhooks(force: Bool = false) async {
        guard force || webhooksState.value == nil else { return }
        guard force || !webhooksState.isLoading else { return }
        webhooksState = .loading
        do { webhooksState = .loaded(try await repository.fetchList(JamfWebhook.self, command: .webhooks)) }
        catch { webhooksState = .failed(error.localizedDescription) }
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
