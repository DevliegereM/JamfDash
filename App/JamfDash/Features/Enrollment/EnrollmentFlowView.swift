import SwiftUI

/// What a new Mac gets when it enrolls through a PreStage, step by step.
struct EnrollmentFlowView: View {
    @Bindable var vm: EnrollmentFlowViewModel
    @State private var selectedPhase: EnrollmentPhase? = .profiles

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 300)
                .frame(maxHeight: .infinity)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            await vm.loadPrestages()
            if case .idle = vm.scanState { vm.startScan() }
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch vm.prestagesState {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ErrorStateView(message: message, retry: { await vm.loadPrestages(force: true) })
            case .loaded(let prestages) where prestages.isEmpty:
                ContentUnavailableView("No Computer PreStages", systemImage: "shippingbox",
                                       description: Text("Create a computer PreStage enrollment in Jamf Pro to see its flow here."))
            case .loaded(let prestages):
                VStack(alignment: .leading, spacing: 6) {
                    Picker("PreStage", selection: Binding(get: { vm.selectedPrestageID }, set: { vm.selectPrestage($0) })) {
                        ForEach(prestages) { Text($0.displayName).tag(Optional($0.id)) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    if let flow = vm.flowState.value {
                        Text(factsLine(flow)).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                phaseList
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            Divider()
            ScanStatusFooter(vm: vm)
                .padding(10)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func factsLine(_ flow: EnrollmentFlow) -> String {
        let p = flow.prestage
        var parts: [String] = []
        if p.adeInstanceID != nil { parts.append("ADE") }
        for fact in p.facts {
            switch (fact.label, fact.value) {
            case ("Supervised", "Yes"): parts.append("Supervised")
            case ("MDM profile removable", "No"): parts.append("MDM not removable")
            case ("MDM profile removable", "Yes"): parts.append("MDM removable")
            case ("Mandatory", "Yes"): parts.append("Mandatory")
            default: break
            }
        }
        if p.customizationID != nil { parts.append("Enrollment Customization") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var phaseList: some View {
        switch vm.flowState {
        case .loaded(let flow):
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(flow.phases.enumerated()), id: \.element.id) { index, phase in
                        let selected = (selectedPhase ?? flow.phases.first?.phase) == phase.phase
                        Button { selectedPhase = phase.phase } label: {
                            PhaseRailRow(number: index + 1, phase: phase)
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(selected ? Color.accentColor.opacity(0.18) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 7))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                    if vm.isScanning, !flow.phases.contains(where: { $0.phase == .setupManager }) {
                        Text("Looking for a Setup Manager profile…")
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(.horizontal, 10).padding(.top, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 8)
            }
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView("Couldn't Load This PreStage", systemImage: "exclamationmark.triangle",
                                   description: Text(message))
        case .idle:
            Spacer()
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let flow = vm.flowState.value,
           let phase = flow.phases.first(where: { $0.phase == selectedPhase }) ?? flow.phases.first {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(phase.phase.title, systemImage: phase.phase.symbol)
                            .font(.title2.weight(.semibold))
                        Text(phase.summary).font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(phase.lines, id: \.self) { line in
                        Text(line).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                    if phase.needsScan {
                        ScanPrompt(vm: vm, reason: "Scan scopes to see which profiles and enrollment policies a new Mac gets.")
                    }
                    if phase.phase == .setupManager {
                        setupManagerDetail
                    } else {
                        items(phase)
                    }
                    if phase.phase == .profiles || phase.phase == .policies, flow.specificOnlyCount > 0 {
                        Text("\(flow.specificOnlyCount) profiles and policies scoped only to named Macs aren't shown.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(24)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if vm.flowState.isLoading {
            ProgressView("Reading the PreStage…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView("Choose a PreStage", systemImage: "list.number",
                                   description: Text("Pick a computer PreStage to see the steps a new Mac goes through."))
        }
    }

    @ViewBuilder
    private var setupManagerDetail: some View {
        SetupManagerStepList(rows: vm.flowSetupManagerRows, showStatus: false)
        let others = vm.setupManagerCandidates.count - 1
        if others > 0 {
            EnrollmentNote(
                text: "\(others) other Setup Manager profile\(others == 1 ? "" : "s") found. Choose which one this flow uses in Settings → Enrollment.",
                symbol: "info.circle", tint: .blue)
        }
    }

    @ViewBuilder
    private func items(_ phase: FlowPhase) -> some View {
        let groups: [(FlowCertainty, [FlowItem])] = [FlowCertainty.certain, .conditional, .excluded].compactMap { c in
            let list = phase.items.filter { $0.certainty == c }
            return list.isEmpty ? nil : (c, list)
        }
        if phase.items.isEmpty && !phase.needsScan
            && [.prestageItems, .profiles, .policies, .apps].contains(phase.phase) {
            Text("Nothing in this step.").foregroundStyle(.secondary)
        }
        ForEach(groups, id: \.0) { certainty, list in
            VStack(alignment: .leading, spacing: 6) {
                Text(certainty.label.uppercased())
                    .font(.caption.weight(.semibold)).tracking(0.5).foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                        FlowItemRow(item: item)
                            .background(index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.03))
                    }
                }
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        if phase.phase == .profiles, !phase.items.isEmpty {
            EnrollmentNote(text: "Smart group membership is decided after the first inventory, so conditional items can arrive minutes to hours after enrollment.",
                           symbol: "info.circle", tint: .blue)
        }
    }
}

private struct PhaseRailRow: View {
    let number: Int
    let phase: FlowPhase

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold)).monospacedDigit()
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(phase.phase.title).fontWeight(.semibold)
                Text(phase.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 4)
            trailing
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number): \(phase.phase.title), \(phase.summary)")
    }

    @ViewBuilder
    private var trailing: some View {
        if phase.needsScan {
            ProgressView().controlSize(.mini)
        } else if !phase.items.isEmpty {
            Text("\(phase.items.count)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
        } else if [.adeAssignment, .setupAssistant, .mdmEnrollment].contains(phase.phase) {
            Image(systemName: "checkmark").font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct FlowItemRow: View {
    let item: FlowItem

    var body: some View {
        HStack(spacing: 10) {
            mark
            Text(item.name).lineLimit(1)
            Spacer(minLength: 12)
            Text(item.condition)
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.tail)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12), in: Capsule())
                .help(item.condition)
            if let id = item.identifier {
                Text(id).font(.system(.caption, design: .monospaced)).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: 150, alignment: .trailing)
                    .help(id)
            }
        }
        .padding(.vertical, 6).padding(.horizontal, 10)
        .accessibilityElement(children: .combine)
    }

    private var mark: some View {
        Group {
            switch item.certainty {
            case .certain:     Image(systemName: "circle.fill").foregroundStyle(.green)
            case .conditional: Image(systemName: "circle.lefthalf.filled").foregroundStyle(.orange)
            case .excluded:    Image(systemName: "circle").foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .accessibilityLabel(item.certainty.label)
    }
}

private struct ScanStatusFooter: View {
    @Bindable var vm: EnrollmentFlowViewModel

    var body: some View {
        switch vm.scanState {
        case .idle:
            Button("Scan Scopes") { vm.startScan() }
        case .scanning(let done, let total):
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                HStack {
                    Text(total == 0 ? "Reading lists…" : "Scanning \(done) of \(total)").monospacedDigit()
                    Spacer()
                    Button("Cancel") { vm.cancelScan() }.controlSize(.small)
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        case .finished(let r):
            HStack {
                Text("Scanned \(r.policies.count) policies and \(r.profiles.count) profiles · \(r.scannedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { vm.startScan() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Scan scopes again")
                    .accessibilityLabel("Scan scopes again")
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 4) {
                Text(message).font(.caption).foregroundStyle(.orange)
                Button("Try Again") { vm.startScan() }
            }
        }
    }
}
