import SwiftUI

struct BlueprintsView: View {
    @Bindable var vm: PlatformViewModel

    var body: some View {
        Group {
            switch vm.blueprintsState {
            case .idle, .loading:
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading blueprints…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let error):
                if PlatformViewModel.isPlatformAuthError(error) {
                    PlatformAuthRequiredView()
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
                HSplitView {
                    blueprintList(blueprints)
                        .frame(minWidth: 200, idealWidth: 240, maxWidth: 320)
                    blueprintDetail
                        .frame(minWidth: 300, maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Blueprints")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await vm.loadBlueprints(force: true) } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(vm.blueprintsState.isLoading)
            }
        }
        .task { await vm.loadBlueprints() }
    }

    private func blueprintList(_ blueprints: [JamfBlueprint]) -> some View {
        Group {
            if blueprints.isEmpty {
                ContentUnavailableView("No Blueprints", systemImage: "square.3.layers.3d", description: Text("No blueprints found in this tenant."))
            } else {
                List(selection: $vm.selectedBlueprintID) {
                    ForEach(blueprints, id: \.id) { bp in
                        Text(bp.name).tag(bp.id)
                    }
                }
                .listStyle(.sidebar)
                .onChange(of: vm.selectedBlueprintID, initial: false) { _, id in
                    guard let id else { return }
                    Task { await vm.loadBlueprintDetail(name: id) }
                }
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
        case .loaded(let json):
            BlueprintDetailView(json: json)
        }
    }
}

// MARK: - Blueprint JSON Models

private struct BlueprintDetail: Decodable {
    let id: String
    let name: String
    let description: String?
    let created: Date?
    let updated: Date?
    let deploymentState: BlueprintDeploymentState?
    let scope: BlueprintScope?
    let steps: [BlueprintStep]?
}

private struct BlueprintDeploymentState: Decodable {
    let state: String
    let lastDeployment: BlueprintLastDeployment?
}

private struct BlueprintLastDeployment: Decodable {
    let started: Date?
    let state: String
}

private struct BlueprintScope: Decodable {
    let deviceGroups: [String]?
}

private struct BlueprintStep: Decodable {
    let name: String
    let components: [BlueprintComponent]?
}

private struct BlueprintComponent: Decodable {
    let identifier: String
    let configuration: BlueprintComponentConfig?
}

private struct BlueprintComponentConfig: Decodable {
    let declarations: [BlueprintDeclaration]?
}

private struct BlueprintDeclaration: Decodable {
    let type: String
    let kind: String?
    let channelType: String?
    let payload: JSONPayload?
}

// Dynamic JSON value for arbitrary declaration payloads
private enum JSONPayload: Decodable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONPayload])
    case object([String: JSONPayload])
    case null

    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil()              { self = .null }
        else if let v = try? c.decode(Bool.self)          { self = .bool(v) }
        else if let v = try? c.decode(Int.self)           { self = .int(v) }
        else if let v = try? c.decode(Double.self)        { self = .double(v) }
        else if let v = try? c.decode(String.self)        { self = .string(v) }
        else if let v = try? c.decode([JSONPayload].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONPayload].self)) }
    }

    var displayString: String {
        switch self {
        case .bool(let b):   return b ? "true" : "false"
        case .int(let i):    return "\(i)"
        case .double(let d): return "\(d)"
        case .string(let s): return s
        case .null:          return "null"
        case .array(let a):  return "[\(a.map(\.displayString).joined(separator: ", "))]"
        case .object(let d): return d.map { "\($0.key): \($0.value.displayString)" }.sorted().joined(separator: ", ")
        }
    }
}

// MARK: - Blueprint Decoder

private func makeBlueprintDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .custom { dec in
        let container = try dec.singleValueContainer()
        let string = try container.decode(String.self)
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFrac.date(from: string) { return date }
        let noFrac = ISO8601DateFormatter()
        noFrac.formatOptions = [.withInternetDateTime]
        if let date = noFrac.date(from: string) { return date }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot parse date: \(string)")
    }
    return decoder
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
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(badgeColor, in: Capsule())
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
    let json: String

    private var detail: BlueprintDetail? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? makeBlueprintDecoder().decode(BlueprintDetail.self, from: data)
    }

    var body: some View {
        if let detail {
            BlueprintStructuredView(detail: detail)
        } else {
            ScrollView {
                Text(json)
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
                    let groupCount = scope.deviceGroups?.count ?? 0
                    BlueprintInfoRow(
                        label: "Device Groups",
                        value: groupCount == 1 ? "1 group" : "\(groupCount) groups"
                    )
                }
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
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
        if declarations.isEmpty {
            // Non-declaration component — just show identifier
            Text(component.identifier)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 2)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(declarations.enumerated()), id: \.offset) { _, decl in
                    DeclarationRow(declaration: decl)
                }
            }
        }
    }
}

private struct DeclarationRow: View {
    let declaration: BlueprintDeclaration

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: type + kind/channelType badges
            HStack(spacing: 6) {
                Text(declaration.type)
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
                            Text(key)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 160, alignment: .leading)
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
                        .frame(width: 160, alignment: .leading)
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

// MARK: - PlatformAuthRequiredView

private struct PlatformAuthRequiredView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(spacing: 12) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Platform Gateway Auth Required")
                            .font(.headline)
                        Text("Blueprints require a Jamf platform profile.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                // Version requirement notice
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Requires jamf-cli 1.17 or later")
                            .font(.callout)
                            .fontWeight(.medium)
                        Link("Download the latest release at github.com/Jamf-Concepts/jamf-cli",
                             destination: URL(string: "https://github.com/Jamf-Concepts/jamf-cli/releases")!)
                            .font(.caption)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Divider()

                // CLI setup instructions
                VStack(alignment: .leading, spacing: 8) {
                    Text("Run this command in Terminal to set one up:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("""
jamf-cli config add-profile <name> \\
  --auth-method platform \\
  --url <gateway-url> \\
  --tenant-id <id>
""")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Environment variable alternative
                VStack(alignment: .leading, spacing: 8) {
                    Text("Or set environment variables:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("JAMF_URL, JAMF_CLIENT_ID, JAMF_CLIENT_SECRET, JAMF_TENANT_ID")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(24)
            .frame(maxWidth: 560, alignment: .leading)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
