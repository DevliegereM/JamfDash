import Foundation
import OSLog

/// Reads enrollment data through jamf-cli. Every call is read-only, and nothing is stored:
/// the view model keeps results in memory for the session.
struct EnrollmentRepository: Sendable {
    let cli: any CLIRunning
    /// Lists that every timeline needs (profile names, PreStages, …), shared for ten minutes.
    let cache = EnrollmentListCache()
    private static let logger = Logger(subsystem: "com.jamfdash", category: "EnrollmentRepository")

    // MARK: - Recent enrollments

    func recentEnrollments(withinDays days: Int, now: Date = Date()) async throws -> [RecentEnrollment] {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        let data: Data
        do {
            // Jamf Pro filters by enrollment date, so only the chosen window is downloaded.
            data = try await cli.run(.recentEnrollments(since: cutoff))
        } catch CLIError.nonZeroExit(let code, let message) where JamfCLIErrorPayload(output: message)?.isPermissionDenied != true {
            // A Jamf Pro version that rejects the filter: fall back to the whole inventory.
            Self.logger.notice("Enrollment date filter failed (exit \(code, privacy: .public)); loading the full inventory")
            data = try await cli.run(.computers)
        }
        return EnrollmentParsing.recentEnrollments(data)
            .filter { ($0.enrolledAt ?? .distantPast) >= cutoff }
            .sorted { ($0.enrolledAt ?? .distantPast) > ($1.enrolledAt ?? .distantPast) }
    }

    // MARK: - Timeline for one Mac

    enum TimelineError: LocalizedError {
        case notFound(String)
        var errorDescription: String? {
            switch self {
            case .notFound(let serial): return "No Mac with serial number \(serial) was found in Jamf Pro."
            }
        }
    }

    /// Loads everything known about one Mac's enrollment. Only the inventory lookup is
    /// required; every other source that fails is reported in `sources` instead.
    func timeline(serial rawSerial: String, enrollmentPolicyIDs: Set<Int> = [],
                  setupManagerPolicies: [Int: String] = [:], now: Date = Date()) async throws -> EnrollmentTimeline {
        let serial = CLICommand.sanitizedSerial(rawSerial)
        guard !serial.isEmpty else { throw TimelineError.notFound(rawSerial) }

        let inventoryData = try await cli.run(.enrollmentInventory(serial: serial))
        guard let detail = Self.decodeDetail(inventoryData) else { throw TimelineError.notFound(serial) }
        let general = detail.general
        let rawRow = EnrollmentParsing.rows(inventoryData).first ?? [:]
        let rawGeneral = (rawRow["general"] as? [String: Any]) ?? [:]
        let method = EnrollmentParsing.enrollmentMethod(rawGeneral["enrollmentMethod"])
        let viaADE = EnrollmentParsing.bool(rawGeneral["enrolledViaAutomatedDeviceEnrollment"])
        let managementId = general?.managementId
        // Department and building come as IDs; the names are needed to match scopes.
        let location = rawRow["userAndLocation"] as? [String: Any] ?? [:]
        let departmentID = EnrollmentParsing.int(location["departmentId"])
        let buildingID = EnrollmentParsing.int(location["buildingId"])
        async let departments: [Int: String] = departmentID == nil ? [:] : namedList(.departments)
        async let buildings: [Int: String] = buildingID == nil ? [:] : namedList(.buildings)
        let departmentNames = await departments, buildingNames = await buildings
        let departmentName = departmentID.flatMap { departmentNames[$0] }
        let buildingName = buildingID.flatMap { buildingNames[$0] }

        let device = EnrollmentTimeline.Device(
            computerID: detail.id,
            name: detail.name,
            serial: detail.hardware?.serialNumber ?? serial,
            managementId: managementId,
            enrolledAt: EnrollmentParsing.date(general?.lastEnrolledDate),
            firstSeenAt: EnrollmentParsing.date(general?.initialEntryDate),
            lastContact: EnrollmentParsing.lastContact(rawGeneral),
            method: method.name ?? general?.enrollmentMethod,
            methodID: method.id,
            supervised: general?.supervised,
            userApprovedMDM: general?.userApprovedMdm,
            groups: (detail.groupMemberships ?? []).compactMap(\.groupName),
            department: departmentName ?? detail.location?.departmentName,
            building: buildingName ?? detail.location?.buildingName
        )
        let installed = EnrollmentParsing.installedProfiles(inventoryData)

        // Everything else in parallel; each source reports its own status.
        let validID = managementId.map(EnrollmentParsing.isManagementID) ?? false
        async let mdm = fetch(validID ? .mdmCommandsForDevice(managementId: managementId!) : nil,
                              missing: "This Mac has no management ID", parse: EnrollmentParsing.mdmCommands)
        async let history = fetch(.computerHistory(serial: serial, subset: .commands),
                                  missing: "", parse: EnrollmentParsing.historyCommands)
        async let policies = fetch(.computerHistory(serial: serial, subset: .policyLogs),
                                   missing: "", parse: EnrollmentParsing.policyLogs)
        async let ddm = fetch(validID ? .ddmStatusItems(managementId: managementId!) : nil,
                              missing: "This Mac has no management ID",
                              parse: { (try? DDMMonitorViewModel.decodeStatusItems(from: $0)) ?? [] })
        let isPrestage = EnrollmentParsing.isPrestageMethod(type: method.type, viaADE: viaADE)
        async let prestage: PrestageDetail? = isPrestage ? matchPrestage(name: method.name, id: method.id) : nil
        async let retention = cache.data(for: "logFlushing") { try? await cli.run(.logFlushingSettings) }
        async let profileNames = namedList(.configProfiles)

        let (mdmRecords, mdmStatus) = await mdm
        let (historyRecords, historyStatus) = await history
        let (policyRecords, policyStatus) = await policies
        let (ddmItems, ddmStatus) = await ddm

        let input = EnrollmentAnalyzer.TimelineInput(
            enrolledAt: device.enrolledAt, firstSeenAt: device.firstSeenAt, method: device.method,
            supervised: device.supervised, lastContact: device.lastContact,
            mdmCommands: mdmRecords, historyCommands: historyRecords, policyLogs: policyRecords,
            installedProfiles: installed, enrollmentPolicyIDs: enrollmentPolicyIDs,
            profileNamesByID: await profileNames, setupManagerPolicies: setupManagerPolicies)

        let ddmSummary: EnrollmentTimeline.DDMSummary? = ddmItems.isEmpty ? nil : .init(
            itemCount: ddmItems.count,
            awaitingConfiguration: ddmItems.first { $0.key == "mdm.is-awaiting-configuration" }?.value
                .flatMap(EnrollmentParsing.bool),
            lastReport: ddmItems.compactMap { EnrollmentParsing.date($0.lastUpdateTime) }.max())

        return EnrollmentTimeline(
            device: device,
            events: EnrollmentAnalyzer.buildEvents(input, now: now),
            sources: [.inventory: .ok(count: installed.count), .mdmCommands: mdmStatus,
                      .commandHistory: historyStatus, .policyLogs: policyStatus, .ddm: ddmStatus],
            installedProfiles: installed,
            ddm: ddmSummary,
            prestage: await prestage,
            historyRetention: (await retention).flatMap(EnrollmentParsing.historyRetention),
            loadedAt: now
        )
    }

    private static func decodeDetail(_ data: Data) -> ComputerDetail? {
        let decoder = JSONDecoder()
        if let wrapped = try? decoder.decode(ResultsWrapper.self, from: data) { return wrapped.results.first }
        if let array = try? decoder.decode([ComputerDetail].self, from: data) { return array.first }
        return try? decoder.decode(ComputerDetail.self, from: data)
    }

    private struct ResultsWrapper: Decodable { let results: [ComputerDetail] }

    /// Runs one optional source; failures become a status instead of an error.
    private func fetch<T: Sendable>(_ command: CLICommand?, missing: String,
                                    parse: @Sendable (Data) -> [T]) async -> ([T], SourceStatus) {
        guard let command else { return ([], .notApplicable(missing)) }
        do {
            let items = parse(try await cli.run(command))
            return (items, .ok(count: items.count))
        } catch CLIError.nonZeroExit(let code, _) where code == 15 {
            return ([], .unavailable("Not supported by this Jamf Pro version"))
        } catch {
            Self.logger.notice("Enrollment source unavailable: \(Self.message(for: error), privacy: .public)")
            return ([], .unavailable(Self.message(for: error)))
        }
    }

    /// jamf-cli prints warnings (such as deprecated command names) before its JSON error,
    /// so show the error's own message rather than the first line of output.
    static func message(for error: Error) -> String {
        if case CLIError.nonZeroExit(_, let stderr) = error, let payload = JamfCLIErrorPayload(output: stderr) {
            return payload.readableMessage
        }
        return ErrorMessageFormatter.message(for: error)
    }

    // MARK: - PreStages

    func prestages() async throws -> [ComputerPrestage] {
        let cli = self.cli
        var cached = await cache.data(for: "prestages", load: { try? await cli.run(.computerPrestages) })
        // The cache swallows errors; run it once more so the caller sees what went wrong.
        if cached == nil { cached = try await cli.run(.computerPrestages) }
        let data = cached ?? Data()
        let rows = EnrollmentParsing.rows(data)
        let rowsData = try JSONSerialization.data(withJSONObject: rows)
        return try JSONDecoder().decode([ComputerPrestage].self, from: rowsData)
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func prestageDetail(id: String) async throws -> PrestageDetail? {
        guard !id.isEmpty, id.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return EnrollmentParsing.prestageDetail(try await cli.run(.computerPrestageDetail(id: id)))
    }

    /// The PreStage a Mac enrolled through, matched by the enrollment method's name, then its ID.
    func matchPrestage(name: String?, id: String?) async -> PrestageDetail? {
        guard name != nil || id != nil, let list = try? await prestages() else { return nil }
        let hit = list.first { $0.displayName.caseInsensitiveCompare(name ?? "") == .orderedSame }
            ?? list.first { $0.id == id }
        guard let hit else { return nil }
        return try? await prestageDetail(id: hit.id)
    }

    // MARK: - Names for the flow

    func namedList(_ command: CLICommand) async -> [Int: String] {
        guard let data = await cache.data(for: command.baseArguments.joined(separator: " "),
                                          load: { try? await cli.run(command) }) else { return [:] }
        var out: [Int: String] = [:]
        for row in EnrollmentParsing.rows(data) {
            if let id = EnrollmentParsing.int(row["id"]), let name = EnrollmentParsing.string(row["name"]) { out[id] = name }
        }
        return out
    }

    func depTokenNames() async -> [String: String] {
        guard let data = try? await cli.run(.depTokens) else { return [:] }
        var out: [String: String] = [:]
        for row in EnrollmentParsing.rows(data) {
            if let id = EnrollmentParsing.string(row["id"]) {
                out[id] = EnrollmentParsing.string(row["orgName"]) ?? EnrollmentParsing.string(row["name"]) ?? id
            }
        }
        return out
    }

    func checkInMinutes() async -> Int? {
        guard let data = try? await cli.run(.clientCheckInSettings) else { return nil }
        return EnrollmentParsing.checkInMinutes(data)
    }

    func appInstallers() async -> [AppInstallerDeployment] {
        guard let data = try? await cli.run(.appInstallerDeployments) else { return [] }
        let rows = EnrollmentParsing.rows(data)
        guard let rowsData = try? JSONSerialization.data(withJSONObject: rows) else { return [] }
        return (try? JSONDecoder().decode([AppInstallerDeployment].self, from: rowsData)) ?? []
    }

    // MARK: - Scope scan

    /// Reads every policy and profile detail to learn their scope and triggers. On large
    /// instances this is hundreds of calls, so it runs six at a time and reports progress.
    func scanScopes(progress: @escaping @Sendable (Int, Int) async -> Void) async throws -> ScopeScanResult {
        async let policyNames = namedList(.policies)
        async let profileNames = namedList(.configProfiles)
        let policies = await policyNames, profiles = await profileNames
        guard !policies.isEmpty || !profiles.isEmpty else {
            throw CLIError.decodingFailed("Couldn't read the policy and profile lists")
        }

        enum Job: Sendable { case policy(Int, String), profile(Int, String) }
        let jobs = policies.map { Job.policy($0.key, $0.value) } + profiles.map { Job.profile($0.key, $0.value) }
        enum Outcome: Sendable { case policy(ScopedPolicy), profile(ScopedProfile), failed }

        var scannedPolicies: [ScopedPolicy] = []
        var scannedProfiles: [ScopedProfile] = []
        var failures = 0
        var done = 0
        await progress(0, jobs.count)
        let cli = self.cli
        for chunk in stride(from: 0, to: jobs.count, by: 6).map({ Array(jobs[$0 ..< min($0 + 6, jobs.count)]) }) {
            try Task.checkCancellation()
            await withTaskGroup(of: Outcome.self) { group in
                for job in chunk {
                    group.addTask {
                        switch job {
                        case .policy(let id, let name):
                            guard let data = try? await cli.run(.policyDetail(id: id)) else { return .failed }
                            return .policy(EnrollmentParsing.scopedPolicy(data, id: id, fallbackName: name))
                        case .profile(let id, let name):
                            guard let data = try? await cli.run(.configProfileDetail(id: id)) else { return .failed }
                            return .profile(EnrollmentParsing.scopedProfile(data, id: id, fallbackName: name))
                        }
                    }
                }
                for await outcome in group {
                    switch outcome {
                    case .policy(let p): scannedPolicies.append(p)
                    case .profile(let p): scannedProfiles.append(p)
                    case .failed: failures += 1
                    }
                }
            }
            done += chunk.count
            await progress(done, jobs.count)
        }
        return ScopeScanResult(
            profiles: scannedProfiles.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
            policies: scannedPolicies.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
            failures: failures, scannedAt: Date())
    }
}

/// In-memory cache for lists that rarely change during a session. Nothing is written to disk.
actor EnrollmentListCache {
    private var entries: [String: (data: Data, at: Date)] = [:]
    private let lifetime: TimeInterval = 10 * 60

    /// Cached data for `key`, or the result of `load` (cached when it isn't nil).
    func data(for key: String, load: @Sendable () async -> Data?) async -> Data? {
        if let hit = entries[key], Date().timeIntervalSince(hit.at) < lifetime { return hit.data }
        guard let fresh = await load() else { return nil }
        entries[key] = (fresh, Date())
        return fresh
    }

    func removeAll() { entries.removeAll() }
}
