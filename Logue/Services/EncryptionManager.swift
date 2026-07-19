import CryptoKit
import Foundation
import os

/// Provides AES-GCM encryption at rest for sensitive user data (meetings, documents, etc.).
///
/// Key management: A 256-bit symmetric key is generated once and stored in the macOS Keychain
/// under `kSecAttrAccessibleAfterFirstUnlock`. The key never leaves the Keychain in plaintext
/// outside of CryptoKit operations.
///
/// File format: `[12-byte nonce] [ciphertext] [16-byte tag]` — the standard AES-GCM sealed box.
enum EncryptionManager {
    private static let logger = Logger(subsystem: AppConstants.bundleID, category: "Encryption")
    private static let keychainKey = "encryption_key_v1"
    /// Encoder/decoder created per-call to avoid thread-safety issues with shared instances
    private static func makeEncoder() -> JSONEncoder {
        JSONEncoder()
    }

    private static func makeDecoder() -> JSONDecoder {
        JSONDecoder()
    }

    // MARK: - Public API

    /// Encrypts raw data using AES-256-GCM with the app's Keychain-stored key.
    static func encrypt(_ plaintext: Data) throws -> Data {
        let key = try getOrCreateKey()
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else {
            throw EncryptionError.sealFailed
        }
        return combined
    }

    /// Decrypts AES-256-GCM encrypted data using the app's Keychain-stored key.
    static func decrypt(_ ciphertext: Data) throws -> Data {
        let key = try getOrCreateKey()
        let box = try AES.GCM.SealedBox(combined: ciphertext)
        return try AES.GCM.open(box, using: key)
    }

    /// Encrypts a `Codable` value to Data suitable for writing to disk.
    static func encryptCodable(_ value: some Encodable) throws -> Data {
        let json = try makeEncoder().encode(value)
        return try encrypt(json)
    }

    /// Decrypts Data from disk back into a `Codable` value.
    static func decryptCodable<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let json = try decrypt(data)
        return try makeDecoder().decode(type, from: json)
    }

    /// S7: Keychain key for tracking whether encryption migration has completed
    /// (stored in Keychain instead of UserDefaults to prevent reset attacks).
    private static let migrationKeychainKey = "encryption_migration_complete_v1"

    /// Cached migration-complete flag — once `true`, never re-read from Keychain.
    /// Thread-safe: stores decrypt concurrently from Task.detached contexts.
    private static let _migrationCompleteCached = OSAllocatedUnfairLock<Bool?>(initialState: nil)

    /// Checks whether encryption migration is complete (stored in Keychain, cached in memory).
    private static var isMigrationComplete: Bool {
        if let cached = _migrationCompleteCached.withLock({ $0 }) {
            return cached
        }
        let result = (try? KeychainHelper.read(key: migrationKeychainKey)) == "true"
        if result {
            // Only cache `true` — `false` can transition to `true` later in this session
            _migrationCompleteCached.withLock { $0 = true }
        }
        return result
    }

    /// Marks encryption migration as complete (stored in Keychain).
    private static func markMigrationComplete() {
        try? KeychainHelper.save(key: migrationKeychainKey, value: "true")
        // Also clear legacy UserDefaults flag if present
        UserDefaults.standard.removeObject(forKey: "encryption_migration_complete_v1")
        _migrationCompleteCached.withLock { $0 = true }
    }

    /// Attempts to decrypt data; if it fails (e.g. unencrypted legacy file), falls back to
    /// plain JSON decoding. This enables transparent migration from unencrypted to encrypted storage.
    /// Once migration is complete (all stores have been re-saved encrypted), fallback is disabled
    /// to prevent an attacker from replacing encrypted files with crafted unencrypted JSON.
    /// Tracks how many stores have confirmed encrypted data. When all 4 stores
    /// (documents, meetings, spaces, scheduled tasks) have decrypted successfully,
    /// we mark migration complete so the plaintext fallback is permanently disabled.
    private static let requiredStoreCount = 4
    /// Thread-safe counter — stores decrypt concurrently from Task.detached contexts.
    private static let _decryptCounter = OSAllocatedUnfairLock(initialState: 0)

    static func decryptCodableWithFallback<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        // Try encrypted first
        if let decrypted = try? decryptCodable(type, from: data) {
            // Track successful encrypted decrypts toward migration completion
            if !isMigrationComplete {
                let count = _decryptCounter.withLock { state -> Int in
                    state += 1
                    return state
                }
                if count >= requiredStoreCount {
                    markMigrationComplete()
                }
            }
            return decrypted
        }
        // Only allow fallback if encryption migration hasn't completed yet
        guard !isMigrationComplete else {
            logger.error("Encrypted data could not be decrypted and migration is complete — refusing unencrypted fallback")
            throw EncryptionError.sealFailed
        }
        // Time-limit the migration window to 7 days to reduce attack surface
        let migrationStartKey = "encryption_migration_start_v1"
        if let startString = try? KeychainHelper.read(key: migrationStartKey),
           let startTime = TimeInterval(startString),
           Date().timeIntervalSince1970 - startTime > 7 * 24 * 3600
        {
            logger.error("Migration window expired (>7 days) — refusing unencrypted fallback")
            markMigrationComplete()
            throw EncryptionError.sealFailed
        }
        // Record migration start time on first fallback
        if (try? KeychainHelper.read(key: migrationStartKey)) == nil {
            try? KeychainHelper.save(key: migrationStartKey, value: "\(Date().timeIntervalSince1970)")
        }
        // Fallback: legacy unencrypted JSON (one-time migration)
        logger.info("Falling back to unencrypted JSON decode (migration pending)")
        return try makeDecoder().decode(type, from: data)
    }

    /// Explicitly mark migration complete. Call from the app delegate after all stores
    /// have confirmed their initial save cycle in encrypted format.
    static func confirmMigrationComplete() {
        if !isMigrationComplete {
            markMigrationComplete()
        }
    }

    // MARK: - Key Management

    /// In-memory cache for the encryption key — loaded once per app session.
    /// Thread-safe: multiple stores may decrypt concurrently from Task.detached contexts.
    private static let _cachedKey = OSAllocatedUnfairLock<SymmetricKey?>(initialState: nil)

    private static func getOrCreateKey() throws -> SymmetricKey {
        // Return cached key if available (avoids repeated Keychain reads during startup)
        if let cached = _cachedKey.withLock({ $0 }) {
            return cached
        }

        // Try to load existing key from Keychain
        if let existingData = try KeychainHelper.loadData(key: keychainKey) {
            let key = SymmetricKey(data: existingData)
            _cachedKey.withLock { $0 = key }
            return key
        }

        // Generate a new 256-bit key with strict accessibility (only when unlocked, this device only)
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        try KeychainHelper.saveData(key: keychainKey, data: keyData, accessibility: kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
        _cachedKey.withLock { $0 = newKey }
        logger.info("Generated and stored new encryption key")
        return newKey
    }

    // MARK: - Errors

    enum EncryptionError: LocalizedError {
        case sealFailed

        var errorDescription: String? {
            switch self {
            case .sealFailed: "Failed to create AES-GCM sealed box"
            }
        }
    }
}
