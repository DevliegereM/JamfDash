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
                        Text("Platform API unlocks Blueprints and Compliance Benchmarks. Choose **Platform API** when adding a connection and enter the **Gateway URL**, **Tenant ID**, **Client ID**, and **Client Secret** from account.jamf.com. Requires jamf-cli 1.17 or later — update via Settings → CLI if needed.")
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
                        Text("Both views require a **Platform API** connection and **jamf-cli 1.17 or later**. If you see an auth error, go to Settings → Connection and add a Platform API profile, then update jamf-cli via Settings → CLI if needed.")
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
