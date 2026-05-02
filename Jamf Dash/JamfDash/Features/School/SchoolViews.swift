import SwiftUI

// MARK: - Overview

struct SchoolOverviewView: View {
    @Bindable var vm: SchoolViewModel
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Group {
            if env.isSyncing {
                SyncBar(
                    title: "Syncing Jamf School",
                    steps: env.syncStepLabels,
                    activeIndex: env.syncCompletedSteps
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                AsyncContentView(state: vm.overviewState, retry: { await vm.loadOverview(force: true) }) { _ in
                    let sections = vm.overviewSections
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 24) {
                            ForEach(sections, id: \.title) { section in
                                SchoolSectionBlock(title: section.title, items: section.items)
                            }
                        }
                        .padding(20)
                    }
                }
            }
        }
        .navigationTitle("School Overview")
        .toolbar { schoolRefreshButton { await vm.loadOverview(force: true) } }
        .task { await vm.loadOverview() }
    }
}

// MARK: - Devices

struct SchoolDevicesView: View {
    @Bindable var vm: SchoolViewModel

    var body: some View {
        AsyncContentView(state: vm.devicesState, retry: { await vm.loadDevices(force: true) }) { devices in
            Table(devices) {
                TableColumn("Name") { Text($0.displayName) }
                TableColumn("Serial") { Text($0.serialNumber ?? "—").foregroundStyle(.secondary) }
                TableColumn("Model") { Text($0.model ?? "—").foregroundStyle(.secondary) }
                TableColumn("OS") { Text($0.osVersion ?? "—").foregroundStyle(.secondary) }
                TableColumn("Managed") {
                    if let managed = $0.managed {
                        Image(systemName: managed ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(managed ? .green : .red)
                    } else {
                        Text("—").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("School Devices")
        .toolbar { schoolRefreshButton { await vm.loadDevices(force: true) } }
        .task { await vm.loadDevices() }
    }
}

// MARK: - Device Groups

struct SchoolDeviceGroupsView: View {
    @Bindable var vm: SchoolViewModel

    var body: some View {
        AsyncContentView(state: vm.deviceGroupsState, retry: { await vm.loadDeviceGroups(force: true) }) { groups in
            Table(groups) {
                TableColumn("Name") { Text($0.name) }
                TableColumn("ID") { Text($0.id).foregroundStyle(.secondary).font(.caption) }
            }
        }
        .navigationTitle("Device Groups")
        .toolbar { schoolRefreshButton { await vm.loadDeviceGroups(force: true) } }
        .task { await vm.loadDeviceGroups() }
    }
}

// MARK: - Users

struct SchoolUsersView: View {
    @Bindable var vm: SchoolViewModel

    var body: some View {
        AsyncContentView(state: vm.usersState, retry: { await vm.loadUsers(force: true) }) { users in
            Table(users) {
                TableColumn("Name") { Text($0.displayName) }
                TableColumn("Username") { Text($0.username ?? "—").foregroundStyle(.secondary) }
                TableColumn("Email") { Text($0.email ?? "—").foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("School Users")
        .toolbar { schoolRefreshButton { await vm.loadUsers(force: true) } }
        .task { await vm.loadUsers() }
    }
}

// MARK: - User Groups

struct SchoolUserGroupsView: View {
    @Bindable var vm: SchoolViewModel

    var body: some View {
        AsyncContentView(state: vm.userGroupsState, retry: { await vm.loadUserGroups(force: true) }) { groups in
            Table(groups) {
                TableColumn("Name") { Text($0.name) }
                TableColumn("ID") { Text($0.id).foregroundStyle(.secondary).font(.caption) }
            }
        }
        .navigationTitle("User Groups")
        .toolbar { schoolRefreshButton { await vm.loadUserGroups(force: true) } }
        .task { await vm.loadUserGroups() }
    }
}

// MARK: - Classes

struct SchoolClassesView: View {
    @Bindable var vm: SchoolViewModel

    var body: some View {
        AsyncContentView(state: vm.classesState, retry: { await vm.loadClasses(force: true) }) { classes in
            Table(classes) {
                TableColumn("Name") { Text($0.name) }
                TableColumn("ID") { Text($0.id).foregroundStyle(.secondary).font(.caption) }
            }
        }
        .navigationTitle("Classes")
        .toolbar { schoolRefreshButton { await vm.loadClasses(force: true) } }
        .task { await vm.loadClasses() }
    }
}

// MARK: - Apps

struct SchoolAppsView: View {
    @Bindable var vm: SchoolViewModel

    var body: some View {
        AsyncContentView(state: vm.appsState, retry: { await vm.loadApps(force: true) }) { apps in
            Table(apps) {
                TableColumn("Name") { Text($0.name) }
                TableColumn("ID") { Text($0.id).foregroundStyle(.secondary).font(.caption) }
            }
        }
        .navigationTitle("Apps")
        .toolbar { schoolRefreshButton { await vm.loadApps(force: true) } }
        .task { await vm.loadApps() }
    }
}

// MARK: - Shared helpers

@MainActor @ToolbarContentBuilder
private func schoolRefreshButton(action: @escaping @MainActor () async -> Void) -> some ToolbarContent {
    ToolbarItem(placement: .primaryAction) {
        Button {
            Task { await action() }
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
        }
    }
}

private struct SchoolSectionBlock: View {
    let title: String
    let items: [OverviewItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DashSectionHeader(title, systemImage: "list.bullet")
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    HStack {
                        Text(item.resource)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(item.value)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 12)
                    .background(idx.isMultiple(of: 2) ? Color.primary.opacity(0.03) : Color.clear)

                    if idx < items.count - 1 {
                        Divider().padding(.horizontal, 12)
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }
}
