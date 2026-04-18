# Jamf Dash

A native macOS dashboard for Jamf Pro, Jamf Protect, and Jamf School. Browse your fleet, review security posture, inspect configuration and analytics, and export reports — all from one app.

---

## Overview

Jamf Dash connects to your Jamf environment via [`jamf-cli`](https://github.com/jamf-concepts/jamf-cli), an open-source CLI maintained by Jamf Concepts. The app downloads and manages `jamf-cli` automatically — no manual installation required.

**Supported products:**

| Product | Sections |
|---|---|
| Jamf Pro | Overview · Security Posture · Fleet & Config · Devices · Device Lookup · Reports |
| Jamf Protect | Overview · Computers · Plans · Analytics · Analytic Sets · Exception Sets |
| Jamf School | Overview · Devices · Device Groups · Users · User Groups · Classes · Apps |

---

## Requirements

- macOS 14 Sonoma or later
- A Jamf Pro, Jamf Protect, or Jamf School account with API access
- An internet connection for the initial `jamf-cli` download

---

## Setup

Jamf Dash guides you through a step-by-step onboarding flow on first launch:

1. **Welcome** — introduction, or try Demo Mode without any credentials
2. **Install jamf-cli** — the binary is downloaded automatically from Jamf Concepts
3. **Choose product** — Jamf Pro, Jamf Protect, or Jamf School
4. **Authenticate** — product-specific credentials (see below)

### Jamf Pro — Local Admin Account

If your instance has local admin accounts enabled, enter your server URL, admin username, and password. Jamf Dash will automatically create a dedicated API client.

### Jamf Pro — SSO / No Local Accounts

If your instance uses SSO or has local admin accounts disabled, create an API client manually first:

1. In Jamf Pro go to **Settings → System → API Roles and Clients**
2. Create an **API Role** with the privileges you need
3. Create an **API Client**, assign the role, and save the **Client ID** and **Client Secret** (shown only once)

Then enter the server URL, Client ID, and Client Secret in Jamf Dash.

### Jamf Protect

1. In Jamf Protect go to **Administration → API Clients**
2. Create an API Client and note the **Client ID**
3. Generate a **Client Secret**

Enter the server URL, Client ID, and Client Secret in Jamf Dash.

### Jamf School

1. In Jamf School go to **Organisation → API**
2. Note your **Network ID** and generate an **API Key**

Enter the server URL, Network ID, and API Key in Jamf Dash.

---

## Features

### Jamf Pro

**Overview**
High-level statistics from the Jamf Pro overview endpoint — device counts, licence usage, health alerts, certificate expiry, and more.

**Security Posture**
A full security compliance report including:
- Compliance summary (FileVault, Gatekeeper, SIP, Firewall) with percentage bars
- OS version distribution donut chart
- Per-device security breakdown table with selectable serial numbers

**Fleet & Config**
Browse all configuration objects in one place:
- Policies, Smart Computer Groups, Categories, Scripts, Packages, Configuration Profiles
- Each section is a sortable table with name and relevant metadata

**Devices**
Three-tab Mac inventory view:
- *All Devices* — searchable list with name, serial, OS version, and last contact time
- *Stale Check-in* — devices not checked in within a configurable number of days (adjustable stepper, default 30 days)
- *macOS Versions* — interactive donut chart with a version legend; click a segment to filter devices by that version

Serial numbers and device names are text-selectable for easy copying.

**Device Lookup**
Look up any Mac by serial number and view full hardware, OS, security, location, storage, network, and configuration profile detail. Run management actions directly from the detail panel:
- Safe: Blank Push, Renew MDM, DDM Sync, Flush Failed Commands, Flush All Commands
- Moderate: Redeploy Framework, Enable/Disable Remote Desktop, Restart, Shutdown
- Destructive (confirmation required): Remove MDM, Set Recovery Lock, Lock (with PIN), Erase

**Reports**
Export a PDF summary of your Jamf Pro environment. Optionally add your company logo from **Settings → Branding** — it will appear in the report header.

---

### Jamf Protect

**Overview**
Deployment and threat summary statistics from the Protect overview endpoint.

**Computers**
Table of enrolled computers showing host name, serial number, OS version, assigned plan, and last check-in time.

**Plans**
All configured Protect plans with action config, telemetry, log level, and auto-update flag. Click any row for a full detail sheet.

**Analytics**
All configured analytics with severity badges (High = red, Medium = orange, Low = yellow, Informational = blue), categories, input type, and source (Jamf built-in vs custom). Click any row for full details.

**Analytic Sets**
Configured analytic sets showing analytics count, types, plans, and managed status. Click any row for details.

**Exception Sets**
All exception sets with their UUID. Click any row to load and display the full exception set detail including description.

---

### Jamf School

**Overview**
Summary statistics for your school — device counts, user counts, groups, classes, and deployed apps.

**Devices**
Table of all enrolled devices with name, serial number, model, OS version, and managed status.

**Device Groups**
All configured device groups.

**Users**
All school users with name, username, and email.

**User Groups**
All configured user groups.

**Classes**
All class assignments.

**Apps**
List of managed apps deployed in your School environment.

---

## Multi-Connection Support

Jamf Dash supports multiple `jamf-cli` profiles — for example, separate Jamf Pro instances, or connections to both Pro and Protect. Add connections at any time from **Settings → Connection → Add Connection**. All credentials are stored securely in the system keychain by `jamf-cli`.

Use the **profile picker at the bottom of the sidebar** to switch between configured instances. All subsequent API calls will use the selected profile.

---

## Demo Mode

Jamf Dash includes a Demo Mode that shows synthetic data without any Jamf connection or credentials. Enable it from:
- The **Welcome** screen during onboarding — click **Try Demo**
- **Settings → CLI → Demo** — click **Enable Demo Mode** after the app is set up

In Demo Mode a banner appears in the toolbar and a product switcher (Pro / Protect / School) appears at the bottom of the sidebar so you can explore all three products.

---

## Settings

| Tab | Options |
|---|---|
| Connection | View configured connections, add new connections (Pro local account, Pro SSO, Protect, School) |
| Profile | Select which `jamf-cli` profile to use for API calls |
| CLI | View installed `jamf-cli` version, check for updates, update the binary, enable Demo Mode |
| Branding | Upload a company logo to include in exported PDF reports |

---

## jamf-cli Updates

Jamf Dash checks for `jamf-cli` updates automatically on launch. When a newer version is available, an **Update** button appears in the toolbar. You can also check manually from **Settings → CLI**.

---

## License

This project is provided as-is. See [LICENSE](LICENSE) for details.
