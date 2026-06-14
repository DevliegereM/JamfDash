import SwiftUI

// MARK: - DriftTrackerView

struct DriftTrackerView: View {
    @Bindable var vm: DriftViewModel
    @State private var selectedEvent: DriftEvent? = nil

    var body: some View {
        VStack(spacing: 0) {
            snapshotSubtitle
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            Divider()

            AsyncContentView(state: vm.eventsState, retry: { await vm.loadEvents() }) { _ in
                if vm.groupedEvents.isEmpty {
                    DriftEmptyStateView(onSnapshot: { await vm.takeSnapshot() })
                } else {
                    List {
                        ForEach(vm.groupedEvents, id: \.key) { section in
                            Section(section.key) {
                                ForEach(section.events) { event in
                                    Button { selectedEvent = event } label: {
                                        DriftEventRow(event: event)
                                    }
                                    .buttonStyle(.plain)
                                    .contentShape(Rectangle())
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }
        }
        .navigationTitle("Configuration Drift")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await vm.takeSnapshot() }
                } label: {
                    if vm.isSnapshotting {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 14, height: 14)
                            Text("Snapshotting…")
                        }
                    } else {
                        Label("Snapshot Now", systemImage: "camera.badge.clock")
                    }
                }
                .disabled(vm.isSnapshotting)
                .help("Capture current state of policies, profiles and scripts and compare against the previous snapshot")
            }

            ToolbarItem(placement: .primaryAction) {
                Picker("Type", selection: $vm.filterType) {
                    Text("All").tag(Optional<DriftItemType>.none)
                    ForEach(DriftItemType.allCases, id: \.self) { type in
                        Label(type.displayName, systemImage: type.icon).tag(Optional(type))
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                .help("Filter by item type")
            }

            ToolbarItem(placement: .primaryAction) {
                Picker("Change", selection: $vm.filterChange) {
                    Text("All").tag(Optional<DriftChangeType>.none)
                    Label("Added", systemImage: DriftChangeType.added.icon).tag(Optional(DriftChangeType.added))
                    Label("Modified", systemImage: DriftChangeType.modified.icon).tag(Optional(DriftChangeType.modified))
                    Label("Removed", systemImage: DriftChangeType.removed.icon).tag(Optional(DriftChangeType.removed))
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                .help("Filter by change type")
            }
        }
        .sheet(item: $selectedEvent) { event in
            DriftDiffSheet(event: event)
        }
        .task { await vm.loadEvents() }
        .liquidGlassToolbar()
    }

    // MARK: - Subtitle

    private var snapshotSubtitle: some View {
        HStack {
            Image(systemName: "clock.badge.checkmark")
                .foregroundStyle(.secondary)
            if vm.snapshotCount == 0 {
                Text("No snapshots taken yet")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                Text("\(vm.snapshotCount) snapshot\(vm.snapshotCount == 1 ? "" : "s") taken")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                if let date = vm.lastSnapshotDate {
                    Text("— last change detected \(RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date()))")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
            }
            Spacer()
        }
    }
}

// MARK: - DriftEventRow

private struct DriftEventRow: View {
    let event: DriftEvent

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: event.changeType.icon)
                .foregroundStyle(event.changeType.color)
                .font(.system(size: 18))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(event.itemName)
                        .font(.body)
                        .lineLimit(1)

                    Text(event.itemType.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                        .foregroundStyle(.secondary)
                }

                Text(event.detectedAtFormatted)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Text(event.changeType.label)
                .font(.caption)
                .foregroundStyle(event.changeType.color)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - DriftEmptyStateView

private struct DriftEmptyStateView: View {
    let onSnapshot: () async -> Void

    var body: some View {
        VStack(spacing: 20) {
            ContentUnavailableView(
                "No Drift Events",
                systemImage: "clock.badge.checkmark",
                description: Text("Take a snapshot to start tracking changes to policies, profiles, and scripts.")
            )

            Button {
                Task { await onSnapshot() }
            } label: {
                Label("Take First Snapshot", systemImage: "camera.badge.clock")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

// MARK: - DriftDiffSheet

private struct DriftDiffSheet: View {
    let event: DriftEvent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: event.changeType.icon)
                    .font(.system(size: 28))
                    .foregroundStyle(event.changeType.color)

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.itemName)
                        .font(.headline)
                    HStack(spacing: 6) {
                        Text(event.changeType.label)
                            .foregroundStyle(event.changeType.color)
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(event.itemType.displayName)
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }

                Spacer()

                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(20)

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Group {
                        switch event.changeType {
                        case .modified:
                            modifiedContent
                        case .added:
                            addedContent
                        case .removed:
                            removedContent
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 480, minHeight: 300)
    }

    // MARK: - Content variants

    private var modifiedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Changes")
                .font(.headline)

            Grid(horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Field")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Before")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("After")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()
                    .gridCellUnsizedAxes(.horizontal)

                let oldDict = parseValueDict(event.oldValue)
                let newDict = parseValueDict(event.newValue)
                let fields = ["name", "category"]

                ForEach(fields, id: \.self) { field in
                    let oldVal = oldDict[field] ?? "—"
                    let newVal = newDict[field] ?? "—"
                    if oldVal != newVal {
                        GridRow {
                            Text(field.capitalized)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(oldVal)
                                .foregroundStyle(.red.opacity(0.8))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(newVal)
                                .foregroundStyle(.green.opacity(0.8))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.callout)
                    }
                }
            }
            .padding(12)
            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var addedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Item")
                .font(.headline)
            let dict = parseValueDict(event.newValue)
            infoGrid(dict: dict)
        }
    }

    private var removedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Removed Item")
                .font(.headline)
            let dict = parseValueDict(event.oldValue)
            infoGrid(dict: dict)
        }
    }

    private func infoGrid(dict: [String: String]) -> some View {
        Grid(horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                Text("Name")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(dict["name"] ?? event.itemName)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            GridRow {
                Text("Category")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(dict["category"] ?? "—")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.callout)
        .padding(12)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Helpers

    private func parseValueDict(_ json: String?) -> [String: String] {
        guard let json, let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        return dict
    }
}
