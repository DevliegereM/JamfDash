import SwiftUI

// MARK: - DigestHistoryView

@available(macOS 26, *)
struct DigestHistoryView: View {

    // MARK: Properties

    let service: DigestService

    // MARK: Body

    var body: some View {
        NavigationStack {
            Group {
                if service.entries.isEmpty {
                    ContentUnavailableView(
                        "No Digests Yet",
                        systemImage: "doc.text",
                        description: Text("Run your first digest to see history here.")
                    )
                } else {
                    List(service.entries.reversed()) { entry in
                        DigestEntryRow(entry: entry)
                    }
                }
            }
            .navigationTitle("Digest History")
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}

// MARK: - DigestEntryRow

@available(macOS 26, *)
private struct DigestEntryRow: View {

    // MARK: Properties

    let entry: DigestEntry

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(entry.bullets, id: \.self) { bullet in
                Text(bullet)
                    .font(.body)
            }
        }
        .padding(.vertical, 4)
    }
}
