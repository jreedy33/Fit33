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
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
