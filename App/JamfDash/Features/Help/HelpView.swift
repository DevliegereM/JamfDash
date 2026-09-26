import SwiftUI

extension Notification.Name {
    static let openHelpWindow = Notification.Name("jamfDash.openHelpWindow")
    static let refreshCurrentView = Notification.Name("jamfDash.refreshCurrentView")
    static let focusSearch = Notification.Name("jamfDash.focusSearch")
    static let openDeviceSearch = Notification.Name("jamfDash.openDeviceSearch")
    static let navigateToSidebarItem = Notification.Name("jamfDash.navigateToSidebarItem")
}

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                HelpSection(title: "Keyboard Shortcuts", icon: "keyboard", color: .purple) {
                    HelpItem(heading: "Available shortcuts") {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Cmd+R — Refresh current view", systemImage: "command").font(.caption)
                            Label("Cmd+K — Jump to Device Search", systemImage: "command").font(.caption)
                            Label("Cmd+F — Focus search field", systemImage: "command").font(.caption)
                            Label("Cmd+1–9 — Navigate sidebar items", systemImage: "command").font(.caption)
                            Label("Cmd+? — Open Help window", systemImage: "command").font(.caption)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                    }
                }

                HelpSection(title: "Getting Started", icon: "star.fill", color: .yellow) {
                    HelpItem(heading: "jamf-cli dependency") {
                        Text("Jamf Dash uses the open-source **jamf-cli** binary (by Jamf Concepts) to communicate with Jamf APIs. The binary is downloaded automatically the first time you connect, or you can install it manually and skip that step. Use the CLI tab in Settings to check for updates or install it at any time.")
                        Link("Jamf Concepts / jamf-cli on GitHub ↗", destination: URL(string: "https://github.com/Jamf-Concepts/jamf-cli")!)
                            .font(.callout)
                    }
                    HelpItem(heading: "Demo Mode") {
                        Text("Enable Demo Mode (Settings → CLI → Demo) to explore the entire app with synthetic data — no Jamf connection required. Restart the app to return to a real connection.")
                    }
                }

                HelpSection(title: "Connections & Profiles", icon: "key.fill", color: .teal) {
                    HelpItem(heading: "Adding a connection") {
                        Text("Open Settings → Connection and click the **+** button. Choose your Jamf product (Pro, Protect, or School) and enter the required credentials. Each connection is stored securely in the system keychain by jamf-cli and appears as a named profile.")
                    }
                    HelpItem(heading: "Jamf Pro — Platform API") {
                        Text("**Recommended.** The Platform API is the only connection that shows every section, including Blueprints and Compliance Benchmarks. In account.jamf.com, create the API integration at the **platform environment** level — a tenant-level integration can't read Blueprints or Compliance Benchmarks. Then choose **Platform API** when adding a connection, pick your **Region**, and enter the **Environment ID**, **Client ID**, and **Client Secret**.\n\nDevice actions (lock, restart, recovery lock, …) aren't available through the Platform API yet — Jamf is still expanding it, so more will become available over time. Until then, add a Jamf Pro API client connection for device actions.")
                    }
                    HelpItem(heading: "Switching profiles") {
                        Text("If you have multiple Jamf environments (e.g., dev and production), add a connection for each. Then use the **Active Profile** picker to choose which environment Jamf Dash queries. Click **Save** to apply the change — all data views will reload automatically.")
                    }
                    HelpItem(heading: "Removing a connection") {
                        Text("Click the trash icon next to any profile in Settings → Connection to permanently remove it from the keychain.")
                    }
                }

                HelpSection(title: "Jamf Pro — Overview", icon: "chart.bar.fill", color: .blue) {
                    HelpItem(heading: "Fleet Summary") {
                        Text("Shows totals for managed computers and mobile devices, and a count of devices that have checked in recently vs. those that have not been seen in 30+ days.")
                    }
                    HelpItem(heading: "Hardware & OS breakdown") {
                        Text("Pie and bar charts showing the distribution of Mac models and operating system versions across your fleet.")
                    }
                }

                HelpSection(title: "Jamf Pro — Security Posture", icon: "lock.shield.fill", color: .green) {
                    HelpItem(heading: "Fleet Health Score") {
                        Text("A 0–100 score computed from six weighted security signals: FileVault encryption (25 pts), SIP (20 pts), Gatekeeper (15 pts), Firewall (15 pts), patch compliance (15 pts), and stale-device ratio (10 pts). The score is shown as a circular gauge with a letter grade (A–F) at the top of the Security view. When the score drops below your configured threshold, the Jamf Dash Dock tile shows a badge with the current score. Use the **Alert Threshold** stepper (gear icon in the Security toolbar) to set the threshold; a macOS notification is also sent the first time the score crosses it.")
                    }
                    HelpItem(heading: "Compliance donuts") {
                        Text("Four donut charts display the percentage of computers that have FileVault encryption, Gatekeeper, System Integrity Protection (SIP), and Firewall enabled.")
                    }
                    HelpItem(heading: "OS Version distribution") {
                        Text("A bar chart showing how many devices are on each macOS version, so you can track patch adoption across the fleet.")
                    }
                    HelpItem(heading: "Device Security Detail table") {
                        Text("Lists every managed computer with a per-row status indicator for FileVault, SIP, Firewall, and Gatekeeper. Use the **Issues Only** toggle in the toolbar to filter down to devices that have at least one non-compliant setting. Click the ↗ icon to open any device directly in the Jamf Pro web console.")
                    }
                }

                HelpSection(title: "AI Assistant (Dashie)", icon: "sparkles", color: .purple) {
                    HelpItem(heading: "What Dashie can do") {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("• Answer fleet questions — device counts, compliance rates, OS distribution, patch status")
                            Text("• Look up any Mac by serial number — hardware specs, installed apps, group memberships")
                            Text("• Report on security posture, smart groups, and policies")
                            Text("• Send management commands (blank push, MDM renew, restart) after your confirmation")
                        }
                        .font(.callout)
                    }
                    HelpItem(heading: "Requirements") {
                        Text("Requires macOS 26 or later with **Apple Intelligence** enabled (System Settings → Apple Intelligence & Siri) on an eligible device. All data processing happens on-device — nothing is sent to external servers.")
                    }
                    HelpItem(heading: "Context compaction") {
                        Text("When a conversation grows long, Dashie automatically summarises the history — capturing message counts, key topics, devices discussed, and important findings — into a JSON file saved to ~/Library/Application Support/JamfDash/. The conversation then continues seamlessly with a fresh context. The saved path is shown in the chat.")
                    }
                    HelpItem(heading: "Limitations") {
                        Text("Dashie cannot create, update, or delete Jamf Pro objects. Use the Jamf Pro web console for configuration changes. Dashie works only with data accessible via jamf-cli.")
                    }
                }

                HelpSection(title: "Jamf Pro — Platform", icon: "globe", color: .purple) {
                    HelpItem(heading: "Blueprints") {
                        Text("Browse all DDM (Declarative Device Management) blueprints. Select any blueprint to see its deployment state, last deployment time, scope, and the full set of declarations. Each declaration shows its type, channel, and all payload settings as structured key-value rows — booleans appear with checkmark or cross icons; nested objects are expanded inline.")
                    }
                    HelpItem(heading: "Compliance Benchmarks") {
                        Text("Lists all configured compliance benchmarks with name and status. Select a benchmark to view its controls and rules. Tap **Load Compliance Results** to fetch the current benchmark results for your fleet.")
                    }
                    HelpItem(heading: "Requirements") {
                        Text("Both views require a **Platform API** connection. If you see an auth error, go to Settings → Connection and add a Platform API profile.")
                    }
                }

                HelpSection(title: "Jamf Pro — Fleet & Config", icon: "gearshape.2.fill", color: .indigo) {
                    HelpItem(heading: "Policies") {
                        Text("Shows all Jamf policies grouped by category. Click any policy row to open a detail sheet displaying its full scope: included computer groups, individual computers, departments, buildings, and any exclusions.")
                    }
                    HelpItem(heading: "Smart Groups") {
                        Text("Displays all smart computer groups. Click any group to open a visual criteria inspector showing each criterion with logical connector badges (IF / AND / OR), optional parenthesis grouping, criterion name, search-type chip, and copyable monospaced value. A read-only banner notes that editing requires the Jamf Pro web console.")
                    }
                    HelpItem(heading: "Scripts") {
                        Text("Full script inventory grouped by category. Click any script to see its contents, description, and parameters in a scrollable detail sheet.")
                    }
                    HelpItem(heading: "Packages") {
                        Text("Lists all packages in Jamf Pro with name, category, and filename.")
                    }
                    HelpItem(heading: "Configuration Profiles") {
                        Text("Lists all configuration profiles grouped by category. Click any profile to see its full scope.")
                    }
                }

                HelpSection(title: "Jamf Pro — Devices", icon: "desktopcomputer", color: .blue) {
                    HelpItem(heading: "Computer inventory") {
                        Text("A full list of all computers in Jamf Pro with name, serial number, OS version, and last check-in time. Switch between All Devices, Stale Check-in (configurable threshold), and the macOS version distribution chart.")
                    }
                }

                HelpSection(title: "Jamf Pro — Mobile Devices", icon: "iphone", color: .blue) {
                    HelpItem(heading: "iOS & iPadOS inventory") {
                        Text("Browse all enrolled mobile devices with name, serial number, model, OS version, and last check-in time. Supports the same All / Stale / OS-version tabs as the Mac Devices view.")
                    }
                }

                HelpSection(title: "Jamf Pro — Device Lookup", icon: "magnifyingglass", color: .purple) {
                    HelpItem(heading: "Search") {
                        Text("Search your entire fleet by device name, serial number, or username. Results appear instantly as you type.")
                    }
                    HelpItem(heading: "Device detail") {
                        Text("Selecting a result shows a full detail view: hardware specs, storage, OS, enrolled user, and management state. Click the **Open in Jamf Pro** button to jump directly to that device record in the web console.")
                    }
                    HelpItem(heading: "Remote Actions") {
                        Text("From the device detail view you can send management commands. Actions are grouped by impact:")
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Safe — Lock Screen, Send Blank Push, Update Inventory", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            Label("Moderate — Enable/Disable Remote Desktop, Set Recovery Lock", systemImage: "exclamationmark.circle.fill").foregroundStyle(.orange)
                            Label("Destructive — Remote Wipe, Erase Device", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                        }
                        .font(.caption)
                        .padding(.top, 2)
                    }
                    HelpItem(heading: "Device History") {
                        Text("At the bottom of each device detail view, a Device History panel shows: an enrollment timeline with first enrolled date, last re-enrolled date (if different), and last check-in; the enrollment method recorded by Jamf Pro; and placeholder sections for MDM command history and user assignment history (data not available via jamf-cli).")
                    }
                }

                HelpSection(title: "Jamf Pro — Org Browser", icon: "building.2.fill", color: .brown) {
                    HelpItem(heading: "Buildings, Departments & Network Segments") {
                        Text("Browse the three foundational org objects in Jamf Pro across separate tabs. Use these to verify that your organisational structure is configured correctly before scoping policies or profiles.")
                    }
                }

                HelpSection(title: "Jamf Pro — Extension Attributes", icon: "tag.fill", color: .teal) {
                    HelpItem(heading: "Attribute table") {
                        Text("Lists all computer extension attributes with name, data type, and input type. Click any row to open a detail sheet showing the full description, inventory display category, enabled state, and — for script-based attributes — the complete script contents in a monospaced, scrollable editor.")
                    }
                }

                HelpSection(title: "Jamf Pro — Patch Management", icon: "bandage.fill", color: .orange) {
                    HelpItem(heading: "Patch Titles") {
                        Text("Lists all software titles registered in Patch Management, including the category and the latest available version. Use this to verify which title versions Jamf Pro currently tracks.")
                    }
                    HelpItem(heading: "Patch Policies") {
                        Text("Shows all configured patch policies with their name, patch title, target version, and enabled state.")
                    }
                }

                HelpSection(title: "Jamf Pro — Enrollment & Prestages", icon: "person.badge.plus.fill", color: .mint) {
                    HelpItem(heading: "DEP Tokens") {
                        Text("Displays all Apple Business Manager / Apple School Manager tokens linked to your Jamf Pro instance, including the associated organisation name and token expiry date. Renew tokens before they expire to avoid enrollment interruptions.")
                    }
                    HelpItem(heading: "Computer Prestages") {
                        Text("Lists all Mac enrollment prestages with their name and whether MDM removal is allowed.")
                    }
                    HelpItem(heading: "Mobile Device Prestages") {
                        Text("Lists all iOS/iPadOS enrollment prestages with their name and MDM removal setting.")
                    }
                }

                HelpSection(title: "Jamf Pro — Reports", icon: "doc.richtext.fill", color: .cyan) {
                    HelpItem(heading: "CSV reports") {
                        Text("Choose from eight built-in report types. Results appear in a full-width table and can be exported to a CSV file via the **Export CSV** button:")
                        VStack(alignment: .leading, spacing: 3) {
                            Text("• **Patch Status** — patch compliance per computer and title")
                            Text("• **Policy Status** — policy execution results per device")
                            Text("• **Profile Status** — configuration profile deployment status")
                            Text("• **App Status** — managed app install status per device")
                            Text("• **Update Status** — macOS software update status")
                            Text("• **Device Compliance** — overall compliance summary per device")
                            Text("• **Inventory Summary** — full inventory snapshot")
                            Text("• **Software Installs** — installed software across the fleet")
                        }
                        .font(.callout)
                    }
                    HelpItem(heading: "PDF export") {
                        Text("Generates a PDF report containing the Overview and Security Posture data. If you have uploaded a company logo (Settings → Branding), it appears in the report header.")
                    }
                }

                HelpSection(title: "Jamf Protect", icon: "shield.lefthalf.filled", color: .red) {
                    HelpItem(heading: "Overview") {
                        Text("Summary of endpoint security events detected across your Protect-managed fleet.")
                    }
                    HelpItem(heading: "Computers") {
                        Text("Lists computers enrolled in Jamf Protect with their agent status and plan assignment.")
                    }
                    HelpItem(heading: "Plans") {
                        Text("Shows all Protect plans (detection rule sets) and how many computers are assigned to each.")
                    }
                    HelpItem(heading: "Analytics, Analytic Sets & Exception Sets") {
                        Text("Browse the analytics (behavioral detections), their groupings into analytic sets, and any exception rules that exclude specific behaviors from alerting.")
                    }
                }

                HelpSection(title: "Jamf School", icon: "graduationcap.fill", color: .orange) {
                    HelpItem(heading: "Overview") {
                        Text("At-a-glance counts for devices, users, classes, and apps in your Jamf School environment.")
                    }
                    HelpItem(heading: "Devices & Device Groups") {
                        Text("Full inventory of school-managed devices and the groups they belong to.")
                    }
                    HelpItem(heading: "Users, User Groups & Classes") {
                        Text("Directory of students and staff, their group memberships, and the classes they are enrolled in.")
                    }
                    HelpItem(heading: "Apps") {
                        Text("Lists all apps distributed through Jamf School, including their assignment scope and install status.")
                    }
                    HelpItem(heading: "Configuration Profiles") {
                        Text("Lists all configuration profiles deployed through Jamf School, showing the profile name, scope, payload count, and enabled/disabled state. A green badge indicates an active profile; grey indicates it is disabled.")
                    }
                    HelpItem(heading: "ADE / DEP Enrollment Pipeline") {
                        Text("Shows all devices in the Apple Device Enrollment (ADE/DEP) pipeline. Each row displays the serial number, model, assigned enrollment profile, and current enrollment status — color-coded from green (enrolled) through yellow (awaiting) to red (failed). Use this view to monitor in-progress deployments and spot any devices stuck in the pipeline.")
                    }
                }

                HelpSection(title: "Jamf Pro — Audit Dashboard", icon: "checklist.checked", color: .indigo) {
                    HelpItem(heading: "What it shows") {
                        Text("A cross-resource health dashboard that runs all audit checks across five categories simultaneously — **Security**, **Compliance**, **Hygiene**, **Enrollment**, and **Platform** — and surfaces the results as a unified, searchable findings list.")
                    }
                    HelpItem(heading: "Severity levels") {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Critical — requires immediate attention", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                            Label("Warning — should be reviewed soon", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            Label("Info — informational, no action required", systemImage: "info.circle.fill").foregroundStyle(.blue)
                        }
                        .font(.caption)
                        .padding(.top, 2)
                    }
                    HelpItem(heading: "Filtering") {
                        Text("Click any severity chip in the summary bar to filter to that level. Use the **Category** picker to narrow by audit domain, or type in the search box to match against finding titles, descriptions, and categories. All filters can be combined.")
                    }
                    HelpItem(heading: "Finding detail panel") {
                        Text("Click any row in the findings table to open an inline detail panel below it. The panel shows the full description of the finding under a **Details** heading, and any available remediation guidance under a **Remediation** heading. The panel is resizable via the divider — drag it up or down to adjust the split.")
                    }
                }

                HelpSection(title: "Jamf Pro — DDM Monitor", icon: "square.3.layers.3d", color: .teal) {
                    HelpItem(heading: "Per-Device view") {
                        Text("Shows the DDM (Declarative Device Management) status for every managed device. Each row displays the device name, last check-in time, and the status of its active declarations. Select a device to open a full declaration detail sheet.")
                    }
                    HelpItem(heading: "Fleet Overview tab") {
                        Text("Switch to **Fleet Overview** using the segmented control in the toolbar to see an aggregate table of all declaration types across the fleet. Each row shows a declaration identifier together with counts of how many devices have it in a Succeeded, Failed, or Pending state — giving you an instant picture of roll-out health without scanning device by device.")
                    }
                }

                HelpSection(title: "Jamf Pro — Configuration Drift Tracker", icon: "clock.arrow.trianglehead.counterclockwise.rotate.90", color: .brown) {
                    HelpItem(heading: "What it tracks") {
                        Text("Monitors changes to **Policies**, **Configuration Profiles**, and **Scripts** over time. Each time you take a snapshot, Jamf Dash records the current state to a local SQLite database and computes a diff against the previous snapshot — surfacing Added, Modified, and Removed events.")
                    }
                    HelpItem(heading: "Taking a snapshot") {
                        Text("Click **Snapshot Now** in the toolbar. Jamf Dash fetches the latest policies, profiles, and scripts in parallel, stores them in the local database, and immediately shows any drift events that have occurred since the last snapshot. The first snapshot establishes the baseline — no events will appear until a second snapshot is taken.")
                    }
                    HelpItem(heading: "Drift timeline") {
                        Text("Events are grouped by date in a scrollable list. Each row is color-coded: **green +** for added items, **yellow ~** for modified items, and **red −** for removed items. An item-type badge (Policy / Profile / Script) appears next to the name.")
                    }
                    HelpItem(heading: "Diff detail") {
                        Text("Click any drift event to open a detail sheet with a two-column table showing the field name, its previous value, and its new value — making it easy to see exactly what changed.")
                    }
                    HelpItem(heading: "Storage") {
                        Text("Snapshots and events are stored locally at ~/Library/Application Support/JamfDash/drift.db. No data is sent externally. You can delete this file at any time to reset the drift history.")
                    }
                }

                HelpSection(title: "Jamf Pro — Device Correlation", icon: "arrow.left.arrow.right", color: .purple) {
                    HelpItem(heading: "What it does") {
                        Text("When both Jamf Pro and Jamf Protect are connected, the Device Correlation view joins computers from both products by serial number, giving you a single unified table that shows the complete picture — security agent status alongside MDM management state — for every device.")
                    }
                    HelpItem(heading: "Match states") {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Matched — device found in both Pro and Protect", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            Label("Pro only — managed by Jamf Pro but not enrolled in Protect", systemImage: "circle.lefthalf.filled").foregroundStyle(.blue)
                            Label("Protect only — in Protect but not found in Jamf Pro", systemImage: "circle.righthalf.filled").foregroundStyle(.orange)
                        }
                        .font(.caption)
                        .padding(.top, 2)
                    }
                    HelpItem(heading: "Detail panel") {
                        Text("Select any device row to open a split detail panel. The **left side** shows Protect details: plan assignment, connection status, FDA state, web protection, agent version, and alert count. The **right side** shows Pro details: management state, OS version, last contact date, and quick-action buttons.")
                    }
                    HelpItem(heading: "Availability") {
                        Text("The Device Correlation item only appears in the sidebar when Protect data has been loaded. Navigate to any Protect view first if it is not visible.")
                    }
                }

                HelpSection(title: "Jamf Pro — Notifications", icon: "bell.badge.fill", color: .red) {
                    HelpItem(heading: "Notification bell") {
                        Text("When Jamf Pro has active system alerts, a bell icon with a badge count appears in the main toolbar. Click it to open a popover listing all current notifications with their severity, title, and creation date. The badge clears automatically when the notification list is empty.")
                    }
                }

                HelpSection(title: "Settings", icon: "gearshape.fill", color: .gray) {
                    HelpItem(heading: "CLI updates") {
                        Text("Use the **CLI** tab to check whether a newer version of jamf-cli is available and to apply updates in one click.")
                    }
                    HelpItem(heading: "Branding") {
                        Text("Upload a PNG or JPEG company logo via the **Branding** tab. The logo is embedded in the header of exported PDF reports.")
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Jamf Dash Help")
        .frame(minWidth: 620, minHeight: 500)
    }
}

// MARK: - HelpSection card

struct HelpSection<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Coloured header row
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                    .frame(width: 20)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(color.opacity(0.08))

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                content
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(color.opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - HelpItem row

struct HelpItem<Content: View>: View {
    let heading: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(heading)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
            content
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
