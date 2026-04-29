//
//  KeychainHelper.swift
//  Fit33
//
//  Secure storage for sensitive tokens using the iOS Keychain
//

import Foundation
import Security

struct KeychainHelper {
    
    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        
        var addQuery = query
        addQuery[kSecValueData as String] = data
        // `kSecAttrAccessibleAfterFirstUnlock` (vs. the default `WhenUnlocked`)
        // lets `BGTask` paths — `BackgroundChallengeSyncService`, silent-push
        // wakes — read OAuth tokens (WHOOP, Oura, Strava, Fitbit, Supabase
        // session) while the screen is locked. Without it, the wearable
        // singletons (`WhoopService`, `OuraService`) initialize during a
        // locked-device wake with `accessToken == nil` → `isConnected = false`,
        // and that stuck state persists for the whole process. Result:
        // dashboard widgets silently disappear on the next user-visible
        // launch even though tokens are valid. Tokens still require device
        // unlock at least once per boot, which matches our threat model.
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(addQuery as CFDictionary, nil)
    }
    
    static func load(key: String) -> String? {
        loadWithStatus(key: key).value
    }

    /// Diagnostic variant — surfaces the raw `OSStatus` from
    /// `SecItemCopyMatching` so callers can distinguish:
    /// • `errSecSuccess` (0) — value present
    /// • `errSecItemNotFound` (-25300) — really wiped (uninstall, explicit delete)
    /// • `errSecInteractionNotAllowed` (-25308) — keychain locked (BGTask wake on locked device)
    /// • `errSecAuthFailed` / others — provisioning / entitlements problem
    /// Used by `WhoopService` + `OuraService` to log structured connect/disconnect
    /// audit entries so we can tell, after the fact, exactly why an OAuth token
    /// "disappeared" between sessions (real wipe vs transient lock vs entitlement
    /// glitch).
    static func loadWithStatus(key: String) -> (value: String?, status: OSStatus) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data {
            return (String(data: data, encoding: .utf8), status)
        }
        return (nil, status)
    }

    /// Human-readable label for an `OSStatus` returned by `SecItemCopyMatching`.
    /// Used in OAuth audit logs — keeps the persisted breadcrumb string short
    /// and grep-friendly.
    static func statusLabel(_ status: OSStatus) -> String {
        switch status {
        case errSecSuccess: return "ok(\(status))"
        case errSecItemNotFound: return "notFound(\(status))"
        case errSecInteractionNotAllowed: return "locked(\(status))"
        case errSecAuthFailed: return "authFailed(\(status))"
        case errSecMissingEntitlement: return "missingEntitlement(\(status))"
        case errSecParam: return "badParam(\(status))"
        default: return "other(\(status))"
        }
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
