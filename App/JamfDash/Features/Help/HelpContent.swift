import Foundation

// MARK: - Model

/// Top-level tabs of the Help window.
enum HelpTab: String, CaseIterable, Identifiable, Sendable {
    case getStarted, jamfPro, protectSchool, dashie, troubleshooting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .getStarted:      return "Get Started"
        case .jamfPro:         return "Jamf Pro"
        case .protectSchool:   return "Protect & School"
        case .dashie:          return "Dashie"
        case .troubleshooting: return "Troubleshooting"
        }
    }

    var symbol: String {
        switch self {
        case .getStarted:      return "star"
        case .jamfPro:         return "desktopcomputer"
        case .protectSchool:   return "shield.lefthalf.filled"
        case .dashie:          return "sparkles"
        case .troubleshooting: return "wrench.and.screwdriver"
        }
    }
}

/// A piece of a help topic's body.
enum HelpBlock: Sendable, Hashable {
    /// A paragraph; supports inline Markdown (**bold**, `code`).
    case text(String)
    /// Numbered steps.
    case steps([String])
    /// A highlighted note or tip.
    case note(String)
    /// Keyboard shortcut rows: (keys, action).
    case shortcuts([Shortcut])

    struct Shortcut: Sendable, Hashable {
        let keys: String
        let action: String
    }

    /// Plain text for search and for Dashie.
    var plainText: String {
        switch self {
        case .text(let s), .note(let s): return s
        case .steps(let steps):          return steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: " ")
        case .shortcuts(let rows):       return rows.map { "\($0.keys): \($0.action)" }.joined(separator: "; ")
        }
    }
}

struct HelpTopic: Identifiable, Sendable, Hashable {
    let id: String
    let tab: HelpTab
    let section: String
    let title: String
    let symbol: String
    /// One sentence shown under the title and in search results.
    let summary: String
    let body: [HelpBlock]
    /// Extra words people might search for.
    let keywords: [String]
    /// Sidebar item this topic is about, for the "Open …" button (SidebarItem raw value).
    let opens: String?

    init(_ id: String, tab: HelpTab, section: String, title: String, symbol: String, summary: String,
         body: [HelpBlock], keywords: [String] = [], opens: String? = nil) {
        self.id = id; self.tab = tab; self.section = section; self.title = title; self.symbol = symbol
        self.summary = summary; self.body = body; self.keywords = keywords; self.opens = opens
    }

    var plainText: String {
        ([summary] + body.map(\.plainText)).joined(separator: " ")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
    }
}

// MARK: - Search

enum HelpSearch {
    /// Topics matching the query, best first. Title words weigh most, then keywords, then text.
    static func search(_ query: String, in topics: [HelpTopic] = HelpLibrary.topics, limit: Int = 20) -> [HelpTopic] {
        let words = Set(FleetKnowledgeIndex.tokens(query))
        guard !words.isEmpty else { return [] }
        let scored: [(HelpTopic, Double)] = topics.compactMap { topic in
            let title = Set(FleetKnowledgeIndex.tokens(topic.title + " " + topic.section))
            let keys = Set(FleetKnowledgeIndex.tokens(topic.keywords.joined(separator: " ")))
            let text = Set(FleetKnowledgeIndex.tokens(topic.plainText))
            var score = 0.0
            for w in words {
                if title.contains(w) { score += 4 }
                else if title.contains(where: { $0.hasPrefix(w) && w.count >= 3 }) { score += 3 }
                if keys.contains(w) { score += 3 }
                else if keys.contains(where: { $0.hasPrefix(w) && w.count >= 3 }) { score += 2 }
                if text.contains(w) { score += 1 }
                else if text.contains(where: { $0.hasPrefix(w) && w.count >= 4 }) { score += 0.5 }
            }
            return score > 0 ? (topic, score) : nil
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    /// Best matching topics as text for Dashie, with where to find them.
    static func answer(_ query: String, limit: Int = 3, characterLimit: Int = 2_400) -> String {
        let hits = search(query, limit: limit)
        guard !hits.isEmpty else {
            return "No Jamf Dash help topic matches “\(query)”. Suggest opening Help → Jamf Dash Help and searching there."
        }
        var out = hits.map { t in
            "## \(t.title) (Help → \(t.tab.title) → \(t.section))\n\(t.plainText)"
        }.joined(separator: "\n\n")
        if out.count > characterLimit { out = String(out.prefix(characterLimit)) + " …" }
        return out
    }
}

// MARK: - Content

enum HelpLibrary {
    static func topic(id: String) -> HelpTopic? { topics.first { $0.id == id } }

    static func sections(in tab: HelpTab) -> [(section: String, topics: [HelpTopic])] {
        var order: [String] = []
        var grouped: [String: [HelpTopic]] = [:]
        for t in topics where t.tab == tab {
            if grouped[t.section] == nil { order.append(t.section) }
            grouped[t.section, default: []].append(t)
        }
        return order.map { ($0, grouped[$0] ?? []) }
    }

    static let topics: [HelpTopic] = getStarted + jamfPro + protectSchool + dashie + troubleshooting

    // MARK: Get Started

    static let getStarted: [HelpTopic] = [
        HelpTopic("welcome", tab: .getStarted, section: "Basics", title: "What Jamf Dash does",
                  symbol: "square.grid.2x2", summary: "A native Mac dashboard for Jamf Pro, Jamf Protect and Jamf School.",
                  body: [
                    .text("Jamf Dash shows your fleet, security posture, configuration and compliance in one window, and lets you run common device actions. It talks to Jamf through **jamf-cli**, Jamf's open-source command-line tool, so it uses the same connections and permissions you set up there."),
                    .text("Choose a section in the sidebar. The product picker at the bottom of the sidebar switches between the Jamf instances you've connected."),
                  ],
                  keywords: ["overview", "introduction", "about", "start"]),
        HelpTopic("jamf-cli", tab: .getStarted, section: "Basics", title: "Install and update jamf-cli",
                  symbol: "terminal", summary: "Jamf Dash downloads and verifies jamf-cli for you.",
                  body: [
                    .text("The first time you open Jamf Dash it downloads jamf-cli into its own folder. Every copy must be signed by JAMF Software and match its published checksum, or Jamf Dash won't run it."),
                    .text("Jamf Dash needs **jamf-cli 1.31.1 or later** and updates older versions when it starts. Check for newer versions in **Settings → CLI** or with **Jamf Dash → Check for CLI Updates…**."),
                  ],
                  keywords: ["cli", "binary", "download", "version", "update", "install"]),
        HelpTopic("add-connection", tab: .getStarted, section: "Connections", title: "Add a connection",
                  symbol: "key", summary: "Connect Jamf Pro, Jamf Protect or Jamf School.",
                  body: [
                    .steps([
                        "Open **Settings → Connection** and click **+**.",
                        "Choose the product. For Jamf Pro, choose **Platform API** (recommended), an API client, or a local account.",
                        "Enter the details and click **Add**. Credentials are stored in your keychain by jamf-cli.",
                    ]),
                    .note("Jamf Dash never shows passwords or client secrets, including in error messages."),
                  ],
                  keywords: ["profile", "credentials", "setup", "login", "api client", "oauth", "keychain"]),
        HelpTopic("platform-api", tab: .getStarted, section: "Connections", title: "Use the Platform API for Jamf Pro",
                  symbol: "globe", summary: "The recommended connection: it's the only one that shows every section.",
                  body: [
                    .steps([
                        "In Jamf Account, create an API integration at the **platform environment** level, not for a single tenant.",
                        "Give it read permissions for what you want to see, including **Deployment → Blueprints: Read** and **Compliance → Compliance Benchmarks: Read**.",
                        "In Jamf Dash, add a Jamf Pro connection, choose **Platform API**, pick your **Region** (US, EU or APAC) and level **Environment**, then enter the Environment ID, Client ID and Client Secret.",
                    ]),
                    .note("Device actions such as lock and restart aren't available through the Platform API yet; Jamf is still expanding it. Add a Jamf Pro API client connection if you need them."),
                  ],
                  keywords: ["gateway", "environment", "tenant", "region", "jamf account", "integration", "permissions", "blueprints", "compliance"]),
        HelpTopic("switch-instance", tab: .getStarted, section: "Connections", title: "Switch between instances",
                  symbol: "arrow.left.arrow.right", summary: "Work with several Jamf environments, such as test and production.",
                  body: [
                    .text("Add a connection for each environment. Then use the picker at the bottom of the sidebar to switch. All sections reload, and Dashie's local fleet index is cleared so it never mixes data from two instances."),
                  ],
                  keywords: ["profile", "environment", "production", "test", "multiple"]),
        HelpTopic("demo", tab: .getStarted, section: "Basics", title: "Try Jamf Dash with demo data",
                  symbol: "play.rectangle", summary: "Explore every section without connecting to Jamf.",
                  body: [
                    .text("Click **Try Demo** on the welcome screen, or **Settings → CLI → Enable Demo Mode**. Demo data is made up; nothing is sent to Jamf. Quit and reopen Jamf Dash to return to your real connection."),
                  ],
                  keywords: ["demo mode", "sample", "test data", "synthetic"]),
        HelpTopic("shortcuts", tab: .getStarted, section: "Basics", title: "Keyboard shortcuts",
                  symbol: "keyboard", summary: "Move around Jamf Dash without the mouse.",
                  body: [
                    .shortcuts([
                        .init(keys: "⌘R", action: "Refresh the current section"),
                        .init(keys: "⌘K", action: "Open Device Lookup"),
                        .init(keys: "⌘F", action: "Search in the current section"),
                        .init(keys: "⌘1 – ⌘9", action: "Go to a sidebar item"),
                        .init(keys: "⌘,", action: "Open Settings"),
                        .init(keys: "⌘?", action: "Open Jamf Dash Help"),
                        .init(keys: "⌘↩", action: "Ask in plain language (Devices)"),
                    ]),
                  ],
                  keywords: ["keys", "hotkeys", "command", "navigate"]),
        HelpTopic("app-updates", tab: .getStarted, section: "Basics", title: "Keep Jamf Dash up to date",
                  symbol: "arrow.down.circle", summary: "Check for new versions automatically or manually.",
                  body: [
                    .text("In **Settings → Updates**, turn **Check for updates automatically** on or off. When on, Jamf Dash checks once a day and asks before installing. Turn on **Download and install updates automatically** to install updates when you quit."),
                    .text("To check now, choose **Jamf Dash → Check for App Updates…**. Updates only download what changed since your version."),
                  ],
                  keywords: ["sparkle", "upgrade", "new version", "automatic", "manual"]),
    ]

    // MARK: Jamf Pro

    static let jamfPro: [HelpTopic] = [
        HelpTopic("overview", tab: .jamfPro, section: "Fleet", title: "Overview and Health & Alerts",
                  symbol: "chart.bar", summary: "Instance totals, health and Jamf Pro's own alerts.",
                  body: [
                    .text("**Overview** shows managed computers and devices, the Jamf Pro version, and counts of policies, profiles, packages and more."),
                    .text("**Health & Alerts** lists Jamf Pro's active notifications. Identical alerts are shown once with a count, and below the table each kind of alert explains what it's about and how to fix it."),
                  ],
                  keywords: ["dashboard", "alerts", "notifications", "health", "instance", "counts"],
                  opens: "pro.overview"),
        HelpTopic("devices", tab: .jamfPro, section: "Devices", title: "Find Macs in Devices",
                  symbol: "desktopcomputer", summary: "Every Mac with serial, macOS version and last check-in.",
                  body: [
                    .text("Search by name or serial, switch to **Stale Check-in** to see Macs that haven't checked in for a while, or **macOS Versions** for the version spread. Export the list with **Export CSV**."),
                  ],
                  keywords: ["computers", "inventory", "stale", "check-in", "csv", "export"],
                  opens: "pro.devices"),
        HelpTopic("ask-devices", tab: .jamfPro, section: "Devices", title: "Ask about devices in plain language",
                  symbol: "sparkle.magnifyingglass", summary: "Type a question and get filters you can adjust.",
                  body: [
                    .steps([
                        "In **Devices**, type a question such as “Macs on macOS 14 not seen for two weeks”.",
                        "Click **Ask** or press ⌘↩.",
                        "Check the filters shown as chips. Click a chip to remove it, or **Clear** to start over.",
                    ]),
                    .text("You can filter on name, macOS version (exact, older than, or newer), days since check-in, and managed or unmanaged. If you ask for something the device list doesn't have, such as department, Jamf Dash says so instead of guessing. This uses Apple's on-device model; nothing leaves your Mac."),
                  ],
                  keywords: ["natural language", "question", "filter", "search", "ai", "query"],
                  opens: "pro.devices"),
        HelpTopic("device-lookup", tab: .jamfPro, section: "Devices", title: "Look up a device and run actions",
                  symbol: "magnifyingglass", summary: "Full details for one Mac, plus management commands.",
                  body: [
                    .text("Search by name or serial (⌘K) to see hardware, storage, macOS, user, security settings and update readiness. **Open in Jamf Pro** opens the record in the web console."),
                    .text("Actions include blank push, renew MDM profile, redeploy the Jamf framework, flush failed commands, restart, lock and more. Destructive actions ask for confirmation first."),
                    .note("With a Platform API connection, device actions aren't available yet. Use a Jamf Pro API client connection for them."),
                  ],
                  keywords: ["serial", "search", "lock", "restart", "erase", "blank push", "mdm", "actions", "commands"],
                  opens: "pro.deviceSearch"),
        HelpTopic("mobile", tab: .jamfPro, section: "Devices", title: "Mobile devices",
                  symbol: "iphone", summary: "iPhone and iPad inventory with the same views as Macs.",
                  body: [.text("Browse enrolled mobile devices with model, OS version and last check-in, including stale devices and the OS version spread.")],
                  keywords: ["iphone", "ipad", "ios", "ipados"], opens: "pro.mobileDevices"),
        HelpTopic("correlation", tab: .jamfPro, section: "Devices", title: "Match devices across Pro and Protect",
                  symbol: "arrow.left.arrow.right", summary: "One table joining Jamf Pro and Jamf Protect by serial number.",
                  body: [
                    .text("When both Jamf Pro and Jamf Protect are connected, **Device Correlation** shows each Mac's Protect agent status next to its management state. It appears in the sidebar once Protect data has loaded."),
                  ],
                  keywords: ["protect", "correlate", "join", "agent"], opens: "pro.deviceCorrelation"),
        HelpTopic("security-posture", tab: .jamfPro, section: "Security", title: "Security Posture and the health score",
                  symbol: "lock.shield", summary: "FileVault, SIP, Gatekeeper and firewall across the fleet.",
                  body: [
                    .text("The health score (0–100, graded A–F) weighs FileVault (25), SIP (20), Gatekeeper (15), firewall (15), patch compliance (15) and stale devices (10). Set an alert threshold with the gear button; below it, the Dock icon shows the score and you get a notification."),
                    .text("Turn on **Issues Only** to list just the Macs with at least one problem."),
                  ],
                  keywords: ["filevault", "sip", "gatekeeper", "firewall", "score", "grade", "encryption", "compliance"],
                  opens: "pro.security"),
        HelpTopic("compliance", tab: .jamfPro, section: "Security", title: "Read compliance benchmark results",
                  symbol: "checkmark.shield", summary: "Fleet score, failing devices and failing rules per benchmark.",
                  body: [
                    .text("Select a benchmark to see the **fleet compliance score**, the devices failing the most rules, and the rules with failures. Expand a rule for its description and failing devices; device names open Device Lookup."),
                    .text("The score is calculated by Jamf: each device's share of rules passed, averaged over all devices in scope. Devices that haven't reported results count as 0%, so a low score often means devices haven't reported yet."),
                    .note("Needs a Platform API connection at environment level with Compliance Benchmarks: Read."),
                  ],
                  keywords: ["cis", "benchmark", "mscp", "rules", "score", "percentage", "failing"],
                  opens: "pro.complianceBenchmarks"),
        HelpTopic("audit", tab: .jamfPro, section: "Security", title: "Audit Dashboard",
                  symbol: "checklist", summary: "Health checks for security, compliance, hygiene, enrollment and platform.",
                  body: [
                    .text("Runs all audit checks and lists the findings. Filter by severity or category, or search. Select a finding for details and remediation. It also flags configuration profiles that use payloads removed or deprecated in macOS 27 and names the declaration that replaces each."),
                  ],
                  keywords: ["findings", "remediation", "hygiene", "macos 27", "deprecation", "severity"],
                  opens: "pro.audit"),
        HelpTopic("fleet-config", tab: .jamfPro, section: "Configuration", title: "Policies, groups, scripts and profiles",
                  symbol: "gearshape.2", summary: "Browse configuration in Fleet & Config.",
                  body: [
                    .text("See policies by category with their scope, smart groups with their criteria, scripts with contents and parameters, packages, and configuration profiles with scope."),
                    .text("**Bulk** actions enable policies in a category or disable policies whose name matches a pattern. Patterns that would match every policy are refused."),
                  ],
                  keywords: ["policies", "smart groups", "scripts", "packages", "configuration profiles", "scope", "bulk", "disable", "enable"],
                  opens: "pro.fleet"),
        HelpTopic("blueprints", tab: .jamfPro, section: "Configuration", title: "Blueprints and deployment status",
                  symbol: "square.3.layers.3d", summary: "DDM blueprints with how many devices succeeded, failed or are pending.",
                  body: [
                    .text("The list shows each blueprint's state and device counts. Select one to see its scope, steps and declarations with every setting."),
                    .note("Needs a Platform API connection at environment level with Deployment → Blueprints: Read."),
                  ],
                  keywords: ["ddm", "declarations", "deployment", "succeeded", "failed", "pending"],
                  opens: "pro.blueprints"),
        HelpTopic("ddm", tab: .jamfPro, section: "Configuration", title: "DDM Monitor and Update Readiness",
                  symbol: "square.stack.3d.up", summary: "Declaration status per device, across the fleet, and macOS 27 readiness.",
                  body: [
                    .text("**Per device** shows each Mac's declarations; **Status Items** shows reported status items for all DDM devices; **Fleet Overview** counts succeeded, failed and pending per declaration."),
                    .text("**Update Readiness** checks every Mac for macOS 27, which only manages software updates declaratively: OS version, DDM enabled, update plans, reported status and profiles that still use legacy update payloads."),
                  ],
                  keywords: ["declarative", "status items", "software update", "macos 27", "readiness", "deferral"],
                  opens: "pro.ddmMonitor"),
        HelpTopic("patch", tab: .jamfPro, section: "Configuration", title: "Patch Management and App Installers",
                  symbol: "bandage", summary: "Patch titles, patch policies, App Installers and restricted software.",
                  body: [
                    .text("See software titles and patch policies, App Installer titles and deployments (with icon, target group, installed, in progress and failed counts), and restricted software."),
                  ],
                  keywords: ["patch", "app installers", "software titles", "restricted software", "updates"],
                  opens: "pro.patchManagement"),
        HelpTopic("drift", tab: .jamfPro, section: "Configuration", title: "Track configuration drift",
                  symbol: "clock.arrow.circlepath", summary: "See what changed in policies, profiles and scripts between snapshots.",
                  body: [
                    .steps([
                        "Open **Config Drift** and click **Snapshot Now** to record the current state.",
                        "Take another snapshot later. Added, modified and removed items appear, grouped by date.",
                        "Select an event to compare old and new values field by field.",
                    ]),
                    .text("Snapshots are stored on your Mac only."),
                  ],
                  keywords: ["changes", "snapshot", "history", "diff", "audit trail"],
                  opens: "pro.driftTracker"),
        HelpTopic("enrollment-timeline", tab: .jamfPro, section: "Configuration", title: "See what happens when a Mac enrolls",
                  symbol: "person.badge.plus", summary: "Follow a new Mac from enrollment through profiles, policies and apps.",
                  body: [
                    .text("**Enrollment → Recent Enrollments** lists the Macs that enrolled in the last 7, 30 or 90 days. Select one to see its timeline: every MDM command, configuration profile, policy and app install since enrollment, in order, with the time after enrollment."),
                    .text("**Needs Attention** at the top lists commands that failed and commands that are **stuck**: still pending after 4 hours or more while the Mac keeps checking in. **Send Blank Push…** asks the Mac to check in so waiting commands can be delivered."),
                    .steps([
                        "Open **Enrollment** and choose **Recent Enrollments**.",
                        "Select a Mac. Choose **First 24 hours**, **First 7 days** or **Since enrollment** to change the period.",
                        "Open **Profiles** to compare the profiles this Mac should have with what's installed. Click **Scan Scopes** the first time; it reads every policy and profile once.",
                        "Open **Policies & Apps** for policy logs, enrollment policies that haven't run yet, and app installs.",
                    ]),
                    .text("**Enrollment → Flow** shows what a new Mac gets from a PreStage, step by step: ADE assignment, Setup Assistant panes, MDM enrollment, PreStage profiles and packages, configuration profiles, enrollment policies, apps and the first inventory. Items are **certain** (in the PreStage or scoped to All Computers) or **conditional** (they depend on smart group membership, decided after the first inventory)."),
                    .text("**Jamf Setup Manager**: when a configuration profile sets Setup Manager's preferences (com.jamf.setupmanager), its steps appear as a step in the Flow, each with the policies its trigger runs, and on a Mac's timeline under **Setup Manager** with the result from the policy logs. With several Setup Manager profiles, choose one in **Settings → Enrollment**; Automatic uses the one installed on the Mac, then the one in the PreStage."),
                    .note("Jamf Pro only keeps command history and policy logs for the period set in **Log Flushing**. For Macs that enrolled earlier, the first events may be gone; the timeline says so. Everything shown is read-only and kept in memory only."),
                    .text("In **Device Lookup**, scroll to **MDM Command History** and click **Enrollment Timeline** to jump to that Mac's timeline. You can also ask Dashie: “What happened when C02XA001 enrolled?”"),
                  ],
                  keywords: ["enrollment", "enroll", "timeline", "prestage", "ade", "dep", "setup assistant", "mdm commands",
                             "stuck", "pending", "failed", "profiles", "new mac", "onboarding", "history", "blank push",
                             "setup manager", "enrollment actions", "com.jamf.setupmanager"],
                  opens: "pro.enrollment"),
        HelpTopic("more-pro", tab: .jamfPro, section: "Configuration", title: "Settings Inspector, extension attributes, enrollment and organization",
                  symbol: "list.bullet.rectangle", summary: "Other Jamf Pro configuration you can browse.",
                  body: [
                    .text("**Settings Inspector** shows Jamf Pro's check-in and Self Service settings. **Extension Attributes** lists attributes with their script. **Enrollment → Tokens & PreStages** shows Automated Device Enrollment tokens (with expiry) and prestages. **Organization** shows buildings, departments and network segments."),
                  ],
                  keywords: ["extension attributes", "prestage", "ade", "dep", "token", "buildings", "departments", "network segments"],
                  opens: "pro.settingsInspector"),
        HelpTopic("reports", tab: .jamfPro, section: "Reports", title: "Run and export reports",
                  symbol: "doc.richtext", summary: "Built-in reports you can export as CSV or PDF.",
                  body: [
                    .text("Choose a report such as patch status, policy status, profile status, app status, update status, device compliance, inventory summary or software installs, then export it. PDF reports include your logo from **Settings → Branding**."),
                  ],
                  keywords: ["csv", "pdf", "export", "report"], opens: "pro.reports"),
    ]

    // MARK: Protect & School

    static let protectSchool: [HelpTopic] = [
        HelpTopic("protect", tab: .protectSchool, section: "Jamf Protect", title: "Jamf Protect",
                  symbol: "shield.lefthalf.filled", summary: "Alerts, computers, plans and analytics.",
                  body: [
                    .text("Switch to a Protect connection with the picker at the bottom of the sidebar. You'll see alerts, computers with agent status, plans, analytics and analytic sets, audit logs, removable storage, unified logging, prevent lists and more."),
                  ],
                  keywords: ["protect", "edr", "alerts", "analytics", "plans", "agent"]),
        HelpTopic("security-cloud", tab: .protectSchool, section: "Jamf Protect", title: "Jamf Security Cloud",
                  symbol: "shield.checkered", summary: "Device risk and deployment state from Jamf Security Cloud.",
                  body: [
                    .text("Add your application ID and secret in **Settings → Security Cloud**. The **Security Cloud** section then lists devices with user, risk level, OS, connector and last seen time."),
                  ],
                  keywords: ["radar", "risk", "wandera", "security cloud", "ztna"], opens: "security.cloud"),
        HelpTopic("school", tab: .protectSchool, section: "Jamf School", title: "Jamf School",
                  symbol: "graduationcap", summary: "Devices, users, classes, apps and profiles.",
                  body: [
                    .text("Switch to a School connection to see devices and device groups, users and user groups, classes, apps, profiles and devices in Automated Device Enrollment with their status."),
                  ],
                  keywords: ["school", "classes", "students", "teachers", "education"]),
    ]

    // MARK: Dashie

    static let dashie: [HelpTopic] = [
        HelpTopic("dashie-intro", tab: .dashie, section: "Using Dashie", title: "What Dashie can do",
                  symbol: "sparkles", summary: "An AI assistant for your fleet that runs on your Mac.",
                  body: [
                    .text("Ask about device counts, stale Macs, one Mac's hardware or apps, security posture, compliance, patch status, policies and smart groups. Dashie can also send management commands after you confirm them."),
                    .text("Dashie can also answer questions about Jamf Dash itself, using this help."),
                  ],
                  keywords: ["ai", "assistant", "chat", "questions", "apple intelligence"], opens: "pro.aiAssistant"),
        HelpTopic("dashie-setup", tab: .dashie, section: "Using Dashie", title: "Set up Apple Intelligence for Dashie",
                  symbol: "apple.intelligence", summary: "Dashie needs Apple's on-device model.",
                  body: [
                    .steps([
                        "Open **System Settings → Apple Intelligence & Siri** (Dashie shows a button for this).",
                        "Turn on Apple Intelligence. Your Mac and Siri language must be supported, such as English.",
                        "Wait for the model to download. Dashie opens by itself when it's ready.",
                    ]),
                    .text("Requires macOS 26 or later on a Mac with Apple silicon."),
                  ],
                  keywords: ["apple intelligence", "enable", "download", "not available", "requirements", "model"]),
        HelpTopic("dashie-questions", tab: .dashie, section: "Using Dashie", title: "Ask good questions",
                  symbol: "text.bubble", summary: "Short, specific questions get the best answers.",
                  body: [
                    .text("Ask one thing at a time: “Which Macs haven't checked in for 30 days?” rather than several questions at once. For one Mac's hardware or apps, include its serial number. For fleet-wide breakdowns, just ask."),
                    .text("Try “What do we have for FileVault?”, “Which rules fail most?”, or “How do I add a Platform API connection?”."),
                  ],
                  keywords: ["prompt", "tips", "examples", "serial"]),
        HelpTopic("dashie-images", tab: .dashie, section: "Using Dashie", title: "Ask about a screenshot",
                  symbol: "photo", summary: "Attach an image and Dashie reads it on your Mac.",
                  body: [
                    .text("Click the paperclip, paste an image, or drop one on the message field, then ask about it, for example a Jamf Pro error or a Self Service message. Available on Macs whose model supports images (macOS 27)."),
                  ],
                  keywords: ["image", "screenshot", "vision", "attach", "paste", "drop", "picture"]),
        HelpTopic("dashie-index", tab: .dashie, section: "How Dashie works", title: "Dashie's fleet index",
                  symbol: "books.vertical", summary: "A local index Dashie searches for names and past digests.",
                  body: [
                    .text("After each sync, Jamf Dash indexes the names of policies, configuration profiles, scripts, packages, smart groups and Macs, blueprint states, compliance results and recent daily digests. Dashie searches it for questions like “What do we have for FileVault?”."),
                    .text("The index stays on your Mac, readable only by you, is never added to Spotlight, and is cleared when you switch instances."),
                  ],
                  keywords: ["index", "search", "knowledge", "digest", "privacy"]),
        HelpTopic("dashie-actions", tab: .dashie, section: "How Dashie works", title: "Actions and confirmation",
                  symbol: "hand.raised", summary: "Dashie asks before changing anything.",
                  body: [
                    .text("Dashie can send a blank push, renew the MDM profile, redeploy the framework, flush failed commands, restart a Mac, run a policy on a Mac, and bulk enable or disable policies. Every action except blank push shows a confirmation dialog first. Dashie can't create, edit or delete other Jamf Pro objects."),
                  ],
                  keywords: ["restart", "blank push", "confirm", "commands", "limitations"]),
        HelpTopic("dashie-privacy", tab: .dashie, section: "How Dashie works", title: "Privacy and long conversations",
                  symbol: "lock", summary: "Everything runs on-device.",
                  body: [
                    .text("Dashie only uses Apple's on-device model; your fleet data and images never leave your Mac. Private Cloud Compute isn't used."),
                    .text("The model can only hold so much of a conversation. Dashie shortens older tool results and summarises earlier messages when needed; summaries stay in memory only. Use **New Chat** for a fresh start."),
                  ],
                  keywords: ["private cloud compute", "pcc", "context", "memory", "new chat", "data"]),
        HelpTopic("digest", tab: .dashie, section: "How Dashie works", title: "Daily digest",
                  symbol: "doc.text.magnifyingglass", summary: "Three points about your fleet, once a day.",
                  body: [
                    .text("After the first sync each day, Jamf Dash writes three short points about overview, security and patch status and sends a notification. See earlier digests with the **Digest History** button in AI Assistant."),
                  ],
                  keywords: ["summary", "notification", "daily", "history"]),
    ]

    // MARK: Troubleshooting

    static let troubleshooting: [HelpTopic] = [
        HelpTopic("permission-errors", tab: .troubleshooting, section: "Connections", title: "Fix “doesn't have permission” errors",
                  symbol: "hand.raised.slash", summary: "Grant the missing permission to your API integration.",
                  body: [
                    .text("The message names the permission to add, for example **Deployment → Policies: Read**. Add it to the API integration in Jamf Account (Platform API) or the API role in Jamf Pro (API client), then refresh. If it still fails, get a fresh token:"),
                    .note("`jamf-cli -p <profile> platform auth token --refresh`"),
                  ],
                  keywords: ["403", "forbidden", "permission denied", "access", "role", "privileges"]),
        HelpTopic("greyed-out", tab: .troubleshooting, section: "Connections", title: "Blueprints or Compliance Benchmarks are greyed out",
                  symbol: "circle.slash", summary: "They need a Platform API connection at environment level.",
                  body: [
                    .text("The sidebar greys them out when the active connection can't read them. Use a Platform API connection created at the **platform environment** level (not tenant) with the read permissions for Blueprints and Compliance Benchmarks."),
                  ],
                  keywords: ["disabled", "unavailable", "tenant", "environment", "blueprints", "compliance"]),
        HelpTopic("actions-unavailable", tab: .troubleshooting, section: "Connections", title: "Device actions aren't available",
                  symbol: "exclamationmark.octagon", summary: "The Platform API doesn't offer lock, restart and similar actions yet.",
                  body: [.text("Add a Jamf Pro API client connection and switch to it for device actions. Jamf is expanding the Platform API, so this may change.")],
                  keywords: ["lock", "restart", "unsupported", "platform api", "mdm commands"]),
        HelpTopic("patch-ea-alert", tab: .troubleshooting, section: "Jamf Pro", title: "“Patch extension attribute issue” alerts",
                  symbol: "bandage", summary: "A patch title needs its extension attribute accepted.",
                  body: [
                    .steps([
                        "In Jamf Pro, open **Settings → Computer management → Patch Management**.",
                        "Select each affected software title.",
                        "Under **Extension Attributes**, accept the attribute. The alert clears after the next inventory update.",
                    ]),
                  ],
                  keywords: ["health", "alerts", "patch", "extension attribute", "notification"]),
        HelpTopic("low-compliance", tab: .troubleshooting, section: "Jamf Pro", title: "Compliance score looks too low",
                  symbol: "chart.line.downtrend.xyaxis", summary: "Devices without results count as 0%.",
                  body: [.text("If many devices show as unknown for every rule, they haven't reported results yet. Check that the benchmark's configuration reaches them and that they've run the checks. Fixing unreported devices usually raises the score more than fixing individual rules.")],
                  keywords: ["benchmark", "percentage", "unknown", "not reported"]),
        HelpTopic("dashie-unavailable", tab: .troubleshooting, section: "Dashie", title: "Dashie isn't available",
                  symbol: "sparkles", summary: "Apple Intelligence is off, downloading, or not supported.",
                  body: [.text("Open **AI Assistant**: it shows what's missing and a button to the right System Settings pane. Dashie needs a Mac with Apple silicon, macOS 26 or later, and a supported language.")],
                  keywords: ["apple intelligence", "not working", "unavailable", "language", "intel"]),
        HelpTopic("logs", tab: .troubleshooting, section: "Diagnostics", title: "Collect logs for a problem",
                  symbol: "ladybug", summary: "Capture detailed logs and export them.",
                  body: [
                    .steps([
                        "Open **Settings → Developer** and turn on **Verbose Unified Logging**.",
                        "Reproduce the problem.",
                        "Click **Export Logs to Downloads** and attach the file to your report.",
                    ]),
                  ],
                  keywords: ["debug", "logging", "console", "export", "report bug", "diagnostics"]),
        HelpTopic("cli-version", tab: .troubleshooting, section: "Diagnostics", title: "jamf-cli errors or outdated version",
                  symbol: "terminal", summary: "Update jamf-cli from Settings → CLI.",
                  body: [.text("Jamf Dash needs jamf-cli 1.31.1 or later and updates it when it starts. If updating fails, try **Settings → CLI**. A jamf-cli copy that isn't signed by JAMF Software is never run.")],
                  keywords: ["cli", "version", "update", "signature", "binary"]),
    ]
}
