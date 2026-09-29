import Foundation
import OSLog

/// Progress of a dependency scan.
struct DependencyScanProgress: Sendable, Equatable {
    var step: String
    var completed: Int
    var total: Int

    var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
}

/// Reads everything the extension attribute dependency map needs from Jamf Pro: both
/// attribute lists, then every smart group, advanced search, policy, configuration profile,
/// restricted software entry and patch policy with its criteria or scope.
///
/// Read-only. Details are fetched a few at a time. A list that can't be read (for example
/// because the API client lacks the privilege) is recorded as a failure and the scan goes on,
/// so the map is as complete as the permissions allow.
struct EADependencyRepository: Sendable {
    private static let logger = Logger(subsystem: "com.jamfdash", category: "EADependencies")
    static let detailConcurrency = 6

    let cli: any CLIRunning

    func scan(progress: @escaping @Sendable (DependencyScanProgress) -> Void) async -> DependencyInventory {
        var inventory = DependencyInventory()

        // 1. Lists.
        progress(DependencyScanProgress(step: "Reading lists", completed: 0, total: 0))
        async let computerEAs = list(.computerExtensionAttributes)
        async let mobileEAs = list(.mobileDeviceExtensionAttributes)
        async let computerGroups = list(.classicComputerGroups)
        async let mobileGroups = list(.classicMobileDeviceGroups)
        async let computerSearches = list(.advancedComputerSearches)
        async let mobileSearches = list(.advancedMobileDeviceSearches)
        async let policies = list(.policies)
        async let macProfiles = list(.configProfiles)
        async let mobileProfiles = list(.mobileConfigProfiles)
        async let restricted = list(.restrictedSoftware)
        async let patch = list(.patchPolicies)

        for (kind, result) in [(EAKind.computer, await computerEAs), (.mobileDevice, await mobileEAs)] {
            switch result {
            case .success(let data):
                let attributes = (try? Self.decodeAttributes(data)) ?? []
                if kind == .computer { inventory.computerAttributes = attributes } else { inventory.mobileAttributes = attributes }
            case .failure(let error):
                inventory.failures.append(DependencyScanFailure(type: nil, kind: kind, isListFailure: true, count: 0,
                                                                message: ErrorMessageFormatter.message(for: error)))
            }
        }

        // 2. Detail jobs for every object in the lists that could be read.
        var jobs: [Job] = []
        func add(_ result: Result<Data, Error>, _ type: DependentObjectType, smartOnly: Bool = false) {
            switch result {
            case .success(let data):
                for row in ClassicDefinitionParser.idsAndNames(data) where !(smartOnly && row.isSmart == false) {
                    jobs.append(Job(type: type, id: row.id, name: row.name))
                }
            case .failure(let error):
                inventory.failures.append(DependencyScanFailure(type: type, kind: type.kind, isListFailure: true, count: 0,
                                                                message: ErrorMessageFormatter.message(for: error)))
            }
        }
        add(await computerGroups, .computerSmartGroup, smartOnly: true)
        add(await computerSearches, .computerAdvancedSearch)
        add(await policies, .policy)
        add(await macProfiles, .macConfigProfile)
        add(await restricted, .restrictedSoftware)
        add(await patch, .patchPolicy)
        add(await mobileGroups, .mobileSmartGroup, smartOnly: true)
        add(await mobileSearches, .mobileAdvancedSearch)
        add(await mobileProfiles, .mobileConfigProfile)

        // 3. Details, a few at a time.
        let total = jobs.count
        var completed = 0
        var failed: [DependentObjectType: (count: Int, message: String)] = [:]
        progress(DependencyScanProgress(step: "Reading details", completed: 0, total: total))
        var iterator = jobs.makeIterator()
        await withTaskGroup(of: (Job, Result<Data, Error>).self) { group in
            func startNext() -> Bool {
                guard let job = iterator.next() else { return false }
                group.addTask { (job, await self.detail(job)) }
                return true
            }
            for _ in 0..<Self.detailConcurrency { guard startNext() else { break } }
            while let (job, result) = await group.next() {
                if Task.isCancelled { group.cancelAll(); break }
                switch result {
                case .success(let data):
                    if !Self.apply(data, job: job, to: &inventory) {
                        failed[job.type, default: (0, "unexpected response")].count += 1
                    }
                case .failure(let error):
                    let message = ErrorMessageFormatter.message(for: error)
                    failed[job.type, default: (0, message)].count += 1
                }
                completed += 1
                progress(DependencyScanProgress(step: "Reading \(job.type.title.lowercased())", completed: completed, total: total))
                _ = startNext()
            }
        }
        for type in DependentObjectType.allCases {
            if let f = failed[type] {
                inventory.failures.append(DependencyScanFailure(type: type, kind: type.kind, isListFailure: false,
                                                                count: f.count, message: f.message))
            }
        }
        inventory.scannedAt = Date()
        Self.logger.info("Dependency scan read \(inventory.objectCount) objects, \(inventory.failures.count) failure group(s)")
        return inventory
    }

    // MARK: - Jobs

    private struct Job: Sendable {
        let type: DependentObjectType
        let id: String
        let name: String

        var command: CLICommand? {
            switch type {
            case .computerSmartGroup:     return .classicComputerGroupDetail(id: id)
            case .computerAdvancedSearch: return .advancedComputerSearchDetail(id: id)
            case .policy:                 return Int(id).map { .policyDetail(id: $0) }
            case .macConfigProfile:       return Int(id).map { .configProfileDetail(id: $0) }
            case .restrictedSoftware:     return .restrictedSoftwareDetail(id: id)
            case .patchPolicy:            return .patchPolicyDetail(id: id)
            case .mobileSmartGroup:       return .classicMobileDeviceGroupDetail(id: id)
            case .mobileAdvancedSearch:   return .advancedMobileDeviceSearchDetail(id: id)
            case .mobileConfigProfile:    return .mobileConfigProfileDetail(id: id)
            }
        }
    }

    private func list(_ command: CLICommand) async -> Result<Data, Error> {
        do { return .success(try await cli.run(command)) }
        catch { return .failure(error) }
    }

    private func detail(_ job: Job) async -> Result<Data, Error> {
        guard let command = job.command else { return .failure(CLIError.decodingFailed("Invalid ID \(job.id)")) }
        return await list(command)
    }

    /// Adds a detail response to the inventory. False when it couldn't be parsed.
    private static func apply(_ data: Data, job: Job, to inventory: inout DependencyInventory) -> Bool {
        switch job.type {
        case .computerSmartGroup, .mobileSmartGroup:
            guard let group = ClassicDefinitionParser.group(data, fallbackID: job.id, fallbackName: job.name) else { return false }
            if job.type == .computerSmartGroup { inventory.computerGroups.append(group) } else { inventory.mobileGroups.append(group) }
        case .computerAdvancedSearch, .mobileAdvancedSearch:
            guard let search = ClassicDefinitionParser.search(data, fallbackID: job.id, fallbackName: job.name) else { return false }
            if job.type == .computerAdvancedSearch { inventory.computerSearches.append(search) } else { inventory.mobileSearches.append(search) }
        case .policy, .macConfigProfile, .restrictedSoftware, .patchPolicy, .mobileConfigProfile:
            guard let object = ClassicDefinitionParser.scopedObject(data, type: job.type, id: job.id, name: job.name) else { return false }
            inventory.scopedObjects.append(object)
        }
        return true
    }

    // MARK: - Attributes

    /// Extension attributes from a Jamf Pro API list (`[…]` or `{"results": […]}`).
    static func decodeAttributes(_ data: Data) throws -> [ExtensionAttribute] {
        let decoder = JSONDecoder()
        if let flat = try? decoder.decode([ExtensionAttribute].self, from: data) { return flat }
        struct Paged: Decodable { let results: [ExtensionAttribute] }
        return try decoder.decode(Paged.self, from: data).results
    }

    /// Only the attribute list, for showing the table before a scan.
    func attributes(_ kind: EAKind) async throws -> [ExtensionAttribute] {
        let data = try await cli.run(kind == .computer ? .computerExtensionAttributes : .mobileDeviceExtensionAttributes)
        return try Self.decodeAttributes(data)
    }
}
