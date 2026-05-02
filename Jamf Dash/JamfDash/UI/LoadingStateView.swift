import SwiftUI

// MARK: - Generic async content helper

struct AsyncContentView<T: Sendable, Content: View, Empty: View>: View {
    let state: LoadState<T>
    let retry: (() async -> Void)?
    @ViewBuilder let content: (T) -> Content
    @ViewBuilder let empty: () -> Empty

    init(
        state: LoadState<T>,
        retry: (() async -> Void)? = nil,
        @ViewBuilder content: @escaping (T) -> Content,
        @ViewBuilder empty: @escaping () -> Empty = { EmptyView() }
    ) {
        self.state = state
        self.retry = retry
        self.content = content
        self.empty = empty
    }

    var body: some View {
        switch state {
        case .idle, .loading:
            SyncingIndicator()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let value):
            content(value)
        case .failed(let message):
            ErrorStateView(message: message, retry: retry)
        }
    }
}

// MARK: - Error state

struct ErrorStateView: View {
    let message: String
    let retry: (() async -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 400)
            if let retry {
                Button("Retry") {
                    Task { await retry() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Section header

struct DashSectionHeader: View {
    let title: String
    let systemImage: String?

    init(_ title: String, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 6) {
            if let icon = systemImage {
                Image(systemName: icon)
                    .foregroundStyle(Color.accentColor)
            }
            Text(title)
                .font(.headline)
        }
        .padding(.bottom, 4)
    }
}
