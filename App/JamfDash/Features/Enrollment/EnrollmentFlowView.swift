import SwiftUI

/// What a new Mac gets when it enrolls through a PreStage, phase by phase.
struct EnrollmentFlowView: View {
    @Bindable var vm: EnrollmentFlowViewModel
    @State private var selectedPhase: EnrollmentPhase? = .profiles

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 380)
            detail
                .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            await vm.loadPrestages()
            if case .idle = vm.scanState { vm.startScan() }
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            AsyncContentView(state: vm.prestagesState, retry: { await vm.loadPrestages(force: true) }) { prestages in
                if prestages.isEmpty {
                    ContentUnavailableView("No Computer PreStages", systemImage: "shippingbox",
                                           description: Text("Create a computer PreStage enrollment in Jamf Pro to see its flow here."))
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        Picker("PreStage", selection: Binding(get: { vm.selectedPrestageID }, set: { vm.selectPrestage($0) })) {
                            ForEach(prestages) { Text($0.displayName).tag(Optional($0.id)) }
                        }
                        .padding(10)
                        phaseList
                    }
                }
            }
            Divider()
            ScanStatusFooter(vm: vm)
                .padding(10)
        }
    }

    @ViewBuilder
    private var phaseList: some View {
        switch vm.flowState {
        case .loaded(let flow):
            List(selection: $selectedPhase) {
                ForEach(Array(flow.phases.enumerated()), id: \.element.id) { index, phase in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold)).monospacedDigit()
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Color.accentColor, in: Circle())
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(phase.phase.title).fontWeight(.medium)
                            Text(phase.summary).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                    .tag(Optional(phase.phase))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Step \(index + 1): \(phase.phase.title), \(phase.summary)")
                }
            }
            .listStyle(.sidebar)
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
                        Text("PreStage “\(flow.prestage.name)”").font(.caption).foregroundStyle(.secondary)
                        Label(phase.phase.title, systemImage: phase.phase.symbol)
                            .font(.title2.weight(.semibold))
                        Text(phase.summary).font(.title3).foregroundStyle(.secondary)
                    }
                    ForEach(phase.lines, id: \.self) { line in
                        Text(line).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                    if phase.needsScan {
                        ScanPrompt(vm: vm, reason: "Scan scopes to see which profiles and enrollment policies a new Mac gets.")
                    }
                    items(phase)
                    if phase.phase == .profiles || phase.phase == .policies, flow.specificOnlyCount > 0 {
                        Text("\(flow.specificOnlyCount) profiles and policies scoped only to named Macs aren't shown.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(24)
                .frame(maxWidth: 720, alignment: .leading)
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
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    ForEach(list) { item in
                        HStack(spacing: 10) {
                            certaintyMark(certainty)
                            Text(item.name)
                            Spacer()
                            Text(item.condition).font(.callout).foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                        .padding(.vertical, 6).padding(.horizontal, 10)
                        .help(item.identifier ?? item.name)
                        .accessibilityElement(children: .combine)
                        Divider().padding(.leading, 30)
                    }
                }
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        if phase.phase == .profiles, !phase.items.isEmpty {
            EnrollmentNote(text: "Group membership is decided after the first inventory, so conditional items can arrive minutes to hours after enrollment.",
                           symbol: "info.circle", tint: .blue)
        }
    }

    private func certaintyMark(_ c: FlowCertainty) -> some View {
        Group {
            switch c {
            case .certain:     Image(systemName: "circle.fill").foregroundStyle(.green)
            case .conditional: Image(systemName: "circle.lefthalf.filled").foregroundStyle(.orange)
            case .excluded:    Image(systemName: "circle").foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .accessibilityLabel(c.label)
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
                Text("Scanned \(r.policies.count) policies · \(r.profiles.count) profiles · \(r.scannedAt.formatted(.relative(presentation: .named)))")
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
