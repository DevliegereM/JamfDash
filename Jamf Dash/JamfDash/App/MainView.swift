import SwiftUI

struct MainView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(AppState.self) private var appState
    @State private var selection: SidebarItem?

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
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
                EnrollmentView(vm: env.fleetVM)

            // MARK: Jamf Protect
            case .protectOverview:
                ProtectOverviewView(vm: env.protectVM)
            case .protectEvents:
                ProtectEventsView()
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

            case nil:
                ContentUnavailableView("Select a section", systemImage: "sidebar.left")
            }
        }
        .task {
            // Set initial selection based on the active product
            if selection == nil {
                selection = SidebarItem.items(for: env.currentProduct).first
            }
        }
        .onChange(of: env.currentProduct) { _, newProduct in
            selection = SidebarItem.items(for: newProduct).first
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
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
}
