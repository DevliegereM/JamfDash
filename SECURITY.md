# Security policy

## Reporting a vulnerability

Please report security problems privately by email to **jamfdash@devliegere.be**, not in a public GitHub issue. Include the Jamf Dash version, what an attacker can do, and the steps to reproduce it. You'll get a reply within a week.

Please don't include real credentials, server addresses or device data from your organisation.

## Supported versions

Only the latest release gets security fixes. Jamf Dash updates itself through Sparkle; you can also check with **Jamf Dash → Check for App Updates…**.

## How Jamf Dash protects your data

- Jamf Dash never sees your Jamf credentials after setup. They're stored by jamf-cli in your login keychain, and passwords are typed into jamf-cli's own prompts through a pseudo-terminal, never passed as command-line arguments.
- Before every run, jamf-cli's code signature is checked against JAMF Software's Developer ID (team 483DWKW443). The running process is checked again before any input is sent to it.
- jamf-cli runs in a separate helper process (an XPC service) that only accepts connections from Jamf Dash signed by the same team, and only runs jamf-cli from Jamf Dash's own folder.
- Actions that change devices or Jamf Pro need a confirmation that's checked centrally, for one command on one connection. Destructive actions (erase, lock, remove MDM, clear Recovery Lock, mobile unmanage and Lost Mode) are off for every connection until you turn them on in **Settings → Connection**.
- Dashie (the on-device assistant) can only run actions when you turn them on in **Settings → Dashie**, and each one shows a confirmation with what Jamf Dash looked up itself.
- App updates are EdDSA-signed, and the update feed itself is signed.

## Scope

In scope: the Jamf Dash app, its helper, and its update feed. Out of scope: jamf-cli itself (report those to [Jamf-Concepts/jamf-cli](https://github.com/Jamf-Concepts/jamf-cli)), and Jamf Pro, Protect and School (report those to Jamf).
