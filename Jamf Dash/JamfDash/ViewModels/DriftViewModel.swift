import Foundation
import OSLog
import Observation

// MARK: - DriftViewModel

@MainActor
@Observable
final class DriftViewModel {

    // MARK: Properties

    private static let logger = Logger(subsystem: "com.jamfdash", category: "DriftViewModel")
    private let cli: any CLIRunning
    private let store: DriftStore

    private(set) var eventsState: LoadState<[DriftEvent]> = .idle
    private(set) var isSnapshotting: Bool = false
    private(set) var snapshotCount: Int = 0
    private(set) var lastSnapshotDate: Date? = nil

    var filterType: DriftItemType? = nil
    var filterChange: DriftChangeType? = nil

    // MARK: Initialization

    init(cli: any CLIRunning, store: DriftStore = .shared) {
        self.cli = cli
        self.store = store
    }

    // MARK: Public Methods

    func loadEvents() async {
        eventsState = .loading
        let events = store.fetchAllDriftEvents()
        eventsState = .loaded(events)
        snapshotCount = store.snapshotCount
        lastSnapshotDate = events.first?.detectedAt
    }

    func takeSnapshot() async {
        guard !isSnapshotting else { return }
        isSnapshotting = true
        defer { isSnapshotting = false }

        Self.logger.info("Starting configuration drift snapshot")

        do {
            // Fetch all three data types in parallel
            async let policiesData = cli.run(.policies)
            async let profilesData = cli.run(.configProfiles)
            async let scriptsData = cli.run(.scripts)

            let (policyBytes, profileBytes, scriptBytes) = try await (policiesData, profilesData, scriptsData)

            let policies = decodeList(Policy.self, from: policyBytes)
            let profiles = decodeList(ConfigProfile.self, from: profileBytes)
            let scripts = decodeList(JamfScript.self, from: scriptBytes)

            let now = Date()
            let isoDate = ISO8601DateFormatter().string(from: now)

            // Fetch previous snapshots
            let previousPolicies = store.fetchLatestSnapshotItems(for: .policy)
            let previousProfiles = store.fetchLatestSnapshotItems(for: .profile)
            let previousScripts = store.fetchLatestSnapshotItems(for: .script)

            // Build current rows
            let currentPolicies = policies.map {
                SnapshotItemRow(itemId: String($0.id), name: $0.name, category: $0.category?.name)
            }
            let currentProfiles = profiles.map {
                SnapshotItemRow(itemId: String($0.id), name: $0.name, category: nil)
            }
            let currentScripts = scripts.map {
                SnapshotItemRow(itemId: $0.id, name: $0.name, category: $0.category?.name)
            }

            // Compute diffs
            var allEvents: [DriftEvent] = []
            allEvents += computeDiff(previous: previousPolicies, current: currentPolicies, type: .policy, now: now)
            allEvents += computeDiff(previous: previousProfiles, current: currentProfiles, type: .profile, now: now)
            allEvents += computeDiff(previous: previousScripts, current: currentScripts, type: .script, now: now)

            // Persist
            let snapshotId = store.insertSnapshot(takenAt: isoDate)
            store.insertSnapshotItems(currentPolicies, type: .policy, snapshotId: snapshotId)
            store.insertSnapshotItems(currentProfiles, type: .profile, snapshotId: snapshotId)
            store.insertSnapshotItems(currentScripts, type: .script, snapshotId: snapshotId)
            store.insertDriftEvents(allEvents)
            store.pruneSnapshots(keepLast: 50)

            snapshotCount = store.snapshotCount
            Self.logger.info("Snapshot complete — \(allEvents.count) drift event(s) detected")

            await loadEvents()
        } catch {
            Self.logger.error("Snapshot failed: \(error)")
            // Reload existing events so the UI isn't left in a broken state
            await loadEvents()
        }
    }

    // MARK: Filtered accessors

    var filteredEvents: [DriftEvent] {
        guard case .loaded(let events) = eventsState else { return [] }
        return events.filter { event in
            if let type = filterType, event.itemType != type { return false }
            if let change = filterChange, event.changeType != change { return false }
            return true
        }
    }

    var groupedEvents: [(key: String, events: [DriftEvent])] {
        let events = filteredEvents
        guard !events.isEmpty else { return [] }
        var order: [String] = []
        var groups: [String: [DriftEvent]] = [:]
        for event in events {
            let key = event.dayKey
            if groups[key] == nil {
                order.append(key)
                groups[key] = []
            }
            groups[key]?.append(event)
        }
        return order.compactMap { key in
            guard let sectionEvents = groups[key] else { return nil }
            return (key: key, events: sectionEvents)
        }
    }

    // MARK: Private Methods

    private func decodeList<T: Decodable>(_ type: T.Type, from data: Data) -> [T] {
        let decoder = JSONDecoder()

        if let direct = try? decoder.decode([T].self, from: data) {
            return direct
        }

        // Fallback: try extracting a "results" array from a paged wrapper
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let resultsArray = json["results"],
           let resultsData = try? JSONSerialization.data(withJSONObject: resultsArray),
           let decoded = try? decoder.decode([T].self, from: resultsData) {
            return decoded
        }

        Self.logger.warning("Failed to decode [\(String(describing: T.self))] — returning empty array")
        return []
    }

    private func computeDiff(
        previous: [SnapshotItemRow],
        current: [SnapshotItemRow],
        type: DriftItemType,
        now: Date
    ) -> [DriftEvent] {
        let previousMap = Dictionary(uniqueKeysWithValues: previous.map { ($0.itemId, $0) })
        let currentMap = Dictionary(uniqueKeysWithValues: current.map { ($0.itemId, $0) })

        var events: [DriftEvent] = []

        // Added: in current but not in previous
        for (itemId, row) in currentMap where previousMap[itemId] == nil {
            events.append(DriftEvent(
                id: 0,
                detectedAt: now,
                itemType: type,
                itemId: itemId,
                itemName: row.name,
                changeType: .added,
                oldValue: nil,
                newValue: nil
            ))
        }

        // Removed: in previous but not in current
        for (itemId, row) in previousMap where currentMap[itemId] == nil {
            events.append(DriftEvent(
                id: 0,
                detectedAt: now,
                itemType: type,
                itemId: itemId,
                itemName: row.name,
                changeType: .removed,
                oldValue: nil,
                newValue: nil
            ))
        }

        // Modified: in both but name or category differs
        for (itemId, currentRow) in currentMap {
            guard let previousRow = previousMap[itemId] else { continue }
            guard currentRow.name != previousRow.name || currentRow.category != previousRow.category else { continue }

            let oldDict: [String: String?] = ["name": previousRow.name, "category": previousRow.category]
            let newDict: [String: String?] = ["name": currentRow.name, "category": currentRow.category]

            let oldValue = (try? JSONSerialization.data(withJSONObject: oldDict.compactMapValues { $0 }))
                .flatMap { String(data: $0, encoding: .utf8) }
            let newValue = (try? JSONSerialization.data(withJSONObject: newDict.compactMapValues { $0 }))
                .flatMap { String(data: $0, encoding: .utf8) }

            events.append(DriftEvent(
                id: 0,
                detectedAt: now,
                itemType: type,
                itemId: itemId,
                itemName: currentRow.name,
                changeType: .modified,
                oldValue: oldValue,
                newValue: newValue
            ))
        }

        return events
    }
}
