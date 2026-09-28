import AppKit
import SwiftUI

struct MainView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(AppState.self) private var appState
    @State private var selection: SidebarItem?
    @State private var showNotificationPopover = false
    @State private var showCrashBanner = false

    var body: some View {
        splitView
            .safeAreaInset(edge: .top, spacing: 0) {
                if showCrashBanner {
                    CrashReportBanner {
                        CrashReports.markSeen()
                        showCrashBanner = false
                    }
                }
            }
            .task { showCrashBanner = CrashReports.unseenCrash() != nil }
    }

    private var splitView: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 360)
        } detail: {
            switch selection {
            // MARK: Jamf Pro
            case .overview:
                OverviewView(vm: env.overviewVM)
            case .security:
                SecurityView(vm: env.securityVM)
            case .fleet:
                FleetView(vm: env.fleetVM)
            case .devices:
                DevicesView(vm: env.devicesVM)
            case .deviceSearch:
                DeviceSearchView(vm: env.deviceSearchVM)
            case .reports:
                ReportView()
            case .mobileDevices:
                MobileDevicesView(vm: env.mobileDevicesVM)
            case .orgBrowser:
                OrgBrowserView(vm: env.fleetVM)
            case .extensionAttributes:
                ExtensionAttributesView(vm: env.fleetVM)
            case .patchManagement:
                PatchView(vm: env.fleetVM)

            case .enrollment:
                EnrollmentSectionView(vm: env.enrollmentVM, fleetVM: env.fleetVM)
            case .settingsInspector:
                SettingsInspectorView(vm: env.settingsInspectorVM)
            case .ddmMonitor:
                DDMMonitorView(vm: env.ddmMonitorVM)
            case .blueprints:
                BlueprintsView(vm: env.platformVM)
            case .complianceBenchmarks:
                ComplianceBenchmarksView(vm: env.platformVM)
            case .aiAssistant:
                AIAssistantView(vm: env.aiAssistantVM)
            case .driftTracker:
                DriftTrackerView(vm: env.driftVM)
            case .deviceCorrelation:
                CorrelationView(vm: env.correlationVM)
            case .auditDashboard:
                AuditView(vm: env.auditVM)
            case .securityCloud:
                if let jscVM = env.jscVM {
                    JamfSecurityView(vm: jscVM)
                } else {
                    ContentUnavailableView(
                        "Security Cloud Not Configured",
                        systemImage: "shield.checkered",
                        description: Text("Add your Jamf Security Cloud credentials in Settings → Security Cloud.")
                    )
                }
            // MARK: Jamf Protect
            case .protectOverview:
                ProtectOverviewView(vm: env.protectVM)
            case .protectEvents:
                ProtectEventsView(vm: env.protectVM)
            case .protectComputers:
                ProtectComputersView(vm: env.protectVM)
            case .protectPlans:
                ProtectPlansView(vm: env.protectVM)
            case .protectAlerts:
                ProtectAlertsView(vm: env.protectVM)
            case .protectInsights:
                ProtectInsightsView(vm: env.protectVM)
            case .protectAuditLogs:
                ProtectAuditLogsView(vm: env.protectVM)
            case .protectRemovableStorage:
                ProtectRemovableStorageView(vm: env.protectVM)
            case .protectUnifiedLogging:
                ProtectUnifiedLoggingView(vm: env.protectVM)
            case .protectActionConfigs:
                ProtectActionConfigsView(vm: env.protectVM)
            case .protectTelemetry:
                ProtectTelemetryView(vm: env.protectVM)
            case .protectPreventLists:
                ProtectPreventListsView(vm: env.protectVM)
            case .protectRoles:
                ProtectRolesView(vm: env.protectVM)
            case .protectUsers:
                ProtectUsersView(vm: env.protectVM)
            case .protectGroups:
                ProtectGroupsView(vm: env.protectVM)
            case .protectAPIClients:
                ProtectAPIClientsView(vm: env.protectVM)

            // MARK: Jamf School
            case .schoolOverview:
                SchoolOverviewView(vm: env.schoolVM)
            case .schoolDevices:
                SchoolDevicesView(vm: env.schoolVM)
            case .schoolDeviceGroups:
                SchoolDeviceGroupsView(vm: env.schoolVM)
            case .schoolUsers:
                SchoolUsersView(vm: env.schoolVM)
            case .schoolUserGroups:
                SchoolUserGroupsView(vm: env.schoolVM)
            case .schoolClasses:
                SchoolClassesView(vm: env.schoolVM)
            case .schoolApps:
                SchoolAppsView(vm: env.schoolVM)
            case .schoolProfiles:
                SchoolProfilesView(vm: env.schoolVM)
            case .schoolDepDevices:
                SchoolDepDevicesView(vm: env.schoolVM)

            case nil:
                ContentUnavailableView("Select a section", systemImage: "sidebar.left")
            }
        }
        .task {
            // Defer initial selection until sync is done so NavigationSplitView
            // can't auto-select .overview and leak "Overview" into the title bar
            // while the launch overlay is still visible.
            if selection == nil && !env.isSyncing {
                selection = SidebarItem.items(for: env.currentProduct).first
            }
        }
        .onChange(of: env.isSyncing) { _, syncing in
            // Once the initial sync completes, make the first selection.
            if !syncing && selection == nil {
                selection = SidebarItem.items(for: env.currentProduct).first
            }
        }
        .onChange(of: env.requestedSection) { _, requested in
            guard let requested else { return }
            selection = requested
            env.requestedSection = nil
        }
        .onChange(of: env.currentProduct) { _, newProduct in
            selection = SidebarItem.items(for: newProduct).first
        }
        .onChange(of: env.profileSwitchCount) { _, _ in
            selection = SidebarItem.items(for: env.currentProduct).first
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshCurrentView)) { _ in
            refreshCurrentView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openDeviceSearch)) { _ in
            selection = .deviceSearch
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSidebarItem)) { notification in
            guard let raw = notification.userInfo?["item"] as? String,
                  let item = SidebarItem(rawValue: raw),
                  SidebarItem.items(for: env.currentProduct).contains(item) else { return }
            selection = item
            NSApp.activate()
            NSApp.windows.first { $0.title != "Jamf Dash Help" && $0.isVisible && $0.canBecomeMain }?
                .makeKeyAndOrderFront(nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToSidebarItem)) { notification in
            guard let index = notification.userInfo?["index"] as? Int else { return }
            let items = SidebarItem.items(for: env.currentProduct)
            if index < items.count {
                selection = items[index]
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if env.currentProduct == .pro && env.notificationCount > 0 {
                    Button {
                        showNotificationPopover.toggle()
                    } label: {
                        Image(systemName: "bell.badge.fill")
                            .foregroundStyle(.orange)
                            .symbolEffect(.bounce, value: env.notificationCount)
                    }
                    .help("\(env.notificationCount) system notification(s)")
                    .accessibilityLabel("\(env.notificationCount) system notifications")
                    .popover(isPresented: $showNotificationPopover) {
                        NotificationPanelView(notifications: env.notificationsState.value ?? [])
                    }
                }
                if appState.isDemoMode {
                    Label("Demo Mode", systemImage: "theatermask.and.paintbrush")
                        .labelStyle(.titleAndIcon)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color.purple)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.purple.opacity(0.12))
                        .clipShape(Capsule())
                }

                if let version = appState.updateAvailable {
                    if appState.isUpdatingBinary {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Updating…").font(.callout).foregroundStyle(.secondary)
                        }
                    } else {
                        Button {
                            Task { await appState.performBinaryUpdate() }
                        } label: {
                            Label("jamf-cli \(version) available", systemImage: "arrow.down.circle.fill")
                                .labelStyle(.titleAndIcon)
                                .font(.callout)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                        .help("Update jamf-cli to version \(version)")
                    }
                }
            }
        }
    }

    private func refreshCurrentView() {
        switch selection {
        case .overview:
            Task { await env.overviewVM.load(force: true) }
        case .security:
            Task { await env.securityVM.load(force: true) }
        case .fleet, .orgBrowser, .extensionAttributes, .patchManagement:
            Task { await env.fleetVM.loadAll(force: true) }
        case .enrollment:
            Task {
                if env.enrollmentVM.tab == .setup { await env.fleetVM.loadAll(force: true) }
                else { await env.enrollmentVM.refresh() }
            }
        case .devices:
            Task { await env.devicesVM.load(force: true) }
        case .mobileDevices:
            Task { await env.mobileDevicesVM.load(force: true) }
        case .ddmMonitor:
            Task { await env.ddmMonitorVM.load(force: true) }
        case .blueprints:
            Task { await env.platformVM.loadBlueprints(force: true) }
        case .complianceBenchmarks:
            Task { await env.platformVM.loadComplianceBenchmarks(force: true) }
        case .protectRemovableStorage: Task { await env.protectVM.loadRemovableStorage(force: true) }
        case .protectUnifiedLogging:   Task { await env.protectVM.loadUnifiedLogging(force: true) }
        case .protectActionConfigs:    Task { await env.protectVM.loadActionConfigs(force: true) }
        case .protectTelemetry:        Task { await env.protectVM.loadTelemetry(force: true) }
        case .protectPreventLists:     Task { await env.protectVM.loadPreventLists(force: true) }
        case .protectRoles:            Task { await env.protectVM.loadRoles(force: true) }
        case .protectUsers:            Task { await env.protectVM.loadUsers(force: true) }
        case .protectGroups:           Task { await env.protectVM.loadGroups(force: true) }
        case .protectAPIClients:       Task { await env.protectVM.loadAPIClients(force: true) }
        case .protectOverview, .protectEvents, .protectComputers, .protectPlans,
             .protectAlerts, .protectInsights, .protectAuditLogs:
            Task { await env.protectVM.load(force: true) }
        case .schoolOverview, .schoolDevices, .schoolDeviceGroups, .schoolUsers,
             .schoolUserGroups, .schoolClasses, .schoolApps,
             .schoolProfiles, .schoolDepDevices:
            Task { await env.schoolVM.load(force: true) }
        case .settingsInspector:
            Task { await env.settingsInspectorVM.load(force: true) }
        case .driftTracker:
            Task { await env.driftVM.loadEvents() }
        case .auditDashboard:
            Task { await env.auditVM.load(force: true) }
        case .securityCloud:
            Task { await env.jscVM?.load(force: true) }
        case .deviceSearch, .reports, .aiAssistant, .deviceCorrelation, nil:
            break
        }
    }
}

// MARK: - Notification Panel

private struct NotificationPanelView: View {
    let notifications: [ProNotification]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("System Notifications", systemImage: "bell.fill")
                    .font(.headline)
                Spacer()
                Text("\(notifications.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.orange, in: Capsule())
            }
            .padding()

            Divider()

            if notifications.isEmpty {
                Text("No active notifications")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(notifications) { notif in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: notif.severityIcon)
                                    .foregroundStyle(notif.severityColor)
                                    .font(.body)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(notif.type.replacingOccurrences(of: "_", with: " ").capitalized)
                                        .font(.caption.weight(.semibold))
                                    Text(notif.message)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                    if let exp = notif.expirationDate {
                                        Text("Expires: \(exp)")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                            .accessibilityElement(children: .combine)

                            if notif.id != notifications.last?.id {
                                Divider().padding(.leading, 40)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(width: 340)
        .frame(minHeight: 200, maxHeight: 480)
    }
}
