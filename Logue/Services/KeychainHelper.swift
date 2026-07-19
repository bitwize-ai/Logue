import Foundation
import os.log
import Security

/// Thin wrapper around the macOS Keychain for storing small secrets (machine ID, license token).
///
/// Uses the **login keychain** (standard macOS Keychain). The data protection keychain
/// (`kSecUseDataProtectionKeychain`) requires a provisioning profile (App ID) which is not
/// available for Developer ID–signed apps distributed outside the App Store. The login keychain
/// works reliably in both sandboxed and non-sandboxed builds.
///
/// With a stable code signing identity (Developer ID for release, Mac Development for Xcode),
/// Keychain items are accessible across updates without password prompts. Ad-hoc signed builds
/// (`CODE_SIGN_IDENTITY="-"`) may trigger prompts — use `make clean` to clear stale items.
enum KeychainHelper {
    private static let logger = Logger(subsystem: AppConstants.bundleID, category: "KeychainHelper")

    enum KeychainError: Error {
        case duplicateItem
        case itemNotFound
        case unexpectedStatus(OSStatus)
        case invalidData
    }

    // MARK: - Public API

    /// Saves a UTF-8 string to the Keychain under the given key.
    @discardableResult
    static func save(key: String, value: String) throws -> Bool {
        guard let data = value.data(using: .utf8) else { throw KeychainError.invalidData }
        return try save(key: key, data: data)
    }

    /// Reads a UTF-8 string from the Keychain.
    static func read(key: String) throws -> String? {
        guard let data = try readData(key: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Deletes the item stored under the given key.
    @discardableResult
    static func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppConstants.bundleID,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)

        let succeeded = status == errSecSuccess || status == errSecItemNotFound
        if !succeeded {
            logger.error("Keychain delete failed for '\(key, privacy: .public)': \(status)")
        }
        return succeeded
    }

    /// Saves raw Data to the Keychain under the given key.
    /// - Parameter accessibility: Keychain accessibility level. Defaults to `kSecAttrAccessibleAfterFirstUnlock`.
    ///   Use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` for encryption keys.
    @discardableResult
    static func saveData(key: String, data: Data, accessibility: CFString = kSecAttrAccessibleAfterFirstUnlock) throws -> Bool {
        try save(key: key, data: data, accessibility: accessibility)
    }

    /// Reads raw Data from the Keychain.
    static func loadData(key: String) throws -> Data? {
        try readData(key: key)
    }

    // MARK: - Internal

    private static func save(key: String, data: Data, accessibility: CFString = kSecAttrAccessibleAfterFirstUnlock) throws -> Bool {
        let searchQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppConstants.bundleID,
            kSecAttrAccount as String: key,
        ]

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppConstants.bundleID,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessibility,
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)

        switch status {
        case errSecSuccess:
            return true
        case errSecDuplicateItem:
            // Update existing item using search-only query.
            let attrs: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(searchQuery as CFDictionary, attrs as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(updateStatus)
            }
            return true
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private static func readData(key: String) throws -> Data? {
        // kSecUseAuthenticationUIFail prevents macOS from showing a password dialog when
        // the item's ACL doesn't match the current code signature (common after debug
        // rebuilds or app updates). Instead it returns errSecInteractionNotAllowed, which
        // we handle below by deleting the stale item so it can be recreated on next save.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppConstants.bundleID,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            return data
        case errSecItemNotFound:
            return nil
        case errSecAuthFailed, errSecInteractionNotAllowed, -25293:
            // ACL mismatch — the item was created by a different code signature
            // (common after debug rebuilds with ad-hoc signing). Delete the stale
            // item so the caller can recreate it with the current app's ACL.
            logger.info("Keychain ACL mismatch for '\(key, privacy: .public)' — deleting stale item")
            delete(key: key)
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
