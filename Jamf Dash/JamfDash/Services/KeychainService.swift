import Foundation
import Security
import OSLog

enum KeychainError: Error, Sendable {
    case notFound
    case malformed
    case osStatus(OSStatus)
}

extension KeychainError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notFound:          return "No credentials found. Add them in Settings → Connection."
        case .malformed:         return "Stored credential data is malformed. Please re-enter your credentials."
        case .osStatus(let s):   return "Keychain error (status \(s))."
        }
    }
}

/// App-level credential storage and reader of jamf-cli's own keychain entries.
actor KeychainService {
    private let service = "com.jamfdash.credentials"
    private let account = "jamfpro"
    private let logger = Logger(subsystem: "com.jamfdash", category: "KeychainService")

    // MARK: - App credentials (legacy)

    func save(_ credentials: JamfCredentials) throws {
        let payload = try JSONEncoder().encode(KeychainPayload(credentials))
        let query: [String: Any] = baseQuery()
        let attrs: [String: Any] = [kSecValueData as String: payload]
        let updateStatus = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = payload
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.osStatus(addStatus) }
            return
        }
        throw KeychainError.osStatus(updateStatus)
    }

    func load() throws -> JamfCredentials {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            if status == errSecItemNotFound { throw KeychainError.notFound }
            throw KeychainError.osStatus(status)
        }
        guard let data = result as? Data else { throw KeychainError.malformed }
        let payload = try JSONDecoder().decode(KeychainPayload.self, from: data)
        return try payload.toCredentials()
    }

    func hasCredentials() -> Bool { (try? load()) != nil }

    func delete() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.osStatus(status)
        }
    }

    // MARK: - jamf-cli profile discovery

    /// Reads profile names from jamf-cli's own keychain entries.
    /// jamf-cli stores items with service="jamf-cli" and accounts like
    /// "Profile Name/client-id" and "Profile Name/client-secret".
    func jamfCLIProfiles() -> [String] {
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      "jamf-cli",
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String:       kSecMatchLimitAll
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [] }

        var profiles = Set<String>()
        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String else { continue }
            for suffix in ["/client-id", "/client-secret", "/api-key", "/token"] {
                if account.hasSuffix(suffix) {
                    profiles.insert(String(account.dropLast(suffix.count)))
                    break
                }
            }
        }
        return profiles.sorted()
    }

    // MARK: - Private

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

// MARK: - Storage payload

private struct KeychainPayload: Codable {
    let serverURL: String
    let clientID: String
    let clientSecret: String

    init(_ c: JamfCredentials) {
        serverURL    = c.serverURL.absoluteString
        clientID     = c.clientID
        clientSecret = c.clientSecret
    }

    func toCredentials() throws -> JamfCredentials {
        guard let url = URL(string: serverURL) else { throw KeychainError.malformed }
        return JamfCredentials(serverURL: url, clientID: clientID, clientSecret: clientSecret)
    }
}
