# Privacy

Jamf Dash is a Mac app for looking at and managing your own Jamf instances. It has no analytics, no tracking and no account with us.

## What stays on your Mac

- **Credentials** are stored by jamf-cli in your login keychain. Jamf Security Cloud credentials, if you add them, are stored in your keychain by Jamf Dash.
- **Fleet data** (devices, policies, reports) is fetched from your Jamf instance when you open a section and kept in memory.
- **Configuration Drift** snapshots and **daily digests** are stored in `~/Library/Application Support/JamfDash/instances/`, one folder per connection.
- **Dashie** uses Apple's on-device model only. Conversations stay in memory and are never sent anywhere.
- **Logs** go to the macOS unified log (subsystem `com.jamfdash`). Server addresses, serials and other values are marked private, so macOS hides them unless you change your logging configuration.

## Network connections

- **Your Jamf instances**, through jamf-cli, and Jamf Security Cloud if you configure it.
- **GitHub**, to download jamf-cli releases (`Jamf-Concepts/jamf-cli`) and to check for Jamf Dash updates (`DevliegereM/JamfDash`). GitHub sees your IP address and the app version, as with any download.

## Problem reports

Nothing is sent unless you use **Help → Report a Problem…** and choose how to send it. Before anything leaves your Mac you see every file and can edit or remove it. Server addresses, serial numbers, names, email and IP addresses, IDs and tokens are replaced with placeholders.

- **Email** (jamfdash@devliegere.be) with the report attached: used only to investigate the problem, and deleted when it's resolved or after 12 months at the latest.
- **GitHub issue**: text only (your description and versions). GitHub issues are public.

To have a report deleted, email jamfdash@devliegere.be with the report ID (JD-…).

## Not affiliated with Jamf

Jamf Dash is an independent project. It isn't made, endorsed or supported by Jamf. Jamf, Jamf Pro, Jamf Protect and Jamf School are trademarks of JAMF Software, LLC.
