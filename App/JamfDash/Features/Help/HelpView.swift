import AppKit
import Observation
import SwiftUI

extension Notification.Name {
    static let openHelpWindow = Notification.Name("jamfDash.openHelpWindow")
    static let refreshCurrentView = Notification.Name("jamfDash.refreshCurrentView")
    static let focusSearch = Notification.Name("jamfDash.focusSearch")
    static let openDeviceSearch = Notification.Name("jamfDash.openDeviceSearch")
    static let navigateToSidebarItem = Notification.Name("jamfDash.navigateToSidebarItem")
    /// userInfo["item"]: a SidebarItem raw value. Sent by Help's "Open …" buttons.
    static let showSidebarItem = Notification.Name("jamfDash.showSidebarItem")
}

// MARK: - Navigation into the Help window

/// Lets the Help menu search, Dashie and other windows open Help at a topic or search.
@MainActor
@Observable
final class HelpNavigator {
    static let shared = HelpNavigator()

    private(set) var requestedTopicID: String?
    private(set) var requestedQuery: String?
    /// Changes on every request so the Help window reacts even to the same topic twice.
    private(set) var requestCount = 0

    /// Opens the Help window, optionally at a topic or with a search.
    func open(topic: String? = nil, query: String? = nil) {
        requestedTopicID = topic
        requestedQuery = query
        requestCount += 1
        NotificationCenter.default.post(name: .openHelpWindow, object: nil)
    }
}

// MARK: - Help menu search

/// Makes help topics appear in the Help menu's search field, next to matching menu items.
final class HelpMenuSearch: NSObject, NSUserInterfaceItemSearching, @unchecked Sendable {
    static let shared = HelpMenuSearch()

    func searchForItems(withSearch searchString: String, resultLimit: Int,
                        matchedItemHandler handleMatchedItems: @escaping ([Any]) -> Void) {
        handleMatchedItems(HelpSearch.search(searchString, limit: min(resultLimit, 8)).map(\.id))
    }

    func localizedTitles(forItem item: Any) -> [String] {
        guard let id = item as? String, let topic = HelpLibrary.topic(id: id) else { return [] }
        return [topic.title]
    }

    func performAction(forItem item: Any) {
        guard let id = item as? String else { return }
        Task { @MainActor in HelpNavigator.shared.open(topic: id) }
    }

    func showAllHelpTopics(forSearch searchString: String) {
        Task { @MainActor in HelpNavigator.shared.open(query: searchString) }
    }
}

// MARK: - Help window

struct HelpView: View {
    @State private var tab: HelpTab = .getStarted
    @State private var selection: String?
    @State private var query = ""
    private let navigator = HelpNavigator.shared

    private var searchResults: [HelpTopic] { HelpSearch.search(query) }
    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            if let id = selection, let topic = HelpLibrary.topic(id: id) {
                HelpTopicView(topic: topic) { selection = $0 }
            } else {
                ContentUnavailableView("Choose a Topic", systemImage: "questionmark.circle",
                                       description: Text("Pick a topic in the sidebar or search Help."))
            }
        }
        .searchable(text: $query, placement: .sidebar, prompt: "Search Help")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Help section", selection: $tab) {
                    ForEach(HelpTab.allCases) { t in
                        Label(t.title, systemImage: t.symbol).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .labelStyle(.titleOnly)
                .help("Help sections")
            }
        }
        .navigationTitle("Jamf Dash Help")
        .frame(minWidth: 820, minHeight: 520)
        .onAppear {
            applyRequest()
            if selection == nil { selection = HelpLibrary.sections(in: tab).first?.topics.first?.id }
        }
        .onChange(of: navigator.requestCount) { applyRequest() }
        .onChange(of: tab) { _, newTab in
            guard !isSearching else { return }
            if let id = selection, HelpLibrary.topic(id: id)?.tab == newTab { return }
            selection = HelpLibrary.sections(in: newTab).first?.topics.first?.id
        }
        .onChange(of: selection) { _, id in
            // Keep the tab in step with the topic, e.g. when picked from search results.
            if let t = id.flatMap(HelpLibrary.topic(id:))?.tab, t != tab { tab = t }
        }
    }

    private func applyRequest() {
        if let q = navigator.requestedQuery, !q.isEmpty {
            query = q
            selection = HelpSearch.search(q).first?.id ?? selection
        }
        if let id = navigator.requestedTopicID, let topic = HelpLibrary.topic(id: id) {
            query = ""
            tab = topic.tab
            selection = id
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        if isSearching {
            let results = searchResults
            if results.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List(selection: $selection) {
                    ForEach(HelpTab.allCases) { t in
                        let inTab = results.filter { $0.tab == t }
                        if !inTab.isEmpty {
                            Section(t.title) {
                                ForEach(inTab) { topic in
                                    TopicRow(topic: topic, showSummary: true).tag(topic.id)
                                }
                            }
                        }
                    }
                }
            }
        } else {
            List(selection: $selection) {
                ForEach(HelpLibrary.sections(in: tab), id: \.section) { group in
                    Section(group.section) {
                        ForEach(group.topics) { topic in
                            TopicRow(topic: topic, showSummary: false).tag(topic.id)
                        }
                    }
                }
            }
        }
    }
}

private struct TopicRow: View {
    let topic: HelpTopic
    let showSummary: Bool

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(topic.title)
                if showSummary {
                    Text(topic.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        } icon: {
            Image(systemName: topic.symbol)
        }
    }
}

// MARK: - Topic page

struct HelpTopicView: View {
    let topic: HelpTopic
    let select: (String) -> Void

    private var related: [HelpTopic] {
        HelpLibrary.topics.filter { $0.tab == topic.tab && $0.section == topic.section && $0.id != topic.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(topic.tab.title) › \(topic.section)")
                        .font(.caption).foregroundStyle(.secondary)
                    Label {
                        Text(topic.title).font(.title2.weight(.semibold))
                    } icon: {
                        Image(systemName: topic.symbol).foregroundStyle(.tint)
                    }
                    Text(topic.summary)
                        .font(.title3).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(Array(topic.body.enumerated()), id: \.offset) { _, block in
                    HelpBlockView(block: block)
                }

                if let raw = topic.opens, let item = SidebarItem(rawValue: raw) {
                    Button {
                        NotificationCenter.default.post(name: .showSidebarItem, object: nil,
                                                        userInfo: ["item": raw])
                    } label: {
                        Label("Open \(item.title)", systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(.bordered)
                }

                if !related.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Related topics").font(.headline)
                        ForEach(related) { other in
                            Button(other.title) { select(other.id) }
                                .buttonStyle(.link)
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .textSelection(.enabled)
    }
}

private struct HelpBlockView: View {
    let block: HelpBlock

    var body: some View {
        switch block {
        case .text(let s):
            Text(LocalizedStringKey(s))
                .fixedSize(horizontal: false, vertical: true)
        case .steps(let steps):
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.callout.weight(.bold)).monospacedDigit()
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Color.accentColor, in: Circle())
                            .accessibilityHidden(true)
                        Text(LocalizedStringKey(step))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("Step \(index + 1): \(step.replacingOccurrences(of: "**", with: ""))")
                    }
                }
            }
        case .note(let s):
            Label {
                Text(LocalizedStringKey(s)).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "info.circle").foregroundStyle(.blue)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        case .shortcuts(let rows):
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                ForEach(rows, id: \.keys) { row in
                    GridRow {
                        Text(row.keys)
                            .font(.body.monospaced())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 5))
                        Text(row.action)
                    }
                }
            }
        }
    }
}
