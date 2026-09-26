import Foundation

// MARK: - Scanned profile

/// A macOS configuration profile reduced to what the deprecation rules need:
/// the payload types it contains and the top-level keys used in each payload.
struct ScannedProfile: Sendable, Hashable, Identifiable {
    let id: Int
    let name: String
    /// PayloadType → top-level keys used in that payload (union across duplicates).
    let payloads: [String: Set<String>]

    var payloadTypes: Set<String> { Set(payloads.keys) }
}

enum ProfilePayloadParser {

    /// Parses a `classic-macos-config-profiles get <id> -o json` response.
    /// Returns nil when the response has no usable `general` section.
    static func parse(detailJSON data: Data, fallbackID: Int? = nil, fallbackName: String? = nil) -> ScannedProfile? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let root = (json["os_x_configuration_profile"] as? [String: Any]) ?? json
        let general = root["general"] as? [String: Any] ?? [:]

        let id = (general["id"] as? Int)
            ?? (general["id"] as? String).flatMap(Int.init)
            ?? fallbackID
        guard let id else { return nil }
        let name = (general["name"] as? String) ?? fallbackName ?? "Profile \(id)"
        let payloadText = (general["payloads"] as? String) ?? (root["payloads"] as? String) ?? ""
        return ScannedProfile(id: id, name: name, payloads: payloads(fromPlist: payloadText))
    }

    /// Extracts PayloadType → keys from a profile plist (XML text).
    static func payloads(fromPlist text: String) -> [String: Set<String>] {
        guard !text.isEmpty else { return [:] }
        var result: [String: Set<String>] = [:]

        if let data = text.data(using: .utf8),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            let contents = plist["PayloadContent"] as? [[String: Any]] ?? []
            for payload in contents {
                guard let type = payload["PayloadType"] as? String else { continue }
                let keys = Set(payload.keys).subtracting(Self.envelopeKeys)
                result[type, default: []].formUnion(keys)
                // Custom Settings (com.apple.ManagedClient.preferences) nest the real domain.
                if type == "com.apple.ManagedClient.preferences",
                   let domains = payload["PayloadContent"] as? [String: Any] {
                    for (domain, value) in domains {
                        var nested: Set<String> = []
                        if let dict = value as? [String: Any],
                           let forced = dict["Forced"] as? [[String: Any]] {
                            for entry in forced {
                                if let settings = entry["mcx_preference_settings"] as? [String: Any] {
                                    nested.formUnion(settings.keys)
                                }
                            }
                        }
                        result[domain, default: []].formUnion(nested)
                    }
                }
            }
            if !result.isEmpty { return result }
        }

        // Fallback for truncated / non-plist payload text: regex scan.
        let types = matches(of: #"<key>PayloadType</key>\s*<string>([^<]+)</string>"#, in: text)
        let keys = Set(matches(of: #"<key>([^<]+)</key>"#, in: text)).subtracting(Self.envelopeKeys)
        for type in types {
            result[type, default: []].formUnion(keys)
        }
        return result
    }

    private static let envelopeKeys: Set<String> = [
        "PayloadType", "PayloadVersion", "PayloadIdentifier", "PayloadUUID",
        "PayloadDisplayName", "PayloadDescription", "PayloadOrganization",
        "PayloadEnabled", "PayloadContent", "PayloadScope",
    ]

    private static func matches(of pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { m in
            guard m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: text) else { return nil }
            return String(text[r]).trimmingCharacters(in: .whitespaces)
        }
    }
}

// MARK: - Rules

/// A rule that flags configuration profiles using payloads (or payload keys)
/// that Apple deprecated or removed with the OS 27 releases.
///
/// Source: Apple's device-management schema (github.com/apple/device-management,
/// `mdm/profiles/*.yaml`, release branch) — `deprecated:` / `removed:` markers.
struct DeprecationRule: Sendable, Identifiable {
    let id: String
    let severity: AuditSeverity
    let title: String
    let payloadTypes: Set<String>
    /// When non-nil, the rule only matches payloads that use at least one of these keys.
    let keys: Set<String>?
    let detail: String
    let replacement: String

    func matches(_ profile: ScannedProfile) -> Bool {
        for (type, used) in profile.payloads where payloadTypes.contains(type) {
            guard let keys else { return true }
            if !used.isDisjoint(with: keys) { return true }
        }
        return false
    }
}

enum DeprecationAuditRules {
    static let category = "deprecation"

    /// Software-update deferral keys in `com.apple.applicationaccess`
    /// (deprecated in 26, removed in 27).
    static let softwareUpdateDeferralKeys: Set<String> = [
        "enforcedSoftwareUpdateDelay",
        "enforcedSoftwareUpdateMajorOSDeferredInstallDelay",
        "enforcedSoftwareUpdateMinorOSDeferredInstallDelay",
        "enforcedSoftwareUpdateNonOSDeferredInstallDelay",
        "forceDelayedSoftwareUpdates",
        "forceDelayedMajorSoftwareUpdates",
        "forceDelayedAppSoftwareUpdates",
    ]

    static let rules: [DeprecationRule] = [
        DeprecationRule(
            id: "os27-softwareupdate-payload",
            severity: .critical,
            title: "Software Update payload removed in macOS 27",
            payloadTypes: ["com.apple.SoftwareUpdate"],
            keys: nil,
            detail: "The com.apple.SoftwareUpdate profile payload is removed in macOS 27 and has no effect on devices running it.",
            replacement: "Use the declarative Software Update Settings configuration (com.apple.configuration.softwareupdate.settings) — in Jamf Pro, a Blueprint or Managed Software Update plan."
        ),
        DeprecationRule(
            id: "os27-softwareupdate-deferrals",
            severity: .critical,
            title: "Software update deferral restrictions removed in macOS 27",
            payloadTypes: ["com.apple.applicationaccess"],
            keys: softwareUpdateDeferralKeys,
            detail: "Restrictions such as enforcedSoftwareUpdateDelay / forceDelayedSoftwareUpdates are removed in macOS 27. Devices on 27 ignore them.",
            replacement: "Move deferrals to com.apple.configuration.softwareupdate.settings (Deferrals) and enforce versions with com.apple.configuration.softwareupdate.enforcement.specific."
        ),
        DeprecationRule(
            id: "os27-applicationaccess-new",
            severity: .warning,
            title: "Parental Controls app restrictions deprecated (com.apple.applicationaccess.new)",
            payloadTypes: ["com.apple.applicationaccess.new"],
            keys: nil,
            detail: "The com.apple.applicationaccess.new payload is deprecated in macOS 27.",
            replacement: "Apple's published schema doesn't have a one-to-one declaration yet (the announced binary allow/deny declaration isn't in the public schema). Use Jamf Pro Restricted Software or Jamf Protect prevent lists for now."
        ),
        DeprecationRule(
            id: "os27-assetcache-managed",
            severity: .warning,
            title: "Content Caching payload deprecated (com.apple.AssetCache.managed)",
            payloadTypes: ["com.apple.AssetCache.managed"],
            keys: nil,
            detail: "The Content Caching profile payload is deprecated in macOS 27.",
            replacement: "Use the Content Cache Settings declaration (com.apple.configuration.content-cache.settings)."
        ),
        DeprecationRule(
            id: "os27-network-dns-relay",
            severity: .warning,
            title: "DNS Settings / DNS Proxy / Relay payloads deprecated",
            payloadTypes: ["com.apple.dnsSettings.managed", "com.apple.dnsProxy.managed", "com.apple.relay.managed"],
            keys: nil,
            detail: "The DNS Settings, DNS Proxy and Relay profile payloads are deprecated in OS 27; network configuration moves to declarations.",
            replacement: "Use com.apple.configuration.network.dns-settings, com.apple.configuration.network.dns-proxy and com.apple.configuration.network.relay."
        ),
        DeprecationRule(
            id: "os27-network-vpn",
            severity: .info,
            title: "VPN profiles can move to declarations",
            payloadTypes: ["com.apple.vpn.managed", "com.apple.vpn.managed.applayer"],
            keys: nil,
            detail: "VPN payloads aren't deprecated yet, but declarative VPN configurations are now available and are the direction of travel.",
            replacement: "Plan a move to com.apple.configuration.network.vpn.ikev2 / .ipsec / .vpn-plugin / .always-on."
        ),
        DeprecationRule(
            id: "os27-pppc-tcc",
            severity: .info,
            title: "PPPC (Privacy Preferences) profile uses services changed in macOS 27",
            payloadTypes: ["com.apple.TCC.configuration-profile-policy"],
            keys: nil,
            detail: "Several PPPC services (e.g. Camera, Microphone, Accessibility, SpeechRecognition, BluetoothAlways) are marked deprecated in macOS 27.",
            replacement: "Review the profile. Apple announced a unified Privacy declaration, but it isn't in the public schema yet — keep the PPPC profile until it ships."
        ),
    ]

    /// Evaluates every rule against the scanned profiles. Rules with no matches produce no finding.
    static func findings(for profiles: [ScannedProfile]) -> [AuditFinding] {
        rules.compactMap { rule in
            let hits = profiles.filter(rule.matches).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            guard !hits.isEmpty else { return nil }
            let names = hits.map(\.name)
            return AuditFinding(
                id: rule.id,
                severity: rule.severity,
                category: category,
                title: rule.title,
                description: rule.detail,
                affectedCount: hits.count,
                remediation: rule.replacement,
                affectedDeviceSerials: nil,
                affectedDeviceNames: names
            )
        }
    }

    /// Profiles whose software-update settings stop working on macOS 27.
    static func legacySoftwareUpdateProfiles(in profiles: [ScannedProfile]) -> [ScannedProfile] {
        let suRules = rules.filter { $0.id == "os27-softwareupdate-payload" || $0.id == "os27-softwareupdate-deferrals" }
        return profiles.filter { p in suRules.contains { $0.matches(p) } }
    }
}
