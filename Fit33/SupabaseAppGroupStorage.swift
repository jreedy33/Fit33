//
//  SupabaseAppGroupStorage.swift
//  Fit33
//
//  Custom `AuthLocalStorage` that parks the supabase-swift session JWT in
//  an App Group-shared UserDefaults suite so multiple processes (main
//  app, widget extension, watchOS companion) can construct their own
//  SupabaseClient against the same authenticated session.
//
//  Realtime Widget Server Pull — Phase 1 (2026-04-26).
//
//  Companion file: `RunningActivityWidget/SupabaseAppGroupStorage.swift`
//  is a verbatim copy that ships into the widget extension target.
//  When you change one, change the other (matches the existing
//  `ActiveChallengeWidgetSnapshot` / `WidgetActiveChallenge` duplication
//  pattern in this repo).
//
//  Security trade-off (see INFRA_SECURITY_AGENT.md invariant 17b):
//  The default supabase-swift `KeychainLocalStorage` writes to the
//  iOS Keychain at service `supabase.gotrue.swift`, which is
//  per-app-group-id by default and NOT readable by extensions without
//  a Keychain Access Group entitlement. Moving to App Group
//  UserDefaults sacrifices Keychain encryption-at-rest for trivial
//  cross-process readability — an acceptable trade because (a) the
//  App Group container is sandboxed to Fit33's processes, and (b) the
//  JWT only authorizes RLS-bounded reads/writes for the signed-in user.
//

import Foundation
import Auth

/// `AuthLocalStorage` implementation that reads/writes session blobs
/// from `UserDefaults(suiteName: "group.com.fit33.app")`. Single shared
/// instance — the widget and watchOS targets each ship their own copy
/// pointing at the same App Group identifier.
public final class SupabaseAppGroupStorage: AuthLocalStorage, @unchecked Sendable {
    /// App Group identifier — must match the entitlement files of every
    /// target that constructs a SupabaseClient (main app, widget
    /// extension, watch companion).
    public static let appGroupID = "group.com.fit33.app"

    /// The custom `storageKey` we hand to `AuthClient.Configuration`.
    /// Distinct from the SDK default (`supabase.auth.token`) so we can
    /// run the one-time keychain → app-group migration unambiguously.
    public static let sharedStorageKey = "fit33.supabase.session.v1"

    /// Migration flag — flipped after the first successful keychain read
    /// so we don't pay the keychain-query cost on every cold start.
    private static let migrationDoneKey = "fit33.supabase.session.migrationDone.v1"

    public static let shared = SupabaseAppGroupStorage()

    private let defaults: UserDefaults
    private let lock = NSLock()

    public init() {
        guard let suite = UserDefaults(suiteName: SupabaseAppGroupStorage.appGroupID) else {
            preconditionFailure("Failed to open App Group UserDefaults suite \(SupabaseAppGroupStorage.appGroupID) — verify the App Group entitlement is enabled on this target.")
        }
        self.defaults = suite
    }

    // MARK: - AuthLocalStorage

    public func store(key: String, value: Data) throws {
        lock.lock(); defer { lock.unlock() }
        defaults.set(value, forKey: appGroupKey(for: key))
    }

    public func retrieve(key: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return defaults.data(forKey: appGroupKey(for: key))
    }

    public func remove(key: String) throws {
        lock.lock(); defer { lock.unlock() }
        defaults.removeObject(forKey: appGroupKey(for: key))
    }

    /// Namespaces all session keys under a single prefix so we don't
    /// collide with widget snapshot keys or any other App Group payload.
    private func appGroupKey(for key: String) -> String {
        "supabase.session.\(key)"
    }

    // MARK: - One-time keychain → App Group migration

    /// Reads the existing session blob out of the default
    /// supabase-swift Keychain item (service `supabase.gotrue.swift`,
    /// key `supabase.auth.token`) and seeds it into the App Group on
    /// first launch after upgrading to this build. Idempotent — flips a
    /// flag in App Group UserDefaults so subsequent calls short-circuit.
    public func migrateFromKeychainIfNeeded() {
        lock.lock(); defer { lock.unlock() }

        if defaults.bool(forKey: SupabaseAppGroupStorage.migrationDoneKey) { return }

        // The supabase-swift SDK historically stored the session under
        // `supabase.auth.token` (current) and `supabase.session` (legacy
        // pre-2.x). Try both so we capture every install path.
        let candidateKeys = ["supabase.auth.token", "supabase.session"]
        var migrated = false

        for sourceKey in candidateKeys {
            guard let data = readKeychainData(service: "supabase.gotrue.swift", account: sourceKey) else { continue }
            let destinationKey = appGroupKey(for: SupabaseAppGroupStorage.sharedStorageKey)
            if defaults.data(forKey: destinationKey) == nil {
                defaults.set(data, forKey: destinationKey)
                migrated = true
            }
        }

        // Flip the flag whether or not we found a session — a logged-out
        // user simply has nothing to migrate, and we don't want to pay
        // the Keychain query cost on every launch.
        defaults.set(true, forKey: SupabaseAppGroupStorage.migrationDoneKey)

        if migrated {
            // Use NSLog rather than AppLogger so this still surfaces
            // when the migration runs from inside the widget extension
            // (where Fit33's logger isn't linked).
            NSLog("[SupabaseAppGroupStorage] Migrated session JWT from default Keychain to App Group container")
        }
    }

    // MARK: - Raw Keychain reader

    private func readKeychainData(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return data
    }
}
