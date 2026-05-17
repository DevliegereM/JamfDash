import SwiftUI

struct SettingsInspectorView: View {
    @Bindable var vm: SettingsInspectorViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                InspectorSection(title: "Self Service", state: vm.selfServiceState)
                InspectorSection(title: "Client Check-in", state: vm.checkInState)
            }
            .padding()
        }
        .navigationTitle("Settings Inspector")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await vm.load(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(vm.selfServiceState.isLoading || vm.checkInState.isLoading)
            }
        }
        .task { await vm.load() }
    }
}

private struct InspectorSection: View {
    let title: String
    let state: LoadState<Data>
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(title, isExpanded: $isExpanded) {
            switch state {
            case .idle, .loading:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading…").foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            case .failed(let msg):
                Text(msg).foregroundStyle(.red).font(.caption).padding(.vertical, 4)
            case .loaded(let data):
                InspectorKeyValueTable(data: data)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct InspectorKeyValueTable: View {
    let data: Data

    private var pairs: [(key: String, value: String)] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return obj.sorted { $0.key < $1.key }.map { (key: $0.key, value: "\($0.value)") }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { index, pair in
                HStack(spacing: 12) {
                    Text(pair.key)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 180, alignment: .leading)
                    Text(pair.value)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(pair.value, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                    .help("Copy value")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.03))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }
}
