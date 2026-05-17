import SwiftUI

struct DDMDeclarationDetailView: View {
    let state: LoadState<[DDMStatusItem]>
    let hasSelection: Bool
    var onRetry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            switch state {
            case .idle:
                emptyPlaceholder

            case .loading:
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Loading status items…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))

            case .loaded(let items) where items.isEmpty:
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No DDM status items reported")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))

            case .loaded(let items):
                statusItemsList(items)

            case .failed(let message):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundStyle(.orange)
                    Text("Failed to load status items")
                        .font(.headline)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                    if let onRetry {
                        Button("Retry", action: onRetry)
                            .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))
            }
        }
    }

    private var emptyPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(hasSelection ? "No DDM status items reported" : "Select a device to view DDM status")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func statusItemsList(_ items: [DDMStatusItem]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.key)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        if let value = item.value {
                            Text(value)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        if let ts = item.lastUpdateTime {
                            Text(ts)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    if idx < items.count - 1 {
                        Divider()
                            .padding(.horizontal, 16)
                    }
                }
            }
        }
    }
}

#Preview {
    DDMDeclarationDetailView(
        state: .loaded([
            DDMStatusItem(key: "device.identifier.serial-number", value: "ZWC4FXYGYV", lastUpdateTime: "2026-04-24T15:56:17.194"),
            DDMStatusItem(key: "management.declarations.activations", value: "{active=true, valid=valid}", lastUpdateTime: "2026-04-24T15:56:17.198")
        ]),
        hasSelection: true
    )
}
