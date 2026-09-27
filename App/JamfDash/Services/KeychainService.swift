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
    private let logger = Logger(subsystem: "com.jamfdash", category: "KeychainService")

    // MARK: - Jamf Security Cloud credentials

    private let jscService = "com.jamfdash.security-cloud"
    private let jscAccount = "jsc"

    func saveJSC(_ credentials: JSCCredentials) throws {
        let payload = try JSONEncoder().encode(credentials)
        let query: [String: Any] = jscBaseQuery()
        let attrs: [String: Any] = [
            kSecValueData as String:      payload,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String]      = payload
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.osStatus(addStatus) }
            return
        }
        throw KeychainError.osStatus(updateStatus)
    }

    func loadJSC() throws -> JSCCredentials {
        var query = jscBaseQuery()
        query[kSecReturnData as String]  = true
        query[kSecMatchLimit as String]  = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            if status == errSecItemNotFound { throw KeychainError.notFound }
            throw KeychainError.osStatus(status)
        }
        guard let data = result as? Data else { throw KeychainError.malformed }
        return try JSONDecoder().decode(JSCCredentials.self, from: data)
    }

    func deleteJSC() throws {
        let status = SecItemDelete(jscBaseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.osStatus(status)
        }
    }

    func hasJSCCredentials() -> Bool { (try? loadJSC()) != nil }

    private func jscBaseQuery() -> [String: Any] {
        [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: jscService,
            kSecAttrAccount as String: jscAccount
        ]
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

}
