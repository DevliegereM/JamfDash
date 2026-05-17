import SwiftUI

// MARK: - Sidebar Items

enum SidebarItem: String, Identifiable {
    // Jamf Pro — existing
    case overview     = "pro.overview"
    case security     = "pro.security"
    case fleet        = "pro.fleet"
    case devices      = "pro.devices"
    case deviceSearch = "pro.deviceSearch"
    case reports      = "pro.reports"

    // Jamf Pro — new
    case mobileDevices       = "pro.mobileDevices"
    case orgBrowser          = "pro.orgBrowser"
    case extensionAttributes = "pro.extensionAttributes"
    case patchManagement     = "pro.patchManagement"
    case enrollment          = "pro.enrollment"
    case ddmMonitor = "pro.ddmMonitor"
    case blueprints = "pro.blueprints"
    case settingsInspector = "pro.settingsInspector"
    case complianceBenchmarks = "pro.complianceBenchmarks"
    case aiAssistant = "pro.aiAssistant"

    // Jamf Protect — existing
    case protectOverview  = "protect.overview"
    case protectEvents    = "protect.events"
    case protectComputers = "protect.computers"
    case protectPlans     = "protect.plans"
    case protectAlerts    = "protect.alerts"
    case protectInsights  = "protect.insights"
    case protectAuditLogs = "protect.auditLogs"

    // Jamf Protect — new
    case protectRemovableStorage = "protect.removableStorage"
    case protectUnifiedLogging   = "protect.unifiedLogging"
    case protectActionConfigs    = "protect.actionConfigs"
    case protectTelemetry        = "protect.telemetry"
    case protectPreventLists     = "protect.preventLists"
    case protectRoles            = "protect.roles"
    case protectUsers            = "protect.users"
    case protectGroups           = "protect.groups"
    case protectAPIClients       = "protect.apiClients"

    // Jamf School
    case schoolOverview      = "school.overview"
    case schoolDevices       = "school.devices"
    case schoolDeviceGroups  = "school.deviceGroups"
    case schoolUsers         = "school.users"
    case schoolUserGroups    = "school.userGroups"
    case schoolClasses       = "school.classes"
    case schoolApps          = "school.apps"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:          return "Overview"
        case .security:          return "Security Posture"
        case .fleet:             return "Fleet & Config"
        case .devices:           return "Devices"
        case .deviceSearch:      return "Device Lookup"
        case .reports:           return "Reports"
        case .mobileDevices:     return "Mobile Devices"
        case .orgBrowser:        return "Organization"
        case .extensionAttributes: return "Extension Attributes"
        case .patchManagement:   return "Patch Management"
        case .enrollment:        return "Enrollment"
        case .ddmMonitor:            return "DDM Monitor"
        case .blueprints:            return "Blueprints"
        case .complianceBenchmarks:  return "Compliance Benchmarks"
        case .aiAssistant:           return "AI Assistant"
        case .settingsInspector:     return "Settings Inspector"
        case .protectOverview:   return "Overview"
        case .protectEvents:     return "Alerts"
        case .protectComputers:  return "Computers"
        case .protectPlans:      return "Plans"
        case .protectAlerts:     return "Analytics"
        case .protectInsights:   return "Analytic Sets"
        case .protectAuditLogs:  return "Exception Sets"
        case .protectRemovableStorage: return "Removable Storage"
        case .protectUnifiedLogging:   return "Unified Logging"
        case .protectActionConfigs:    return "Action Configs"
        case .protectTelemetry:        return "Telemetry"
        case .protectPreventLists:     return "Prevent Lists"
        case .protectRoles:            return "Roles"
        case .protectUsers:            return "Users"
        case .protectGroups:           return "Groups"
        case .protectAPIClients:       return "API Clients"
        case .schoolOverview:    return "Overview"
        case .schoolDevices:     return "Devices"
        case .schoolDeviceGroups: return "Device Groups"
        case .schoolUsers:       return "Users"
        case .schoolUserGroups:  return "User Groups"
        case .schoolClasses:     return "Classes"
        case .schoolApps:        return "Apps"
        }
    }

    var icon: String {
        switch self {
        case .overview:          return "chart.bar.doc.horizontal"
        case .security:          return "lock.shield"
        case .fleet:             return "desktopcomputer"
        case .devices:           return "laptopcomputer.and.iphone"
        case .deviceSearch:      return "magnifyingglass.circle"
        case .reports:           return "doc.richtext"
        case .mobileDevices:     return "iphone"
        case .orgBrowser:        return "building.2"
        case .extensionAttributes: return "function"
        case .patchManagement:   return "bandage"
        case .enrollment:        return "person.badge.plus"
        case .ddmMonitor:            return "arrow.triangle.2.circlepath.circle"
        case .blueprints:            return "square.3.layers.3d"
        case .complianceBenchmarks:  return "checkmark.shield"
        case .aiAssistant:           return "brain.head.profile"
        case .settingsInspector:     return "slider.horizontal.3"
        case .protectOverview:   return "chart.bar.doc.horizontal"
        case .protectEvents:     return "exclamationmark.triangle"
        case .protectComputers:  return "laptopcomputer"
        case .protectPlans:      return "doc.badge.gearshape"
        case .protectAlerts:     return "waveform.path.ecg"
        case .protectInsights:   return "rectangle.stack"
        case .protectAuditLogs:  return "shield.slash"
        case .protectRemovableStorage: return "externaldrive"
        case .protectUnifiedLogging:   return "doc.text.magnifyingglass"
        case .protectActionConfigs:    return "bell.and.waveform"
        case .protectTelemetry:        return "chart.xyaxis.line"
        case .protectPreventLists:     return "hand.raised"
        case .protectRoles:            return "person.fill.badge.plus"
        case .protectUsers:            return "person.2"
        case .protectGroups:           return "person.3"
        case .protectAPIClients:       return "key"
        case .schoolOverview:    return "chart.bar.doc.horizontal"
        case .schoolDevices:     return "ipad.and.iphone"
        case .schoolDeviceGroups: return "rectangle.3.group"
        case .schoolUsers:       return "person.2"
        case .schoolUserGroups:  return "person.3"
        case .schoolClasses:     return "book"
        case .schoolApps:        return "app.badge"
        }
    }

    static func items(for product: JamfProduct) -> [SidebarItem] {
        switch product {
        case .pro:
            return [
                .overview, .security, .fleet, .devices, .deviceSearch, .ddmMonitor,
                .blueprints, .complianceBenchmarks,
                .mobileDevices,
                .orgBrowser, .extensionAttributes, .patchManagement, .enrollment,
                .settingsInspector,
                .reports, .aiAssistant
            ]
        case .protect:
            return [
                .protectOverview, .protectEvents, .protectComputers, .protectPlans,
                .protectAlerts, .protectInsights, .protectAuditLogs,
                .protectRemovableStorage, .protectUnifiedLogging, .protectActionConfigs,
                .protectTelemetry, .protectPreventLists, .protectRoles,
                .protectUsers, .protectGroups, .protectAPIClients
            ]
        case .school:
            return [.schoolOverview, .schoolDevices, .schoolDeviceGroups,
                    .schoolUsers, .schoolUserGroups, .schoolClasses, .schoolApps]
        }
    }
}

// MARK: - SidebarView

struct SidebarView: View {
    @Binding var selection: SidebarItem?
    @Environment(AppEnvironment.self) private var env
    @State private var showSwitchError = false
    @AppStorage("jamfDash.aiEnabled") private var isAIEnabled = false

    var body: some View {
        let items = SidebarItem.items(for: env.currentProduct).filter { $0 != .aiAssistant || isAIEnabled }
        List(items, selection: $selection) { item in
            Label(item.title, systemImage: item.icon)
                .tag(item)
        }
        .listStyle(.sidebar)
        .navigationTitle("Jamf Dash")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            instancePickerBar
        }
        .onChange(of: env.currentProduct) { _, _ in
            selection = SidebarItem.items(for: env.currentProduct).first
        }
        .onChange(of: env.switchError) { _, error in
            showSwitchError = error != nil
        }
        .alert("Connection Failed", isPresented: $showSwitchError) {
            Button("OK") { env.clearSwitchError() }
        } message: {
            Text(env.switchError ?? "")
        }
    }

    // MARK: - Demo product picker

    @ViewBuilder
    private var demoProductPicker: some View {
        VStack(spacing: 6) {
            Picker("Product", selection: Binding(
                get: { env.currentProduct },
                set: { env.switchDemoProduct($0) }
            )) {
                ForEach(JamfProduct.allCases, id: \.self) { product in
                    Text(product.displayName).tag(product)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)

            Text("Demo Mode")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
        }
        .padding(.top, 8)
        .background(.bar)
    }

    // MARK: - Instance picker pinned at the bottom of the sidebar

    @ViewBuilder
    private var instancePickerBar: some View {
        VStack(spacing: 0) {
            Divider()
            if env.isDemoMode {
                demoProductPicker
            } else if env.availableProfiles.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: env.currentProduct.icon)
                        .foregroundStyle(.secondary)
                        .imageScale(.small)
                    Text(env.currentProfileName.isEmpty ? "Default Instance" : env.currentProfileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)
            } else {
                Menu {
                    ForEach(env.availableProfiles, id: \.self) { profile in
                        Button {
                            env.switchInstance(to: profile)
                        } label: {
                            HStack {
                                Text(profile)
                                if profile == env.currentProfileName {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .disabled(env.isSwitchingProfile)
                    }
                } label: {
                    HStack(spacing: 8) {
                        if env.isSwitchingProfile {
                            ProgressView()
                                .scaleEffect(0.65)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: env.currentProduct.icon)
                                .foregroundStyle(.secondary)
                                .imageScale(.small)
                        }
                        Text(env.isSwitchingProfile ? "Verifying…" : (env.currentProfileName.isEmpty ? "Default Instance" : env.currentProfileName))
                            .font(.caption)
                            .foregroundStyle(env.isSwitchingProfile ? .secondary : .primary)
                            .lineLimit(1)
                        Spacer()
                        if !env.isSwitchingProfile {
                            Image(systemName: "chevron.up.chevron.down")
                                .foregroundStyle(.secondary)
                                .font(.caption2)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .disabled(env.isSwitchingProfile)
                .background(.bar)
            }
        }
    }
}
