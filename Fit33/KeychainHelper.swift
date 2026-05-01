//
//  KeychainHelper.swift
//  Fit33
//
//  Secure storage for sensitive tokens using the iOS Keychain.
//
//  2026-04-29 — bug-intel `af583196` ("WHOOP refresh token wiped"):
//  the original `save(_:value:)` discarded the `OSStatus` from
//  `SecItemDelete` + `SecItemAdd`. If the keychain was momentarily
//  unreadable (BGTask wake on a locked device, post-restore lock
//  window, provisioning glitch), the SecItemAdd silently failed and
//  callers believed the token had been written. The very next refresh
//  re-read the keychain, found the rotated refresh_token gone, and
//  hit the "rt_wiped_keychain_readable" disconnect branch — auto-
//  signing the user out of WHOOP "almost every login". Same race
//  applies to Oura / Strava / Fitbit since they share this helper.
//
//  Fix: every write now returns its `OSStatus`, logs failures, and a
//  `saveAndVerify` variant performs an immediate read-back so OAuth
//  refresh paths can detect a silent write failure and abort BEFORE
//  declaring success / persisting `tokenExpiresAt`. Callers that don't
//  care (UserDefaults migration, optional bookkeeping) keep using the
//  `@discardableResult` shape and pay nothing.
//

import Foundation
import Security

struct KeychainHelper {

    /// Persists `value` under `key`. Returns the final `OSStatus` from
    /// the underlying `SecItemUpdate` / `SecItemAdd` (`errSecSuccess`
    /// on success). Failures are logged at `.warning` level so the
    /// diagnostic breadcrumb survives even when callers `_ = save(...)`.
    ///
    /// 2026-04-29 — bug-intel "WHOOP keeps logging me out (no `disconnect()`
    /// log line, no HTTP 4xx)": the previous implementation was
    /// `SecItemDelete` → `SecItemAdd` (NOT atomic). On a BGTask wake
    /// that hit a transient `errSecInteractionNotAllowed`, the delete
    /// succeeded and the add failed — wiping the entry permanently.
    /// The very next cold launch saw `accessToken == nil` →
    /// `isConnected = false` and the dashboard WHOOP/Oura card vanished
    /// even though `user_profiles.is_whoop_connected = true` in the cloud
    /// (the additive sync guard refuses to mirror the local `false`, but
    /// the in-app card reads local state). Now: `SecItemUpdate` first
    /// (atomic, leaves the prior value intact on failure) and only fall
    /// back to delete+add when the entry doesn't yet exist. The "delete
    /// window" that could lose the entry no longer exists for the
    /// rotation path; brand-new writes still take a single `SecItemAdd`.
    @discardableResult
    static func save(key: String, value: String) -> OSStatus {
        guard let data = value.data(using: .utf8) else {
            AppLogger.warning(
                "[Keychain] save(\(key)) skipped — value not UTF-8 encodable",
                category: .auth
            )
            return errSecParam
        }

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]

        // Atomic update path: if the item already exists, replace its
        // value in-place. SecItemUpdate is atomic — on failure the prior
        // value remains intact (no "delete window"). This is the path
        // taken on every token rotation, which is where the silent loss
        // was occurring.
        let updateAttrs: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecSuccess { return updateStatus }

        // Only fall through to the add-new-entry path when the item
        // genuinely doesn't exist. Any other status (locked, etc.) is
        // logged loudly and returned WITHOUT touching the existing
        // entry — same defense as before.
        if updateStatus != errSecItemNotFound {
            AppLogger.warning(
                "[Keychain] save(\(key)) update \(statusLabel(updateStatus)) — leaving prior value untouched",
                category: .auth
            )
            return updateStatus
        }

        var addQuery = baseQuery
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

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            // Race: between SecItemUpdate's notFound and SecItemAdd, another
            // caller landed an entry. Retry the update once — atomic again.
            let retryStatus = SecItemUpdate(baseQuery as CFDictionary, updateAttrs as CFDictionary)
            if retryStatus != errSecSuccess {
                AppLogger.warning(
                    "[Keychain] save(\(key)) duplicate then update \(statusLabel(retryStatus))",
                    category: .auth
                )
            }
            return retryStatus
        }
        if addStatus != errSecSuccess {
            // Loud — silent SecItemAdd failures were the root cause of the
            // "WHOOP keeps logging me out" pain point. Surfacing them to
            // bug-intel pre-classifier (no fingerprint pollution because
            // the message embeds the OSStatus label) lets us correlate
            // OAuth-token-wipe complaints to the real underlying cause.
            AppLogger.warning(
                "[Keychain] save(\(key)) FAILED — SecItemAdd \(statusLabel(addStatus))",
                category: .auth
            )
        }
        return addStatus
    }

    /// Persists `value` under `key`, then immediately reads it back. Returns
    /// `true` ONLY when the round-trip confirms the new value is in the
    /// keychain. Used by OAuth refresh paths to abort BEFORE marking the
    /// token rotation as successful — without this, a silent SecItemAdd
    /// failure (BGTask wake, provisioning glitch) leaves the in-memory
    /// `accessToken` looking valid while the keychain has the old / no
    /// rotated refresh_token, guaranteeing the next refresh disconnects
    /// the user. The verify step is cheap (one SecItemCopyMatching) and
    /// runs at most a handful of times per session.
    static func saveAndVerify(key: String, value: String) -> Bool {
        let status = save(key: key, value: value)
        guard status == errSecSuccess else { return false }
        let readBack = load(key: key)
        let verified = readBack == value
        if !verified {
            AppLogger.warning(
                "[Keychain] saveAndVerify(\(key)) read-back mismatch — write reported \(statusLabel(status)) but readback differed (got \(readBack == nil ? "nil" : "len=\(readBack?.count ?? 0)"))",
                category: .auth
            )
        }
        return verified
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
        case errSecDuplicateItem: return "duplicate(\(status))"
        case errSecNotAvailable: return "notAvailable(\(status))"
        default: return "other(\(status))"
        }
    }

    @discardableResult
    static func delete(key: String) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            AppLogger.warning(
                "[Keychain] delete(\(key)) \(statusLabel(status))",
                category: .auth
            )
        }
        return status
    }
}
