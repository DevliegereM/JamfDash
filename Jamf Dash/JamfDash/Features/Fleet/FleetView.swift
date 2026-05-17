import SwiftUI

struct FleetView: View {
    @Bindable var vm: FleetViewModel
    @Environment(AppEnvironment.self) private var env
    @State private var selectedTab = 0
    @State private var selectedSmartGroup: SmartComputerGroup? = nil
    @State private var selectedPolicy: Policy? = nil
    @State private var selectedConfigProfile: ConfigProfile? = nil
    @State private var selectedScript: JamfScript? = nil
    @State private var selectedPackage: JamfPackage? = nil

    private func consoleURL(_ path: String) -> URL? {
        guard let base = env.currentServerURL else { return nil }
        let root = base.hasSuffix("/") ? String(base.dropLast()) : base
        return URL(string: "\(root)\(path)")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search + tabs
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search…", text: $vm.searchText)
                        .textFieldStyle(.plain)
                    if !vm.searchText.isEmpty {
                        Button {
                            vm.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.regularMaterial)

                Picker("Category", selection: $selectedTab) {
                    Text("Policies").tag(0)
                    Text("Smart Groups").tag(1)
                    Text("Scripts").tag(2)
                    Text("Packages").tag(3)
                    Text("Config Profiles").tag(4)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(.regularMaterial)
            }

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    switch selectedTab {
                    case 0: policiesContent
                    case 1: groupsContent
                    case 2: scriptsContent
                    case 3: packagesContent
                    case 4: configProfilesContent
                    default: EmptyView()
                    }
                }
                .padding(.vertical, 12)
            }
            .id(selectedTab)
        }
        .navigationTitle("Fleet & Configuration")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await vm.loadAll(force: true) } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .sheet(item: $selectedSmartGroup) { group in
            SmartGroupMemberSheet(group: group, vm: vm)
                .onAppear { Task { await vm.loadSmartGroupDetail(id: group.id) } }
                .onDisappear { selectedSmartGroup = nil }
        }
        .sheet(item: $selectedPolicy) { policy in
            PolicyScopeSheet(policy: policy, vm: vm)
                .onAppear { Task { await vm.loadPolicyScope(id: policy.id) } }
                .onDisappear { selectedPolicy = nil }
        }
        .sheet(item: $selectedConfigProfile) { profile in
            ConfigProfileScopeSheet(profile: profile, vm: vm)
                .onAppear { Task { await vm.loadConfigProfileScope(id: profile.id) } }
                .onDisappear { selectedConfigProfile = nil }
        }
        .sheet(item: $selectedScript) { script in
            ScriptDetailSheet(script: script, vm: vm)
                .onAppear { Task { await vm.loadScriptDetail(id: script.id) } }
                .onDisappear { selectedScript = nil }
        }
        .sheet(item: $selectedPackage) { pkg in
            PackageDetailSheet(package: pkg, vm: vm)
                .onAppear { Task { await vm.loadPackageDetail(id: pkg.id) } }
                .onDisappear { selectedPackage = nil }
        }
    }

    // MARK: - Policies

    private var policiesContent: some View {
        Group {
            if vm.policiesState.isPending {
                SyncingIndicator().frame(maxWidth: .infinity, minHeight: 100)
            } else if let error = vm.policiesState.errorMessage {
                ErrorStateView(message: error) { await vm.loadPolicies() }
            } else if vm.policies.isEmpty {
                emptyState(icon: "list.bullet.rectangle", label: vm.searchText.isEmpty ? "No policies" : "No results")
            } else {
                ForEach(vm.policiesByCategory, id: \.name) { group in
                    CategorySection(title: group.name, count: group.policies.count) {
                        ForEach(group.policies) { policy in
                            Button {
                                selectedPolicy = policy
                            } label: {
                                FleetRow(
                                    name: policy.name,
                                    detail: policy.category?.name,
                                    consoleURL: consoleURL("/policies.html?id=\(policy.id)&o=r"),
                                    hasDetail: true
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Smart Groups

    private var groupsContent: some View {
        Group {
            if vm.groupsState.isPending {
                SyncingIndicator().frame(maxWidth: .infinity, minHeight: 100)
            } else if let error = vm.groupsState.errorMessage {
                ErrorStateView(message: error) { await vm.loadGroups() }
            } else if vm.smartGroups.isEmpty {
                emptyState(icon: "person.3", label: vm.searchText.isEmpty ? "No smart groups" : "No results")
            } else {
                CategorySection(title: "Smart Computer Groups", count: vm.smartGroups.count) {
                    ForEach(vm.smartGroups) { group in
                        Button {
                            selectedSmartGroup = group
                        } label: {
                            FleetRow(
                                name: group.name,
                                detail: nil,
                                consoleURL: consoleURL("/smartComputerGroups.html?id=\(group.id)&o=r"),
                                hasDetail: true
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Scripts

    private var scriptsContent: some View {
        Group {
            if vm.scriptsState.isPending {
                SyncingIndicator().frame(maxWidth: .infinity, minHeight: 100)
            } else if let error = vm.scriptsState.errorMessage {
                ErrorStateView(message: error) { await vm.loadScripts() }
            } else if vm.scripts.isEmpty {
                emptyState(icon: "doc.text", label: vm.searchText.isEmpty ? "No scripts" : "No results")
            } else {
                CategorySection(title: "Scripts", count: vm.scripts.count) {
                    ForEach(vm.scripts) { script in
                        Button {
                            selectedScript = script
                        } label: {
                            FleetRow(
                                name: script.name,
                                detail: script.category?.name,
                                consoleURL: consoleURL("/view/settings/computer-management/scripts/\(script.id)"),
                                hasDetail: true
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Packages

    private var packagesContent: some View {
        Group {
            if vm.packagesState.isPending {
                SyncingIndicator().frame(maxWidth: .infinity, minHeight: 100)
            } else if let error = vm.packagesState.errorMessage {
                ErrorStateView(message: error) { await vm.loadPackages() }
            } else if vm.packages.isEmpty {
                emptyState(icon: "shippingbox", label: vm.searchText.isEmpty ? "No packages" : "No results")
            } else {
                CategorySection(title: "Packages", count: vm.packages.count) {
                    ForEach(vm.packages) { pkg in
                        Button {
                            selectedPackage = pkg
                        } label: {
                            FleetRow(name: pkg.name, detail: nil, hasDetail: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Config Profiles

    private var configProfilesContent: some View {
        Group {
            if vm.configProfilesState.isPending {
                SyncingIndicator().frame(maxWidth: .infinity, minHeight: 100)
            } else if let error = vm.configProfilesState.errorMessage {
                ErrorStateView(message: error) { await vm.loadConfigProfiles() }
            } else if vm.configProfiles.isEmpty {
                emptyState(icon: "gearshape.2", label: vm.searchText.isEmpty ? "No configuration profiles" : "No results")
            } else {
                ForEach(vm.configProfilesByCategory, id: \.name) { group in
                    CategorySection(title: group.name, count: group.profiles.count) {
                        ForEach(group.profiles) { profile in
                            Button {
                                selectedConfigProfile = profile
                            } label: {
                                FleetRow(
                                    name: profile.name,
                                    detail: vm.configProfileCategoryMap[profile.id],
                                    consoleURL: consoleURL("/OSXConfigurationProfiles.html?id=\(profile.id)&o=r"),
                                    hasDetail: true
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func emptyState(icon: String, label: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(label)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }
}

// MARK: - Supporting views

private struct CategorySection<Content: View>: View {
    let title: String
    let count: Int
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.04))

            content()
        }
    }
}

private struct FleetRow: View {
    let name: String
    let detail: String?
    var consoleURL: URL? = nil
    var hasDetail: Bool = false

    var body: some View {
        HStack {
            Text(name).lineLimit(1)
            Spacer()
            if let d = detail {
                Text(d)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            if let url = consoleURL {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right.square")
                        .imageScale(.small)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Open in Jamf Pro")
            }
            if hasDetail {
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)

        Divider().padding(.horizontal, 20)
    }
}

// MARK: - Smart Group Inspector Sheet

private struct SmartGroupMemberSheet: View {
    let group: SmartComputerGroup
    @Bindable var vm: FleetViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sheetHeader
            Divider()
            readOnlyBanner
            Divider()
            sheetContent
        }
        .frame(minWidth: 500, minHeight: 400)
    }

    private var sheetHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(group.name)
                    .font(.title2)
                    .bold()
                Text("Smart Computer Group")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(20)
    }

    private var readOnlyBanner: some View {
        Label(
            "Criteria are read-only — editing smart groups requires the Jamf Pro web console.",
            systemImage: "info.circle"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03))
    }

    @ViewBuilder
    private var sheetContent: some View {
        switch vm.smartGroupDetailState {
        case .loading, .idle:
            SyncingIndicator().frame(maxWidth: .infinity, maxHeight: .infinity)

        case .failed(let msg):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)
                Text("Could not load criteria").font(.headline)
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()

        case .loaded(let detail):
            if detail.criteria.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No criteria defined for this group")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        criteriaSection(detail.criteria)
                    }
                    .padding(20)
                }
            }
        }
    }

    private func criteriaSection(_ criteria: [SmartGroupCriterion]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Membership Criteria")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(criteria.enumerated()), id: \.element.id) { index, criterion in
                    SmartGroupCriterionRow(criterion: criterion, isFirst: index == 0)
                    if index < criteria.count - 1 {
                        Divider().padding(.horizontal, 12)
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08)))
        }
    }
}

private struct SmartGroupCriterionRow: View {
    let criterion: SmartGroupCriterion
    let isFirst: Bool

    private var connectorLabel: String {
        isFirst ? "IF" : criterion.andOr.uppercased()
    }

    private var connectorColor: Color {
        if isFirst { return .secondary }
        return criterion.andOr.lowercased() == "or" ? .orange : .accentColor
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(connectorLabel)
                .font(.caption.weight(.bold))
                .foregroundStyle(connectorColor)
                .frame(width: 28, alignment: .center)
                .padding(.vertical, 3)
                .padding(.horizontal, 6)
                .background(connectorColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))

            if criterion.openingParen {
                Text("(")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(criterion.name)
                    .font(.callout.weight(.medium))
                HStack(spacing: 6) {
                    Text(criterion.searchType)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                    Text(criterion.value.isEmpty ? "—" : criterion.value)
                        .font(.caption)
                        .monospaced()
                        .foregroundStyle(criterion.value.isEmpty ? .tertiary : .primary)
                        .textSelection(.enabled)
                }
            }

            Spacer()

            if criterion.closingParen {
                Text(")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        var parts: [String] = []
        if isFirst {
            parts.append("If")
        } else {
            parts.append(criterion.andOr.capitalized)
        }
        if criterion.openingParen { parts.append("open parenthesis") }
        parts.append(criterion.name)
        parts.append(criterion.searchType)
        if !criterion.value.isEmpty { parts.append(criterion.value) }
        if criterion.closingParen { parts.append("close parenthesis") }
        return parts.joined(separator: " ")
    }
}

// MARK: - Shared scope sheet body

private struct ScopeSheetBody: View {
    let scope: JamfScope

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if scope.isEmpty && !scope.limitations.hasAny {
                    Text("No scope targets defined.")
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .center)
                        .padding(40)
                } else {
                    // MARK: Targets
                    if scope.allComputers {
                        scopeSection(title: "Targets", icon: "globe") {
                            scopeRow(name: "All Computers")
                        }
                    } else if !scope.isEmpty {
                        if !scope.computerGroups.isEmpty {
                            scopeSection(title: "Computer Groups", icon: "person.3") {
                                ForEach(scope.computerGroups) { scopeRow(name: $0.name) }
                            }
                        }
                        if !scope.computers.isEmpty {
                            scopeSection(title: "Computers", icon: "laptopcomputer") {
                                ForEach(scope.computers) { scopeRow(name: $0.name) }
                            }
                        }
                        if !scope.departments.isEmpty {
                            scopeSection(title: "Departments", icon: "building.2") {
                                ForEach(scope.departments) { scopeRow(name: $0.name) }
                            }
                        }
                        if !scope.buildings.isEmpty {
                            scopeSection(title: "Buildings", icon: "building") {
                                ForEach(scope.buildings) { scopeRow(name: $0.name) }
                            }
                        }
                    }

                    // MARK: Limitations
                    if scope.limitations.hasAny {
                        Divider()
                        if !scope.limitations.users.isEmpty {
                            scopeSection(title: "Limited to Users", icon: "person") {
                                ForEach(scope.limitations.users, id: \.name) { scopeRow(name: $0.name) }
                            }
                        }
                        if !scope.limitations.userGroups.isEmpty {
                            scopeSection(title: "Limited to User Groups", icon: "person.2") {
                                ForEach(scope.limitations.userGroups, id: \.name) { scopeRow(name: $0.name) }
                            }
                        }
                        if !scope.limitations.networkSegments.isEmpty {
                            scopeSection(title: "Limited to Network Segments", icon: "network") {
                                ForEach(scope.limitations.networkSegments) { scopeRow(name: $0.name) }
                            }
                        }
                        if !scope.limitations.ibeacons.isEmpty {
                            scopeSection(title: "Limited to iBeacons", icon: "dot.radiowaves.left.and.right") {
                                ForEach(scope.limitations.ibeacons) { scopeRow(name: $0.name) }
                            }
                        }
                    }

                    // MARK: Exclusions
                    if scope.exclusions.hasAny {
                        Divider()
                        if !scope.exclusions.computerGroups.isEmpty {
                            scopeSection(title: "Excluded Groups", icon: "person.3.fill", tint: .red) {
                                ForEach(scope.exclusions.computerGroups) { scopeRow(name: $0.name, tint: .red) }
                            }
                        }
                        if !scope.exclusions.computers.isEmpty {
                            scopeSection(title: "Excluded Computers", icon: "laptopcomputer.slash", tint: .red) {
                                ForEach(scope.exclusions.computers) { scopeRow(name: $0.name, tint: .red) }
                            }
                        }
                        if !scope.exclusions.departments.isEmpty {
                            scopeSection(title: "Excluded Departments", icon: "building.2.slash", tint: .red) {
                                ForEach(scope.exclusions.departments) { scopeRow(name: $0.name, tint: .red) }
                            }
                        }
                        if !scope.exclusions.buildings.isEmpty {
                            scopeSection(title: "Excluded Buildings", icon: "building.slash", tint: .red) {
                                ForEach(scope.exclusions.buildings) { scopeRow(name: $0.name, tint: .red) }
                            }
                        }
                        if !scope.exclusions.users.isEmpty {
                            scopeSection(title: "Excluded Users", icon: "person.slash", tint: .red) {
                                ForEach(scope.exclusions.users, id: \.name) { scopeRow(name: $0.name, tint: .red) }
                            }
                        }
                        if !scope.exclusions.userGroups.isEmpty {
                            scopeSection(title: "Excluded User Groups", icon: "person.2.slash", tint: .red) {
                                ForEach(scope.exclusions.userGroups, id: \.name) { scopeRow(name: $0.name, tint: .red) }
                            }
                        }
                        if !scope.exclusions.networkSegments.isEmpty {
                            scopeSection(title: "Excluded Network Segments", icon: "network.slash", tint: .red) {
                                ForEach(scope.exclusions.networkSegments) { scopeRow(name: $0.name, tint: .red) }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private func scopeSection<Content: View>(title: String, icon: String, tint: Color = .primary,
                                             @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint == .primary ? AnyShapeStyle(.primary) : AnyShapeStyle(tint))
            VStack(alignment: .leading, spacing: 0) { content() }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08)))
        }
    }

    @ViewBuilder
    private func scopeRow(name: String, tint: Color = .primary) -> some View {
        HStack {
            Text(name).foregroundStyle(tint == .primary ? AnyShapeStyle(.primary) : AnyShapeStyle(tint))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        Divider().padding(.horizontal, 12)
    }
}

// MARK: - Config Profile Scope Sheet

private struct ConfigProfileScopeSheet: View {
    let profile: ConfigProfile
    @Bindable var vm: FleetViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.name).font(.title2).bold()
                    Text("Configuration Profile Scope").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            switch vm.configProfileDetailState {
            case .loading, .idle:
                SyncingIndicator().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let msg):
                errorState(msg)
            case .loaded(let scope):
                ScopeSheetBody(scope: scope)
            }
        }
        .frame(minWidth: 460, minHeight: 360)
    }

    @ViewBuilder
    private func errorState(_ msg: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 36)).foregroundStyle(.orange)
            Text("Could not load scope").font(.headline)
            Text(msg).font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
    }
}

// MARK: - Bulk Actions View

struct BulkActionsView: View {
    @Bindable var vm: FleetViewModel
    @State private var selectedOp = 0
    @State private var param1 = ""
    @State private var param2 = ""
    @State private var isRunning = false
    @State private var resultMessage: String? = nil

    private let ops = ["Enable Policies (by category)", "Disable Policies (by pattern)",
                       "Add to Group (from file)", "Remove from Group (from file)", "Send Command to Group"]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Bulk Operations").font(.title2).bold()
                .padding(.horizontal, 24).padding(.top, 24)

            Form {
                Picker("Operation", selection: $selectedOp) {
                    ForEach(ops.indices, id: \.self) { i in Text(ops[i]).tag(i) }
                }
                .pickerStyle(.menu)

                switch selectedOp {
                case 0:
                    TextField("Category name", text: $param1)
                case 1:
                    TextField("Name pattern", text: $param1)
                case 2, 3:
                    TextField("Group name", text: $param1)
                    TextField("File path (CSV with serials)", text: $param2)
                case 4:
                    TextField("Command (e.g. BlankPush)", text: $param1)
                    TextField("Group name", text: $param2)
                default: EmptyView()
                }

                if let msg = resultMessage {
                    Label(msg, systemImage: msg.contains("failed") ? "xmark.circle" : "checkmark.circle")
                        .foregroundStyle(msg.contains("failed") ? .red : .green)
                }
            }
            .formStyle(.grouped)
            .frame(maxHeight: 260)

            Button {
                Task { await runBulk() }
            } label: {
                Label(isRunning ? "Running…" : "Execute", systemImage: "bolt.horizontal")
                    .frame(minWidth: 140)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isRunning || param1.isEmpty)
            .padding(.horizontal, 24)

            Spacer()
        }
        .navigationTitle("Bulk Actions")
    }

    private func runBulk() async {
        isRunning = true
        resultMessage = nil
        defer { isRunning = false }
        do {
            let cmd: CLICommand
            switch selectedOp {
            case 0: cmd = .bulkEnablePolicies(category: param1)
            case 1: cmd = .bulkDisablePolicies(pattern: param1)
            case 2: cmd = .bulkAddToGroup(group: param1, file: param2)
            case 3: cmd = .bulkRemoveFromGroup(group: param1, file: param2)
            case 4: cmd = .bulkSendCommand(command: param1, group: param2)
            default: return
            }
            _ = try await vm.runCLI(cmd)
            resultMessage = "Operation completed successfully."
        } catch {
            resultMessage = "Operation failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Org Browser View

struct OrgBrowserView: View {
    @Bindable var vm: FleetViewModel
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("Resource", selection: $selectedTab) {
                Text("Buildings").tag(0)
                Text("Departments").tag(1)
                Text("Network Segments").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(.regularMaterial)

            Divider()

            switch selectedTab {
            case 0: orgList(state: vm.buildingsState, load: { await vm.loadBuildings(force: true) },
                            rows: { vm.buildingsState.value ?? [] },
                            row: { b in SimpleRow(primary: b.name) })
            case 1: orgList(state: vm.departmentsState, load: { await vm.loadDepartments(force: true) },
                            rows: { vm.departmentsState.value ?? [] },
                            row: { d in SimpleRow(primary: d.name) })
            case 2: ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if vm.networkSegmentsState.isPending {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 60)
                    } else if let error = vm.networkSegmentsState.errorMessage {
                        ErrorStateView(message: error) { await vm.loadNetworkSegments() }
                    } else {
                        let segs = vm.networkSegmentsState.value ?? []
                        if segs.isEmpty {
                            Text("No network segments").foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center).padding(40)
                        } else {
                            ForEach(segs) { seg in
                                HStack {
                                    Text(seg.name)
                                    Spacer()
                                    if let start = seg.startingAddress, let end = seg.endingAddress {
                                        Text("\(start) – \(end)").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 20).padding(.vertical, 8)
                                Divider().padding(.horizontal, 20)
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            default: EmptyView()
            }
        }
        .navigationTitle("Organization")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task {
                    await vm.loadBuildings(force: true)
                    await vm.loadDepartments(force: true)
                    await vm.loadNetworkSegments(force: true)
                }} label: { Label("Refresh", systemImage: "arrow.clockwise") }
            }
        }
        .task { await vm.loadBuildings(); await vm.loadDepartments(); await vm.loadNetworkSegments() }
    }

    @ViewBuilder
    private func orgList<T: Identifiable>(state: LoadState<[T]>, load: @escaping () async -> Void,
                                          rows: () -> [T], row: @escaping (T) -> SimpleRow) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if state.isPending {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 60)
                } else if let error = state.errorMessage {
                    ErrorStateView(message: error) { await load() }
                } else {
                    let items = rows()
                    if items.isEmpty {
                        Text("No items found").foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center).padding(40)
                    } else {
                        ForEach(items) { item in
                            row(item)
                                .padding(.horizontal, 20).padding(.vertical, 8)
                            Divider().padding(.horizontal, 20)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
}

private struct SimpleRow: View {
    let primary: String
    var secondary: String? = nil
    var body: some View {
        HStack {
            Text(primary)
            Spacer()
            if let s = secondary { Text(s).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

// MARK: - Extension Attributes View

struct ExtensionAttributesView: View {
    @Bindable var vm: FleetViewModel
    @State private var selectedID: String?
    @State private var detailAttr: ExtensionAttribute?

    var body: some View {
        AsyncContentView(state: vm.extensionAttributesState,
                         retry: { await vm.loadExtensionAttributes(force: true) }) { attrs in
            Table(attrs, selection: $selectedID) {
                TableColumn("Name") { Text($0.name) }
                TableColumn("Data Type") { Text($0.dataType ?? "—").foregroundStyle(.secondary) }
                TableColumn("Input Type") { Text($0.inputType ?? "—").foregroundStyle(.secondary) }
                TableColumn("Enabled") { attr in
                    if let enabled = attr.enabled {
                        Label(enabled ? "Yes" : "No",
                              systemImage: enabled ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(enabled ? .green : .secondary)
                            .labelStyle(.titleAndIcon)
                    } else {
                        Text("—").foregroundStyle(.secondary)
                    }
                }
            }
            .onChange(of: selectedID) { _, id in
                detailAttr = id.flatMap { id in attrs.first { $0.id == id } }
            }
        }
        .navigationTitle("Extension Attributes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await vm.loadExtensionAttributes(force: true) } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .task { await vm.loadExtensionAttributes() }
        .sheet(item: $detailAttr) { attr in
            ExtensionAttributeDetailSheet(attr: attr)
                .onDisappear { selectedID = nil }
        }
    }
}

// MARK: - Extension Attribute Detail Sheet

private struct ExtensionAttributeDetailSheet: View {
    let attr: ExtensionAttribute
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(attr.name).font(.title2).bold()
                    Text("Extension Attribute · ID \(attr.id)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if let enabled = attr.enabled {
                    Label(enabled ? "Enabled" : "Disabled",
                          systemImage: enabled ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(enabled ? .green : .red)
                        .font(.caption.weight(.medium))
                }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .padding(.leading, 12)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Metadata grid
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 24, verticalSpacing: 10) {
                        if let dataType = attr.dataType {
                            GridRow {
                                Text("Data Type").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                                Text(dataType)
                            }
                        }
                        if let inputType = attr.inputType {
                            GridRow {
                                Text("Input Type").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                                Text(inputType)
                            }
                        }
                        if let display = attr.inventoryDisplayType {
                            GridRow {
                                Text("Inventory Display").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                                Text(display)
                            }
                        }
                    }
                    .font(.callout)

                    if let desc = attr.description, !desc.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Description")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(desc)
                                .font(.callout)
                        }
                    }

                    if let script = attr.scriptContents, !script.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Script")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ScrollView(.vertical) {
                                Text(script)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                            }
                            .frame(maxHeight: 320)
                            .background(Color.primary.opacity(0.05),
                                        in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 520, minHeight: 380)
    }
}

// MARK: - Patch Management View

struct PatchView: View {
    @Bindable var vm: FleetViewModel
    @State private var selectedTab = 0
    @State private var selectedTitleID: PatchTitle.ID? = nil
    @State private var detailTitle: PatchTitle? = nil
    @State private var selectedPolicyID: PatchPolicy.ID? = nil
    @State private var detailPolicy: PatchPolicy? = nil

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $selectedTab) {
                Text("Patch Titles").tag(0)
                Text("Patch Policies").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(.regularMaterial)

            Divider()

            switch selectedTab {
            case 0:
                AsyncContentView(state: vm.patchTitlesState,
                                 retry: { await vm.loadPatchTitles(force: true) }) { titles in
                    Table(titles, selection: $selectedTitleID) {
                        TableColumn("Name") { Text($0.name) }
                        TableColumn("Category") { Text($0.category ?? "—").foregroundStyle(.secondary) }
                        TableColumn("ID") { Text($0.id).foregroundStyle(.secondary) }
                    }
                    .onChange(of: selectedTitleID) { _, newID in
                        guard let id = newID, let item = titles.first(where: { $0.id == id }) else { return }
                        detailTitle = item
                        Task { await vm.loadPatchTitleDetail(id: item.id) }
                    }
                }
                .task { await vm.loadPatchTitles() }
                .sheet(item: $detailTitle) { item in
                    PatchTitleDetailSheet(item: item, vm: vm)
                        .onDisappear { selectedTitleID = nil }
                }
            case 1:
                AsyncContentView(state: vm.patchPoliciesState,
                                 retry: { await vm.loadPatchPolicies(force: true) }) { policies in
                    Table(policies, selection: $selectedPolicyID) {
                        TableColumn("Name") { Text($0.name) }
                        TableColumn("Enabled") { policy in
                            if let enabled = policy.enabled {
                                Image(systemName: enabled ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(enabled ? .green : .secondary)
                            } else {
                                Text("—").foregroundStyle(.secondary)
                            }
                        }
                        TableColumn("Target Version") { Text($0.targetVersion ?? "—").foregroundStyle(.secondary) }
                        TableColumn("Patch Title") { Text($0.patchTitle ?? "—").foregroundStyle(.secondary) }
                        TableColumn("ID") { Text($0.id).foregroundStyle(.secondary) }
                    }
                    .onChange(of: selectedPolicyID) { _, newID in
                        guard let id = newID, let item = policies.first(where: { $0.id == id }) else { return }
                        detailPolicy = item
                        Task { await vm.loadPatchPolicyDetail(id: item.id) }
                    }
                }
                .task { await vm.loadPatchPolicies() }
                .sheet(item: $detailPolicy) { item in
                    PatchPolicyDetailSheet(item: item, vm: vm)
                        .onDisappear { selectedPolicyID = nil }
                }
            default: EmptyView()
            }
        }
        .navigationTitle("Patch Management")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task {
                    await vm.loadPatchTitles(force: true)
                    await vm.loadPatchPolicies(force: true)
                }} label: { Label("Refresh", systemImage: "arrow.clockwise") }
            }
        }
    }
}

private struct PatchTitleDetailSheet: View {
    let item: PatchTitle
    @Bindable var vm: FleetViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name).font(.title2).bold()
                    if let cat = item.category {
                        Text(cat).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            switch vm.patchTitleDetailState {
            case .loading:
                SyncingIndicator().frame(maxWidth: .infinity, maxHeight: .infinity)

            case .loaded(let detail):
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let cat = detail.category  { patchDetailRow("Category", value: cat) }
                        if let v   = detail.latestVersion { patchDetailRow("Latest Version", value: v) }
                        if let versions = detail.versions, versions.count > 1 {
                            let vList = versions.compactMap(\.softwareVersion).joined(separator: "\n")
                            if !vList.isEmpty { patchDetailRow("All Versions", value: vList) }
                        }
                        patchDetailRow("ID", value: detail.id)
                    }
                    .padding(20)
                }

            case .failed(let msg):
                patchDetailError(msg)

            case .idle:
                EmptyView()
            }
        }
        .frame(minWidth: 440, minHeight: 280)
    }
}

private struct PatchPolicyDetailSheet: View {
    let item: PatchPolicy
    @Bindable var vm: FleetViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name).font(.title2).bold()
                    if let t = item.patchTitle {
                        Text(t).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            switch vm.patchPolicyDetailState {
            case .loading:
                SyncingIndicator().frame(maxWidth: .infinity, maxHeight: .infinity)

            case .loaded(let detail):
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let v = detail.patchTitle     { patchDetailRow("Patch Title", value: v) }
                        if let v = detail.targetVersion  { patchDetailRow("Target Version", value: v) }
                        if let v = detail.enabled        { patchDetailRow("Enabled", value: v ? "Yes" : "No") }
                        patchDetailRow("ID", value: detail.id)
                    }
                    .padding(20)
                }

            case .failed(let msg):
                patchDetailError(msg)

            case .idle:
                EmptyView()
            }
        }
        .frame(minWidth: 440, minHeight: 240)
    }
}

@ViewBuilder
private func patchDetailRow(_ label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        Text(value)
            .textSelection(.enabled)
    }
}

@ViewBuilder
private func patchDetailError(_ msg: String) -> some View {
    VStack(spacing: 12) {
        Image(systemName: "exclamationmark.triangle").font(.system(size: 36)).foregroundStyle(.orange)
        Text("Could not load details").font(.headline)
        Text(msg).font(.caption).foregroundStyle(.secondary)
            .multilineTextAlignment(.center).frame(maxWidth: 300)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
}

// MARK: - Enrollment & Prestages View

struct EnrollmentView: View {
    @Bindable var vm: FleetViewModel
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $selectedTab) {
                Text("DEP Tokens").tag(0)
                Text("Computer Prestages").tag(1)
                Text("Mobile Prestages").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(.regularMaterial)

            Divider()

            switch selectedTab {
            case 0:
                AsyncContentView(state: vm.depTokensState,
                                 retry: { await vm.loadDepTokens(force: true) }) { tokens in
                    Table(tokens) {
                        TableColumn("ID") { Text($0.id).foregroundStyle(.secondary) }
                        TableColumn("Organization") { Text($0.orgName ?? "—") }
                        TableColumn("Expires") { token in
                            Text(token.tokenExpiration.flatMap(formatExpiryDate) ?? token.tokenExpiration ?? "—")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .task { await vm.loadDepTokens() }
            case 1:
                AsyncContentView(state: vm.computerPrestagesState,
                                 retry: { await vm.loadComputerPrestages(force: true) }) { prestages in
                    Table(prestages) {
                        TableColumn("Name") { Text($0.displayName) }
                        TableColumn("MDM Removable") {
                            Text($0.mdmRemovable == true ? "Yes" : "No").foregroundStyle(.secondary)
                        }
                        TableColumn("Enrollment Site") { Text($0.enrollmentSiteId ?? "—").foregroundStyle(.secondary) }
                    }
                }
                .task { await vm.loadComputerPrestages() }
            case 2:
                AsyncContentView(state: vm.mobileDevicePrestagesState,
                                 retry: { await vm.loadMobileDevicePrestages(force: true) }) { prestages in
                    Table(prestages) {
                        TableColumn("Name") { Text($0.displayName) }
                        TableColumn("Enrollment Site") { Text($0.enrollmentSiteId ?? "—").foregroundStyle(.secondary) }
                    }
                }
                .task { await vm.loadMobileDevicePrestages() }
            default: EmptyView()
            }
        }
        .navigationTitle("Enrollment & Prestages")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task {
                    await vm.loadDepTokens(force: true)
                    await vm.loadComputerPrestages(force: true)
                    await vm.loadMobileDevicePrestages(force: true)
                }} label: { Label("Refresh", systemImage: "arrow.clockwise") }
            }
        }
    }
}

private func formatExpiryDate(_ raw: String) -> String? {
    let formatters: [ISO8601DateFormatter] = [
        { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }(),
        { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f }(),
    ]
    // Also handle "2025-06-15 00:00:00 +0000" style
    let dfFallback: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return f
    }()
    let date = formatters.lazy.compactMap { $0.date(from: raw) }.first
               ?? dfFallback.date(from: raw)
    guard let date else { return nil }
    let out = DateFormatter()
    out.dateStyle = .medium
    out.timeStyle = .none
    return out.string(from: date)
}

// MARK: - Webhooks View

struct WebhooksView: View {
    @Bindable var vm: FleetViewModel

    var body: some View {
        AsyncContentView(state: vm.webhooksState,
                         retry: { await vm.loadWebhooks(force: true) }) { hooks in
            Table(hooks) {
                TableColumn("Name") { Text($0.name) }
                TableColumn("Event") { Text($0.event ?? "—").foregroundStyle(.secondary) }
                TableColumn("Enabled") { Text($0.enabled == true ? "Yes" : "No").foregroundStyle(.secondary) }
                TableColumn("URL") { Text($0.url ?? "—").foregroundStyle(.secondary).lineLimit(1) }
            }
        }
        .navigationTitle("Webhooks")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await vm.loadWebhooks(force: true) } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .task { await vm.loadWebhooks() }
    }
}

// MARK: - Script Detail Sheet

private struct ScriptDetailSheet: View {
    let script: JamfScript
    @Bindable var vm: FleetViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(script.name).font(.title2).bold()
                    if let cat = script.category?.name {
                        Text(cat).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            switch vm.scriptDetailState {
            case .loading, .idle:
                SyncingIndicator().frame(maxWidth: .infinity, maxHeight: .infinity)

            case .failed(let msg):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 36)).foregroundStyle(.orange)
                    Text("Could not load script").font(.headline)
                    Text(msg).font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).frame(maxWidth: 300)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding()

            case .loaded(let detail):
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Metadata grid
                        if detail.filename != nil || detail.priority != nil ||
                           detail.osRequirements != nil || detail.categoryName != nil {
                            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 20, verticalSpacing: 8) {
                                if let cat = detail.categoryName, !cat.isEmpty {
                                    GridRow {
                                        Text("Category").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                                        Text(cat)
                                    }
                                }
                                if let fn = detail.filename, !fn.isEmpty {
                                    GridRow {
                                        Text("Filename").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                                        Text(fn).textSelection(.enabled)
                                    }
                                }
                                if let p = detail.priority, !p.isEmpty {
                                    GridRow {
                                        Text("Priority").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                                        Text(p.capitalized)
                                    }
                                }
                                if let os = detail.osRequirements, !os.isEmpty {
                                    GridRow {
                                        Text("OS Requirements").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                                        Text(os).textSelection(.enabled)
                                    }
                                }
                                GridRow {
                                    Text("ID").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                                    Text(detail.id).foregroundStyle(.secondary)
                                }
                            }
                            .font(.callout)
                        }

                        // Parameters
                        let params = (detail.parameters ?? [:]).filter { !$0.value.isEmpty }.sorted(by: { $0.key < $1.key })
                        if !params.isEmpty {
                            Divider()
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Parameters")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 20, verticalSpacing: 6) {
                                    ForEach(params, id: \.key) { key, value in
                                        GridRow {
                                            Text(key).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                                            Text(value).textSelection(.enabled)
                                        }
                                    }
                                }
                                .font(.callout)
                            }
                        }

                        // Info / Notes
                        if let info = detail.info, !info.isEmpty {
                            Divider()
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Info").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                Text(info).font(.callout).textSelection(.enabled)
                            }
                        }
                        if let notes = detail.notes, !notes.isEmpty {
                            Divider()
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Notes").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                Text(notes).font(.callout).textSelection(.enabled)
                            }
                        }

                        // Script contents
                        if let contents = detail.scriptContents, !contents.isEmpty {
                            Divider()
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Script Contents")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                ScrollView(.vertical) {
                                    Text(contents)
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(12)
                                }
                                .frame(maxHeight: 360)
                                .background(Color.primary.opacity(0.05),
                                            in: RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 400)
    }
}

// MARK: - Package Detail Sheet

private struct PackageDetailSheet: View {
    let package: JamfPackage
    @Bindable var vm: FleetViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(package.name).font(.title2).bold()
                    Text("Package · ID \(package.id)").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            switch vm.packageDetailState {
            case .loading, .idle:
                SyncingIndicator().frame(maxWidth: .infinity, maxHeight: .infinity)

            case .failed(let msg):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 36)).foregroundStyle(.orange)
                    Text("Could not load package").font(.headline)
                    Text(msg).font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).frame(maxWidth: 300)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding()

            case .loaded(let detail):
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 20, verticalSpacing: 8) {
                            if let cat = detail.category, !cat.isEmpty, cat != "None" {
                                GridRow {
                                    Text("Category").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                                    Text(cat)
                                }
                            }
                            if let fn = detail.filename, !fn.isEmpty {
                                GridRow {
                                    Text("Filename").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                                    Text(fn).textSelection(.enabled)
                                }
                            }
                            if let p = detail.priority {
                                GridRow {
                                    Text("Priority").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                                    Text("\(p)")
                                }
                            }
                            if let os = detail.osRequirements, !os.isEmpty {
                                GridRow {
                                    Text("OS Requirements").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                                    Text(os).textSelection(.enabled)
                                }
                            }
                            if let proc = detail.requiredProcessor, !proc.isEmpty, proc != "None" {
                                GridRow {
                                    Text("Required Processor").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                                    Text(proc)
                                }
                            }
                            GridRow {
                                Text("Reboot Required").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                                Text(detail.rebootRequired == true ? "Yes" : "No")
                            }
                            GridRow {
                                Text("Allow Uninstall").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                                Text(detail.allowUninstalled == true ? "Yes" : "No")
                            }
                            GridRow {
                                Text("Fill User Template").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                                Text(detail.fillUserTemplate == true ? "Yes" : "No")
                            }
                        }
                        .font(.callout)

                        if let sw = detail.switchWithPackage, !sw.isEmpty, sw != "Do Not Install" {
                            Divider()
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Switch With Package").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                Text(sw).font(.callout).textSelection(.enabled)
                            }
                        }

                        if let info = detail.info, !info.isEmpty {
                            Divider()
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Info").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                Text(info).font(.callout).textSelection(.enabled)
                            }
                        }
                        if let notes = detail.notes, !notes.isEmpty {
                            Divider()
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Notes").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                Text(notes).font(.callout).textSelection(.enabled)
                            }
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 360)
    }
}

// MARK: - Policy Scope Sheet

private struct PolicyScopeSheet: View {
    let policy: Policy
    @Bindable var vm: FleetViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(policy.name).font(.title2).bold()
                    Text("Policy Scope").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            switch vm.policyDetailState {
            case .loading, .idle:
                SyncingIndicator().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let msg):
                errorState(msg)
            case .loaded(let scope):
                ScopeSheetBody(scope: scope)
            }
        }
        .frame(minWidth: 460, minHeight: 360)
    }

    @ViewBuilder
    private func errorState(_ msg: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 36)).foregroundStyle(.orange)
            Text("Could not load scope").font(.headline)
            Text(msg).font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
    }
}
