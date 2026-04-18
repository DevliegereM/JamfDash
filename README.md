# Jamf Dash

A native macOS dashboard for Jamf Pro, Jamf Protect, and Jamf School. Browse your fleet, review security posture, inspect analytics and configuration, and export reports — all from one app.

---

## Jamf Dash App

### Overview

Jamf Dash is a read-mostly macOS dashboard that connects to your Jamf environment via [`jamf-cli`](https://github.com/jamf-concepts/jamf-cli), an open-source CLI maintained by Jamf Concepts. The app downloads and manages `jamf-cli` automatically — no manual installation required.

**Supported products:**

| Product | Sidebar sections |
|---|---|
| Jamf Pro | Overview · Security Posture · Fleet & Config · Devices · Device Lookup · Reports |
| Jamf Protect | Overview · Computers · Plans · Analytics · Analytic Sets · Exception Sets |
| Jamf School | Overview · Devices · Device Groups · Users · User Groups · Classes · Apps |

### Requirements

- macOS 14 Sonoma or later
- A Jamf Pro, Jamf Protect, or Jamf School account with API access
- An internet connection for the initial `jamf-cli` download

### Setup

Jamf Dash guides you through a four-step onboarding flow the first time it launches:

1. **Welcome** — introduction
2. **Install jamf-cli** — the binary is downloaded automatically from Jamf Concepts
3. **Choose product** — Jamf Pro, Jamf Protect, or Jamf School
4. **Authenticate** — product-specific credentials (see below)

#### Jamf Pro — Local Admin Account

If your Jamf Pro instance has local admin accounts enabled, enter your server URL, admin username, and password. Jamf Dash will automatically create a dedicated API client for you.

#### Jamf Pro — SSO / No Local Accounts

If your instance uses SSO or has local accounts disabled, you need to create an API client manually first:

1. In Jamf Pro, go to **Settings → System → API Roles and Clients**
2. Create an **API Role** with the privileges you need
3. Create an **API Client**, assign the role, and save the **Client ID** and **Client Secret** (shown only once)

Then enter the server URL, Client ID, and Client Secret in Jamf Dash.

#### Jamf Protect

1. In Jamf Protect, go to **Administration → API Clients**
2. Create an API Client and note the **Client ID**
3. Generate a **Client Secret**

Enter the server URL, Client ID, and Client Secret in Jamf Dash.

#### Jamf School

1. In Jamf School, go to **Organisation → API**
2. Note your **Network ID** and generate an **API Key**

Enter the server URL, Network ID, and API Key in Jamf Dash.

### Adding More Connections

After initial setup, you can add connections for additional products or additional Jamf instances from **Settings → Connection → Add Connection**. All credentials are stored securely in the system keychain by `jamf-cli`.

### Switching Profiles

If you have multiple `jamf-cli` profiles configured (e.g. separate Jamf Pro instances or both Pro and Protect), use the **profile picker at the bottom of the sidebar** to switch between them. All subsequent API calls will use the selected profile.

### Features

#### Jamf Pro

**Overview**
High-level stats fetched from the Jamf Pro overview endpoint — device counts, licence usage, and more.

**Security Posture**
A security report with compliance charts and OS distribution breakdown.

**Fleet & Config**
Browse policies, smart computer groups, categories, scripts, packages, and configuration profiles in one place.

**Devices**
Three-tab view of your Mac inventory:
- *All Devices* — searchable list with name, serial number, OS version, and last contact time
- *Stale Check-in* — devices that have not checked in within a configurable number of days (default 30), with an adjustable stepper
- *macOS Versions* — interactive donut chart with a version legend; tap a version to see which devices are on it

Serial numbers and device names are selectable so you can copy them directly.

**Device Lookup**
Look up any Mac by serial number and run device management actions:
- Safe actions: Blank Push, Renew MDM, DDM Sync, Flush Failed/All Commands
- Moderate actions: Redeploy Framework, Enable/Disable Remote Desktop, Restart, Shutdown
- Destructive actions (with confirmation): Remove MDM, Set Recovery Lock, Lock, Erase

**Reports**
Export a PDF summary of your Jamf Pro environment. Optionally add your company logo from **Settings → Branding** — it will appear in the report header.

#### Jamf Protect

**Overview**
Summary statistics from the Protect overview endpoint.

**Computers**
Table of enrolled computers showing host name, serial number, OS version, assigned plan, and last check-in time.

**Plans**
List of Protect plans with action config, telemetry, log level, and auto-update flag. Click any row to see full details.

**Analytics**
All configured analytics with severity badges (colour-coded: High = red, Medium = orange, Low = yellow, Informational = blue), categories, and source. Click any row to see full details.

**Analytic Sets**
Configured analytic sets with analytics count, types, plans, and managed status. Click any row to see full details.

**Exception Sets**
All exception sets with their UUID. Click any row to load and display the full exception set detail.

#### Jamf School

**Overview**
Summary statistics from the School overview endpoint.

**Devices / Device Groups**
Browse enrolled devices and their groups.

**Users / User Groups / Classes**
Browse school users, user groups, and class assignments.

**Apps**
List of managed apps in your School environment.

### jamf-cli Updates

Jamf Dash checks for `jamf-cli` updates automatically. When a newer version is available, an update banner appears at the top of the app. You can also check manually from **Settings → CLI → Check for Updates**.

---

## JamfCLI Bash Tool

The `JamfCLI/` directory contains a standalone bash script that generates **self-contained HTML reports** for Jamf Pro environments — no app required.

### Features

- **Cleanup analysis** — surfaces unused categories, scripts, packages, policies, and smart groups
- **History tracking** — compares each run against previous runs to highlight what changed
- **Self-contained output** — produces a single `.html` file with no external dependencies
- **swiftDialog UI wrapper** — optional macOS GUI for selecting options and displaying progress
- **Demo mode** — generates a sample report without a live Jamf Pro connection

### Usage

See [`JamfCLI/README.md`](JamfCLI/README.md) for full usage instructions, prerequisites, and configuration options.

---

## Project Structure

```
Jamf Dash/
├── App/
│   └── JamfDash/
│       ├── App/                    # AppState, AppEnvironment, RootView
│       ├── Features/
│       │   ├── Onboarding/         # Setup wizard
│       │   ├── Settings/           # Connection, profile, CLI, branding settings
│       │   ├── Sidebar/            # NavigationSplitView sidebar
│       │   ├── Overview/           # Jamf Pro overview
│       │   ├── Security/           # Security posture + charts
│       │   ├── Fleet/              # Policies, groups, categories, scripts, packages
│       │   ├── Devices/            # Device inventory + stale check-in + OS chart
│       │   ├── DeviceSearch/       # Device lookup + actions
│       │   ├── Export/             # PDF report generation
│       │   ├── Protect/            # All Jamf Protect views
│       │   └── School/             # All Jamf School views
│       ├── Models/                 # Codable data models
│       ├── Services/               # CLIManager, KeychainService, CLIDownloader
│       └── ViewModels/             # @Observable view models per feature
└── JamfCLI/                        # Standalone bash HTML report tool
```

## License

This project is provided as-is. See [LICENSE](LICENSE) for details.
