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
    private(set) var modernPatchState:            LoadState<[ModernPatchTitle]>       = .idle
    private(set) var appInstallerTitlesState:     LoadState<[AppInstallerTitle]>      = .idle
    private(set) var appInstallerDeploymentsState: LoadState<[AppInstallerDeployment]> = .idle
    private(set) var restrictedSoftwareState:     LoadState<[RestrictedSoftware]>     = .idle
    private(set) var depTokensState:              LoadState<[DEPToken]>              = .idle
    private(set) var computerPrestagesState:      LoadState<[ComputerPrestage]>      = .idle
    private(set) var mobileDevicePrestagesState:  LoadState<[MobileDevicePrestage]>  = .idle

    var searchText = ""

    private(set) var policyCategoryMap:       [Int: String] = [:]
    private(set) var configProfileCategoryMap: [Int: String] = [:]

    /// Tracks in-flight category back-fill tasks so a force-refresh can cancel them.
    private var policyCategoryTask:    Task<Void, Never>?
    private var profileCategoryTask:   Task<Void, Never>?
    private var patchTitleEnrichTask:  Task<Void, Never>?

    private let repository: FleetRepository

    /// Where category lookups are cached for the current instance; nil keeps them in
    /// memory only (demo mode).
    var categoryCacheURL: URL? {
        didSet { categoryCache = CategoryCache.load(from: categoryCacheURL) }
    }
    private var categoryCache = CategoryCache()

    init(repository: FleetRepository) {
        self.repository = repository
    }

    func loadAll(force: Bool = false) async {
        let start = Date()
        // A forced refresh looks up every category again.
        if force { categoryCache = CategoryCache() }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadPolicies(force: force, suppressEnrichment: true) }
            group.addTask { await self.loadGroups(force: force) }
            group.addTask { await self.loadScripts(force: force) }
            group.addTask { await self.loadPackages(force: force) }
            group.addTask { await self.loadConfigProfiles(force: force, suppressEnrichment: true) }
        }
        let elapsed = String(format: "%.2f", Date().timeIntervalSince(start))
        Self.logger.debug("loadAll finished in \(elapsed, privacy: .public)s")
        startPostSyncEnrichment()
    }

    /// Triggers category back-fill for policies and config profiles using already-loaded state.
    /// Called after a sync group completes so enrichment doesn't race with the main data load.
    ///
    /// Categories looked up in the last day are reused, so a sync only fetches details for
    /// new policies and profiles instead of one per item every time.
    func startPostSyncEnrichment() {
        if !categoryCache.isFresh { categoryCache = CategoryCache() }
        if let policies = policiesState.value {
            let uncategorized = policies.filter { $0.category == nil }
            if !uncategorized.isEmpty {
                let cached = categoryCache.policies.filter { id, _ in uncategorized.contains { $0.id == id } }
                let missing = uncategorized.filter { cached[$0.id] == nil }
                policyCategoryMap = cached
                policyCategoryTask?.cancel()
                policyCategoryTask = Task {
                    let fetched = missing.isEmpty ? [:] : await repository.fetchPolicyCategoryMap(for: missing)
                    guard !Task.isCancelled else { return }
                    policyCategoryMap = cached.merging(fetched) { _, new in new }
                    categoryCache.policies = policyCategoryMap
                    saveCategoryCache()
                }
            }
        }
        if let profiles = configProfilesState.value {
            let cached = categoryCache.profiles.filter { id, _ in profiles.contains { $0.id == id } }
            let missing = profiles.filter { cached[$0.id] == nil }
            configProfileCategoryMap = cached
            profileCategoryTask?.cancel()
            profileCategoryTask = Task {
                let fetched = missing.isEmpty ? [:] : await repository.fetchConfigProfileCategoryMap(for: missing)
                guard !Task.isCancelled else { return }
                configProfileCategoryMap = cached.merging(fetched) { _, new in new }
                categoryCache.profiles = configProfileCategoryMap
                saveCategoryCache()
            }
        }
    }

    private func saveCategoryCache() {
        if categoryCache.savedAt == .distantPast { categoryCache.savedAt = Date() }
        categoryCache.save(to: categoryCacheURL)
    }

    func loadPolicies(force: Bool = false, suppressEnrichment: Bool = false) async {
        guard force || policiesState.value == nil else {
            Self.logger.debug("Policies already cached — skipping")
            return
        }
        guard force || !policiesState.isLoading else { return }
        Self.logger.debug("Loading policies")
        policiesState = .loading
        do {
            let policies = try await repository.fetchPolicies()
            Self.logger.debug("Loaded \(policies.count) policies")
            policiesState = .loaded(policies)
            guard !suppressEnrichment else { return }
            let uncategorized = policies.filter { $0.category == nil }
            if !uncategorized.isEmpty {
                policyCategoryTask?.cancel()
                policyCategoryTask = Task {
                    let map = await repository.fetchPolicyCategoryMap(for: uncategorized)
                    if !Task.isCancelled { policyCategoryMap = map }
                }
            }
        }
        catch {
            Self.logger.error("Failed to load policies: \(error)")
            policiesState = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    func loadGroups(force: Bool = false) async {
        guard force || groupsState.value == nil else {
            Self.logger.debug("Smart groups already cached — skipping")
            return
        }
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
        guard force || scriptsState.value == nil else {
            Self.logger.debug("Scripts already cached — skipping")
            return
        }
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
        guard force || packagesState.value == nil else {
            Self.logger.debug("Packages already cached — skipping")
            return
        }
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

    func loadConfigProfiles(force: Bool = false, suppressEnrichment: Bool = false) async {
        guard force || configProfilesState.value == nil else {
            Self.logger.debug("Config profiles already cached — skipping")
            return
        }
        guard force || !configProfilesState.isLoading else { return }
        Self.logger.debug("Loading config profiles")
        configProfilesState = .loading
        do {
            let profiles = try await repository.fetchConfigProfiles()
            Self.logger.debug("Loaded \(profiles.count) config profiles")
            configProfilesState = .loaded(profiles)
            guard !suppressEnrichment else { return }
            profileCategoryTask?.cancel()
            profileCategoryTask = Task {
                let map = await repository.fetchConfigProfileCategoryMap(for: profiles)
                if !Task.isCancelled { configProfileCategoryMap = map }
            }
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
        do {
            // 1. Show names immediately — the list endpoint only returns id + name.
            let thin = try await repository.fetchList(PatchTitle.self, command: .patchTitles)
            patchTitlesState = .loaded(thin)

            // 2. Batch-enrich with detail calls (category + current version) in the background.
            if !thin.isEmpty {
                patchTitleEnrichTask?.cancel()
                patchTitleEnrichTask = Task {
                    Self.logger.info("Enriching \(thin.count) patch titles with detail calls")
                    let enriched = await Self.enrichPatchTitles(thin, cli: repository.cli)
                    if !Task.isCancelled { patchTitlesState = .loaded(enriched) }
                }
            }
        } catch {
            Self.logger.error("Failed to load patch titles: \(error)")
            patchTitlesState = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    func loadPatchPolicies(force: Bool = false) async {
        guard force || patchPoliciesState.value == nil else { return }
        guard force || !patchPoliciesState.isLoading else { return }
        patchPoliciesState = .loading
        do {
            // 1. Load thin list via Classic API (id + name only) — fast.
            let thin = try await repository.fetchList(PatchPolicy.self, command: .patchPolicies)
            patchPoliciesState = .loaded(thin)   // show names immediately

            // 2. Batch-enrich all policies in parallel using the detail endpoint.
            //    This fills Enabled, Target Version and Patch Title without making the user click.
            if !thin.isEmpty {
                Self.logger.debug("Enriching \(thin.count) patch policies with detail calls")
                let enriched = await Self.enrichPatchPolicies(thin, cli: repository.cli)
                patchPoliciesState = .loaded(enriched)
            }
        } catch {
            Self.logger.error("Failed to load patch policies: \(error)")
            patchPoliciesState = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    /// Batch-fetches category and current version for each Classic patch title.
    nonisolated private static func enrichPatchTitles(
        _ items: [PatchTitle],
        cli: any CLIRunning
    ) async -> [PatchTitle] {
        var result: [PatchTitle] = []
        for chunk in items.chunked(by: enrichConcurrency) {
            guard !Task.isCancelled else { break }
            await withTaskGroup(of: PatchTitle.self) { group in
                for item in chunk {
                    group.addTask {
                        guard let data = try? await cli.run(.patchTitleDetail(id: item.id)),
                              let detail = try? JSONDecoder().decode(PatchTitleDetail.self, from: data)
                        else { return item }
                        return PatchTitle(thin: item, detail: detail)
                    }
                }
                for await t in group { result.append(t) }
            }
        }
        return result.sorted { $0.name < $1.name }
    }

    /// Batch-fetches individual detail for each patch policy and returns enriched items.
    nonisolated private static func enrichPatchPolicies(
        _ items: [PatchPolicy],
        cli: any CLIRunning
    ) async -> [PatchPolicy] {
        var result: [PatchPolicy] = []
        for chunk in items.chunked(by: enrichConcurrency) {
            guard !Task.isCancelled else { break }
            await withTaskGroup(of: PatchPolicy.self) { group in
                for item in chunk {
                    group.addTask {
                        guard let data = try? await cli.run(.patchPolicyDetail(id: item.id)),
                              let detail = try? JSONDecoder().decode(PatchPolicyDetail.self, from: data)
                        else { return item }
                        return PatchPolicy(thin: item, detail: detail)
                    }
                }
                for await p in group { result.append(p) }
            }
        }
        return result.sorted { $0.name < $1.name }
    }

    func loadModernPatch(force: Bool = false) async {
        guard force || modernPatchState.value == nil else { return }
        guard force || !modernPatchState.isLoading else { return }
        modernPatchState = .loading
        do {
            let data = try await repository.cli.run(.patchSoftwareTitleConfigurations)
            let decoder = JSONDecoder()
            var titles: [ModernPatchTitle]?
            titles = try? decoder.decode([ModernPatchTitle].self, from: data)
            if titles == nil, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for key in ["results", "items", "data", "softwareTitles", "titles", "patchTitles"] {
                    if let arr = obj[key],
                       let d = try? JSONSerialization.data(withJSONObject: arr) {
                        titles = try? decoder.decode([ModernPatchTitle].self, from: d)
                        if titles != nil { break }
                    }
                }
            }
            modernPatchState = .loaded(titles ?? [])
        } catch {
            Self.logger.error("Failed to load modern patch: \(error)")
            modernPatchState = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    func loadAppInstallerTitles(force: Bool = false) async {
        guard force || appInstallerTitlesState.value == nil else { return }
        guard force || !appInstallerTitlesState.isLoading else { return }
        appInstallerTitlesState = .loading
        do {
            let data = try await repository.cli.run(.appInstallerTitles)
            let decoder = JSONDecoder()
            var items: [AppInstallerTitle]?
            items = try? decoder.decode([AppInstallerTitle].self, from: data)
            if items == nil, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for key in ["results", "items", "data", "titles", "appInstallerTitles"] {
                    if let arr = obj[key],
                       let d = try? JSONSerialization.data(withJSONObject: arr) {
                        items = try? decoder.decode([AppInstallerTitle].self, from: d)
                        if items != nil { break }
                    }
                }
            }
            appInstallerTitlesState = .loaded(items ?? [])
        } catch {
            Self.logger.error("Failed to load app installer titles: \(error)")
            appInstallerTitlesState = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    func loadAppInstallerDeployments(force: Bool = false) async {
        guard force || appInstallerDeploymentsState.value == nil else { return }
        guard force || !appInstallerDeploymentsState.isLoading else { return }
        appInstallerDeploymentsState = .loading
        do {
            let data = try await repository.cli.run(.appInstallerDeployments)
            let decoder = JSONDecoder()
            var items: [AppInstallerDeployment]?
            items = try? decoder.decode([AppInstallerDeployment].self, from: data)
            if items == nil, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for key in ["results", "items", "data", "deployments"] {
                    if let arr = obj[key],
                       let d = try? JSONSerialization.data(withJSONObject: arr) {
                        items = try? decoder.decode([AppInstallerDeployment].self, from: d)
                        if items != nil { break }
                    }
                }
            }
            Self.logger.info("Loaded \(items?.count ?? 0) app installer deployments")
            appInstallerDeploymentsState = .loaded(items ?? [])
        } catch {
            Self.logger.error("Failed to load app installer deployments: \(error)")
            appInstallerDeploymentsState = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    func loadRestrictedSoftware(force: Bool = false) async {
        guard force || restrictedSoftwareState.value == nil else { return }
        guard force || !restrictedSoftwareState.isLoading else { return }
        restrictedSoftwareState = .loading
        do {
            let data = try await repository.cli.run(.restrictedSoftware)
            let decoder = JSONDecoder()
            var items: [RestrictedSoftware]?
            items = try? decoder.decode([RestrictedSoftware].self, from: data)
            if items == nil, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for key in ["results", "items", "data", "restrictedSoftware", "restricted_software"] {
                    if let arr = obj[key],
                       let d = try? JSONSerialization.data(withJSONObject: arr) {
                        items = try? decoder.decode([RestrictedSoftware].self, from: d)
                        if items != nil { break }
                    }
                }
            }
            var resolved = items ?? []
            // The Classic API list only returns id+name; batch-fetch individual details in
            // parallel to populate process_name, kill_process, etc. from the "general" sub-object.
            if resolved.allSatisfy({ $0.processName == nil && $0.killProcess == nil }) && !resolved.isEmpty {
                Self.logger.debug("Restricted software list is thin — enriching \(resolved.count) items with detail calls")
                resolved = await Self.enrichRestrictedSoftware(resolved, cli: repository.cli)
            }
            restrictedSoftwareState = .loaded(resolved)
        } catch {
            Self.logger.error("Failed to load restricted software: \(error)")
            restrictedSoftwareState = .failed(ErrorMessageFormatter.message(for: error))
        }
    }

    /// Batch-fetches full detail for each restricted software item in parallel.
    nonisolated private static func enrichRestrictedSoftware(
        _ items: [RestrictedSoftware],
        cli: any CLIRunning
    ) async -> [RestrictedSoftware] {
        var result: [RestrictedSoftware] = []
        for chunk in items.chunked(by: enrichConcurrency) {
            guard !Task.isCancelled else { break }
            await withTaskGroup(of: RestrictedSoftware.self) { group in
                for item in chunk {
                    group.addTask {
                        guard let data = try? await cli.run(.restrictedSoftwareDetail(id: item.id)),
                              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { return item }

                        // Classic API response: {"restricted_software": {"general": {...}, ...}}
                        // The "general" dict contains id/name plus all the process fields.
                        // We always use the thin item's id/name (reliable); only take process
                        // fields from the detail so the enriched item is never "Unknown".
                        let generalDict: [String: Any]?
                        if let rs = raw["restricted_software"] as? [String: Any] {
                            generalDict = rs["general"] as? [String: Any]
                        } else {
                            // Some jamf-cli builds flatten the response
                            generalDict = raw["general"] as? [String: Any] ?? raw
                        }
                        guard let g = generalDict else { return item }

                        let processName: String? = {
                            let v = (g["process_name"] as? String) ?? (g["processName"] as? String) ?? (g["process"] as? String)
                            return v?.isEmpty == false ? v : nil
                        }()
                        let matchExact     = (g["match_exact_process_name"] as? Bool)
                                          ?? (g["matchExact"] as? Bool)
                                          ?? (g["match_exact"] as? Bool)
                        let killProcess    = (g["kill_process"] as? Bool)
                                          ?? (g["killProcess"] as? Bool)
                        let deleteExec     = (g["delete_executable"] as? Bool)
                                          ?? (g["deleteExecutable"] as? Bool)
                        let displayMsg: String? = {
                            let v = (g["display_message"] as? String) ?? (g["displayMessage"] as? String)
                            return v?.isEmpty == false ? v : nil
                        }()

                        return RestrictedSoftware(
                            id: item.id, name: item.name,
                            processName: processName,
                            matchExact: matchExact,
                            killProcess: killProcess,
                            deleteExecutable: deleteExec,
                            displayMessage: displayMsg
                        )
                    }
                }
                for await item in group { result.append(item) }
            }
        }
        return result.sorted { $0.name < $1.name }
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

// MARK: - Collection chunking (local to this file)

/// Maximum simultaneous jamf-cli detail calls for any enrichment back-fill.
/// Accessible to both `@MainActor` methods and `nonisolated` static helpers.
private let enrichConcurrency = 6

private extension Array {
    func chunked(by size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

/// Policy and profile categories looked up from their details, kept for a day.
struct CategoryCache: Codable {
    var savedAt = Date.distantPast
    var policies: [Int: String] = [:]
    var profiles: [Int: String] = [:]

    var isFresh: Bool { Date().timeIntervalSince(savedAt) < 86_400 }

    static func load(from url: URL?) -> CategoryCache {
        guard let url, let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(CategoryCache.self, from: data), cache.isFresh
        else { return CategoryCache() }
        return cache
    }

    func save(to url: URL?) {
        guard let url, let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
