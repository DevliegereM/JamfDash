import SwiftUI

struct BlueprintsView: View {
    // @Bindable required: provides $vm.selectedBlueprintID binding for List(selection:)
    @Bindable var vm: PlatformViewModel
    @State private var refreshTask: Task<Void, Never>? = nil

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        switch env.access(for: .blueprints) {
        case .available, .checking:
            content
        case let access:
            PlatformAPIUnavailableView(featureName: "Blueprints", systemImage: "square.3.layers.3d",
                                       permission: "Deployment → Blueprints: Read", access: access)
        }
    }

    private var content: some View {
        Group {
            switch vm.blueprintsState {
            case .idle:
                ContentUnavailableView("Blueprints", systemImage: "square.3.layers.3d")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loading:
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading blueprints…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let error):
                if PlatformViewModel.isPlatformAuthError(error) {
                    PlatformAuthRequiredView(featureName: "Blueprints")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle").font(.system(size: 36)).foregroundStyle(.orange)
                        Text("Failed to load blueprints").font(.headline)
                        Text(error).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 300)
                        Button("Retry") { Task { await vm.loadBlueprints(force: true) } }.buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .loaded(let blueprints):
                HStack(spacing: 0) {
                    blueprintList(blueprints)
                        .frame(width: 240)
                    Divider()
                    blueprintDetail
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Blueprints")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    refreshTask?.cancel()
                    refreshTask = Task { await vm.loadBlueprints(force: true) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(vm.blueprintsState.isLoading)
            }
        }
        .task { await vm.loadBlueprints() }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func blueprintList(_ blueprints: [JamfBlueprint]) -> some View {
        if blueprints.isEmpty {
            ContentUnavailableView("No Blueprints", systemImage: "square.3.layers.3d", description: Text("No blueprints found in this tenant."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: $vm.selectedBlueprintID) {
                ForEach(blueprints, id: \.id) { bp in
                    Text(bp.name).tag(bp.id)
                }
            }
            .listStyle(.sidebar)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: vm.selectedBlueprintID, initial: false) { _, id in
                guard let id else { return }
                Task { await vm.loadBlueprintDetail(name: id) }
            }
        }
    }

    @ViewBuilder
    private var blueprintDetail: some View {
        switch vm.blueprintDetailState {
        case .idle:
            ContentUnavailableView("Select a Blueprint", systemImage: "square.3.layers.3d")
        case .loading:
            VStack { ProgressView(); Text("Loading detail…").foregroundStyle(.secondary) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let e):
            VStack { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange); Text(e).font(.caption) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let result):
            BlueprintDetailView(result: result)
        }
    }
}

// MARK: - Deployment State Badge

private struct DeploymentStateBadge: View {
    let state: String

    private var badgeColor: Color {
        switch state.uppercased() {
        case "DEPLOYED", "SUCCEEDED": return .green
        case "FAILED": return .red
        default: return .orange
        }
    }

    var body: some View {
        Text(state)
            .font(.caption.weight(.semibold))
            .foregroundStyle(badgeColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(badgeColor.opacity(0.15), in: Capsule())
            .accessibilityLabel("Deployment state: \(state)")
    }
}

// MARK: - Blueprint Info Row

private struct BlueprintInfoRow: View {
    let label: String
    let value: String
    var selectable = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            if selectable {
                Text(value)
                    .font(.subheadline)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(value)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Blueprint Detail View

private struct BlueprintDetailView: View {
    let result: BlueprintDetailResult

    var body: some View {
        if let detail = result.detail {
            BlueprintStructuredView(detail: detail)
        } else {
            ScrollView {
                Text(result.rawJSON)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Blueprint Structured View

private struct BlueprintStructuredView: View {
    let detail: BlueprintDetail

    private static let dateFormatter: Date.FormatStyle = .dateTime.day().month(.abbreviated).year().hour().minute()

    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(Self.dateFormatter)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                detailsSection
                if detail.deploymentState != nil {
                    deploymentSection
                }
                if detail.scope != nil {
                    scopeSection
                }
                if let steps = detail.steps, !steps.isEmpty {
                    stepsSection(steps)
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(detail.name)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let state = detail.deploymentState?.state {
                    DeploymentStateBadge(state: state)
                }
                Spacer()
            }
            if let description = detail.description, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            DashSectionHeader("Details", systemImage: "info.circle")
            VStack(alignment: .leading, spacing: 8) {
                BlueprintInfoRow(label: "ID", value: detail.id, selectable: true)
                Divider()
                BlueprintInfoRow(label: "Created", value: formattedDate(detail.created))
                Divider()
                BlueprintInfoRow(label: "Updated", value: formattedDate(detail.updated))
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var deploymentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            DashSectionHeader("Deployment", systemImage: "arrow.triangle.2.circlepath")
            VStack(alignment: .leading, spacing: 8) {
                if let ds = detail.deploymentState {
                    BlueprintInfoRow(label: "State", value: ds.state)
                    if let last = ds.lastDeployment {
                        Divider()
                        let lastRunValue = "\(formattedDate(last.started))  (\(last.state))"
                        BlueprintInfoRow(label: "Last Run", value: lastRunValue)
                    }
                }
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var scopeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            DashSectionHeader("Scope", systemImage: "scope")
            VStack(alignment: .leading, spacing: 8) {
                if let scope = detail.scope {
                    scopeRows(for: scope)
                }
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder
    private func scopeRows(for scope: BlueprintScope) -> some View {
        let deviceGroups = scope.deviceGroups ?? []
        let devices      = scope.devices ?? []
        let users        = scope.users ?? []
        let userGroups   = scope.userGroups ?? []

        if deviceGroups.isEmpty && devices.isEmpty && users.isEmpty && userGroups.isEmpty {
            Text("No scope assigned").font(.subheadline).foregroundStyle(.secondary)
        } else {
            let rows: [(label: String, names: [String])] = [
                ("Device Groups", deviceGroups),
                ("Devices",       devices),
                ("Users",         users),
                ("User Groups",   userGroups),
            ].filter { !$0.names.isEmpty }

            ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                if idx > 0 { Divider() }
                scopeNameList(label: row.label, names: row.names)
            }
        }
    }

    private func scopeNameList(label: String, names: [String]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(names, id: \.self) { name in
                    Text(name)
                        .font(.subheadline)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func stepsSection(_ steps: [BlueprintStep]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DashSectionHeader("Applied Settings", systemImage: "list.number")
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                    VStack(alignment: .leading, spacing: 8) {
                        if steps.count > 1 {
                            Text(step.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        if let components = step.components {
                            ForEach(components, id: \.identifier) { component in
                                DeclarationComponentView(component: component)
                            }
                        }
                    }
                }
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

// MARK: - Declaration Component View

private struct DeclarationComponentView: View {
    let component: BlueprintComponent

    var body: some View {
        let declarations = component.configuration?.declarations ?? []
        if !declarations.isEmpty {
            // Shape 1: structured nested declarations
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(declarations.enumerated()), id: \.offset) { _, decl in
                    DeclarationRow(declaration: decl)
                }
            }
        } else {
            // Shape 2 & 3: flat payload on the component itself
            ComponentPayloadRow(
                identifier: component.identifier,
                type: component.type,
                channelType: component.channelType,
                payload: component.effectivePayload
            )
        }
    }
}

// MARK: - Component Payload Row (flat shape)

private struct ComponentPayloadRow: View {
    let identifier: String
    let type: String?
    let channelType: String?
    let payload: JSONPayload?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(spacing: 6) {
                Text(identifier.humanizedDeclarationID)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                Spacer()
                if let ch = channelType { kindBadge(ch, color: .purple) }
                // Show the Apple declaration type only when it differs from the identifier
                if let t = type, t != identifier { kindBadge(t.humanizedDeclarationID, color: .blue) }
            }

            // Content
            if let payload {
                payloadContent(payload)
            } else {
                // No payload at all — show domain as dim fallback
                Text(identifier)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .padding(.top, 2)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }

    @ViewBuilder
    private func payloadContent(_ p: JSONPayload) -> some View {
        switch p {
        case .object(let dict) where !dict.isEmpty:
            payloadTable(dict)
        case .null:
            EmptyView()
        default:
            Text(p.displayString)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private func payloadTable(_ dict: [String: JSONPayload]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(dict.keys.sorted(), id: \.self) { key in
                HStack(alignment: .top, spacing: 0) {
                    Text(key.camelToWords)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 180, alignment: .leading)
                    payloadValueView(dict[key])
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func payloadValueView(_ value: JSONPayload?) -> some View {
        if let value {
            switch value {
            case .bool(let b):
                HStack(spacing: 4) {
                    Image(systemName: b ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(b ? .green : .red).font(.caption)
                    Text(b ? "true" : "false")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(b ? .green : .red)
                }
            case .null:
                Text("null").font(.caption).foregroundStyle(.tertiary)
            default:
                Text(value.displayString)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        } else {
            Text("—").font(.caption).foregroundStyle(.tertiary)
        }
    }

    private func kindBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.1), in: Capsule())
    }
}

private struct DeclarationRow: View {
    let declaration: BlueprintDeclaration

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: humanized type + kind/channelType badges
            HStack(spacing: 6) {
                Text(declaration.type.humanizedDeclarationID)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                Spacer()
                if let kind = declaration.kind {
                    kindBadge(kind, color: .blue)
                }
                if let channel = declaration.channelType {
                    kindBadge(channel, color: .purple)
                }
            }

            // Payload key-value table
            if case .object(let dict) = declaration.payload, !dict.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(dict.keys.sorted(), id: \.self) { key in
                        HStack(alignment: .top, spacing: 0) {
                            Text(key.camelToWords)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 180, alignment: .leading)
                            payloadValueView(dict[key])
                        }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            } else if let payload = declaration.payload, case .null = payload {
                EmptyView()
            } else if let payload = declaration.payload {
                HStack(alignment: .top, spacing: 0) {
                    Text("value")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 180, alignment: .leading)
                    payloadValueView(payload)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }

    @ViewBuilder
    private func payloadValueView(_ value: JSONPayload?) -> some View {
        if let value {
            switch value {
            case .bool(let b):
                HStack(spacing: 4) {
                    Image(systemName: b ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(b ? .green : .red)
                        .font(.caption)
                    Text(b ? "true" : "false")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(b ? .green : .red)
                }
            case .null:
                Text("null").font(.caption).foregroundStyle(.tertiary)
            default:
                Text(value.displayString)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        } else {
            Text("—").font(.caption).foregroundStyle(.tertiary)
        }
    }

    private func kindBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.1), in: Capsule())
    }
}

// MARK: - String helpers for declaration display

private extension String {
    /// Strips well-known Apple/Jamf DDM reverse-DNS prefixes and title-cases the remainder.
    /// e.g. "com.jamf.ddm.passcode-settings"          → "Passcode Settings"
    ///      "com.apple.configuration.passcode.settings" → "Passcode Settings"
    var humanizedDeclarationID: String {
        var s = self
        for prefix in [
            "com.jamf.ddm.",
            "com.apple.configuration.",
            "com.apple.management.",
            "com.apple.",
            "com.jamf."
        ] {
            if s.hasPrefix(prefix) { s = String(s.dropFirst(prefix.count)); break }
        }
        return s
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    /// Splits camelCase into spaced Title Words.
    /// e.g. "passcodeMinLength" → "Passcode Min Length"
    var camelToWords: String {
        var result = ""
        for char in self {
            if char.isUppercase && !result.isEmpty {
                result += " "
            }
            result.append(char)
        }
        return result
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

// MARK: - Bullet Label Style

private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon
                .font(.system(size: 5))
                .foregroundStyle(.secondary)
            configuration.title
        }
    }
}
