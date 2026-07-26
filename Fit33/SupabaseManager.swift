import Foundation
import Supabase
import SwiftUI
import Auth
import CoreData
import Combine
import CryptoKit

// MARK: - Supabase Manager
// This class handles all communication with your cloud database

class SupabaseManager: ObservableObject {
    static let shared = SupabaseManager()
    
    // MARK: - Supabase Credentials
    // Credentials are loaded from Secrets.swift (gitignored) via AppConfig.
    // See Secrets.template.swift for the schema and SECURITY_CHECKLIST.md for the RLS audit.
    private let supabaseURL = AppConfig.Supabase.url
    private let supabaseKey = AppConfig.Supabase.anonKey
    
    // Non-optional to avoid implicit-unwrap crashes. A bad AppConfig.Supabase.url
    // is a fatal misconfiguration, not a recoverable runtime path, so we
    // preconditionFailure in init rather than let every call site crash later.
    internal let client: SupabaseClient
    
    // MARK: - Cached Date Formatters (Performance Optimization)
    /// ISO8601DateFormatter is expensive to create - reuse these instances.
    /// `iso8601Formatter` = withInternetDateTime (no fractional seconds).
    /// `iso8601Fractional` = withInternetDateTime + fractional seconds (for Postgres
    ///   `timestamptz` values serialized with microsecond precision).
    /// `ymdFormatter` = `yyyy-MM-dd` local day formatter.
    private let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    private let iso8601Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let ymdFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    
    /// Convert Date to ISO8601 string for database storage
    @inline(__always)
    private func dateToISO(_ date: Date) -> String {
        iso8601Formatter.string(from: date)
    }
    
    /// Convert ISO8601 string to Date (nil if invalid)
    @inline(__always)
    private func isoToDate(_ string: String) -> Date? {
        ISO8601Parser.parse(string)
    }
    
    /// Convert birthday from display format (MM/DD/YYYY or DD/MM/YYYY) to ISO format (YYYY-MM-DD)
    /// Handles both US (MM/DD/YYYY) and international (DD/MM/YYYY) formats
    /// Returns nil if the input is nil, empty, or invalid
    /// If already in ISO format (YYYY-MM-DD), returns as-is
    private func birthdayToISO(_ birthday: String?) -> String? {
        guard let birthday = birthday, !birthday.isEmpty else { return nil }
        
        // If already in ISO format (YYYY-MM-DD), return as-is
        if birthday.contains("-") && birthday.count == 10 {
            return birthday
        }
        
        // Parse from slash format (MM/DD/YYYY or DD/MM/YYYY)
        let parts = birthday.split(separator: "/")
        guard parts.count == 3 else { return nil }
        
        guard let part1 = Int(parts[0]),
              let part2 = Int(parts[1]),
              let year = Int(parts[2]) else { return nil }
        
        let month: Int
        let day: Int
        
        // Determine format based on values
        // If first part > 12, it must be a day (DD/MM/YYYY format)
        // If second part > 12, it must be a day (MM/DD/YYYY format)
        // Otherwise, use locale preference
        if part1 > 12 {
            // First part is day (DD/MM/YYYY - international format)
            day = part1
            month = part2
        } else if part2 > 12 {
            // Second part is day (MM/DD/YYYY - US format)
            month = part1
            day = part2
        } else {
            // Ambiguous - check device locale
            let usesMonthFirst = Locale.current.identifier.hasPrefix("en_US") ||
                                 Locale.current.identifier.hasPrefix("en_PH") ||
                                 Locale.current.region?.identifier == "US"
            if usesMonthFirst {
                month = part1
                day = part2
            } else {
                day = part1
                month = part2
            }
        }
        
        // Validate and format
        guard month >= 1 && month <= 12,
              day >= 1 && day <= 31,
              year >= 1900 && year <= 2100 else { return nil }
        
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
    
    // Public getter for client (needed by FoodDatabaseService)
    var supabaseClient: SupabaseClient {
        return client
    }
    
    // Q2-82 invariant (Sprint 8): These `@Published` properties are written
    // from many async contexts (auth listener, sign-in/out, session recovery).
    // EVERY assignment MUST be wrapped in `await MainActor.run { … }`. The class
    // is intentionally NOT `@MainActor`-annotated because it performs heavy
    // network work that should NOT serialize onto the main thread. Audit this
    // invariant before adding any new `@Published` vars.
    @Published var currentUser: Auth.User?
    @Published var isAuthenticated = false
    @Published var isLoading = false
    
    private var authListenerTask: Task<Void, Never>?

    /// Single-flight guard for `checkAuthOnly`. Fit33App now fires the auth
    /// check from `init()` so it begins before SwiftUI commits the first
    /// frame, AND the existing `WindowGroup.task` still calls `checkAuthOnly`
    /// for backwards compat. Without this gate the two callers would each
    /// race their own `client.auth.currentSession` + `MainActor.run` chain,
    /// double-publishing `isAuthenticated`. Pattern mirrors QP invariant
    /// #24c-foreground (`HealthDataService.inFlightSyncTask`).
    private var inFlightAuthCheckTask: Task<Void, Never>?
    
    private init() {
        guard let url = URL(string: supabaseURL) else {
            preconditionFailure("Invalid Supabase URL in AppConfig — check Secrets.swift configuration")
        }
        precondition(!supabaseKey.isEmpty, "Missing Supabase anon key in AppConfig — check Secrets.swift")

        // Realtime Widget Server Pull (Phase 1, 2026-04-26):
        // The Supabase session JWT lives in an App Group-shared UserDefaults
        // suite (`group.com.fit33.app`) so the widget extension AND the
        // watchOS companion can construct their own SupabaseClient and
        // pull challenge progress directly from Postgres — independent of
        // the iPhone foreground app's state. The custom storage performs
        // a one-time migration from the previous default Keychain at
        // service `supabase.gotrue.swift` (where supabase-swift's
        // `KeychainLocalStorage()` parked the session) so existing users
        // don't get logged out on upgrade. See INFRA_SECURITY_AGENT.md
        // invariant 17b for the security trade-off rationale.
        let sharedStorage = SupabaseAppGroupStorage.shared
        sharedStorage.migrateFromKeychainIfNeeded()

        self.client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: supabaseKey,
            options: .init(
                auth: .init(
                    storage: sharedStorage,
                    redirectToURL: URL(string: "fit33://"),
                    storageKey: SupabaseAppGroupStorage.sharedStorageKey,
                    emitLocalSessionAsInitialSession: true
                )
            )
        )

        // NOTE: Auth check is performed by Fit33App.swift's .task modifier
        // to avoid duplicate/racing auth+sync calls during startup.

        startAuthStateListener()
    }
    
    /// Listens for Supabase auth state changes (token refresh, sign-out, etc.)
    /// and keeps isAuthenticated in sync automatically.
    private func startAuthStateListener() {
        authListenerTask = Task { [weak self] in
            guard let self else { return }
            for await (event, session) in self.client.auth.authStateChanges {
                switch event {
                case .signedIn, .tokenRefreshed:
                    if let user = session?.user {
                        await MainActor.run {
                            self.currentUser = user
                            self.isAuthenticated = true
                        }
                        AppLogger.debug("[AUTH LISTENER] Session active (\(event))", category: .auth)
                    }
                case .signedOut:
                    await MainActor.run {
                        self.currentUser = nil
                        self.isAuthenticated = false
                    }
                    AppLogger.debug("[AUTH LISTENER] Signed out", category: .auth)
                default:
                    break
                }
            }
        }
    }
    
    /// Attempts to recover an expired session. Call from foreground handler
    /// when isAuthenticated is false so the app self-heals mid-session.
    func recoverSessionIfNeeded() async {
        guard !isAuthenticated else { return }
        
        AppLogger.info("[AUTH] Attempting session recovery...", category: .auth)
        do {
            let session = try await client.auth.refreshSession()
            await MainActor.run {
                currentUser = session.user
                isAuthenticated = true
            }
            AppLogger.info("[AUTH] Session recovered for \(session.user.email ?? "unknown")", category: .auth)
        } catch {
            AppLogger.debug("[AUTH] Session recovery failed: \(error.localizedDescription)", category: .auth)
        }
    }

    /// Cluster D gate: wait until `isAuthenticated == true` or the timeout
    /// elapses. Returns `true` if auth became ready, `false` otherwise.
    ///
    /// Call this from fan-out orchestrators (dashboard hydrate, foreground
    /// refresh) BEFORE scattering 14+ parallel RPCs. Previously each RPC
    /// independently raced the session recovery, producing waves of 401s
    /// that landed as bug_intelligence_fingerprints. The single gate
    /// collapses that into one recovery attempt + then serial fan-out.
    ///
    /// Safe to call when already authenticated — returns immediately.
    /// Attempts an explicit `recoverSessionIfNeeded()` once at start so a
    /// stale JWT doesn't block on a publisher that will never fire.
    func waitForFreshSession(timeout: TimeInterval = 5.0) async -> Bool {
        let startedAt = Date()
        let signpostState = PerformanceSignposts.begin(.authWaitForFreshSession)
        defer { PerformanceSignposts.end(signpostState, slowThresholdMs: Int(timeout * 1000) + 500) }

        if isAuthenticated { return true }

        // ⚡️ Cold-start speedup Phase 2.8 (2026-04-25, revised):
        // BEFORE awaiting the in-flight `checkAuthOnly` task, fast-path off
        // the SDK's cached session. The cached session is updated
        // synchronously by `client.auth.currentSession` and lives outside
        // the @Published publish path — so even when MainActor is jammed
        // by 3s of synchronous singleton inits during cold start, we can
        // unblock the dashboard's 14-call social fan-out instantly.
        // PostgREST will 401 on a truly-stale token; the SDK auto-refreshes.
        // The @Published `isAuthenticated = true` will land later (when
        // main settles), backfilling SwiftUI bindings.
        if let cached = client.auth.currentSession, !cached.isExpired {
            // Schedule a low-priority main publish so view bindings catch up
            // when main is free, but don't wait for it here.
            Task { @MainActor [weak self] in
                guard let self, !self.isAuthenticated else { return }
                self.currentUser = cached.user
                self.isAuthenticated = true
            }
            return true
        }

        // No cached session — fall back to coalescing on the in-flight check.
        if let inFlight = inFlightAuthCheckTask {
            await inFlight.value
            if isAuthenticated { return true }
        }

        await recoverSessionIfNeeded()
        if isAuthenticated { return true }

        // Race publisher-first vs timeout. Never leak the Combine sink:
        // both sides cancel each other via the shared lock.
        let ready: Bool = await withCheckedContinuation { continuation in
            let lock = NSLock()
            var resumed = false
            var cancellable: AnyCancellable?

            let sleepTask = Task { [timeout] in
                try? await Task.sleep(for: .seconds(timeout))
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                cancellable?.cancel()
                continuation.resume(returning: false)
            }

            cancellable = $isAuthenticated
                .first(where: { $0 })
                .sink { _ in
                    lock.lock()
                    defer { lock.unlock() }
                    guard !resumed else { return }
                    resumed = true
                    sleepTask.cancel()
                    continuation.resume(returning: true)
                }
        }

        if !ready {
            AppLogger.warning(
                "[AUTH] waitForFreshSession timed out",
                category: .auth,
                context: DiagnosticContext.timing(
                    op: "auth.wait_for_fresh_session",
                    elapsedMs: Int(Date().timeIntervalSince(startedAt) * 1000)
                )
            )
        }
        return ready
    }
    
    // MARK: - Authentication
    
    /// Verify session and set isAuthenticated WITHOUT triggering cloud sync.
    /// Returns quickly (<200ms typical) so the UI can render from cached Core Data.
    /// Cloud sync should be scheduled separately after the UI is interactive.
    ///
    /// **Fast path (Sprint 1.38.54 — auth.session_recovery 5824ms regression fix):**
    /// The previous implementation `await`ed `client.auth.session` unconditionally,
    /// which internally calls `refreshSession()` whenever the access token is expired
    /// or within 30s of expiry. On a slow / congested network that refresh can take
    /// 5-6+ seconds, blocking the whole `.task` chain before first-frame interactivity.
    ///
    /// New flow:
    ///   1. `currentSession` (nonisolated, sync) — read cached session instantly.
    ///   2. If cached && not expired → set auth immediately. No network.
    ///   3. If cached but expired → race `refreshSession()` against a 1.5s timeout.
    ///      On timeout, STILL set auth = true optimistically using the cached user
    ///      and retry refresh in a detached background task. The access token may
    ///      be stale for a second but: (a) PostgREST responds 401 if so, (b) the
    ///      SDK auto-refreshes on 401, and (c) losing a second of UI responsiveness
    ///      is better than 6s of main-thread blocking.
    ///   4. If no cached session at all → try `session` once (no timeout — this is
    ///      the truly-signed-out path; fast even on slow network because it short-
    ///      circuits when there is nothing to refresh).
    ///
    /// Profile verification always runs in a background task so slow `user_profiles`
    /// queries do not extend the hot path.
    ///
    /// Sprint 2026-04-25 (cold-start speedup Phase 1.1): single-flight wrapper.
    /// `Fit33App.init()` now fires `checkAuthOnly` BEFORE SwiftUI evaluates
    /// `WindowGroup.body` so auth completes while the view tree is still being
    /// constructed (no main-actor contention from singleton inits). The
    /// existing `WindowGroup.task` also calls `checkAuthOnly` — both callers
    /// now await the same in-flight task instead of racing two parallel
    /// `client.auth.currentSession` + `MainActor.run` chains.
    func checkAuthOnly() async {
        if let existing = inFlightAuthCheckTask {
            await existing.value
            return
        }
        let task: Task<Void, Never> = Task { [weak self] in
            await self?._performAuthCheck()
            return ()
        }
        inFlightAuthCheckTask = task
        await task.value
        inFlightAuthCheckTask = nil
    }

    private func _performAuthCheck() async {
        // Sprint 2026-04-24 Phase 2 L: inner-timing instrumentation. Caller
        // (`Fit33App.task`) also wraps this in a signpost — when the two disagree
        // it tells us whether the time is in the auth work itself or in `.task`
        // scheduling latency (SwiftUI may delay starting the closure until main
        // thread has capacity). 1.38 (54) logs showed `[STARTUP] checkAuthOnly
        // completed in 1482ms` despite the fast-path log firing — most of that
        // was scheduling latency, not auth work. Inner timing disambiguates.
        let innerStart = CFAbsoluteTimeGetCurrent()
        defer {
            let innerMs = Int((CFAbsoluteTimeGetCurrent() - innerStart) * 1000)
            if innerMs > 500 {
                AppLogger.warning("[AUTH] checkAuthOnly inner-work took \(innerMs)ms (outer wrap may differ due to .task scheduling latency)", category: .auth)
            } else {
                AppLogger.debug("[AUTH] checkAuthOnly inner-work: \(innerMs)ms", category: .auth)
            }
        }
        
        // Fast path 1 — cached valid session
        if let cached = client.auth.currentSession, !cached.isExpired {
            await MainActor.run {
                currentUser = cached.user
                isAuthenticated = true
            }
            AppLogger.info("Session restored from cache (UI unblocked, no network): \(cached.user.email ?? "unknown")", category: .auth)
            Task { await self.reconcileProfileAfterSessionRestore(userId: cached.user.id) }
            return
        }
        
        // Fast path 2 — cached but expired:
        // ⚡️ Cold-start speedup Phase 5.3 (2026-04-25):
        // PREVIOUSLY: this branch awaited `refreshSession()` against a 1.5s
        // timeout BEFORE flipping `isAuthenticated = true`. On a typical
        // cold start, that's a 1.5s gate before the dashboard's social
        // fan-out can begin (observed: `[DASHBOARD] Auth ready (2399ms)…`
        // in 2026-04-25T19:23 logs). Worse, while the inner `await` runs,
        // every `MainActor.run` hop the path eventually performs queues
        // behind SwiftUI's body-evaluation chain on main, dragging
        // `app.first_frame` from ~2.7s (fast-path 1) up to ~4.9s.
        //
        // NEW BEHAVIOR: flip `isAuthenticated = true` IMMEDIATELY using
        // the cached user, then race the refresh in a detached
        // background Task that doesn't gate first frame. If the access
        // token is truly stale, PostgREST will 401 and the Supabase SDK
        // auto-refreshes on retry — same recovery as before, just no
        // foreground wait. The dashboard renders cached state instantly
        // and replaces it with fresh data when the bg refresh + first
        // network calls land. No new flicker — cached data already
        // shows the same user.
        if let cached = client.auth.currentSession {
            await MainActor.run {
                currentUser = cached.user
                isAuthenticated = true
            }
            AppLogger.info("Cached session expired — UI unblocked optimistically; racing refresh in background", category: .auth)

            Task.detached { [client, weak self] in
                if let refreshed = try? await client.auth.refreshSession() {
                    await MainActor.run {
                        self?.currentUser = refreshed.user
                    }
                    AppLogger.info("Background refresh succeeded post-first-frame: \(refreshed.user.email ?? "unknown")", category: .auth)
                    if let self = self {
                        await self.reconcileProfileAfterSessionRestore(userId: refreshed.user.id)
                    }
                } else {
                    AppLogger.warning("Background refresh failed; PostgREST will retry-on-401 if token is truly stale", category: .auth)
                    if let self = self {
                        await self.reconcileProfileAfterSessionRestore(userId: cached.user.id)
                    }
                }
            }
            return
        }
        
        // No cached session — we are truly signed out. This path should be fast
        // on any network because there is nothing to refresh.
        do {
            let session = try await client.auth.session
            await MainActor.run {
                currentUser = session.user
                isAuthenticated = true
            }
            AppLogger.info("Session restored (no cache, hit network): \(session.user.email ?? "unknown")", category: .auth)
            Task { await self.reconcileProfileAfterSessionRestore(userId: session.user.id) }
        } catch {
            await MainActor.run {
                isAuthenticated = false
                currentUser = nil
            }
            AppLogger.info("No active session", category: .auth)
        }
    }
    
    /// Race an async throwing operation against a timeout. Returns the operation's
    /// value, or `nil` on timeout. Used by `checkAuthOnly` to bound network-bound
    /// session refresh. Generic helper — add new call sites cautiously; cancellation
    /// of in-flight Supabase work depends on the SDK honoring `Task.cancel()`.
    private func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async -> T?) async -> T? {
        return await withTaskGroup(of: T?.self, returning: T?.self) { group in
            group.addTask {
                await operation()
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? nil
        }
    }
    
    /// Confirms the row in `user_profiles` still exists after restore. Runs off the hot path.
    private func reconcileProfileAfterSessionRestore(userId: UUID) async {
        let result = await verifyUserProfile(userId: userId)
        switch result {
        case .valid:
            AppLogger.debug("[VERIFY] Profile OK after restore (\(userId.uuidString.prefix(8))…)", category: .auth)
        case .missingOrIncomplete:
            AppLogger.warning("Session exists but user was deleted or profile empty — forcing sign out", category: .auth)
            try? await client.auth.signOut()
            await MainActor.run {
                currentUser = nil
                isAuthenticated = false
                PersistenceController.shared.clearAllUserData()
            }
        case .transientFailure:
            AppLogger.warning("[VERIFY] Transient failure after restore — keeping session; retrying shortly", category: .network)
            try? await Task.sleep(for: .seconds(4))
            let retry = await verifyUserProfile(userId: userId)
            if case .missingOrIncomplete = retry {
                AppLogger.warning("Profile still invalid after retry — forcing sign out", category: .auth)
                try? await client.auth.signOut()
                await MainActor.run {
                    currentUser = nil
                    isAuthenticated = false
                    PersistenceController.shared.clearAllUserData()
                }
            }
        }
    }
    
    /// Full auth check that also syncs all data from cloud (legacy entry point).
    /// Prefer checkAuthOnly() + deferred syncAllDataFromCloud() for faster startup.
    func checkAuth() async {
        await checkAuthOnly()
        
        guard isAuthenticated else { return }
        
        #if DEBUG
        if !UserDefaults.standard.bool(forKey: "FAST_STARTUP_MODE") {
            await syncAllDataFromCloud()
        } else {
            AppLogger.debug("[FAST STARTUP] Skipping cloud sync - using cached data", category: .network)
        }
        #else
        await syncAllDataFromCloud()
        #endif
    }
    
    private enum UserProfileVerificationResult: Sendable {
        /// Row exists with at least name or email
        case valid
        /// No row or both name and email empty (new / deleted account)
        case missingOrIncomplete
        /// Network or server error — do not treat as "no profile"
        case transientFailure
    }
    
    /// Verifies that a user actually exists in the database (not just has a session)
    /// Check if a user profile exists AND has meaningful data (not just an empty row)
    private func verifyUserProfile(userId: UUID) async -> UserProfileVerificationResult {
        do {
            // Select critical fields to verify the profile has actual data
            let response: [UserProfileDTO] = try await client
                .from("user_profiles")
                .select("id, name, email, has_completed_onboarding")
                .eq("id", value: userId.uuidString)
                .execute()
                .value
            
            // Check if profile exists AND has meaningful data
            guard let profile = response.first else {
                AppLogger.debug("[VERIFY] No profile found for user \(userId.uuidString)", category: .network)
                return .missingOrIncomplete
            }
            
            // If name and email are both null/empty, treat as incomplete profile
            let hasName = !(profile.name ?? "").isEmpty
            let hasEmail = !(profile.email ?? "").isEmpty
            
            if !hasName && !hasEmail {
                AppLogger.warning("[VERIFY] Profile exists but has no name or email - treating as new user", category: .network)
                return .missingOrIncomplete
            }
            
            AppLogger.info("[VERIFY] Valid profile found - Name: \(profile.name ?? "nil"), Email: \(profile.email ?? "nil")", category: .network)
            return .valid
        } catch {
            AppLogger.warning("[VERIFY] Error checking user profile: \(error)", category: .network)
            return .transientFailure
        }
    }
    
    /// OAuth "returning user?" check — **transient failures return false** (legacy behavior:
    /// may re-enter onboarding on flaky network rather than skip account setup).
    private func verifyUserProfileExistsForOAuth(userId: UUID) async -> Bool {
        switch await verifyUserProfile(userId: userId) {
        case .valid: return true
        case .missingOrIncomplete, .transientFailure: return false
        }
    }
    
    func signUp(email: String, password: String, name: String) async throws {
        await MainActor.run { isLoading = true }
        SessionLogManager.shared.logAuthAttempt(method: "email_signup")
        
        let startTime = Date()
        AppLogger.debug("[SUPABASE] Starting signup request for: \(email)", category: .auth)

        do {
            AppLogger.debug("[SUPABASE] Calling client.auth.signUp...", category: .auth)
            let response = try await client.auth.signUp(email: email, password: password)
            
            let duration = Date().timeIntervalSince(startTime)
            AppLogger.debug("[SUPABASE] signUp response received in \(String(format: "%.2f", duration))s", category: .auth)
            
            let user = response.user
            AppLogger.debug("[SUPABASE] User ID: \(user.id)", category: .auth)
            
            // Set auth state BEFORE profile creation so subsequent API calls have a session
            await MainActor.run {
                currentUser = user
                isAuthenticated = true
                UserDefaults.standard.removeObject(forKey: "user_manually_signed_out")
            }
            
            // Create user profile — if this fails, auth user still exists and can be recovered
            do {
                AppLogger.debug("[SUPABASE] Creating user profile...", category: .auth)
                try await createUserProfile(userId: user.id, name: name, email: email)
                AppLogger.info("[SUPABASE] Profile created successfully", category: .auth)
            } catch {
                _ = NetworkErrorClassifier.log(
                    error,
                    context: "[SUPABASE] Profile creation failed (auth user exists, recoverable)",
                    category: .auth,
                    op: PerformanceSignposts.Op.profileWrite.rawValue,
                    endpoint: "user_profiles(insert)",
                    userId: user.id
                )
                // Don't throw — the auth user is created and authenticated.
                // Profile can be created/repaired later via ensureProfileExists().
            }
            
            await MainActor.run { isLoading = false }
            
            let totalDuration = Date().timeIntervalSince(startTime)
            AppLogger.info("Sign up successful: \(email) (total: \(String(format: "%.2f", totalDuration))s)", category: .auth)
            SessionLogManager.shared.logAuthSuccess(method: "email_signup", userId: user.id.uuidString)
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            await MainActor.run { isLoading = false }
            
            let desc = error.localizedDescription.lowercased()
            let isRateLimit = desc.contains("rate limit") || desc.contains("rate_limit") || desc.contains("too many") || desc.contains("429")
            
            if isRateLimit {
                let retryAfter = passwordResetRateLimitRetryAfter(error) ?? 60
                AppLogger.warning("[AUTH] Sign up rate limited after \(String(format: "%.2f", duration))s — retry in \(retryAfter)s", category: .auth)
                SessionLogManager.shared.logAuthFailure(method: "email_signup", error: "rate_limited retry_after=\(retryAfter)s | Duration: \(String(format: "%.2f", duration))s")
                throw SupabaseAuthError.signUpRateLimited(retryAfterSeconds: retryAfter)
            } else {
                _ = NetworkErrorClassifier.log(
                    error,
                    context: "[AUTH] Sign up failed after \(String(format: "%.2f", duration))s",
                    category: .auth,
                    op: PerformanceSignposts.Op.authSignUp.rawValue,
                    endpoint: "auth/sign_up",
                    startedAt: startTime
                )
            }
            SessionLogManager.shared.logAuthFailure(method: "email_signup", error: "\(error.localizedDescription) | Duration: \(String(format: "%.2f", duration))s")
            throw error
        }
    }
    
    func signIn(email: String, password: String) async throws {
        await MainActor.run { isLoading = true }
        SessionLogManager.shared.logAuthAttempt(method: "email")

        do {
            let session = try await client.auth.signIn(email: email, password: password)
            SessionLogManager.shared.logAuthSuccess(method: "email", userId: session.user.id.uuidString)
            
            await MainActor.run {
                currentUser = session.user
                isAuthenticated = true
                isLoading = false
                
                // Clear the manual sign-out flag since user is logging back in
                UserDefaults.standard.removeObject(forKey: "user_manually_signed_out")
            }
            SessionLogManager.shared.log(.info, category: .auth, message: "🔐 Sign in successful", metadata: [
                "email": email,
                "user_id": String(currentUser?.id.uuidString.prefix(8) ?? "?")
            ])
            AppLogger.info("Sign in successful: \(email)", category: .auth)
            
            // Sync all data from cloud — force=true so a stale throttle from the
            // previous (signed-out) session can't prevent hasCompletedOnboarding refresh.
            await syncAllDataFromCloud(force: true)
        } catch {
            await MainActor.run { isLoading = false }
            SessionLogManager.shared.logAuthFailure(method: "email", error: error.localizedDescription)
            _ = NetworkErrorClassifier.log(
                error,
                context: "Sign in error",
                category: .auth,
                op: PerformanceSignposts.Op.authSignIn.rawValue,
                endpoint: "auth/sign_in"
            )

            // M-19 (Sprint 5): surface unverified-email as a typed error so the
            // onboarding UI can show a dedicated resend/blocked banner instead
            // of a generic "invalid credentials" message.
            if isEmailNotConfirmedError(error) {
                throw SupabaseAuthError.emailNotConfirmed(email: email)
            }
            throw error
        }
    }
    
    // MARK: - Auth Provider Detection
    
    /// Check what authentication provider an email is registered with
    /// Returns: "apple", "google", "email", "none", or comma-separated if multiple
    func checkAuthProvider(for email: String) async -> String {
        do {
            let response: String = try await client.rpc("check_auth_provider", params: ["email_to_check": email.lowercased()]).execute().value
            AppLogger.debug("Auth provider for \(email): \(response)", category: .auth)
            return response
        } catch {
            AppLogger.warning("Could not check auth provider: \(error.localizedDescription)", category: .auth)
            return "unknown"
        }
    }
    
    /// Get a user-friendly message for the detected auth provider
    func getAuthProviderMessage(for provider: String) -> (message: String, shouldShowApple: Bool, shouldShowGoogle: Bool)? {
        switch provider.lowercased() {
        case "apple":
            return ("This email is linked to Sign in with Apple. Please use the Apple button below to sign in.", true, false)
        case "google":
            return ("This email is linked to Sign in with Google. Please use the Google button below to sign in.", false, true)
        case "apple,google", "google,apple":
            return ("This email is linked to Apple and Google. Please use either button below to sign in.", true, true)
        case "email":
            return nil // Normal email/password login is fine
        case "none":
            return nil // Email not registered, they can sign up
        default:
            return nil
        }
    }
    
    // MARK: - Social Sign-In (Apple & Google)
    
    /// Sign in with Apple using the identity token from ASAuthorizationAppleIDCredential
    /// Returns true if this is a NEW user who needs onboarding
    /// - Parameters:
    ///   - idToken: The identity token from Apple
    ///   - nonce: The nonce used for the request
    ///   - appleProvidedName: The full name provided by Apple (only available on first sign-in)
    @discardableResult
    func signInWithApple(idToken: String, nonce: String, appleProvidedName: String? = nil) async throws -> Bool {
        await MainActor.run { isLoading = true }
        
        do {
            let session = try await client.auth.signInWithIdToken(
                credentials: .init(
                    provider: .apple,
                    idToken: idToken,
                    nonce: nonce
                )
            )
            
            // Check if this is a new user (no profile exists yet)
            let profileExists = await verifyUserProfileExistsForOAuth(userId: session.user.id)
            var isNewUser = false
            
            if !profileExists {
                // Get email from Supabase session (Apple provides this to Supabase)
                let appleEmail = session.user.email ?? "apple_user_\(session.user.id.uuidString.prefix(8))@private.appleid.com"
                
                // Priority for FULL NAME (first + last):
                // 1. appleProvidedName (FULL NAME directly from Apple credentials - only first sign-in)
                // 2. Persisted full name from previous sign-in (UserDefaults - per user)
                // 3. Global Apple name cache (survives account deletion)
                // 4. Supabase user metadata (full_name or name)
                // 5. Email prefix (if not private relay and looks like a real name)
                // 6. Don't store anything (let user enter their name)
                var appleFullName: String?
                
                AppLogger.debug("[APPLE] Starting name resolution for user: \(session.user.id.uuidString.prefix(8))...", category: .auth)
                AppLogger.debug("[APPLE] appleProvidedName: \(appleProvidedName ?? "nil")", category: .auth)
                
                if let providedName = appleProvidedName, !providedName.isEmpty, providedName != "Apple User" {
                    appleFullName = providedName
                    // Persist for future sign-ins (Apple only provides name once)
                    // Store both per-user AND globally (global survives account deletion)
                    UserDefaults.standard.set(providedName, forKey: "apple_user_name_\(session.user.id.uuidString)")
                    UserDefaults.standard.set(providedName, forKey: "apple_global_name")
                    AppLogger.debug("[APPLE] Persisted user FULL NAME for future sign-ins: \(providedName)", category: .auth)
                    AppLogger.debug("[APPLE] Also stored globally as fallback", category: .auth)
                } else {
                    // Check per-user persisted name
                    let persistedKey = "apple_user_name_\(session.user.id.uuidString)"
                    let persistedFullName = UserDefaults.standard.string(forKey: persistedKey)
                    AppLogger.debug("[APPLE] Checking UserDefaults[\(persistedKey)]: \(persistedFullName ?? "nil")", category: .auth)
                    
                    if let persistedFullName = persistedFullName, 
                       !persistedFullName.isEmpty,
                       persistedFullName != "Apple User" {
                        appleFullName = persistedFullName
                        AppLogger.debug("[APPLE] Using persisted FULL NAME from previous sign-in: \(persistedFullName)", category: .auth)
                    } else {
                        // Check global name cache (survives account deletion)
                        let globalName = UserDefaults.standard.string(forKey: "apple_global_name")
                        AppLogger.debug("[APPLE] Checking global cache [apple_global_name]: \(globalName ?? "nil")", category: .auth)
                        
                        if let globalName = globalName, !globalName.isEmpty, globalName != "Apple User" {
                            appleFullName = globalName
                            // Restore to per-user cache
                            UserDefaults.standard.set(globalName, forKey: "apple_user_name_\(session.user.id.uuidString)")
                            AppLogger.debug("[APPLE] Using GLOBAL cached name (restored from previous session): \(globalName)", category: .auth)
                        } else if let fullName = session.user.userMetadata["full_name"] as? String, !fullName.isEmpty {
                            AppLogger.debug("[APPLE] Checking metadata full_name: \(fullName)", category: .auth)
                            if fullName != "Apple User" {
                                appleFullName = fullName
                            }
                        } else if let name = session.user.userMetadata["name"] as? String, !name.isEmpty {
                            AppLogger.debug("[APPLE] Checking metadata name: \(name)", category: .auth)
                            if name != "Apple User" {
                                appleFullName = name
                            }
                        } else if let email = session.user.email, !email.contains("privaterelay"), !email.contains("@icloud") {
                            // Only use email prefix if it looks like a real name (not private relay or iCloud)
                            let emailPrefix = email.components(separatedBy: "@").first ?? ""
                            // Check if email prefix looks like a real name (contains letters, not too many numbers)
                            let letterCount = emailPrefix.filter { $0.isLetter }.count
                            AppLogger.debug("[APPLE] Checking email prefix: \(emailPrefix) (letters: \(letterCount))", category: .auth)
                            if letterCount > 2 && emailPrefix.count > 2 {
                                appleFullName = emailPrefix.capitalized
                            }
                        }
                    }
                }
                
                AppLogger.debug("Apple Sign-In - Email: \(appleEmail), Full Name: \(appleFullName ?? "(none - user will enter)")", category: .auth)
                
                // ⚠️ IMPORTANT: Do NOT create profile here!
                // The profile should only be created when user taps "Create Account" at end of onboarding.
                // This prevents "zombie" accounts with null data if user abandons onboarding.
                // Store the Apple FULL NAME temporarily ONLY if we have a valid one - profile will be created in completeOnboarding()
                if let fullName = appleFullName, !fullName.isEmpty {
                    UserDefaults.standard.set(fullName, forKey: "pending_oauth_name")
                    AppLogger.debug("[APPLE] Stored pending full name: \(fullName)", category: .auth)
                } else {
                    // Don't store anything - user will be prompted to enter their name
                    UserDefaults.standard.removeObject(forKey: "pending_oauth_name")
                    AppLogger.warning("[APPLE] No valid name available - user will be prompted to enter name", category: .auth)
                    AppLogger.info("[APPLE] To fix: Sign out of Apple ID in Settings > [Your Name] > Sign In & Security > Apps Using Your Apple ID > Fit33 > Stop Using Apple ID", category: .auth)
                    AppLogger.info("[APPLE] Then sign in again - Apple will provide your name on the FIRST sign-in with a new connection", category: .auth)
                }
                UserDefaults.standard.set(appleEmail, forKey: "pending_oauth_email")
                
                isNewUser = true
                AppLogger.debug("New Apple user - needs onboarding", category: .auth)
            }
            
            await MainActor.run {
                currentUser = session.user
                isAuthenticated = true
                isLoading = false
                UserDefaults.standard.removeObject(forKey: "user_manually_signed_out")
            }
            AppLogger.info("Apple Sign-In successful: \(session.user.email ?? "private email")", category: .auth)
            
            // Only sync data for EXISTING users (not new users who need onboarding)
            // force=true bypasses any residual throttle from a prior session so the
            // existing user's hasCompletedOnboarding state is refreshed in Core Data
            // before ContentView routes them. Without this, login can bounce back to
            // the onboarding screen.
            if !isNewUser {
                await syncAllDataFromCloud(force: true)
            }
            
            return isNewUser
        } catch {
            await MainActor.run { isLoading = false }
            _ = NetworkErrorClassifier.log(
                error,
                context: "Apple Sign-In error",
                category: .auth,
                op: PerformanceSignposts.Op.authSignIn.rawValue,
                endpoint: "auth/apple_sign_in"
            )
            throw error
        }
    }
    
    /// Handle OAuth callback URL (for Google/Facebook Sign-In)
    /// This handles the implicit flow response where tokens are in the URL fragment
    func handleOAuthCallback(url: URL) async throws -> (isNewUser: Bool, socialUsername: String?) {
        await MainActor.run { isLoading = true }
        
        do {
            // First, try the standard PKCE session flow
            // If that fails (implicit flow), parse tokens from URL fragment manually
            let session: Session
            var jwtUserMetadata: [String: Any]? = nil  // Store metadata from JWT for implicit flow
            
            do {
                session = try await client.auth.session(from: url)
            } catch {
                // PKCE failed - try parsing implicit flow tokens from URL fragment
                AppLogger.debug("[OAUTH] PKCE failed, trying implicit flow token parsing...", category: .auth)
                
                guard let fragment = url.fragment else {
                    throw error
                }
                
                // Parse the fragment as query parameters
                var params: [String: String] = [:]
                for pair in fragment.components(separatedBy: "&") {
                    let parts = pair.components(separatedBy: "=")
                    if parts.count == 2 {
                        params[parts[0]] = parts[1].removingPercentEncoding ?? parts[1]
                    }
                }
                
                guard let accessToken = params["access_token"],
                      let refreshToken = params["refresh_token"] else {
                    AppLogger.warning("[OAUTH] Missing tokens in URL fragment", category: .auth)
                    throw error
                }
                
                // Decode the JWT to extract user metadata (it's in the payload)
                jwtUserMetadata = decodeJWTPayload(accessToken)
                if let metadata = jwtUserMetadata?["user_metadata"] as? [String: Any] {
                    AppLogger.debug("[OAUTH] Decoded user metadata from JWT: \(metadata)", category: .auth)
                    jwtUserMetadata = metadata
                }
                
                AppLogger.debug("[OAUTH] Found tokens in URL fragment, setting session...", category: .auth)
                
                // Set the session using the tokens
                session = try await client.auth.setSession(accessToken: accessToken, refreshToken: refreshToken)
                AppLogger.info("[OAUTH] Session set from implicit flow tokens", category: .auth)
            }
            
            // Check if this is a new user (no profile exists yet)
            let profileExists = await verifyUserProfileExistsForOAuth(userId: session.user.id)
            var isNewUser = false
            var socialUsername: String? = nil
            
            if !profileExists {
                // Determine provider from metadata - check both session and JWT-decoded metadata
                let provider = session.user.appMetadata["provider"] as? String 
                    ?? jwtUserMetadata?["iss"] as? String ?? "unknown"
                
                let userEmail: String
                let userName: String
                let avatarUrl: String?
                
                // Try to get name from session first, then from JWT-decoded metadata
                let sessionFullName = session.user.userMetadata["full_name"] as? String
                let sessionName = session.user.userMetadata["name"] as? String
                let jwtFullName = jwtUserMetadata?["full_name"] as? String
                let jwtName = jwtUserMetadata?["name"] as? String
                avatarUrl = session.user.userMetadata["avatar_url"] as? String 
                    ?? session.user.userMetadata["picture"] as? String
                    ?? jwtUserMetadata?["avatar_url"] as? String
                    ?? jwtUserMetadata?["picture"] as? String
                
                if provider == "facebook" || provider.contains("facebook") {
                    // Facebook-specific data extraction
                    userEmail = session.user.email ?? "facebook_user_\(session.user.id.uuidString.prefix(8))@facebook.com"
                    userName = sessionFullName ?? sessionName ?? jwtFullName ?? jwtName ?? "Facebook User"
                    
                    // Extract username if available
                    socialUsername = session.user.userMetadata["user_name"] as? String 
                        ?? session.user.userMetadata["username"] as? String
                    
                    AppLogger.debug("Facebook Sign-In - Username: @\(socialUsername ?? "unknown"), Name: \(userName)", category: .auth)
                } else {
                    // Google or other OAuth provider
                    userEmail = session.user.email ?? "oauth_user_\(session.user.id.uuidString.prefix(8))@email.com"
                    userName = sessionFullName ?? sessionName ?? jwtFullName ?? jwtName ?? "User"
                    AppLogger.debug("OAuth Sign-In - Provider: \(provider), Name: \(userName)", category: .auth)
                    AppLogger.debug("OAuth Sign-In - Session metadata: \(session.user.userMetadata)", category: .auth)
                    AppLogger.debug("OAuth Sign-In - JWT metadata: \(jwtUserMetadata ?? [:])", category: .auth)
                }
                
                // ⚠️ IMPORTANT: Do NOT create profile here!
                // The profile should only be created when user taps "Create Account" at end of onboarding.
                // This prevents "zombie" accounts with null data if user abandons onboarding.
                // Store the OAuth data temporarily - profile will be created in completeOnboarding()
                await MainActor.run {
                    UserDefaults.standard.set(userName, forKey: "pending_oauth_name")
                    UserDefaults.standard.set(userEmail, forKey: "pending_oauth_email")
                    if let avatar = avatarUrl {
                        UserDefaults.standard.set(avatar, forKey: "pending_oauth_avatar")
                    }
                    AppLogger.debug("[OAUTH] Stored pending profile data (will create on onboarding completion)", category: .auth)
                    AppLogger.debug("[OAUTH] Pending name: \(userName), email: \(userEmail)", category: .auth)
                }
                
                isNewUser = true
            }
            
            await MainActor.run {
                currentUser = session.user
                isAuthenticated = true
                isLoading = false
                UserDefaults.standard.removeObject(forKey: "user_manually_signed_out")
            }
            AppLogger.info("OAuth Sign-In successful: \(session.user.email ?? "unknown")", category: .auth)
            
            // Only sync for existing users
            // force=true ensures hasCompletedOnboarding refreshes even if a prior
            // signed-out session left a residual throttle window in place.
            if !isNewUser {
                await syncAllDataFromCloud(force: true)
            }
            
            return (isNewUser, socialUsername)
        } catch {
            await MainActor.run { isLoading = false }
            _ = NetworkErrorClassifier.log(
                error,
                context: "OAuth callback error",
                category: .auth,
                op: PerformanceSignposts.Op.authSignIn.rawValue,
                endpoint: "auth/oauth_callback"
            )
            throw error
        }
    }
    
    /// Decode a JWT payload to extract user metadata
    private func decodeJWTPayload(_ jwt: String) -> [String: Any]? {
        let parts = jwt.components(separatedBy: ".")
        guard parts.count == 3 else { return nil }
        
        var payload = parts[1]
        // Add padding if needed for base64 decoding
        let remainder = payload.count % 4
        if remainder > 0 {
            payload = payload.padding(toLength: payload.count + 4 - remainder, withPad: "=", startingAt: 0)
        }
        
        // Convert base64url to base64
        payload = payload
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        
        return json
    }
    
    /// Get the OAuth URL for Google Sign-In
    func getGoogleOAuthURL() -> URL? {
        let redirectURL = "fit33://login-callback"
        
        var components = URLComponents(string: "\(supabaseURL)/auth/v1/authorize")
        components?.queryItems = [
            URLQueryItem(name: "provider", value: "google"),
            URLQueryItem(name: "redirect_to", value: redirectURL)
        ]
        
        return components?.url
    }
    
    /// Get the OAuth URL for Facebook Sign-In
    func getFacebookOAuthURL() -> URL? {
        let redirectURL = "fit33://login-callback"
        
        var components = URLComponents(string: "\(supabaseURL)/auth/v1/authorize")
        components?.queryItems = [
            URLQueryItem(name: "provider", value: "facebook"),
            URLQueryItem(name: "redirect_to", value: redirectURL)
        ]
        
        return components?.url
    }
    
    func signOut() async throws {
        await MainActor.run { isLoading = true }
        SessionLogManager.shared.logLogout()

        do {
            await PushNotificationService.shared.removeDeviceToken()

            // Tear down Realtime channels BEFORE revoking the JWT, otherwise
            // the socket stays open with stale credentials and leaks onto
            // the next signed-in user (and burns battery until iOS reaps it).
            await RealtimeService.shared.disconnect()

            try await client.auth.signOut()

            // Sprint 5 M-8: flush any in-flight coalesced fetches so a task
            // that was kicked off for the previous user can't land on the
            // next user's `@Published` state.
            await RequestCoalescer.shared.reset()

            await MainActor.run {
                // Clear Core Data and UserDefaults
                PersistenceController.shared.clearAllUserData()
                SmackTalkWidgetBridge.clear()
                RealtimeService.shared.clearAllDashboardBattleCryStateForLogout()

                // Clear profile photo cache - critical for multi-user scenarios
                ProfilePhotoCache.shared.clearCache()
                
                // Clear challenge cache - ensures no challenge data leaks between users
                ChallengeService.shared.clearCache()

                // Audit PR-18 (2026-07-26): zero the remaining social /
                // nutrition / league singletons. Before this, the next
                // account on the same device briefly saw the previous
                // user's friends, feed, private challenges, league standing,
                // contact suggestions, and meals until each surface refetched.
                FriendService.shared.resetForSignOut()
                ActivityFeedService.shared.resetForSignOut()
                PrivateChallengeService.shared.clearCache()
                CommunityChallengeService.shared.resetForSignOut()
                WeeklyLeagueService.shared.resetForSignOut()
                ContactsService.shared.resetForSignOut()
                MealService.shared.resetForSignOut()

                // Clear progressive-unlock maturity cache so the next signed-in
                // user starts from a fresh recompute. Without this, a returning
                // user could see the previous account's cached profile (or, more
                // commonly, the empty-default profile that gates autogen to
                // foundational/stretch-only exercises). Bug-intel Report 8.
                ProgressiveExerciseUnlockService.shared.clearCache()

                // Snappiness Overhaul Phase 5.B
                // (`PerfFlags.phase5RecommenderPrewarm`): drop the
                // `SmartProgramRecommender.getSuggestedProgram` cache so a
                // previously-signed-in user's recommendation cannot leak
                // across the auth boundary. `clearSuggestedProgramCache()`
                // is always safe to call (no-op when empty / flag OFF).
                SmartProgramRecommender.shared.clearSuggestedProgramCache()

                // Snappiness Overhaul Phase 5.A
                // (`PerfFlags.phase5DashboardCache`): broadcast sign-out so
                // the dashboard social-fanout disk cache can purge every
                // user's plist file. Gated on the flag so that adding the
                // new notification name doesn't change behavior for any
                // future observer when the flag is OFF.
                if PerfFlags.phase5DashboardCache {
                    NotificationCenter.default.post(name: .userDidSignOut, object: nil)
                }
                
                // Mark that user manually signed out (for development mode)
                UserDefaults.standard.set(true, forKey: "user_manually_signed_out")
                
                // Reset authentication state
                currentUser = nil
                isAuthenticated = false
                isLoading = false
            }

            // 🔓 Reset cloud-sync throttle so the NEXT login (especially a fast
            // sign-out → sign-in cycle) is not blocked by the 5-minute
            // minSyncInterval. Without this, an existing user who logs back in
            // within the throttle window would have syncAllDataFromCloud()
            // skipped, leaving hasCompletedOnboarding=false in Core Data and
            // bouncing them back to the onboarding screen.
            SupabaseManager.isSyncInProgress = false
            SupabaseManager.lastSyncTime = nil

            SessionLogManager.shared.log(.info, category: .auth, message: "🔐 Sign out complete")
            AppLogger.info("Sign out successful - all local data cleared", category: .auth)
        } catch {
            await MainActor.run { isLoading = false }
            _ = NetworkErrorClassifier.log(
                error,
                context: "Sign out error",
                category: .auth,
                op: PerformanceSignposts.Op.authSignOut.rawValue,
                endpoint: "auth/sign_out",
                userId: currentUser?.id
            )
            throw error
        }
    }
    
    /// Delete the current user's account completely
    /// This uses a Supabase function to delete from auth.users (requires running DELETE_USER_ACCOUNT.sql)
    func deleteAccount() async throws {
        guard let userId = currentUser?.id else {
            throw NSError(domain: "SupabaseManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "No user logged in"])
        }
        
        AppLogger.info("STARTING ACCOUNT DELETION", category: .auth)
        AppLogger.info("User ID: \(userId.uuidString)", category: .auth)
        
        await MainActor.run { isLoading = true }
        
        // STEP 1: Always delete all user data from tables first (this always works)
        AppLogger.debug("Step 1: Deleting all user data from tables...", category: .network)
        await deleteAllUserDataFromTables(userId: userId)
        
        // STEP 2: Delete profile photo from storage
        AppLogger.debug("Step 2: Deleting profile photo...", category: .network)
        await deleteProfilePhotoFromStorage(userId: userId)
        
        // STEP 3: Try to delete from auth.users via RPC (requires complete_account_deletion.sql)
        // The RPC returns JSONB: { "success": true, "user_id": "...", "deleted": {...} }
        AppLogger.debug("Step 3: Attempting to delete from auth.users via RPC...", category: .network)
        var authUserDeleted = false
        struct DeleteAccountRPCResponse: Decodable {
            let success: Bool?
        }
        do {
            let result: DeleteAccountRPCResponse = try await client
                .rpc("delete_user_account", params: ["user_id_to_delete": userId.uuidString])
                .execute()
                .value

            authUserDeleted = result.success ?? false
            if authUserDeleted {
                AppLogger.info("User deleted from auth.users via RPC", category: .auth)
            } else {
                AppLogger.warning("RPC returned success=false - auth.users entry may still exist", category: .auth)
            }
        } catch {
            AppLogger.warning("RPC delete_user_account failed: \(error.localizedDescription)", category: .network)
            AppLogger.warning("Run complete_account_deletion.sql in Supabase to enable full deletion", category: .network)
            // Continue anyway - profile data is already deleted
        }
        
        // STEP 4: Sign out and clear local data
        AppLogger.debug("Step 4: Signing out and clearing local data...", category: .auth)
        await RealtimeService.shared.disconnect()
        try? await client.auth.signOut()
        
        await MainActor.run {
            PersistenceController.shared.clearAllUserData()
            ProfilePhotoCache.shared.clearCache()
            ChallengeService.shared.clearCache()
            ChallengeService.shared.activeChallenges = []
            ChallengeService.shared.pendingInvites = []
            // Audit PR-18 (2026-07-26): same singleton wipe as signOut() —
            // deletion must never leave more residue than a plain sign-out.
            FriendService.shared.resetForSignOut()
            ActivityFeedService.shared.resetForSignOut()
            PrivateChallengeService.shared.clearCache()
            CommunityChallengeService.shared.resetForSignOut()
            WeeklyLeagueService.shared.resetForSignOut()
            ContactsService.shared.resetForSignOut()
            MealService.shared.resetForSignOut()
            UserDefaults.standard.set(true, forKey: "user_manually_signed_out")
            currentUser = nil
            isAuthenticated = false
            isLoading = false
        }

        // 🔓 Reset cloud-sync throttle so a brand-new account created right
        // after a deletion is not throttled out of its first post-auth sync.
        SupabaseManager.isSyncInProgress = false
        SupabaseManager.lastSyncTime = nil

        if authUserDeleted {
            AppLogger.info("ACCOUNT FULLY DELETED - user can re-register with same email", category: .auth)
        } else {
            AppLogger.warning("PROFILE DATA DELETED but auth.users entry may remain", category: .auth)
            AppLogger.warning("User may need to use a different email or run DELETE_USER_ACCOUNT.sql", category: .auth)
        }
    }
    
    /// Delete all user data from all tables (comprehensive cleanup)
    private func deleteAllUserDataFromTables(userId: UUID) async {
        // Order matters due to foreign key constraints - delete child tables first
        let deletions: [(table: String, column: String)] = [
            // Challenge data (delete daily progress first)
            ("challenge_daily_progress", "user_id"),
            ("challenge_participants", "user_id"),
            
            // Friend/social data — friendships uses requester_id/addressee_id, NOT user_id/friend_id
            ("friendships", "requester_id"),
            ("friendships", "addressee_id"),
            // Shared workouts — table is shared_workouts, NOT sent_workouts
            ("shared_workouts", "sender_id"),
            ("shared_workouts", "recipient_id"),
            
            // Contact sync data
            ("user_synced_contacts", "user_id"),
            ("contact_joined_notifications", "notified_user_id"),
            
            // Push notifications
            ("user_push_tokens", "user_id"),
            ("push_notification_queue", "recipient_user_id"),
            
            // Workout data
            ("workout_history", "user_id"),
            ("workout_exercises", "user_id"),
            ("workout_context", "user_id"),
            ("workouts", "user_id"),
            ("exercise_usage_logs", "user_id"),
            ("exercise_performance_history", "user_id"),
            
            // Program data
            ("user_active_programs", "user_id"),
            ("user_custom_programs", "user_id"),
            ("program_history", "user_id"),
            
            // Food/meal data
            ("meal_logs", "user_id"),
            ("user_food_history", "user_id"),
            ("user_food_frequency", "user_id"),
            ("user_ingredient_preferences", "user_id"),
            ("user_cuisine_preferences", "user_id"),
            ("user_favorite_foods", "user_id"),
            
            // Favorites and custom content
            ("user_favorites", "user_id"),
            ("favorite_workouts", "user_id"),
            ("custom_exercises", "user_id"),
            ("user_exercise_nicknames", "user_id"),
            
            // Health data
            ("step_tracking", "user_id"),
            ("weight_logs", "user_id"),
            ("weight_goals", "user_id"),
            ("weight_statistics", "user_id"),
            ("hydration_logs", "user_id"),
            ("daily_activity_summary", "user_id"),
            ("daily_summaries", "user_id"),
            ("sleep_logs", "user_id"),
            ("heart_rate_daily", "user_id"),
            ("body_composition_logs", "user_id"),
            ("inbody_connections", "user_id"),
            
            // Cardio data
            ("cardio_personal_records", "user_id"),
            ("cardio_streaks", "user_id"),
            ("cardio_weekly_summaries", "user_id"),
            ("cardio_goals", "user_id"),
            ("cardio_workouts", "user_id"),
            
            // Intelligence/insights data
            ("user_personalized_insights", "user_id"),
            ("user_streak_tracking", "user_id"),
            ("user_metric_correlations", "user_id"),
            ("user_behavior_patterns", "user_id"),
            ("user_performance_windows", "user_id"),
            
            // Strava integration
            ("user_strava_tokens", "user_id"),
            ("strava_activities", "user_id"),
            
            // Notifications
            ("app_notifications", "user_id"),
            
            // Other user data
            ("bug_reports", "user_id"),
            ("user_progress", "user_id")
        ]
        
        for (table, column) in deletions {
            do {
                try await client
                    .from(table)
                    .delete()
                    .eq(column, value: userId.uuidString)
                    .execute()
                AppLogger.debug("Deleted from \(table)", category: .network)
            } catch {
                // Table might not exist or no data - continue
                AppLogger.warning("\(table): \(error.localizedDescription)", category: .network)
            }
        }
        
        // Delete challenges created by this user (table is group_challenges, NOT friend_challenges)
        do {
            try await client
                .from("group_challenges")
                .delete()
                .eq("created_by", value: userId.uuidString)
                .execute()
            AppLogger.debug("Deleted created challenges", category: .network)
        } catch {
            AppLogger.warning("group_challenges (created_by): \(error.localizedDescription)", category: .network)
        }
        
        // Finally delete the user profile
        do {
            try await client
                .from("user_profiles")
                .delete()
                .eq("id", value: userId.uuidString)
                .execute()
            AppLogger.debug("Deleted user_profiles", category: .network)
        } catch {
            AppLogger.warning("user_profiles: \(error.localizedDescription)", category: .network)
        }
        
        AppLogger.info("All user data deletion complete", category: .network)
    }
    
    /// Delete profile photo from Supabase Storage
    private func deleteProfilePhotoFromStorage(userId: UUID) async {
        do {
            let filePath = "profile_photos/\(userId.uuidString).jpg"
            try await client.storage
                .from("avatars")
                .remove(paths: [filePath])
            AppLogger.debug("Profile photo deleted from storage", category: .network)
        } catch {
            // Photo might not exist, which is fine
            AppLogger.warning("Could not delete profile photo from storage: \(error.localizedDescription)", category: .network)
        }
    }
    
    
    func resetPassword(email: String) async throws {
        await MainActor.run { isLoading = true }

        do {
            // Configure redirect URL for password reset
            // This URL will be used in the email link that user receives
            let redirectURL = "fit33://reset-password"  // Deep link to app

            try await client.auth.resetPasswordForEmail(
                email,
                redirectTo: URL(string: redirectURL)
            )
            await MainActor.run { isLoading = false }
            AppLogger.info("Password reset email sent to: \(email)", category: .auth)
        } catch {
            await MainActor.run { isLoading = false }

            // Detect GoTrue `over_email_send_rate_limit` (HTTP 429) and rethrow
            // as a typed error so the onboarding UI can render a cooldown with
            // a live countdown instead of the generic "failed to send" message
            // that was driving users to tap again and inflate the counter
            // further. Bug-intel fingerprints 0080557f / 1edfaad0 / a22cd96f.
            if let retryAfter = passwordResetRateLimitRetryAfter(error) {
                AppLogger.warning(
                    "Password reset rate-limited (retry after \(retryAfter)s) for \(email)",
                    category: .auth
                )
                throw SupabaseAuthError.passwordResetRateLimited(retryAfterSeconds: retryAfter)
            }

            _ = NetworkErrorClassifier.log(
                error,
                context: "Password reset error",
                category: .auth,
                op: PerformanceSignposts.Op.authPasswordReset.rawValue,
                endpoint: "auth/reset_password_for_email"
            )
            throw error
        }
    }

    // MARK: - Email Verification (M-19, Sprint 5)
    // Supabase project setting "Confirm email" must be enabled for this flow to
    // actually block sign-in. When it's on, GoTrue returns an `email_not_confirmed`
    // error during `signInWithPassword` for users whose `email_confirmed_at` is
    // NULL. The client recognizes that error, throws `.emailNotConfirmed`, and the
    // onboarding UI shows a dedicated "check your inbox" banner with a resend
    // button (see `NewOnboardingView+Auth.swift`). Enable this in the Supabase
    // dashboard at Auth > Providers > Email > "Confirm email" = ON.

    /// Strongly-typed auth errors surfaced to onboarding so the UI can render a
    /// bespoke state (resend button, blocked banner, etc.) instead of a raw
    /// localized string.
    enum SupabaseAuthError: LocalizedError {
        case emailNotConfirmed(email: String)
        /// Supabase rate-limited the password reset email for this address.
        /// `retryAfterSeconds` is parsed from the `Retry-After` header when
        /// present, else defaults to 60s per GoTrue's `over_email_send_rate_limit`
        /// enforcement. Bug-intel fingerprints 0080557f / 1edfaad0 / a22cd96f.
        case passwordResetRateLimited(retryAfterSeconds: Int)
        /// Supabase rate-limited the signup confirmation email. The default
        /// hosted SMTP allows ~2 emails/hour, so a few retries (or stale dev
        /// attempts) trigger this. UI shows a live countdown so users stop
        /// hammering Continue. See `[auth.rate_limit] email_sent` in
        /// `supabase/config.toml`.
        case signUpRateLimited(retryAfterSeconds: Int)

        var errorDescription: String? {
            switch self {
            case .emailNotConfirmed:
                return "Please verify your email before signing in."
            case .passwordResetRateLimited(let retry):
                return "Too many reset emails — please wait \(retry)s before trying again."
            case .signUpRateLimited(let retry):
                let mins = max(1, Int(ceil(Double(retry) / 60.0)))
                return "Email signup is temporarily rate-limited. Please wait \(retry < 60 ? "\(retry)s" : "~\(mins) min") and try again, or use a different email."
            }
        }
    }

    /// Heuristic for GoTrue `over_email_send_rate_limit` error shape. The SDK
    /// surfaces rate-limited password-reset and sign-up attempts as either a
    /// string match or an HTTP 429; we catch both. Reused for sign-up cooldown
    /// (see `signUpRateLimited` typed error).
    private func passwordResetRateLimitRetryAfter(_ error: Error) -> Int? {
        let desc = error.localizedDescription.lowercased()
        let looksRateLimited = desc.contains("over_email_send_rate_limit")
            || desc.contains("email rate limit")
            || desc.contains("rate limit exceeded")
            || desc.contains("too many requests")
            || desc.contains("email rate limit exceeded")
            || desc.contains("429")
            || desc.contains("status code: 429")
            || desc.contains("\"status\":429")
        guard looksRateLimited else { return nil }

        // Try to parse "Retry-After: NNN" out of the stringified response if
        // the SDK happened to include response headers in the error. Otherwise
        // fall back to 60s (GoTrue's default floor).
        if let range = desc.range(of: #"retry-after"#, options: [.caseInsensitive, .regularExpression]) {
            let tail = desc[range.upperBound...]
            let digits = tail.prefix { !$0.isNumber }.isEmpty
                ? tail.prefix { $0.isNumber }
                : tail.drop { !$0.isNumber }.prefix { $0.isNumber }
            if let seconds = Int(digits), seconds > 0 {
                return seconds
            }
        }
        return 60
    }

    /// Heuristic for Supabase/GoTrue "email not confirmed" errors. Error shape
    /// varies across SDK versions so we do a lowercase substring match.
    private func isEmailNotConfirmedError(_ error: Error) -> Bool {
        let desc = error.localizedDescription.lowercased()
        return desc.contains("email not confirmed")
            || desc.contains("email_not_confirmed")
            || desc.contains("not verified")
            || desc.contains("confirm your email")
    }

    /// Re-send the signup confirmation email for a user whose account exists
    /// but hasn't clicked the verification link yet. Throws on failure.
    /// Uses Supabase's GoTrue `resend` endpoint with `type: .signup`.
    func resendEmailConfirmation(email: String) async throws {
        AppLogger.debug("Resending email confirmation to \(email)", category: .auth)
        do {
            try await client.auth.resend(email: email, type: .signup)
            AppLogger.info("Resent email confirmation to \(email)", category: .auth)
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "Resend email confirmation failed",
                category: .auth,
                op: PerformanceSignposts.Op.authResendEmail.rawValue,
                endpoint: "auth/resend"
            )
            throw error
        }
    }

    /// Check whether the current signed-in user has confirmed their email. Used
    /// by onboarding after the user taps "I've verified" to refresh the session
    /// and see the updated `email_confirmed_at` claim.
    func isCurrentUserEmailConfirmed() async -> Bool {
        do {
            try await client.auth.refreshSession()
            let user = try await client.auth.session.user
            return user.emailConfirmedAt != nil
        } catch {
            AppLogger.warning("Could not refresh session to check email confirmation: \(error.localizedDescription)", category: .auth)
            return false
        }
    }
    
    // MARK: - Onboarding Logging
    
    /// Log an onboarding event to the database for debugging
    func logOnboardingEvent(
        eventType: String,
        stepName: String? = nil,
        eventData: [String: Any]? = nil,
        errorMessage: String? = nil,
        sessionId: String? = nil
    ) async {
        do {
            // Get device info
            let deviceInfo: [String: Any] = [
                "device_model": getDeviceModel(),
                "os_version": UIDevice.current.systemVersion,
                "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                "build_number": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
                "locale": Locale.current.identifier,
                "timezone": TimeZone.current.identifier,
                "language": Locale.preferredLanguages.first ?? "unknown",
                "region": Locale.current.region?.identifier ?? "unknown"
            ]
            
            // Build params
            var params: [String: Any] = [
                "p_event_type": eventType,
                "p_device_info": deviceInfo
            ]
            
            if let userId = currentUser?.id {
                params["p_user_id"] = userId.uuidString
            }
            
            if let sessionId = sessionId ?? OnboardingSessionManager.shared.currentSessionId {
                params["p_session_id"] = sessionId
            }
            
            if let stepName = stepName {
                params["p_step_name"] = stepName
            }
            
            if let eventData = eventData {
                params["p_event_data"] = eventData
            }
            
            if let errorMessage = errorMessage {
                params["p_error_message"] = errorMessage
            }
            
            // Call the RPC function (convert to Encodable for Supabase)
            try await client.rpc("log_onboarding_event", params: params.toEncodable()).execute()
            
            AppLogger.debug("[ONBOARDING LOG] \(eventType) - \(stepName ?? "N/A")", category: .network)
        } catch {
            // Don't throw - logging should never break the app
            AppLogger.warning("[ONBOARDING LOG] Failed to log event: \(error.localizedDescription)", category: .network)
        }
    }
    
    /// Get the device model name
    private func getDeviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }
    
    /// Log an individual field's value at a specific stage (collected, sent_to_db, verified_in_db)
    func logOnboardingField(
        fieldName: String,
        stage: String, // "collected", "sent_to_db", "verified_in_db"
        value: Any?,
        rawInput: String? = nil,
        convertedValue: String? = nil,
        sessionId: String? = nil
    ) async {
        do {
            // Determine field type and string value
            let (fieldValue, fieldType) = stringifyValue(value)
            
            // Get device info
            let deviceInfo: [String: Any] = [
                "device_model": getDeviceModel(),
                "os_version": UIDevice.current.systemVersion,
                "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                "locale": Locale.current.identifier,
                "timezone": TimeZone.current.identifier,
                "region": Locale.current.region?.identifier ?? "unknown"
            ]
            
            var params: [String: Any] = [
                "p_field_name": fieldName,
                "p_stage": stage,
                "p_field_type": fieldType,
                "p_device_info": deviceInfo
            ]
            
            if let userId = currentUser?.id {
                params["p_user_id"] = userId.uuidString
            }
            
            if let sessionId = sessionId ?? OnboardingSessionManager.shared.currentSessionId {
                params["p_session_id"] = sessionId
            }
            
            if let fieldValue = fieldValue {
                params["p_field_value"] = fieldValue
            }
            
            if let rawInput = rawInput {
                params["p_raw_input"] = rawInput
            }
            
            if let convertedValue = convertedValue {
                params["p_converted_value"] = convertedValue
            }
            
            try await client.rpc("log_onboarding_field", params: params.toEncodable()).execute()
            
            let valueDesc = fieldValue ?? "NULL"
            AppLogger.debug("[FIELD LOG] \(fieldName) @ \(stage): \(valueDesc)", category: .network)
        } catch {
            AppLogger.warning("[FIELD LOG] Failed: \(error.localizedDescription)", category: .network)
        }
    }
    
    /// Convert any value to a string representation for logging
    private func stringifyValue(_ value: Any?) -> (String?, String) {
        guard let value = value else {
            return (nil, "null")
        }
        
        if let str = value as? String {
            return (str.isEmpty ? nil : str, "string")
        } else if let num = value as? Int {
            return (String(num), "number")
        } else if let num = value as? Int16 {
            return (String(num), "number")
        } else if let num = value as? Double {
            return (String(num), "number")
        } else if let arr = value as? [String] {
            return (arr.isEmpty ? nil : arr.joined(separator: ", "), "array")
        } else if let bool = value as? Bool {
            return (String(bool), "boolean")
        } else {
            return (String(describing: value), "unknown")
        }
    }
    
    /// Verify what's actually saved in the database and log it
    func verifyAndLogSavedProfile() async {
        guard let userId = currentUser?.id else { return }
        
        do {
            struct ProfileRow: Decodable {
                let name: String?
                let email: String?
                let username: String?
                let age: Int?
                let gender: String?
                let height_cm: Double?
                let weight_kg: Double?
                let fitness_goal: String?
                let experience_level: String?
                let equipment: [String]?
                let available_days: Int?
                let workout_environment: String?
                let birthday: String?
            }
            
            let response: ProfileRow = try await client
                .from("user_profiles")
                .select("name, email, username, age, gender, height_cm, weight_kg, fitness_goal, experience_level, equipment, available_days, workout_environment, birthday")
                .eq("id", value: userId.uuidString)
                .single()
                .execute()
                .value
            
            // Log each field as verified in DB
            let fieldsToVerify: [(String, Any?)] = [
                ("name", response.name),
                ("email", response.email),
                ("username", response.username),
                ("age", response.age),
                ("gender", response.gender),
                ("height_cm", response.height_cm),
                ("weight_kg", response.weight_kg),
                ("fitness_goal", response.fitness_goal),
                ("experience_level", response.experience_level),
                ("equipment", response.equipment),
                ("available_days", response.available_days),
                ("workout_environment", response.workout_environment),
                ("birthday", response.birthday)
            ]
            
            for (fieldName, fieldValue) in fieldsToVerify {
                await logOnboardingField(
                    fieldName: fieldName,
                    stage: "verified_in_db",
                    value: fieldValue
                )
            }
            
            AppLogger.info("[VERIFY] Logged all verified field values from database", category: .network)
            
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "[VERIFY] Failed to verify saved profile",
                category: .network,
                op: PerformanceSignposts.Op.profileRead.rawValue,
                endpoint: "user_profiles(select verify)",
                userId: currentUser?.id
            )
            await logOnboardingEvent(
                eventType: "error",
                stepName: "verify_profile",
                errorMessage: "Failed to read back profile: \(error.localizedDescription)"
            )
        }
    }
    
    // MARK: - User Profile
    
    private func createUserProfile(userId: UUID, name: String, email: String, hasCompletedOnboarding: Bool = false) async throws {
        // Use SECURITY DEFINER function to bypass RLS during signup
        // This fixes the "database error saving new user" issue
        struct CreateProfileParams: Encodable {
            let user_id: String
            let user_name: String
            let user_email: String
        }
        
        let params = CreateProfileParams(
            user_id: userId.uuidString,
            user_name: name,
            user_email: email
        )
        
        do {
            // Try using the secure RPC function first
            try await client.rpc("create_user_profile", params: params).execute()
            AppLogger.info("User profile created via RPC function", category: .network)
        } catch {
            // Fallback to direct insert if RPC function doesn't exist
            AppLogger.warning("RPC function not available, trying direct insert: \(error.localizedDescription)", category: .network)
            
            struct ProfileInsert: Encodable {
                let id: String
                let name: String
                let email: String
                let has_completed_onboarding: Bool
            }
            
            let profile = ProfileInsert(
                id: userId.uuidString,
                name: name,
                email: email,
                has_completed_onboarding: hasCompletedOnboarding
            )
            
            // Use upsert to handle edge cases where profile might partially exist
            try await client
                .from("user_profiles")
                .upsert(profile, onConflict: "id")
                .execute()
        }
        
        // Create initial progress record (also uses upsert)
        try await createUserProgress(userId: userId)
        
        AppLogger.info("User profile created (onboarding: \(hasCompletedOnboarding ? "complete" : "pending"))", category: .network)
    }
    
    /// Public helper: ensure a profile row exists for a user (idempotent upsert).
    /// Used to recover from partial signup failures where auth user was created but profile wasn't.
    func ensureProfileExists(userId: UUID, name: String, email: String) async throws {
        try await createUserProfile(userId: userId, name: name, email: email)
    }
    
    // MARK: - Activity & Integration Tracking
    
    /// Update last login timestamp - call when app opens
    func updateLastLogin() async {
        guard let userId = currentUser?.id else { return }
        
        do {
            try await client.rpc("update_last_login", params: ["p_user_id": userId.uuidString]).execute()
            AppLogger.info("[ACTIVITY] Updated last login timestamp", category: .network)
        } catch {
            // Fallback to direct update if RPC doesn't exist
            do {
                struct LastLoginUpdate: Encodable {
                    let last_login_at: String
                }
                
                let update = LastLoginUpdate(last_login_at: iso8601Formatter.string(from: Date()))
                
                try await client
                    .from("user_profiles")
                    .update(update)
                    .eq("id", value: userId.uuidString)
                    .execute()
                AppLogger.info("[ACTIVITY] Updated last login timestamp (direct)", category: .network)
            } catch {
                AppLogger.warning("[ACTIVITY] Failed to update last login: \(error.localizedDescription)", category: .network)
            }
        }
    }
    
    /// Update integration connection status
    func updateIntegrationStatus(integration: String, isConnected: Bool) async {
        guard let userId = currentUser?.id else { return }
        
        // Use direct update (simpler and more reliable than RPC for this use case)
        do {
            let columnName: String
            switch integration {
            case "strava": columnName = "is_strava_connected"
            case "fitbit": columnName = "is_fitbit_connected"
            case "apple_health": columnName = "is_apple_health_connected"
            case "inbody": columnName = "is_inbody_connected"
            case "whoop": columnName = "is_whoop_connected"
            case "oura": columnName = "is_oura_connected"
            default:
                AppLogger.warning("[INTEGRATIONS] Unknown integration: \(integration)", category: .network)
                return
            }

            struct IntegrationUpdate: Encodable {
                let is_strava_connected: Bool?
                let is_fitbit_connected: Bool?
                let is_apple_health_connected: Bool?
                let is_inbody_connected: Bool?
                let is_whoop_connected: Bool?
                let is_oura_connected: Bool?
            }

            let update = IntegrationUpdate(
                is_strava_connected: integration == "strava" ? isConnected : nil,
                is_fitbit_connected: integration == "fitbit" ? isConnected : nil,
                is_apple_health_connected: integration == "apple_health" ? isConnected : nil,
                is_inbody_connected: integration == "inbody" ? isConnected : nil,
                is_whoop_connected: integration == "whoop" ? isConnected : nil,
                is_oura_connected: integration == "oura" ? isConnected : nil
            )
            
            try await client
                .from("user_profiles")
                .update(update)
                .eq("id", value: userId.uuidString)
                .execute()
            AppLogger.info("[INTEGRATIONS] Updated \(integration) status to \(isConnected)", category: .network)
        } catch {
            AppLogger.warning("[INTEGRATIONS] Failed to update \(integration) status: \(error.localizedDescription)", category: .network)
        }
    }
    
    /// Update all integration statuses at once (called on app launch)
    func syncAllIntegrationStatuses() async {
        guard let userId = currentUser?.id else { return }

        let (stravaConnected, fitbitConnected, appleHealthConnected, inbodyConnected, whoopConnected, ouraConnected) = await MainActor.run {
            (
                StravaService.shared.isConnected,
                FitbitService.shared.isConnected,
                HealthKitManager.shared.isAuthorized,
                InBodyService.shared.isConnected,
                WhoopService.shared.isConnected,
                OuraService.shared.isConnected
            )
        }

        // CRITICAL — DO NOT overwrite OAuth integration statuses with `false` from
        // this launch-time bulk path. iOS keychain entries for OAuth tokens
        // (WHOOP/Oura/Strava/Fitbit) sometimes get cleared on app uninstall/
        // reinstall — Apple's documented post-iOS-10.3 behavior is "may be
        // removed", in practice it's variable per service per device. The
        // logs from a real reinstall show this clearly: same launch, same
        // device, Strava SURVIVED (`Strava: true`) while WHOOP + Oura were
        // wiped (`WHOOP: false, Oura: false`). When we blindly pushed the
        // local `false` to Supabase, we destroyed the cloud signal "this
        // user has WHOOP/Oura linked", which (a) corrupted analytics + Bug
        // Intel rollups that key off integration capability, (b) prevented
        // any "you lost your token, tap to reconnect" prompt because by the
        // time UI runs the cloud already agrees user is disconnected, (c)
        // misdirected silent-push and edge-function targeting that decides
        // routing based on `is_whoop_connected`. Empty local state is NOT
        // proof of user intent to disconnect.
        //
        // Rule: this bulk-launch path is ADDITIVE for OAuth services — only
        // pushes `true` (catches up missed connect-time writes). The
        // canonical `false` writers are the explicit user paths
        // (`WhoopService.disconnect()` / `OuraService.disconnect()` /
        // `StravaService.disconnect()` / `FitbitService.disconnect()` —
        // they each call `updateIntegrationStatus(integration:isConnected:false)`
        // in-line). Apple Health + InBody push their actual state because
        // those aren't OAuth — Apple Health is HealthKit runtime auth (can
        // legitimately revoke per-launch), InBody is BLE pairing.
        struct CoreIntegrationUpdate: Encodable {
            let is_strava_connected: Bool?
            let is_fitbit_connected: Bool?
            let is_apple_health_connected: Bool?
            let is_inbody_connected: Bool?
            let is_whoop_connected: Bool?
        }

        do {
            try await client
                .from("user_profiles")
                .update(CoreIntegrationUpdate(
                    is_strava_connected: stravaConnected ? true : nil,
                    is_fitbit_connected: fitbitConnected ? true : nil,
                    is_apple_health_connected: appleHealthConnected,
                    is_inbody_connected: inbodyConnected,
                    is_whoop_connected: whoopConnected ? true : nil
                ))
                .eq("id", value: userId.uuidString)
                .execute()
        } catch {
            AppLogger.warning("[INTEGRATIONS] Failed to sync core statuses: \(error.localizedDescription)", category: .network)
        }

        // Oura column requires migration 20260328_oura_integration.sql — sync separately.
        // Same additive rule: only push `true` so a reinstall that wiped the
        // Oura keychain doesn't destroy the cloud signal.
        if ouraConnected {
            do {
                struct OuraUpdate: Encodable { let is_oura_connected: Bool }
                try await client
                    .from("user_profiles")
                    .update(OuraUpdate(is_oura_connected: true))
                    .eq("id", value: userId.uuidString)
                    .execute()
                AppLogger.info("[INTEGRATIONS] Updated oura status to true", category: .network)
            } catch {
                AppLogger.debug("[INTEGRATIONS] Oura column not available yet (run 20260328_oura_integration.sql): \(error.localizedDescription)", category: .network)
            }
        }

        AppLogger.info("[INTEGRATIONS] Synced all integration statuses (additive for OAuth) - Strava: \(stravaConnected), Fitbit: \(fitbitConnected), Apple Health: \(appleHealthConnected), InBody: \(inbodyConnected), WHOOP: \(whoopConnected), Oura: \(ouraConnected)", category: .network)
    }
    
    /// Public function to create user profile for OAuth users when they complete onboarding
    /// This should be called when the user taps "Create Account" at the end of onboarding
    /// Only creates the profile if the user is authenticated via OAuth but doesn't have a profile yet
    func createProfileForOAuthUser(
        name: String,
        email: String,
        username: String?,
        birthday: String?,  // Added: birthday string (e.g., "26/10/1996")
        age: Int?,
        gender: String?,
        heightCm: Double?,
        weightKg: Double?,
        fitnessGoal: String?,
        experienceLevel: String?,
        equipment: [String]?,
        availableDays: Int?,
        workoutEnvironment: String?,
        phoneNumber: String? = nil  // For 2FA / account security (private)
    ) async throws {
        guard let userId = currentUser?.id else {
            AppLogger.error("[PROFILE] Cannot create profile - no authenticated user", category: .network)
            throw NSError(domain: "SupabaseManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Check if profile already exists (safety check)
        var profileCheck = await verifyUserProfile(userId: userId)
        if case .transientFailure = profileCheck {
            try? await Task.sleep(for: .milliseconds(800))
            profileCheck = await verifyUserProfile(userId: userId)
        }
        if case .valid = profileCheck {
            AppLogger.warning("[PROFILE] Profile already exists for user \(userId), updating instead", category: .network)
            try await updateUserProfile(
                name: name,
                heightCm: heightCm,
                weightKg: weightKg,
                fitnessGoal: fitnessGoal,
                experienceLevel: experienceLevel,
                equipment: equipment,
                availableDays: availableDays,
                workoutEnvironment: workoutEnvironment,
                birthday: birthday,  // Include birthday in update
                age: age,
                gender: gender
            )
            // Also set username if provided
            if let username = username {
                try await setUsername(username)
            }
            // Mark onboarding as complete
            try await client
                .from("user_profiles")
                .update(["has_completed_onboarding": true])
                .eq("id", value: userId.uuidString)
                .execute()
            // Stamp the push timestamp so the admin-CMS guard in
            // syncCoreDataProfile() recognizes that this device just wrote
            // the row (and won't immediately re-pull a stale read on the
            // very next sync cycle).
            UserDefaults.standard.set(Date(), forKey: SupabaseManager.lastProfilePushKey)
            return
        }
        
        AppLogger.debug("[PROFILE] Creating profile for OAuth user at end of onboarding...", category: .network)
        AppLogger.debug("[PROFILE] User ID: \(userId), Name: \(name), Email: \(email)", category: .network)
        
        // Create the full profile with all onboarding data
        struct OAuthProfileInsert: Encodable {
            let id: String
            let name: String
            let email: String
            let phone_number: String?  // For 2FA / account security (private)
            let phone_verified: Bool  // Whether phone was verified during onboarding
            let username: String?
            let birthday: String?  // Birthday string (e.g., "26/10/1996" or "1996-10-26")
            let age: Int?
            let gender: String?
            let height_cm: Double?
            let weight_kg: Double?
            let fitness_goal: String?
            let experience_level: String?
            let equipment: [String]?
            let available_days: Int?
            let workout_environment: String?
            let has_completed_onboarding: Bool
        }
        
        let profile = OAuthProfileInsert(
            id: userId.uuidString,
            name: name,
            email: email,
            phone_number: phoneNumber,  // 2FA phone number (private)
            phone_verified: phoneNumber != nil,  // true if phone provided = verified during onboarding
            username: username,
            birthday: birthday,  // Birthday string from onboarding
            age: age,
            gender: gender,
            height_cm: heightCm,
            weight_kg: weightKg,
            fitness_goal: fitnessGoal,
            experience_level: experienceLevel,
            equipment: equipment,
            available_days: availableDays,
            workout_environment: workoutEnvironment,
            has_completed_onboarding: true  // Profile created at end of onboarding = complete
        )
        
        // Log the upsert attempt with all data for debugging
        AppLogger.debug("[PROFILE] Attempting upsert with data: id=\(userId.uuidString), name=\(name), email=\(email), phone=\(phoneNumber ?? "nil"), username=\(username ?? "nil"), birthday=\(birthday ?? "nil"), age=\(age ?? 0), gender=\(gender ?? "nil"), height_cm=\(heightCm ?? 0), weight_kg=\(weightKg ?? 0), fitness_goal=\(fitnessGoal ?? "nil"), experience_level=\(experienceLevel ?? "nil"), equipment=\(equipment ?? []), available_days=\(availableDays ?? 0), workout_environment=\(workoutEnvironment ?? "nil")", category: .network)
        
        do {
            try await client
                .from("user_profiles")
                .upsert(profile, onConflict: "id")
                .execute()
            AppLogger.info("[PROFILE] Upsert to user_profiles succeeded", category: .network)
            // Stamp the push timestamp so the admin-CMS guard in
            // syncCoreDataProfile() recognizes that this device just wrote
            // the row.
            UserDefaults.standard.set(Date(), forKey: SupabaseManager.lastProfilePushKey)
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "[PROFILE] Upsert FAILED",
                category: .network,
                op: PerformanceSignposts.Op.profileWrite.rawValue,
                endpoint: "user_profiles(upsert)",
                userId: userId
            )
            
            // Log the error to the onboarding_logs table
            await logOnboardingEvent(
                eventType: "profile_update_error",
                stepName: "createProfileForOAuthUser",
                eventData: [
                    "user_id": userId.uuidString,
                    "name": name,
                    "email": email,
                    "attempted_action": "upsert"
                ],
                errorMessage: error.localizedDescription
            )
            
            throw error
        }
        
        // Create initial progress record
        do {
            try await createUserProgress(userId: userId)
            AppLogger.info("[PROFILE] User progress record created", category: .network)
        } catch {
            AppLogger.warning("[PROFILE] Failed to create user progress (non-fatal): \(error.localizedDescription)", category: .network)
            // Don't throw - profile was created successfully
        }
        
        // Clear the pending OAuth data from UserDefaults
        await MainActor.run {
            UserDefaults.standard.removeObject(forKey: "pending_oauth_name")
            UserDefaults.standard.removeObject(forKey: "pending_oauth_email")
            UserDefaults.standard.removeObject(forKey: "pending_oauth_avatar")
        }
        
        AppLogger.info("[PROFILE] OAuth user profile created successfully with all onboarding data!", category: .network)
    }
    
    func updateUserProfile(
        name: String?,
        heightCm: Double?,
        weightKg: Double?,
        fitnessGoal: String?,
        experienceLevel: String?,
        equipment: [String]? = nil,
        availableDays: Int? = nil,
        workoutEnvironment: String? = nil,
        birthday: String? = nil,  // Added: birthday string
        age: Int? = nil,
        gender: String? = nil
    ) async throws {
        guard let userId = currentUser?.id else { return }
        
        struct ProfileUpdate: Encodable {
            let name: String?
            let height_cm: Double?
            let weight_kg: Double?
            let fitness_goal: String?
            let experience_level: String?
            let equipment: [String]?
            let available_days: Int?
            let workout_environment: String?
            let birthday: String?
            let age: Int?
            let gender: String?
            let updated_at: String
        }
        
        let update = ProfileUpdate(
            name: name,
            height_cm: heightCm,
            weight_kg: weightKg,
            fitness_goal: fitnessGoal,
            experience_level: experienceLevel,
            equipment: equipment,
            available_days: availableDays,
            workout_environment: workoutEnvironment,
            birthday: birthday,
            age: age,
            gender: gender,
            updated_at: dateToISO(Date())
        )
        
        try await client
            .from("user_profiles")
            .update(update)
            .eq("id", value: userId.uuidString)
            .execute()
        
        AppLogger.info("User profile updated - Equipment: \(equipment ?? []), Days: \(availableDays ?? 0)", category: .network)
    }
    
    // MARK: - Last Active Tracking

    private var lastActiveRecordedAt: Date?

    func recordLastActive() async {
        guard let userId = currentUser?.id else { return }

        if let last = lastActiveRecordedAt, Date().timeIntervalSince(last) < 60 { return }
        lastActiveRecordedAt = Date()

        do {
            try await client
                .from("user_profiles")
                .update(["last_active_at": dateToISO(Date())])
                .eq("id", value: userId.uuidString)
                .execute()
        } catch {
            AppLogger.warning("Failed to record last_active_at: \(error.localizedDescription)", category: .network)
        }
    }

    // MARK: - Phone Number
    
    /// Update phone number for existing user (used for contact matching & 2FA)
    /// Sets phone_verified = true in database after successful verification
    func updatePhoneNumber(_ phoneNumber: String) async throws {
        guard let userId = currentUser?.id else {
            AppLogger.error("[PHONE] Cannot update phone - no authenticated user", category: .network)
            throw NSError(domain: "SupabaseManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        struct PhoneUpdate: Encodable {
            let phone_number: String
            let phone_verified: Bool
            let updated_at: String
        }
        
        let update = PhoneUpdate(
            phone_number: phoneNumber,
            phone_verified: true,  // Mark as verified since this is called after successful verification
            updated_at: dateToISO(Date())
        )
        
        try await client
            .from("user_profiles")
            .update(update)
            .eq("id", value: userId.uuidString)
            .execute()
        
        AppLogger.info("[PHONE] Phone number updated and marked as verified for user: \(phoneNumber)", category: .network)
    }
    
    /// Check if current user has a phone number saved
    func getUserPhoneNumber() async -> String? {
        guard let userId = currentUser?.id else { return nil }
        
        do {
            let result: [PhoneResult] = try await client
                .from("user_profiles")
                .select("phone_number")
                .eq("id", value: userId.uuidString)
                .execute()
                .value
            
            return result.first?.phone_number
        } catch {
            AppLogger.warning("[PHONE] Error fetching phone number: \(error)", category: .network)
            return nil
        }
    }
    
    private struct PhoneResult: Decodable {
        let phone_number: String?
    }
    
    // MARK: - Profile Photo
    
    /// Upload a profile photo and update the user profile with the URL
    func uploadProfilePhoto(imageData: Data) async throws -> String {
        guard let userId = currentUser?.id else {
            throw NSError(domain: "SupabaseManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No user logged in"])
        }
        
        let fileName = "profile_photos/\(userId.uuidString).jpg"
        let bucket = "avatars"
        
        // Upload to Supabase Storage
        try await client.storage
            .from(bucket)
            .upload(
                path: fileName,
                file: imageData,
                options: FileOptions(
                    cacheControl: "3600",
                    contentType: "image/jpeg",
                    upsert: true
                )
            )
        
        // Get the public URL
        let publicUrl = try client.storage
            .from(bucket)
            .getPublicURL(path: fileName)
        
        // Update the user profile with the photo URL using RPC (handles UUID casting)
        do {
            let success: Bool = try await client
                .rpc("set_profile_photo_for_user", params: [
                    "p_user_id": userId.uuidString,
                    "p_photo_url": publicUrl.absoluteString
                ])
                .execute()
                .value
            
            if success {
                AppLogger.info("Profile photo uploaded via RPC: \(publicUrl.absoluteString)", category: .network)
            } else {
                AppLogger.warning("RPC returned false, trying direct update...", category: .network)
                throw NSError(domain: "SupabaseManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "RPC returned false"])
            }
        } catch {
            // Fallback to direct update
            AppLogger.warning("Profile photo RPC failed: \(error.localizedDescription), trying direct update...", category: .network)
            struct PhotoUpdate: Encodable {
                let profile_photo_url: String
                let updated_at: String
            }
            
            let update = PhotoUpdate(
                profile_photo_url: publicUrl.absoluteString,
                updated_at: dateToISO(Date())
            )
            
            try await client
                .from("user_profiles")
                .update(update)
                .eq("id", value: userId.uuidString)
                .execute()
            
            AppLogger.info("Profile photo uploaded via direct update: \(publicUrl.absoluteString)", category: .network)
        }
        return publicUrl.absoluteString
    }
    
    /// Delete the current profile photo
    func deleteProfilePhoto() async throws {
        guard let userId = currentUser?.id else { return }
        
        let fileName = "profile_photos/\(userId.uuidString).jpg"
        let bucket = "avatars"
        
        // Delete from storage
        try await client.storage
            .from(bucket)
            .remove(paths: [fileName])
        
        // Update the user profile to remove the photo URL
        struct PhotoUpdate: Encodable {
            let profile_photo_url: String?
            let updated_at: String
        }
        
        let update = PhotoUpdate(
            profile_photo_url: nil,
            updated_at: dateToISO(Date())
        )
        
        try await client
            .from("user_profiles")
            .update(update)
            .eq("id", value: userId.uuidString)
            .execute()
        
        AppLogger.info("Profile photo deleted", category: .network)
    }
    
    /// Mark onboarding as complete in the cloud
    func markOnboardingComplete() async throws {
        guard let userId = currentUser?.id else { return }
        
        struct OnboardingUpdate: Encodable {
            let has_completed_onboarding: Bool
            let updated_at: String
        }
        
        let update = OnboardingUpdate(
            has_completed_onboarding: true,
            updated_at: dateToISO(Date())
        )
        
        try await client
            .from("user_profiles")
            .update(update)
            .eq("id", value: userId.uuidString)
            .execute()
        
        AppLogger.info("Onboarding marked as complete in cloud", category: .network)
    }
    
    // MARK: - Username Management
    
    /// Check if a username is available (case-insensitive)
    func isUsernameAvailable(_ username: String) async throws -> Bool {
        // Client-side validation first
        let cleanUsername = username.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard cleanUsername.count >= 3 else { return false }
        guard cleanUsername.count <= 30 else { return false }
        
        // Check alphanumeric + underscore only
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        guard cleanUsername.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }) else {
            return false
        }
        
        // Check with database
        let result: Bool = try await client
            .rpc("is_username_available", params: ["check_username": cleanUsername])
            .execute()
            .value
        
        return result
    }
    
    /// Set the username for the current user
    func setUsername(_ username: String) async throws {
        AppLogger.debug("[USERNAME] SET USERNAME START - Input: '\(username)'", category: .network)
        
        guard let user = currentUser else {
            AppLogger.error("[USERNAME] Not authenticated - currentUser is nil", category: .network)
            throw NSError(domain: "SupabaseManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        AppLogger.debug("[USERNAME] Current user ID: \(user.id.uuidString), email: \(user.email ?? "nil")", category: .network)
        
        // Debug: Check profile state before setting username
        await debugProfileState()
        
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        AppLogger.debug("[USERNAME] Cleaned username: '\(cleanUsername)'", category: .network)
        
        // Validate on client side first
        guard cleanUsername.count >= 3 else {
            AppLogger.error("[USERNAME] Username too short: \(cleanUsername.count) chars", category: .network)
            throw NSError(domain: "SupabaseManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Username must be at least 3 characters"])
        }
        
        var rpcSucceeded = false
        
        // Try RPC with user_id parameter (handles UUID casting internally)
        do {
            AppLogger.debug("[USERNAME] Trying Method 1: RPC set_username_for_user with user_id: '\(user.id.uuidString)', username: '\(cleanUsername)'", category: .network)
            let success: Bool = try await client
                .rpc("set_username_for_user", params: [
                    "p_user_id": user.id.uuidString,
                    "p_username": cleanUsername
                ])
                .execute()
                .value
            
            AppLogger.debug("[USERNAME] RPC returned: \(success)", category: .network)
            
            if success {
                rpcSucceeded = true
                AppLogger.info("[USERNAME] RPC success!", category: .network)
            } else {
                AppLogger.warning("[USERNAME] RPC returned false, will try fallback...", category: .network)
            }
            
        } catch {
            AppLogger.warning("[USERNAME] RPC set_username_for_user failed: \(error.localizedDescription)", category: .network)
            
            // Try the original set_username as fallback
            do {
                AppLogger.debug("[USERNAME] Trying Method 2: RPC set_username (auth.uid based)", category: .network)
                let success: Bool = try await client
                    .rpc("set_username", params: ["new_username": cleanUsername])
                    .execute()
                    .value
                
                if success {
                    rpcSucceeded = true
                    AppLogger.info("[USERNAME] Fallback RPC success!", category: .network)
                }
            } catch {
                AppLogger.warning("[USERNAME] Fallback RPC also failed: \(error.localizedDescription)", category: .network)
            }
        }
        
        // Fallback: Direct table update if RPC failed
        if !rpcSucceeded {
            do {
                AppLogger.debug("[USERNAME] Trying Method 3: Direct table update", category: .network)
                
                try await client
                    .from("user_profiles")
                    .update(["username": cleanUsername])
                    .eq("id", value: user.id.uuidString)
                    .execute()
                
                AppLogger.info("[USERNAME] Direct update executed", category: .network)
                
            } catch {
                _ = NetworkErrorClassifier.log(
                    error,
                    context: "[USERNAME] Direct update also failed",
                    category: .network,
                    op: PerformanceSignposts.Op.usernameWrite.rawValue,
                    endpoint: "user_profiles(update username)",
                    userId: user.id
                )
                throw error
            }
        }
        
        // Verify the username was actually saved
        AppLogger.debug("[USERNAME] Verifying save...", category: .network)
        let savedUsername = try await getCurrentUsername()
        if savedUsername == cleanUsername {
            AppLogger.info("[USERNAME] VERIFIED: Username saved as '@\(cleanUsername)'", category: .network)
        } else if let saved = savedUsername {
            AppLogger.warning("[USERNAME] Mismatch! Expected '\(cleanUsername)' but got '\(saved)'", category: .network)
        } else {
            AppLogger.error("[USERNAME] FAILED: Username is still NULL after save attempt!", category: .network)
            throw NSError(domain: "SupabaseManager", code: 4, userInfo: [NSLocalizedDescriptionKey: "Username failed to save to database"])
        }
        
        AppLogger.debug("[USERNAME] SET USERNAME END", category: .network)
    }
    
    /// Get the current user's username
    func getCurrentUsername() async throws -> String? {
        guard let userId = currentUser?.id else { return nil }
        
        struct UsernameResult: Decodable {
            let username: String?
        }
        
        let response: [UsernameResult] = try await client
            .from("user_profiles")
            .select("username")
            .eq("id", value: userId.uuidString)
            .execute()
            .value
        
        return response.first?.username
    }
    
    /// Debug: Check profile state and username
    func debugProfileState() async {
        AppLogger.debug("[DEBUG] PROFILE STATE CHECK", category: .network)
        
        guard let user = currentUser else {
            AppLogger.error("[DEBUG] No current user - not authenticated", category: .network)
            return
        }
        
        AppLogger.debug("[DEBUG] Current User ID: \(user.id.uuidString), Email: \(user.email ?? "nil"), Is Authenticated: \(isAuthenticated)", category: .network)
        
        // Check if profile exists
        do {
            struct ProfileCheck: Decodable {
                let id: String
                let username: String?
                let name: String?
                let email: String?
                let has_completed_onboarding: Bool?
            }
            
            let profiles: [ProfileCheck] = try await client
                .from("user_profiles")
                .select("id, username, name, email, has_completed_onboarding")
                .eq("id", value: user.id.uuidString)
                .execute()
                .value
            
            if let profile = profiles.first {
                AppLogger.debug("[DEBUG] Profile EXISTS in database: ID=\(profile.id), Username=\(profile.username ?? "NULL"), Name=\(profile.name ?? "NULL"), Email=\(profile.email ?? "NULL"), Onboarding Complete=\(profile.has_completed_onboarding ?? false)", category: .network)
            } else {
                AppLogger.error("[DEBUG] Profile NOT FOUND in user_profiles table! Searched for id = '\(user.id.uuidString)'", category: .network)
            }
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "[DEBUG] Failed to query profile",
                category: .network,
                op: PerformanceSignposts.Op.profileRead.rawValue,
                endpoint: "user_profiles(select debug)",
                userId: user.id
            )
        }
        
        AppLogger.debug("[DEBUG] PROFILE STATE CHECK END", category: .network)
    }
    
    func fetchUserProfile() async throws -> UserProfileDTO? {
        guard let userId = currentUser?.id else { return nil }
        
        let response: [UserProfileDTO] = try await client
            .from("user_profiles")
            .select()
            .eq("id", value: userId.uuidString)
            .execute()
            .value
        
        return response.first
    }
    
    // MARK: - Profile Sync from Core Data
    
    /// Tracks when the app last pushed a profile to cloud, so we can detect CMS/admin edits
    private static let lastProfilePushKey = "lastProfilePushTime"
    
    /// Syncs the local Core Data user profile to Supabase cloud
    /// Uses UPSERT to ensure data is saved even if profile row is missing or empty
    /// ⚠️ IMPORTANT: Checks cloud updated_at first to avoid overwriting admin CMS changes
    func syncCoreDataProfile(from user: User) async throws {
        guard let authUser = currentUser else {
            AppLogger.warning("[SYNC] No authenticated Supabase user - cannot sync profile", category: .network)
            return
        }
        
        AppLogger.debug("[SYNC] Starting profile sync for user: \(authUser.id.uuidString)", category: .network)
        AppLogger.debug("[SYNC] Core Data user: name=\(user.name ?? "nil"), email=\(user.email ?? "nil")", category: .network)
        
        // ═══════════════════════════════════════════════════════════════════
        // ADMIN CMS GUARD: Check if cloud was updated more recently by admin
        // If so, pull from cloud instead of pushing (prevents overwriting CMS edits)
        //
        // ⚠️ IMPORTANT: On the FIRST push for a new account (`lastPushTime ==
        // .distantPast`), the cloud row was either just created by `signUp()`
        // with a placeholder name="User" or by `createProfileForOAuthUser`.
        // The CMS could not have edited it yet, so the local Core Data write
        // (which carries the real onboarding values) MUST win. Skipping the
        // guard on the first push prevents the email/password race where a
        // stale cloud read overwrites the user's real name with "User".
        // ═══════════════════════════════════════════════════════════════════
        let lastPushTime = UserDefaults.standard.object(forKey: SupabaseManager.lastProfilePushKey) as? Date ?? Date.distantPast
        let isFirstPush = lastPushTime == .distantPast

        if !isFirstPush, let cloudProfile = try? await fetchUserProfile() {
            AppLogger.debug("[SYNC] Cloud profile verified=\(cloudProfile.isVerified ?? false), goldVerified=\(cloudProfile.isGoldVerified ?? false)", category: .network)
            await MainActor.run {
                UserManager.shared.isVerified = cloudProfile.isVerified ?? false
                UserManager.shared.isGoldVerified = cloudProfile.isGoldVerified ?? false
            }

            if let cloudUpdatedStr = cloudProfile.updatedAt {
                // Parse the cloud updated_at timestamp (try fractional seconds first, fall back to plain)
                if let cloudUpdated = iso8601Fractional.date(from: cloudUpdatedStr) ?? iso8601Formatter.date(from: cloudUpdatedStr) {
                    if cloudUpdated > lastPushTime {
                        AppLogger.debug("[SYNC] Cloud profile is newer than last push (\(cloudUpdatedStr) > \(lastPushTime))", category: .network)
                        AppLogger.debug("[SYNC] Likely updated by admin CMS — pulling from cloud instead of pushing", category: .network)
                        await syncUserProfileToCoreData(profile: cloudProfile)
                        // Update last push time so we don't keep pulling every sync cycle
                        UserDefaults.standard.set(Date(), forKey: SupabaseManager.lastProfilePushKey)
                        return
                    }
                }
            }
        } else if isFirstPush {
            AppLogger.info("[SYNC] First push for this account (no prior pushes recorded) — bypassing admin-CMS guard so onboarding values win the race against signup-time placeholders", category: .network)
        }
        
        struct ProfileSync: Encodable {
            let name: String?
            let email: String?
            let phone_number: String?  // For 2FA / account security (private, not displayed)
            let phone_verified: Bool  // Whether phone was verified
            let birthday: String?
            let age: Int?
            let gender: String?
            let height_cm: Double?
            let height_inches: Int?
            let weight_kg: Double?
            let weight_lbs: Double?
            let fitness_goal: String?
            let experience_level: String?
            let strength_level: String?  // Smart recommendation strength assessment
            let workout_environment: String?  // Gym, Home, Outdoor, Hybrid
            let equipment: [String]?
            let available_days: Int?
            let current_streak: Int?
            let longest_streak: Int?
            let total_workouts: Int?
            let xp: Int?
            let last_workout_date: String?
            let updated_at: String
            // Unit preferences
            let weight_unit: String?
            let height_unit: String?
            let distance_unit: String?
            let week_start_day: String?
        }
        
        // Get equipment array from User
        let equipmentArray = user.getEquipment() ?? []
        
        // Get unit preferences from UnitSettingsManager
        let unitSettings = UnitSettingsManager.shared
        
        let profile = ProfileSync(
            name: user.name,
            email: user.email,
            phone_number: user.phoneNumber,  // 2FA phone number (private)
            phone_verified: user.phoneNumber != nil && !(user.phoneNumber?.isEmpty ?? true),  // true if phone exists and not empty
            birthday: birthdayToISO(user.birthday),  // Convert to ISO format for database
            age: Int(user.age),
            gender: user.gender,
            height_cm: Double(user.height),
            height_inches: Int(user.heightInches),
            weight_kg: Double(user.weight),
            weight_lbs: user.weightLbs,
            fitness_goal: user.fitnessGoal,
            experience_level: user.experienceLevel,
            strength_level: user.strengthLevel,  // For smart weight recommendations
            workout_environment: user.workoutEnvironment,  // Gym, Home, Outdoor, Hybrid
            equipment: equipmentArray.isEmpty ? nil : equipmentArray,
            available_days: Int(user.availableDays),
            current_streak: Int(user.currentStreak),
            longest_streak: Int(user.longestStreak),
            total_workouts: Int(user.totalWorkouts),
            xp: Int(user.xp),
            last_workout_date: user.lastWorkoutDate.map { dateToISO($0) },
            updated_at: dateToISO(Date()),
            weight_unit: unitSettings.weightUnit.rawValue,
            height_unit: unitSettings.heightUnit.rawValue,
            distance_unit: unitSettings.distanceUnit.rawValue,
            week_start_day: unitSettings.startWeekOn.rawValue
        )
        
        guard let userId = currentUser?.id else { 
            AppLogger.error("[SYNC] No authenticated user ID - cannot sync profile", category: .network)
            return 
        }
        
        // Use UPSERT instead of UPDATE to ensure data is saved even if profile doesn't exist
        // This fixes the issue where UPDATE silently fails if no matching row exists
        struct ProfileUpsert: Encodable {
            let id: String
            let name: String?
            let email: String?
            let phone_number: String?  // For 2FA / account security (private)
            let phone_verified: Bool  // Whether phone was verified
            let birthday: String?
            let age: Int?
            let gender: String?
            let height_cm: Double?
            let height_inches: Int?
            let weight_kg: Double?
            let weight_lbs: Double?
            let fitness_goal: String?
            let experience_level: String?
            let strength_level: String?
            let workout_environment: String?
            let equipment: [String]?
            let available_days: Int?
            let current_streak: Int?
            let longest_streak: Int?
            let total_workouts: Int?
            let xp: Int?
            let last_workout_date: String?
            let updated_at: String
            let weight_unit: String?
            let height_unit: String?
            let distance_unit: String?
            let week_start_day: String?
            let has_completed_onboarding: Bool
        }
        
        let upsertProfile = ProfileUpsert(
            id: userId.uuidString,
            name: profile.name,
            email: profile.email,
            phone_number: profile.phone_number,  // 2FA phone number (private)
            phone_verified: profile.phone_verified,  // Pass through from ProfileSync
            birthday: profile.birthday,
            age: profile.age,
            gender: profile.gender,
            height_cm: profile.height_cm,
            height_inches: profile.height_inches,
            weight_kg: profile.weight_kg,
            weight_lbs: profile.weight_lbs,
            fitness_goal: profile.fitness_goal,
            experience_level: profile.experience_level,
            strength_level: profile.strength_level,
            workout_environment: profile.workout_environment,
            equipment: profile.equipment,
            available_days: profile.available_days,
            current_streak: profile.current_streak,
            longest_streak: profile.longest_streak,
            total_workouts: profile.total_workouts,
            xp: profile.xp,
            last_workout_date: profile.last_workout_date,
            updated_at: profile.updated_at,
            weight_unit: profile.weight_unit,
            height_unit: profile.height_unit,
            distance_unit: profile.distance_unit,
            week_start_day: profile.week_start_day,
            has_completed_onboarding: true
        )
        
        do {
            try await client
                .from("user_profiles")
                .upsert(upsertProfile, onConflict: "id")
                .execute()
            
            AppLogger.info("[SYNC] Profile UPSERTED to cloud for user: \(userId.uuidString)", category: .network)
            // Track when we last pushed so we can detect CMS/admin edits
            UserDefaults.standard.set(Date(), forKey: SupabaseManager.lastProfilePushKey)
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "[SYNC] UPSERT FAILED — User can try Settings > Sync Profile to force retry",
                category: .network,
                op: PerformanceSignposts.Op.profileSync.rawValue,
                endpoint: "user_profiles(upsert sync)",
                userId: userId
            )
            throw error  // Propagate error so caller knows sync failed
        }
        let ft = user.heightInches / 12
        let inches = user.heightInches % 12
        AppLogger.info("Full profile synced to cloud: Name=\(user.name ?? "nil"), Birthday=\(user.birthday ?? "nil"), Age=\(user.age), Gender=\(user.gender ?? "nil"), Height=\(ft)'\(inches)\" (\(user.heightInches)in/\(user.height)cm), Weight=\(user.weightLbs)lbs (\(user.weight)kg), Goal=\(user.fitnessGoal ?? "nil"), Level=\(user.experienceLevel ?? "nil"), Equipment=\(equipmentArray), Days=\(user.availableDays), XP=\(user.xp), Streak=\(user.currentStreak), Workouts=\(user.totalWorkouts)", category: .network)
    }
    
    /// Force sync profile from Core Data to cloud - call this if sync seems broken
    /// This is a public method that can be called from Settings to manually trigger a sync
    func forceSyncProfileToCloud() async throws {
        guard let user = await MainActor.run(body: { UserManager.shared.currentUser }) else {
            AppLogger.error("[FORCE SYNC] No local user to sync", category: .network)
            throw NSError(domain: "SupabaseManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "No local user found"])
        }
        
        guard let userId = currentUser?.id else {
            AppLogger.error("[FORCE SYNC] Not authenticated", category: .network)
            throw NSError(domain: "SupabaseManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        AppLogger.debug("[FORCE SYNC] Starting forced profile sync...", category: .network)
        AppLogger.debug("[FORCE SYNC] User: \(user.name ?? "unknown"), Age: \(user.age), Gender: \(user.gender ?? "nil")", category: .network)
        
        // Build complete profile update with ALL fields
        struct FullProfileUpdate: Encodable {
            let name: String?
            let birthday: String?
            let age: Int?
            let gender: String?
            let height_cm: Double?
            let height_inches: Int?
            let weight_kg: Double?
            let weight_lbs: Double?
            let fitness_goal: String?
            let experience_level: String?
            let strength_level: String?
            let workout_environment: String?
            let equipment: [String]?
            let available_days: Int?
            let has_completed_onboarding: Bool
            let updated_at: String
        }
        
        let equipmentArray = user.getEquipment() ?? []
        
        let fullUpdate = FullProfileUpdate(
            name: user.name,
            birthday: birthdayToISO(user.birthday),  // Convert to ISO format for database
            age: user.age > 0 ? Int(user.age) : nil,
            gender: user.gender,
            height_cm: user.height > 0 ? Double(user.height) : nil,
            height_inches: user.heightInches > 0 ? Int(user.heightInches) : nil,
            weight_kg: user.weight > 0 ? Double(user.weight) : nil,
            weight_lbs: user.weightLbs > 0 ? user.weightLbs : nil,
            fitness_goal: user.fitnessGoal,
            experience_level: user.experienceLevel,
            strength_level: user.strengthLevel,
            workout_environment: user.workoutEnvironment,
            equipment: equipmentArray.isEmpty ? nil : equipmentArray,
            available_days: user.availableDays > 0 ? Int(user.availableDays) : nil,
            has_completed_onboarding: true,
            updated_at: dateToISO(Date())
        )
        
        try await client
            .from("user_profiles")
            .update(fullUpdate)
            .eq("id", value: userId.uuidString)
            .execute()
        
        // Track push time so we can detect CMS/admin edits
        UserDefaults.standard.set(Date(), forKey: SupabaseManager.lastProfilePushKey)
        
        AppLogger.info("[FORCE SYNC] Profile force synced successfully! Name=\(user.name ?? "nil"), Birthday=\(user.birthday ?? "nil"), Age=\(user.age), Gender=\(user.gender ?? "nil"), Height=\(user.height)cm/\(user.heightInches)in, Weight=\(user.weight)kg/\(user.weightLbs)lbs, Goal=\(user.fitnessGoal ?? "nil"), Level=\(user.experienceLevel ?? "nil")", category: .network)
    }
    
    // MARK: - Custom Exercises
    
    func createCustomExercise(
        name: String,
        category: String,
        primaryMuscles: [String],
        secondaryMuscles: [String],
        equipment: String,
        instructions: String,
        iconName: String
    ) async throws {
        guard let userId = currentUser?.id else {
            throw NSError(domain: "SupabaseManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        struct CustomExerciseInsert: Encodable {
            let user_id: String
            let name: String
            let category: String
            let primary_muscles: [String]
            let secondary_muscles: [String]
            let equipment: String
            let instructions: String
            let icon_name: String
        }
        
        let exercise = CustomExerciseInsert(
            user_id: userId.uuidString,
            name: name,
            category: category,
            primary_muscles: primaryMuscles,
            secondary_muscles: secondaryMuscles,
            equipment: equipment,
            instructions: instructions,
            icon_name: iconName
        )
        
        try await client
            .from("custom_exercises")
            .insert(exercise)
            .execute()
        
        AppLogger.info("Custom exercise created: \(name)", category: .network)
    }
    
    // MARK: - Exercise Migration
    
    func uploadExercises<T: Encodable>(_ exercises: [T]) async throws {
        try await client
            .from("exercises")
            .insert(exercises)
            .execute()
    }
    
    /// 🔒 Track in-flight exercise fetch to prevent duplicates
    private static var exerciseFetchTask: Task<[ExerciseDTO], Error>?
    private static var cachedExercises: [ExerciseDTO]?
    private static var cacheTimestamp: Date?
    private static let exerciseCacheTTL: TimeInterval = 60 // 60 second cache
    
    func fetchAllExercises() async throws -> [ExerciseDTO] {
        // ⚡️ PERFORMANCE: Check cache first
        if let cached = SupabaseManager.cachedExercises,
           let timestamp = SupabaseManager.cacheTimestamp,
           Date().timeIntervalSince(timestamp) < SupabaseManager.exerciseCacheTTL {
            AppLogger.debug("[EXERCISES] Returning \(cached.count) cached exercises", category: .network)
            return cached
        }
        
        // ⚡️ PERFORMANCE: Reuse in-flight request if one exists
        if let existingTask = SupabaseManager.exerciseFetchTask {
            AppLogger.debug("[EXERCISES] Reusing in-flight fetch request", category: .network)
            return try await existingTask.value
        }
        
        // Create new fetch task
        let task = Task<[ExerciseDTO], Error> {
            defer { SupabaseManager.exerciseFetchTask = nil }
            return try await self.performExerciseFetch()
        }
        
        SupabaseManager.exerciseFetchTask = task
        
        let result = try await task.value
        
        // Cache the result
        SupabaseManager.cachedExercises = result
        SupabaseManager.cacheTimestamp = Date()
        
        return result
    }
    
    /// Internal exercise fetch implementation
    private func performExerciseFetch() async throws -> [ExerciseDTO] {
        // ⚡️ PERFORMANCE: Use materialized view for public exercises (60-90% faster)
        // Fetch ALL exercises from Supabase using pagination
        // Supabase default limit is 1000, so we need to paginate to get all ~7000 exercises
        var allExercises: [ExerciseDTO] = []
        let pageSize = 1000
        var offset = 0
        var hasMoreData = true
        
        AppLogger.debug("Starting paginated fetch of all exercises...", category: .network)
        
        // Try materialized view first (much faster), fallback to regular table
        let tableName = "mv_public_exercises"
        let fallbackTable = "exercises"
        var usingMaterializedView = true
        
        while hasMoreData {
            do {
                // Attempt to use materialized view first
                let response: [ExerciseDTO] = try await client
                    .from(tableName)
                    .select()
                    .range(from: offset, to: offset + pageSize - 1)
                    .execute()
                    .value
                
                allExercises.append(contentsOf: response)
                if usingMaterializedView {
                    AppLogger.debug("Using cached view for faster performance", category: .network)
                    usingMaterializedView = false // Only log once
                }
                AppLogger.debug("Fetched \(response.count) exercises (total: \(allExercises.count))", category: .network)
                
                if response.count < pageSize {
                    hasMoreData = false
                } else {
                    offset += pageSize
                }
            } catch {
                // Fallback to regular table if materialized view doesn't exist
                AppLogger.info("Materialized view not available, using regular table", category: .network)
                let response: [ExerciseDTO] = try await client
                    .from(fallbackTable)
                    .select()
                    .eq("is_custom", value: false)
                    .range(from: offset, to: offset + pageSize - 1)
                    .execute()
                    .value
                
                allExercises.append(contentsOf: response)
                AppLogger.debug("Fetched \(response.count) exercises (total: \(allExercises.count))", category: .network)
                
                if response.count < pageSize {
                    hasMoreData = false
                } else {
                    offset += pageSize
                }
                
                // Don't retry materialized view if it failed once
                usingMaterializedView = false
            }
        }
        
        AppLogger.info("Fetched ALL \(allExercises.count) exercises from cloud", category: .network)
        return allExercises
    }
    
    /// Fetch all exercises for audit (raw DTOs without filtering)
    func fetchAllExercisesRaw() async throws -> [ExerciseDTO] {
        var allExercises: [ExerciseDTO] = []
        let pageSize = 1000
        var offset = 0
        var hasMoreData = true
        
        AppLogger.debug("[AUDIT] Fetching all exercises for audit...", category: .network)
        
        while hasMoreData {
            let response: [ExerciseDTO] = try await client
                .from("exercises")
                .select()
                .range(from: offset, to: offset + pageSize - 1)
                .order("name", ascending: true)
                .execute()
                .value
            
            allExercises.append(contentsOf: response)
            
            if response.count < pageSize {
                hasMoreData = false
            } else {
                offset += pageSize
            }
        }
        
        AppLogger.info("[AUDIT] Fetched \(allExercises.count) exercises for audit", category: .network)
        return allExercises
    }
    
    /// Fetch stretch exercises for a specific body area using server-side RPC
    func fetchStretchesForArea(_ area: String, gender: String? = nil, limit: Int = 8) async throws -> [ExerciseDTO] {
        var params: [String: String] = ["p_area": area]
        if let gender = gender {
            params["p_gender"] = gender
        }
        // p_limit needs special handling since RPC expects int
        let response: [ExerciseDTO] = try await client
            .rpc("fetch_stretches_for_area", params: params)
            .execute()
            .value
        
        AppLogger.info("Fetched \(response.count) stretches for area '\(area)' via RPC", category: .network)
        return response
    }
    
    /// Update an exercise in the database
    func updateExercise(_ exercise: ExerciseDTO) async throws {
        guard let exerciseId = exercise.id else {
            throw NSError(domain: "SupabaseManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Exercise ID is required"])
        }
        
        // FULL update payload with all editable fields
        struct FullExerciseUpdate: Encodable {
            // Basic info
            let name: String
            let category: String
            let equipment: ExplicitNull<String>
            let primary_muscles: ExplicitNull<[String]>
            let secondary_muscles: ExplicitNull<[String]>
            let description: ExplicitNull<String>
            let instructions: ExplicitNull<String>
            let workout_type: ExplicitNull<String>  // Strength, Cardio, Stretch, Plyometrics
            
            // Movement classification
            let movement_pattern: ExplicitNull<String>
            let force_type: ExplicitNull<String>
            let movement_type: ExplicitNull<String>
            let laterality: ExplicitNull<String>
            
            // Position & Grip
            let body_position: ExplicitNull<String>
            let grip_type: ExplicitNull<String>
            let grip_width: ExplicitNull<String>
            
            // Ratings
            let difficulty_level: ExplicitNull<Int>
            let home_gym_friendly: ExplicitNull<Bool>
        }
        
        // Wrapper that encodes nil as explicit JSON null (not omitted)
        enum ExplicitNull<T: Encodable>: Encodable {
            case value(T)
            case null
            
            init(_ value: T?) {
                if let v = value {
                    self = .value(v)
                } else {
                    self = .null
                }
            }
            
            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .value(let v):
                    try container.encode(v)
                case .null:
                    try container.encodeNil()
                }
            }
        }
        
        // Get muscles as arrays
        let primaryMusclesArray: [String]?
        if let raw = exercise.primaryMusclesRaw {
            let arr = raw.asArray.filter { !$0.isEmpty }
            primaryMusclesArray = arr.isEmpty ? nil : arr
        } else {
            primaryMusclesArray = nil
        }
        
        let secondaryMusclesArray: [String]?
        if let raw = exercise.secondaryMusclesRaw {
            let arr = raw.asArray.filter { !$0.isEmpty }
            secondaryMusclesArray = arr.isEmpty ? nil : arr
        } else {
            secondaryMusclesArray = nil
        }
        
        // Helper to convert empty strings to nil (so they save as NULL in DB)
        func emptyToNil(_ str: String?) -> String? {
            guard let s = str, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return s
        }
        
        let update = FullExerciseUpdate(
            name: exercise.name,
            category: exercise.category,
            equipment: ExplicitNull(emptyToNil(exercise.equipment)),
            primary_muscles: ExplicitNull(primaryMusclesArray?.isEmpty == true ? nil : primaryMusclesArray),
            secondary_muscles: ExplicitNull(secondaryMusclesArray?.isEmpty == true ? nil : secondaryMusclesArray),
            description: ExplicitNull(emptyToNil(exercise.description)),
            instructions: ExplicitNull(emptyToNil(exercise.instructions)),
            workout_type: ExplicitNull(emptyToNil(exercise.workoutType)),
            movement_pattern: ExplicitNull(emptyToNil(exercise.movementPattern)),
            force_type: ExplicitNull(emptyToNil(exercise.forceType)),
            movement_type: ExplicitNull(emptyToNil(exercise.movementType)),
            laterality: ExplicitNull(emptyToNil(exercise.laterality)),
            body_position: ExplicitNull(emptyToNil(exercise.bodyPosition)),
            grip_type: ExplicitNull(emptyToNil(exercise.gripType)),
            grip_width: ExplicitNull(emptyToNil(exercise.gripWidth)),
            difficulty_level: ExplicitNull(exercise.difficultyLevel),
            home_gym_friendly: ExplicitNull(exercise.homeGymFriendly)
        )
        
        AppLogger.debug("SENDING FULL UPDATE TO SUPABASE - ID: \(exerciseId), Name: \(exercise.name), Category: \(exercise.category), Equipment: \(exercise.equipment ?? "nil"), Primary: \(primaryMusclesArray ?? []), Secondary: \(secondaryMusclesArray ?? []), Movement: \(exercise.movementPattern ?? "nil"), Force: \(exercise.forceType ?? "nil"), Difficulty: \(exercise.difficultyLevel ?? -1)", category: .network)
        
        do {
            let response = try await client
                .from("exercises")
                .update(update)
                .eq("id", value: exerciseId)
                .execute()
            
            AppLogger.info("SUPABASE UPDATE SUCCESS! HTTP Status: \(response.status), Exercise: \(exercise.name), ID: \(exerciseId)", category: .network)
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "SUPABASE UPDATE FAILED (exercise id \(exerciseId))",
                category: .network,
                op: PerformanceSignposts.Op.exerciseUpdate.rawValue,
                endpoint: "exercises(update)",
                userId: currentUser?.id
            )
            throw error
        }
    }
    
    /// Delete an exercise from the database
    func deleteExercise(id: String) async throws {
        try await client
            .from("exercises")
            .delete()
            .eq("id", value: id)
            .execute()
        
        AppLogger.debug("Deleted exercise ID: \(id)", category: .network)
    }
    
    /// @deprecated - exercise_pairings table was replaced by exercises table
    /// Exercise pairing logic is now handled by SmartExercisePairingEngine locally
    func fetchExercisePairings() async throws -> [ExercisePairingDTO] {
        // Table deprecated - return empty array
        AppLogger.warning("exercise_pairings table deprecated, using local SmartExercisePairingEngine instead", category: .network)
        return []
    }
    
    func fetchEquipmentSubstitutions() async throws -> [EquipmentSubstitutionDTO] {
        let response: [EquipmentSubstitutionDTO] = try await client
            .from("equipment_substitutions")
            .select()
            .order("quality_score", ascending: false)
            .execute()
            .value
        
        AppLogger.debug("Fetched \(response.count) equipment substitutions", category: .network)
        return response
    }
    
    func fetchCustomExercises() async throws -> [CustomExerciseDTO] {
        guard let userId = currentUser?.id else { return [] }
        
        let response: [CustomExerciseDTO] = try await client
            .from("custom_exercises")
            .select()
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value
        
        AppLogger.debug("Fetched \(response.count) custom exercises", category: .network)
        return response
    }
    
    // MARK: - Workout History
    
    func saveWorkout(
        name: String,
        date: Date,
        durationSeconds: Int,
        xpEarned: Int,
        exercises: [(name: String, sets: Int)],
        programId: String? = nil,
        programDay: Int? = nil
    ) async throws {
        guard let userId = currentUser?.id else { return }
        
        struct WorkoutInsert: Encodable {
            let user_id: String
            let name: String
            let date: String
            let duration_seconds: Int
            let xp_earned: Int
            let program_id: String?
            let program_day: Int?
        }
        
        let workout = WorkoutInsert(
            user_id: userId.uuidString,
            name: name,
            date: dateToISO( date),
            duration_seconds: durationSeconds,
            xp_earned: xpEarned,
            program_id: programId,
            program_day: programDay
        )
        
        let response: [WorkoutDTO] = try await client
            .from("workouts")
            .insert(workout)
            .select()
            .execute()
            .value
        
        if let workoutId = response.first?.id {
            // Save exercise details
            for exercise in exercises {
                try await saveWorkoutExercise(
                    workoutId: workoutId,
                    exerciseName: exercise.name,
                    setsCompleted: exercise.sets
                )
            }
            
            // Update user progress
            try await updateUserProgress(xpEarned: xpEarned)
        }
        
        AppLogger.info("Workout saved: \(name)", category: .network)
    }
    
    private func saveWorkoutExercise(workoutId: String, exerciseName: String, setsCompleted: Int) async throws {
        struct WorkoutExerciseInsert: Encodable {
            let workout_id: String
            let exercise_name: String
            let sets_completed: Int
        }
        
        let exercise = WorkoutExerciseInsert(
            workout_id: workoutId,
            exercise_name: exerciseName,
            sets_completed: setsCompleted
        )
        
        try await client
            .from("workout_exercises")
            .insert(exercise)
            .execute()
    }
    
    func fetchRecentWorkouts(limit: Int = 10) async throws -> [WorkoutDTO] {
        guard let userId = currentUser?.id else { return [] }
        
        let response: [WorkoutDTO] = try await client
            .from("workouts")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("date", ascending: false)
            .limit(limit)
            .execute()
            .value
        
        AppLogger.debug("Fetched \(response.count) recent workouts", category: .network)
        return response
    }
    
    // MARK: - Exercise Popularity Tracking
    
    func logExerciseUsage(
        exerciseName: String,
        exerciseId: String,
        setsCompleted: Int,
        totalReps: Int,
        totalWeightKg: Double,
        workoutType: String,
        programId: String? = nil,
        workoutId: String? = nil
    ) async throws {
        guard let userId = currentUser?.id else { return }
        
        struct ExerciseUsageLog: Encodable {
            let user_id: String
            let exercise_id: String
            let exercise_name: String
            let workout_id: String?
            let sets_completed: Int
            let total_reps: Int
            let total_weight_kg: Double
            let workout_type: String
            let program_id: String?
        }
        
        let log = ExerciseUsageLog(
            user_id: userId.uuidString,
            exercise_id: exerciseId,
            exercise_name: exerciseName,
            workout_id: workoutId,
            sets_completed: setsCompleted,
            total_reps: totalReps,
            total_weight_kg: totalWeightKg,
            workout_type: workoutType,
            program_id: programId
        )
        
        try await client
            .from("exercise_usage_logs")
            .insert(log)
            .execute()
    }
    
    func fetchPopularExercises(limit: Int = 50) async throws -> [PopularExerciseDTO] {
        let response: [PopularExerciseDTO] = try await client
            .from("exercise_popularity_stats")
            .select()
            .order("popularity_score", ascending: false)
            .limit(limit)
            .execute()
            .value
        
        return response
    }
    
    func fetchTrendingExercises(limit: Int = 50) async throws -> [PopularExerciseDTO] {
        let response: [PopularExerciseDTO] = try await client
            .from("exercise_popularity_stats")
            .select()
            .order("trending_score", ascending: false)
            .limit(limit)
            .execute()
            .value
        
        return response
    }
    
    func fetchMostFavoritedExercises(limit: Int = 50) async throws -> [PopularExerciseDTO] {
        let response: [PopularExerciseDTO] = try await client
            .from("exercise_popularity_stats")
            .select()
            .order("favorite_count", ascending: false)
            .limit(limit)
            .execute()
            .value
        
        // Filter out exercises with 0 favorites
        return response.filter { $0.favoriteCount > 0 }
    }
    
    // MARK: - User Progress
    
    private func createUserProgress(userId: UUID) async throws {
        // Try using the secure RPC function first (bypasses RLS during signup)
        struct CreateProgressParams: Encodable {
            let user_id: String
        }
        
        do {
            try await client.rpc("create_user_progress", params: CreateProgressParams(user_id: userId.uuidString)).execute()
            AppLogger.info("User progress created via RPC function", category: .network)
        } catch {
            // Fallback to direct insert if RPC function doesn't exist
            AppLogger.warning("RPC function not available for progress, trying direct insert: \(error.localizedDescription)", category: .network)
            
            struct ProgressInsert: Encodable {
                let user_id: String
                let date: String
                let xp: Int
                let current_level: Int
                let current_streak: Int
                let longest_streak: Int
                let total_workouts: Int
                let last_workout_date: String?
            }
            
            let progress = ProgressInsert(
                user_id: userId.uuidString,
                date: dateToISO(Date()),
                xp: 0,
                current_level: 1,
                current_streak: 0,
                longest_streak: 0,
                total_workouts: 0,
                last_workout_date: nil
            )
            
            // Use upsert to handle existing records (e.g., when user profile was deleted but progress remained)
            try await client
                .from("user_progress")
                .upsert(progress, onConflict: "user_id,date")
                .execute()
        }
    }
    
    private func updateUserProgress(xpEarned: Int) async throws {
        guard let userId = currentUser?.id else { return }
        
        // Fetch current progress
        let response: [UserProgressDTO] = try await client
            .from("user_progress")
            .select()
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value
        
        guard let current = response.first else { return }
        
        let newTotalXp = current.totalXp + xpEarned
        let newLevel = (newTotalXp / 100) + 1  // Level up every 100 XP (matches UserManager.getLevel())
        
        struct ProgressUpdate: Encodable {
            let total_xp: Int
            let current_level: Int
            let total_workouts: Int
            let last_workout_date: String
            let updated_at: String
        }
        
        let update = ProgressUpdate(
            total_xp: newTotalXp,
            current_level: newLevel,
            total_workouts: current.totalWorkouts + 1,
            last_workout_date: dateToISO(Date()),
            updated_at: dateToISO(Date())
        )
        
        try await client
            .from("user_progress")
            .update(update)
            .eq("user_id", value: userId.uuidString)
            .execute()
        
        AppLogger.info("User progress updated: +\(xpEarned) XP", category: .network)
    }
    
    func fetchUserProgress() async throws -> UserProgressDTO? {
        guard let userId = currentUser?.id else { return nil }
        
        let response: [UserProgressDTO] = try await client
            .from("user_progress")
            .select()
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value
        
        return response.first
    }
    
    // MARK: - Favorites
    
    /// Toggle favorite - now stores exercise NAME for reliable syncing
    /// (Exercise IDs change on each sync, but names are stable)
    func toggleFavorite(exerciseId: String, exerciseType: String = "default", exerciseName: String? = nil) async throws {
        guard let userId = currentUser?.id else { return }
        
        // Use exercise name for lookup if provided (more reliable)
        // Fall back to ID for backwards compatibility
        let lookupField = exerciseName != nil ? "exercise_name" : "exercise_id"
        let lookupValue = exerciseName ?? exerciseId
        
        // Check if already favorited
        let existing: [UserFavoriteDTO] = try await client
            .from("user_favorites")
            .select()
            .eq("user_id", value: userId.uuidString)
            .eq(lookupField, value: lookupValue)
            .execute()
            .value
        
        if existing.isEmpty {
            // Add favorite - include exercise name for reliable syncing
            struct FavoriteInsert: Encodable {
                let user_id: String
                let exercise_id: String
                let exercise_type: String
                let exercise_name: String?
            }
            
            let favorite = FavoriteInsert(
                user_id: userId.uuidString,
                exercise_id: exerciseId,
                exercise_type: exerciseType,
                exercise_name: exerciseName
            )
            
            try await client
                .from("user_favorites")
                .insert(favorite)
                .execute()
            
            AppLogger.info("Added to favorites: \(exerciseName ?? exerciseId)", category: .network)
        } else {
            // Remove favorite
            guard let firstExisting = existing.first else { return }
            try await client
                .from("user_favorites")
                .delete()
                .eq("id", value: firstExisting.id)
                .execute()
            
            AppLogger.info("Removed from favorites: \(exerciseName ?? exerciseId)", category: .network)
        }
    }
    
    /// Fetch favorites - returns exercise NAMES for reliable Core Data matching
    func fetchFavorites() async throws -> [String] {
        guard let userId = currentUser?.id else { return [] }
        
        let response: [UserFavoriteDTO] = try await client
            .from("user_favorites")
            .select()
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value
        
        // Return exercise names (preferred) or IDs (fallback for old data)
        return response.compactMap { $0.exerciseName ?? $0.exerciseId }
    }
    
    /// Fetch favorite exercise names only (for reliable Core Data syncing)
    func fetchFavoriteExerciseNames() async throws -> [String] {
        guard let userId = currentUser?.id else { return [] }
        
        let response: [UserFavoriteDTO] = try await client
            .from("user_favorites")
            .select()
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value
        
        // Return only entries that have exercise names
        return response.compactMap { $0.exerciseName }
    }
    
    // MARK: - Favorite Workouts (Cloud Sync)
    
    /// Save a favorite workout template to cloud
    func saveFavoriteWorkout(
        workoutName: String,
        exerciseNames: [String],
        originalWorkoutId: String
    ) async throws {
        guard let userId = currentUser?.id else { return }
        
        struct FavoriteWorkoutInsert: Encodable {
            let user_id: String
            let workout_name: String
            let exercise_names: [String]
            let original_workout_id: String
            let created_at: String
        }
        
        let favoriteWorkout = FavoriteWorkoutInsert(
            user_id: userId.uuidString,
            workout_name: workoutName,
            exercise_names: exerciseNames,
            original_workout_id: originalWorkoutId,
            created_at: dateToISO(Date())
        )
        
        try await client
            .from("favorite_workouts")
            .insert(favoriteWorkout)
            .execute()
        
        AppLogger.info("Favorite workout saved to cloud: \(workoutName)", category: .network)
    }
    
    /// Remove a favorite workout from cloud
    func removeFavoriteWorkout(originalWorkoutId: String) async throws {
        guard let userId = currentUser?.id else { return }
        
        try await client
            .from("favorite_workouts")
            .delete()
            .eq("user_id", value: userId.uuidString)
            .eq("original_workout_id", value: originalWorkoutId)
            .execute()
        
        AppLogger.info("Favorite workout removed from cloud", category: .network)
    }
    
    /// Fetch all favorite workouts from cloud
    func fetchFavoriteWorkouts() async throws -> [FavoriteWorkoutDTO] {
        guard let userId = currentUser?.id else { return [] }
        
        let response: [FavoriteWorkoutDTO] = try await client
            .from("favorite_workouts")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value
        
        AppLogger.debug("Fetched \(response.count) favorite workouts from cloud", category: .network)
        return response
    }
    
    // MARK: - Admin/Analytics Queries (All Users)
    
    /// Get aggregate workout statistics across all users
    func fetchWorkoutAnalytics() async throws -> WorkoutAnalyticsDTO {
        // Get total workouts
        let workoutCountResponse: [WorkoutCountDTO] = try await client
            .from("workouts")
            .select("id")
            .execute()
            .value
        
        // Get unique users who have worked out
        let uniqueUsersResponse: [UniqueUserDTO] = try await client
            .from("workouts")
            .select("user_id")
            .execute()
            .value
        
        let uniqueUsers = Set(uniqueUsersResponse.map { $0.userId }).count
        
        // Get workouts in last 7 days
        let sevenDaysAgo = dateToISO( Date().addingTimeInterval(-7 * 24 * 60 * 60))
        let recentWorkouts: [WorkoutDTO] = try await client
            .from("workouts")
            .select()
            .gte("date", value: sevenDaysAgo)
            .execute()
            .value
        
        return WorkoutAnalyticsDTO(
            totalWorkouts: workoutCountResponse.count,
            uniqueUsers: uniqueUsers,
            workoutsLast7Days: recentWorkouts.count,
            avgWorkoutsPerUser: uniqueUsers > 0 ? Double(workoutCountResponse.count) / Double(uniqueUsers) : 0
        )
    }
    
    /// Get top completed workouts across all users
    func fetchTopWorkouts(limit: Int = 10) async throws -> [TopWorkoutDTO] {
        struct WorkoutAggregation: Codable {
            let name: String?
            let count: Int
            
            enum CodingKeys: String, CodingKey {
                case name
                case count
            }
        }
        
        // Use RPC call for aggregation
        let response: [WorkoutAggregation] = try await client
            .rpc("get_top_workouts", params: ["result_limit": limit])
            .execute()
            .value
        
        return response.compactMap { agg in
            guard let name = agg.name else { return nil }
            return TopWorkoutDTO(workoutName: name, completionCount: agg.count)
        }
    }
    
    /// Get user statistics
    func fetchUserStatistics() async throws -> UserStatisticsDTO {
        let profiles: [UserProfileDTO] = try await client
            .from("user_profiles")
            .select()
            .execute()
            .value
        
        let totalUsers = profiles.count
        
        // Count users with recent activity (last 30 days)
        let thirtyDaysAgo = dateToISO( Date().addingTimeInterval(-30 * 24 * 60 * 60))
        let activeUsers: [UserProfileDTO] = try await client
            .from("user_profiles")
            .select()
            .gte("updated_at", value: thirtyDaysAgo)
            .execute()
            .value
        
        return UserStatisticsDTO(
            totalUsers: totalUsers,
            activeUsersLast30Days: activeUsers.count,
            avgStreakLength: profiles.compactMap { $0.currentStreak }.reduce(0, +) / max(totalUsers, 1),
            avgTotalWorkouts: profiles.compactMap { $0.totalWorkouts }.reduce(0, +) / max(totalUsers, 1)
        )
    }
    
    /// Get step tracking statistics across all users
    func fetchStepStatisticsAllUsers() async throws -> StepAnalyticsDTO {
        // Get all step records from last 7 days
        let sevenDaysAgo = dateToISO( Date().addingTimeInterval(-7 * 24 * 60 * 60))
        
        let stepData: [StepDataDTO] = try await client
            .from("step_tracking")
            .select()
            .gte("date", value: sevenDaysAgo)
            .execute()
            .value
        
        let totalSteps = stepData.reduce(0) { $0 + $1.steps }
        let avgStepsPerDay = stepData.isEmpty ? 0 : totalSteps / stepData.count
        let uniqueUsers = Set(stepData.map { $0.userId }).count
        let goalsMetCount = stepData.filter { $0.steps >= $0.goal }.count
        let goalCompletionRate = stepData.isEmpty ? 0.0 : Double(goalsMetCount) / Double(stepData.count)
        
        return StepAnalyticsDTO(
            totalStepsAllUsers: totalSteps,
            avgStepsPerDay: avgStepsPerDay,
            usersTrackingSteps: uniqueUsers,
            goalCompletionRate: goalCompletionRate,
            daysTracked: stepData.count
        )
    }
    
    // MARK: - Step Tracking (Cloud-Based)
    
    /// Save daily step data to cloud
    func saveStepData(date: Date, steps: Int, goal: Int) async throws {
        // Data Invariant #26 — auth-guarded write.
        // Previously this upsert would throw 42501 RLS if JWT was stale,
        // which landed in bug_intelligence_fingerprints as noise.
        guard isAuthenticated, let userId = currentUser?.id else {
            AppLogger.info(
                "[STEPS] Skipping saveStepData — not authenticated",
                category: .health,
                context: DiagnosticContext(op: "step.save", endpoint: "step_tracking")
            )
            return
        }

        struct StepDataUpsert: Encodable {
            let user_id: String
            let date: String
            let steps: Int
            let goal: Int
            let synced_at: String
        }
        
        let dateString = dateToISO( date)
        
        let stepData = StepDataUpsert(
            user_id: userId.uuidString,
            date: dateString,
            steps: steps,
            goal: goal,
            synced_at: dateToISO(Date())
        )
        
        // Upsert (insert or update) to avoid duplicates
        // The unique constraint on (user_id, date) ensures one record per day
        try await client
            .from("step_tracking")
            .upsert(stepData, onConflict: "user_id,date")
            .execute()
    }
    
    /// Batch save multiple days of step data in a single database call
    /// ⚡️ PERFORMANCE: Reduces 100 individual queries to 1 batch query
    func batchSaveStepData(_ dailySteps: [HealthKitManager.DailySteps], goal: Int) async throws {
        guard isAuthenticated, let userId = currentUser?.id else {
            AppLogger.info(
                "[STEPS] Skipping batchSaveStepData — not authenticated",
                category: .health,
                context: DiagnosticContext(op: "step.save", endpoint: "step_tracking")
            )
            return
        }
        guard !dailySteps.isEmpty else { return }
        
        struct StepDataUpsert: Encodable {
            let user_id: String
            let date: String
            let steps: Int
            let goal: Int
            let synced_at: String
        }
        
        let syncTime = iso8601Formatter.string(from: Date())
        
        // Convert all daily steps to upsert records
        let stepDataBatch = dailySteps.map { [iso8601Formatter] dailyStep in
            StepDataUpsert(
                user_id: userId.uuidString,
                date: iso8601Formatter.string(from: dailyStep.date),
                steps: dailyStep.steps,
                goal: goal,
                synced_at: syncTime
            )
        }
        
        // Single batch upsert for all records
        try await client
            .from("step_tracking")
            .upsert(stepDataBatch, onConflict: "user_id,date")
            .execute()
    }
    
    /// Fetch recent step data from cloud
    func fetchRecentSteps(days: Int = 30) async throws -> [StepDataDTO] {
        guard let userId = currentUser?.id else { return [] }
        
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let startDateString = dateToISO( startDate)
        
        let response: [StepDataDTO] = try await client
            .from("step_tracking")
            .select()
            .eq("user_id", value: userId.uuidString)
            .gte("date", value: startDateString)
            .order("date", ascending: false)
            .execute()
            .value
        
        AppLogger.debug("Fetched \(response.count) days of step data from cloud", category: .network)
        return response
    }
    
    /// Update user's daily step goal
    func updateStepGoal(_ goal: Int) async throws {
        guard let userId = currentUser?.id else { return }
        
        struct StepGoalUpdate: Encodable {
            let daily_step_goal: Int
            let updated_at: String
        }
        
        let update = StepGoalUpdate(
            daily_step_goal: goal,
            updated_at: dateToISO(Date())
        )
        
        try await client
            .from("user_profiles")
            .update(update)
            .eq("id", value: userId.uuidString)
            .execute()
        
        AppLogger.info("Step goal updated to \(goal)", category: .network)
    }
    
    /// Fetch user's step goal from cloud
    func fetchStepGoal() async throws -> Int? {
        guard let userId = currentUser?.id else { return nil }
        
        struct StepGoalResponse: Codable {
            let daily_step_goal: Int?
            
            enum CodingKeys: String, CodingKey {
                case daily_step_goal = "daily_step_goal"
            }
        }
        
        let response: [StepGoalResponse] = try await client
            .from("user_profiles")
            .select("daily_step_goal")
            .eq("id", value: userId.uuidString)
            .execute()
            .value
        
        return response.first?.daily_step_goal
    }
    
    /// Get step statistics for a date range
    func fetchStepStatistics(startDate: Date, endDate: Date) async throws -> StepStatisticsDTO? {
        guard let userId = currentUser?.id else { return nil }
        
        let startString = dateToISO( startDate)
        let endString = dateToISO( endDate)
        
        let response: [StepDataDTO] = try await client
            .from("step_tracking")
            .select()
            .eq("user_id", value: userId.uuidString)
            .gte("date", value: startString)
            .lte("date", value: endString)
            .execute()
            .value
        
        guard !response.isEmpty else { return nil }
        
        let totalSteps = response.reduce(0) { $0 + $1.steps }
        let averageSteps = totalSteps / response.count
        let maxSteps = response.map { $0.steps }.max() ?? 0
        let daysGoalMet = response.filter { $0.steps >= $0.goal }.count
        
        return StepStatisticsDTO(
            totalSteps: totalSteps,
            averageSteps: averageSteps,
            maxSteps: maxSteps,
            daysTracked: response.count,
            daysGoalMet: daysGoalMet,
            goalCompletionRate: Double(daysGoalMet) / Double(response.count)
        )
    }
    
    // MARK: - Cardio Workout Tracking
    
    /// Save a completed cardio workout to the cloud
    func saveCardioWorkout(_ workout: CardioWorkoutData) async throws -> String? {
        // The RPC binds the row to `auth.uid()` server-side (Data inv. 7),
        // but we still fast-fail on logged-out callers to avoid an
        // unnecessary network round-trip.
        guard currentUser?.id != nil else {
            AppLogger.warning("[CARDIO] Cannot save - no user logged in", category: .network)
            return nil
        }

        // Cardio Redesign Phase 1 — switched from bare `cardio_workouts`
        // INSERT to the `record_cardio_workout` RPC (migration 185).
        // Single-transaction server-side fanout:
        //   • idempotent on (user_id, source='fit33', external_id) — guards
        //     double-tap on Finish (the previous bare insert created two
        //     duplicate rows on a fast double-tap)
        //   • same-origin overlap dedup (≥50% time overlap → newer wins)
        //   • cross-origin Strava merge (a 'strava' row that overlaps the
        //     fit33 row is DELETEd because native is canonical)
        //   • +50 'workout' LP (parity with strength) + graduated
        //     'cardio_bonus' LP (base_per_km × km × intensity_multiplier,
        //     daily cap +50). The iOS-side `+50 cardioSession` award in
        //     `UserManager.completeCardioWorkout` was removed in the same
        //     PR train to avoid double-counting.
        //   • PR detection
        //   • friend feed (only when goal_achieved)
        //
        // External_id is generated client-side as a stable UUID — the same
        // value SHOULD be used for retries of the same physical session
        // so the RPC's idempotency check fires. We re-derive it from the
        // (started_at, completed_at, activity_type) tuple so a network
        // retry of the same payload returns the original row.
        let externalId = stableExternalId(for: workout)
        let formatter = iso8601Formatter
        let timezone = TimeZone.current.identifier

        // Build the JSONB envelope keys that match the RPC contract.
        // Keep it as `[String: AnyJSON]` via a hand-rolled Encodable so
        // optional fields drop cleanly to NULL on the SQL side.
        let envelope = RecordCardioPayload(
            external_id: externalId,
            activity_type: workout.activityType,
            workout_name: workout.workoutName,
            goal_type: workout.goalType,
            goal_value: workout.goalValue,
            goal_achieved: workout.goalAchieved,
            duration_seconds: workout.durationSeconds,
            distance_meters: workout.distanceMeters,
            calories_burned: workout.caloriesBurned,
            average_pace: workout.averagePace,
            best_pace: workout.bestPace,
            average_speed: workout.averageSpeed,
            max_speed: workout.maxSpeed,
            average_heart_rate: workout.averageHeartRate,
            max_heart_rate: workout.maxHeartRate,
            cadence: workout.cadence,
            average_power: workout.averagePower,
            // Native cardio uses the new `polyline_native` column. The
            // legacy `route_coordinates` column is kept populated (raw
            // JSON) for back-compat with the existing recap map renderer.
            polyline_native: nil, // populated by Wave 5 share-card path
            splits_native_json: workout.splitsJSON,
            gps_avg_accuracy_m: nil, // populated when result.gpsAvgAccuracy ships through
            weather_json: nil,
            route_coordinates: workout.routeCoordinatesJSON,
            xp_earned: 0, // friend feed XP — UserManager fills in via own path
            timezone: timezone,
            started_at: formatter.string(from: workout.startedAt),
            completed_at: formatter.string(from: workout.completedAt)
        )

        // RPC returns a UUID. Supabase Swift SDK encodes a single-arg JSONB
        // call as `params: ["p_payload": <obj>]` and returns the scalar
        // result via `.value`.
        struct RpcArgs: Encodable {
            let p_payload: RecordCardioPayload
        }
        let args = RpcArgs(p_payload: envelope)

        let workoutId: String
        do {
            workoutId = try await client
                .rpc("record_cardio_workout", params: args)
                .execute()
                .value
        } catch {
            AppLogger.error(
                "[CARDIO] record_cardio_workout RPC failed: \(error.localizedDescription)",
                category: .network
            )
            throw error
        }

        AppLogger.info(
            "[CARDIO] Workout saved via RPC: \(workout.activityType) - \(workout.durationSeconds)s [id=\(workoutId)]",
            category: .network
        )

        // PR detection runs server-side via _check_cardio_prs in the RPC.
        // The legacy `checkAndSaveCardioPRs` Swift path is preserved for
        // Strava / HK ingest paths that still use direct inserts.

        // Streak update is still client-side because Core Data is the
        // canonical streak source on iOS. Idempotent — same call from
        // RunCompletionView just no-ops on a same-day re-fire.
        await MainActor.run {
            UserManager.shared.updateStreak()
        }

        return workoutId
    }

    /// Deterministic external_id for a cardio session so a retry of the
    /// same payload hits the RPC's idempotency check.
    ///
    /// CRITICAL: must be **stable across processes**. Swift's
    /// `String.hashValue` is randomized per-process, so a network retry
    /// from a fresh launch would produce a different ID and the RPC would
    /// double-insert. SHA-256 of the (start, end, activity, distance,
    /// duration) tuple is process-stable + collision-safe across the
    /// (user_id, source='fit33', external_id) idempotency key.
    /// Formatted in UUID 8-4-4-4-12 hex shape so it slots cleanly into
    /// `external_id TEXT` and reads as a UUID in DB tools.
    private func stableExternalId(for workout: CardioWorkoutData) -> String {
        let formatter = iso8601Formatter
        let raw = [
            formatter.string(from: workout.startedAt),
            formatter.string(from: workout.completedAt),
            workout.activityType,
            String(format: "%.2f", workout.distanceMeters),
            String(workout.durationSeconds)
        ].joined(separator: "|")

        let digest = SHA256.hash(data: Data(raw.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        // Take the first 32 hex chars (128 bits) and slot into UUID
        // 8-4-4-4-12 form. Plenty of collision resistance for a per-user
        // (auth.uid()) idempotency key — a hash collision would require
        // the same user logging two physically different cardio sessions
        // that share start, end, activity_type, distance, AND duration.
        let p = Array(hex.prefix(32))
        let a = String(p[0..<8])
        let b = String(p[8..<12])
        let c = String(p[12..<16])
        let d = String(p[16..<20])
        let e = String(p[20..<32])
        return "\(a)-\(b)-\(c)-\(d)-\(e)"
    }
    
    /// Check for personal records and save any new PRs
    private func checkAndSaveCardioPRs(workout: CardioWorkoutData, workoutId: String) async {
        guard let userId = currentUser?.id else { return }
        
        // Fetch existing PRs for this activity type
        let existingPRs = await fetchCardioPRs(activityType: workout.activityType)
        
        var newPRs: [(type: String, category: String, value: Double, unit: String)] = []
        
        // Check distance PR (longest workout)
        if workout.distanceMeters > 0 {
            let existingDistancePR = existingPRs.first { $0.recordType == "longest_distance" }
            if existingDistancePR == nil || workout.distanceMeters > (existingDistancePR?.value ?? 0) {
                newPRs.append(("longest_distance", "distance", workout.distanceMeters, "meters"))
            }
        }
        
        // Check duration PR (longest duration)
        if workout.durationSeconds > 0 {
            let existingDurationPR = existingPRs.first { $0.recordType == "longest_duration" }
            if existingDurationPR == nil || Double(workout.durationSeconds) > (existingDurationPR?.value ?? 0) {
                newPRs.append(("longest_duration", "duration", Double(workout.durationSeconds), "seconds"))
            }
        }
        
        // Check calories PR (most calories)
        if workout.caloriesBurned > 0 {
            let existingCaloriesPR = existingPRs.first { $0.recordType == "most_calories" }
            if existingCaloriesPR == nil || workout.caloriesBurned > (existingCaloriesPR?.value ?? 0) {
                newPRs.append(("most_calories", "calories", workout.caloriesBurned, "calories"))
            }
        }
        
        // Check pace PR (fastest pace) - lower is better
        if let pace = workout.averagePace, pace > 0, workout.distanceMeters >= 1000 { // At least 1km
            let existingPacePR = existingPRs.first { $0.recordType == "fastest_pace" }
            if existingPacePR == nil || pace < (existingPacePR?.value ?? Double.infinity) {
                newPRs.append(("fastest_pace", "speed", pace, "min/km"))
            }
        }
        
        // Check specific distance PRs (5K, 10K, etc.)
        let distanceKm = workout.distanceMeters / 1000
        if distanceKm >= 5.0 {
            // Calculate 5K time
            let pacePerKm = Double(workout.durationSeconds) / distanceKm
            let time5K = pacePerKm * 5.0
            let existing5KPR = existingPRs.first { $0.recordType == "fastest_5k" }
            if existing5KPR == nil || time5K < (existing5KPR?.value ?? Double.infinity) {
                newPRs.append(("fastest_5k", "speed", time5K, "seconds"))
            }
        }
        
        if distanceKm >= 10.0 {
            let pacePerKm = Double(workout.durationSeconds) / distanceKm
            let time10K = pacePerKm * 10.0
            let existing10KPR = existingPRs.first { $0.recordType == "fastest_10k" }
            if existing10KPR == nil || time10K < (existing10KPR?.value ?? Double.infinity) {
                newPRs.append(("fastest_10k", "speed", time10K, "seconds"))
            }
        }
        
        // Save new PRs
        for pr in newPRs {
            do {
                try await saveCardioPR(
                    userId: userId.uuidString,
                    activityType: workout.activityType,
                    recordType: pr.type,
                    recordCategory: pr.category,
                    value: pr.value,
                    unit: pr.unit,
                    workoutId: workoutId,
                    previousValue: existingPRs.first { $0.recordType == pr.type }?.value
                )
                AppLogger.info("[CARDIO PR] New \(pr.type): \(pr.value) \(pr.unit)", category: .network)
            } catch {
                AppLogger.warning("[CARDIO PR] Failed to save \(pr.type): \(error)", category: .network)
            }
        }
    }
    
    /// Save a personal record
    private func saveCardioPR(
        userId: String,
        activityType: String,
        recordType: String,
        recordCategory: String,
        value: Double,
        unit: String,
        workoutId: String,
        previousValue: Double?
    ) async throws {
        struct CardioPRUpsert: Encodable {
            let user_id: String
            let activity_type: String
            let record_type: String
            let record_category: String
            let value: Double
            let unit: String
            let workout_id: String
            let previous_value: Double?
            let improvement_percentage: Double?
            let achieved_at: String
        }
        
        var improvement: Double? = nil
        if let prev = previousValue, prev > 0 {
            if recordCategory == "speed" {
                // For pace/time, lower is better
                improvement = ((prev - value) / prev) * 100
            } else {
                // For distance/calories/duration, higher is better
                improvement = ((value - prev) / prev) * 100
            }
        }
        
        let upsert = CardioPRUpsert(
            user_id: userId,
            activity_type: activityType,
            record_type: recordType,
            record_category: recordCategory,
            value: value,
            unit: unit,
            workout_id: workoutId,
            previous_value: previousValue,
            improvement_percentage: improvement,
            achieved_at: dateToISO(Date())
        )
        
        try await client
            .from("cardio_personal_records")
            .upsert(upsert, onConflict: "user_id,activity_type,record_type")
            .execute()
    }
    
    /// Fetch personal records for an activity type
    func fetchCardioPRs(activityType: String? = nil) async -> [CardioPRDTO] {
        guard let userId = currentUser?.id else { return [] }
        
        do {
            var query = client
                .from("cardio_personal_records")
                .select()
                .eq("user_id", value: userId.uuidString)
            
            if let activity = activityType {
                query = query.eq("activity_type", value: activity)
            }
            
            let response: [CardioPRDTO] = try await query
                .order("achieved_at", ascending: false)
                .execute()
                .value
            
            return response
        } catch {
            AppLogger.warning("[CARDIO] Failed to fetch PRs: \(error)", category: .network)
            return []
        }
    }
    
    /// Fetch recent cardio workouts
    func fetchRecentCardioWorkouts(limit: Int = 20, activityType: String? = nil) async throws -> [CardioWorkoutDTO] {
        guard let userId = currentUser?.id else { return [] }
        
        var query = client
            .from("cardio_workouts")
            .select()
            .eq("user_id", value: userId.uuidString)
        
        if let activity = activityType {
            query = query.eq("activity_type", value: activity)
        }
        
        let response: [CardioWorkoutDTO] = try await query
            .order("completed_at", ascending: false)
            .limit(limit)
            .execute()
            .value
        
        AppLogger.debug("[CARDIO] Fetched \(response.count) workouts", category: .network)
        return response
    }
    
    /// Fetch total cardio workout count (all-time) for the current user.
    /// Lightweight query — only fetches IDs, not full workout data.
    func fetchCardioWorkoutCount() async throws -> Int {
        guard let userId = currentUser?.id else { return 0 }
        
        struct IdOnly: Codable { let id: String }
        let rows: [IdOnly] = try await client
            .from("cardio_workouts")
            .select("id")
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value
        
        return rows.count
    }
    
    /// Fetch cardio statistics for a date range
    func fetchCardioStats(startDate: Date, endDate: Date) async throws -> CardioStatsDTO {
        guard let userId = currentUser?.id else {
            return CardioStatsDTO(totalWorkouts: 0, totalDuration: 0, totalDistance: 0, totalCalories: 0, workoutsByType: [:])
        }
        
        let startString = iso8601Formatter.string(from: startDate)
        let endString = iso8601Formatter.string(from: endDate)
        
        let workouts: [CardioWorkoutDTO] = try await client
            .from("cardio_workouts")
            .select()
            .eq("user_id", value: userId.uuidString)
            .gte("completed_at", value: startString)
            .lte("completed_at", value: endString)
            .execute()
            .value
        
        let totalDuration = workouts.reduce(0) { $0 + $1.durationSeconds }
        let totalDistance = workouts.reduce(0.0) { $0 + $1.distanceMeters }
        let totalCalories = workouts.reduce(0.0) { $0 + $1.caloriesBurned }
        
        // Group by activity type
        var byType: [String: Int] = [:]
        for workout in workouts {
            byType[workout.activityType, default: 0] += 1
        }
        
        return CardioStatsDTO(
            totalWorkouts: workouts.count,
            totalDuration: totalDuration,
            totalDistance: totalDistance,
            totalCalories: totalCalories,
            workoutsByType: byType
        )
    }
    
    /// Fetch cardio streak information
    func fetchCardioStreak() async -> CardioStreakDTO? {
        guard let userId = currentUser?.id else { return nil }
        
        do {
            let response: [CardioStreakDTO] = try await client
                .from("cardio_streaks")
                .select()
                .eq("user_id", value: userId.uuidString)
                .eq("streak_type", value: "daily_cardio")
                .execute()
                .value
            
            return response.first
        } catch {
            AppLogger.warning("[CARDIO] Failed to fetch streak: \(error)", category: .network)
            return nil
        }
    }
    
    /// Fetch weekly cardio summaries for trend analysis
    func fetchCardioWeeklySummaries(weeks: Int = 12) async throws -> [CardioWeeklySummaryDTO] {
        guard let userId = currentUser?.id else { return [] }
        
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .weekOfYear, value: -weeks, to: Date()) ?? Date()
        let startString = dateToISO( startDate)
        
        let response: [CardioWeeklySummaryDTO] = try await client
            .from("cardio_weekly_summaries")
            .select()
            .eq("user_id", value: userId.uuidString)
            .gte("week_start", value: startString)
            .order("week_start", ascending: false)
            .execute()
            .value
        
        return response
    }
    
    // MARK: - Cardio Goals
    
    /// Create a new cardio goal
    func createCardioGoal(
        name: String,
        goalType: String,
        activityType: String?,
        targetValue: Double,
        unit: String,
        periodType: String,
        periodStart: Date,
        periodEnd: Date
    ) async throws {
        guard let userId = currentUser?.id else { return }
        
        struct CardioGoalInsert: Encodable {
            let user_id: String
            let goal_name: String
            let goal_type: String
            let activity_type: String?
            let target_value: Double
            let unit: String
            let period_type: String
            let period_start: String
            let period_end: String
        }
        
        let dateFormatter = ymdFormatter
        
        let insert = CardioGoalInsert(
            user_id: userId.uuidString,
            goal_name: name,
            goal_type: goalType,
            activity_type: activityType,
            target_value: targetValue,
            unit: unit,
            period_type: periodType,
            period_start: dateFormatter.string(from: periodStart),
            period_end: dateFormatter.string(from: periodEnd)
        )
        
        try await client
            .from("cardio_goals")
            .insert(insert)
            .execute()
        
        AppLogger.info("[CARDIO] Goal created: \(name)", category: .network)
    }
    
    /// Fetch active cardio goals
    func fetchActiveCardioGoals() async throws -> [CardioGoalDTO] {
        guard let userId = currentUser?.id else { return [] }
        
        let today = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
        
        let response: [CardioGoalDTO] = try await client
            .from("cardio_goals")
            .select()
            .eq("user_id", value: userId.uuidString)
            .eq("is_active", value: true)
            .execute()
            .value
        
        return response
    }
    
    // MARK: - Exercise Nicknames
    
    /// Fetch all exercise nicknames for the current user
    func fetchExerciseNicknames() async throws -> [ExerciseNicknameDTO] {
        guard let userId = currentUser?.id else { return [] }
        
        let response: [ExerciseNicknameDTO] = try await client
            .from("user_exercise_nicknames")
            .select()
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value
        
        AppLogger.debug("[NICKNAMES] Fetched \(response.count) exercise nicknames", category: .network)
        return response
    }
    
    /// Save or update an exercise nickname
    func saveExerciseNickname(officialName: String, nickname: String, exerciseId: UUID? = nil) async throws {
        guard let userId = currentUser?.id else {
            AppLogger.warning("[NICKNAMES] Cannot save - no user logged in", category: .network)
            return
        }
        
        struct NicknameUpsert: Encodable {
            let user_id: String
            let official_name: String
            let nickname: String
            let exercise_id: String?
            let updated_at: String
        }
        
        let upsert = NicknameUpsert(
            user_id: userId.uuidString,
            official_name: officialName,
            nickname: nickname,
            exercise_id: exerciseId?.uuidString,
            updated_at: dateToISO(Date())
        )
        
        try await client
            .from("user_exercise_nicknames")
            .upsert(upsert, onConflict: "user_id,official_name")
            .execute()
        
        AppLogger.info("[NICKNAMES] Saved: '\(officialName)' -> '\(nickname)'", category: .network)
    }
    
    /// Delete an exercise nickname (revert to official name)
    func deleteExerciseNickname(officialName: String) async throws {
        guard let userId = currentUser?.id else { return }
        
        try await client
            .from("user_exercise_nicknames")
            .delete()
            .eq("user_id", value: userId.uuidString)
            .eq("official_name", value: officialName)
            .execute()
        
        AppLogger.info("[NICKNAMES] Deleted nickname for '\(officialName)'", category: .network)
    }
    
    // MARK: - Comprehensive Data Sync
    
    /// 🔒 Sync state tracking to prevent duplicate syncs
    private static var isSyncInProgress = false
    private static var lastSyncTime: Date?
    private static let minSyncInterval: TimeInterval = 300 // Minimum 5 minutes between full syncs
    
    /// Syncs all user data from cloud to Core Data
    /// ⚡️ PERFORMANCE: Now with deduplication, throttling, and heavy work signaling
    /// - Parameter force: When true, bypasses both the dedup guard and the time-based throttle.
    ///   Used after authentication (OAuth/email sign-in) where we MUST refresh `hasCompletedOnboarding`
    ///   and other cloud state regardless of how recently a previous (signed-out) session synced.
    func syncAllDataFromCloud(force: Bool = false) async {
        // 🛡️ DEDUPLICATION: Prevent concurrent syncs (skipped when forced post-auth)
        if !force {
            guard !SupabaseManager.isSyncInProgress else {
                AppLogger.warning("[SYNC] Skipping - sync already in progress", category: .network)
                return
            }

            // 🛡️ THROTTLING: Prevent too-frequent syncs
            if let lastSync = SupabaseManager.lastSyncTime,
               Date().timeIntervalSince(lastSync) < SupabaseManager.minSyncInterval {
                AppLogger.warning("[SYNC] Skipping - synced \(Int(Date().timeIntervalSince(lastSync)))s ago (min: \(Int(SupabaseManager.minSyncInterval))s)", category: .network)
                return
            }
        } else if SupabaseManager.isSyncInProgress {
            AppLogger.info("[SYNC] Forced sync requested while another sync is running - proceeding to ensure post-auth state is fresh", category: .network)
        } else {
            AppLogger.info("[SYNC] Forced sync requested - bypassing throttle (post-auth refresh)", category: .network)
        }
        
        SupabaseManager.isSyncInProgress = true
        
        // 🔴 Signal heavy work - pauses video prefetching to reduce CPU load
        HeavyWorkSentinel.shared.beginHeavyWork(reason: "Data sync from cloud")
        
        defer { 
            SupabaseManager.isSyncInProgress = false 
            SupabaseManager.lastSyncTime = Date()
            // 🟢 Signal heavy work complete - resumes video prefetching
            HeavyWorkSentinel.shared.endHeavyWork(reason: "Data sync from cloud")
        }
        
        let wf = StartupWaterfall.shared
        wf.mark("CloudSync (total)")
        AppLogger.debug("Starting comprehensive data sync from cloud...", category: .network)
        
        do {
            // Snappiness Overhaul Phase 5.E (2026-05-07) — measure-window
            // slimming for `CloudSync: profile` (was 4800ms cold-start, now
            // ~150-300ms = pure network + Core Data write).
            //
            // OFF (legacy path): two MainActor.run hops INSIDE the measure
            // — the outer one set isVerified/isGoldVerified redundantly with
            // the inner one inside `syncUserProfileToCoreData`'s tail. Each
            // hop blocks the bg-init Task on main runloop quiescence; cold
            // start contention inflated the wall time.
            //
            // ON (Phase 5.E): only the data work (network fetch + bgContext
            // .perform write) lives inside the measure. The MainActor side
            // effects (isVerified, UnitSettings, reloadCurrentUser,
            // checkAndBreakStreakIfNeeded) are deferred to a fire-and-forget
            // Task that runs AFTER the measure block exits. Field-by-field
            // Core Data write is byte-identical (audit: see test
            // `Phase5ProfileSyncTests.testFieldsPopulatedIdentical`).
            if PerfFlags.phase5ProfileSync {
                var fetchedProfile: UserProfileDTO?
                await wf.measure("CloudSync: profile") {
                    if let cloudProfile = try? await fetchUserProfile() {
                        fetchedProfile = cloudProfile
                        await applyProfileToCoreDataFast(profile: cloudProfile)
                    }
                }
                if let profile = fetchedProfile {
                    Task { @MainActor in
                        UserManager.shared.isVerified = profile.isVerified ?? false
                        UserManager.shared.isGoldVerified = profile.isGoldVerified ?? false
                        UnitSettingsManager.shared.loadFromCloud(
                            weightUnit: profile.weightUnit,
                            heightUnit: profile.heightUnit,
                            distanceUnit: profile.distanceUnit,
                            weekStartDay: profile.weekStartDay
                        )
                        UserManager.shared.reloadCurrentUser()
                        UserManager.shared.checkAndBreakStreakIfNeeded()
                    }
                }
            } else {
                await wf.measure("CloudSync: profile") {
                    if let cloudProfile = try? await fetchUserProfile() {
                        await MainActor.run {
                            UserManager.shared.isVerified = cloudProfile.isVerified ?? false
                            UserManager.shared.isGoldVerified = cloudProfile.isGoldVerified ?? false
                        }
                        await syncUserProfileToCoreData(profile: cloudProfile)
                    }
                }
            }
            
            if !WorkoutManager.shared.isWorkoutActive {
                await wf.measure("CloudSync: exercises") {
                    await ExerciseLibraryService.shared.syncExercisesFromCloud()
                }
            } else {
                AppLogger.warning("[SYNC] Skipping exercise sync during active workout", category: .network)
            }
            
            try await wf.measure("CloudSync: favorites+custom") {
                let favoriteNames = try await fetchFavorites()
                await syncFavoritesToCoreData(favoriteNames: favoriteNames)
                let customExercises = try await fetchCustomExercises()
                await syncCustomExercisesToCoreData(customExercises: customExercises)
            }
            
            try await wf.measure("CloudSync: workoutHistory") {
                let favoriteWorkouts = try await fetchFavoriteWorkouts()
                await syncFavoriteWorkoutsToCoreData(favoriteWorkouts: favoriteWorkouts)
                let workoutHistory = try await fetchWorkoutHistory()
                await syncWorkoutHistoryToCoreData(workouts: workoutHistory)
            }
            
            try await wf.measure("CloudSync: meals+nicknames") {
                let mealLogs = try await fetchMealLogs()
                await syncMealLogsToCoreData(meals: mealLogs)
                await ExerciseNicknameService.shared.loadNicknames()
            }
            
            wf.end("CloudSync (total)")
            AppLogger.info("Comprehensive data sync completed!", category: .network)

            // After workout history is hydrated into Core Data, eagerly recompute
            // the progressive-unlock maturity profile so the autogen path doesn't
            // briefly see the post-sign-in empty default and gate the user to
            // foundational/stretch-only exercises. Bug-intel Report 8.
            await MainActor.run {
                let viewContext = PersistenceController.shared.container.viewContext
                Task { @MainActor in
                    await ProgressiveExerciseUnlockService.shared.recomputeProfile(context: viewContext)
                }
            }
        } catch {
            wf.end("CloudSync (total)")
            // Cluster F (fingerprint c8898dbd): comprehensive sync runs on
            // foreground/login — if the device is briefly offline the sync
            // throws -1005 / -1009 and the generic `.error` fingerprinted
            // every recovery. Classify so transient network lands at
            // `.warning` (retry queue owns recovery) and only genuine sync
            // bugs surface at `.error`.
            _ = NetworkErrorClassifier.log(
                error,
                context: "Error during comprehensive sync",
                category: .network,
                op: "cloud_sync.comprehensive",
                userId: currentUser?.id
            )
        }
    }
    
    /// Snappiness Overhaul Phase 5.E (2026-05-07) — Fast variant of
    /// `syncUserProfileToCoreData` that ONLY does the bgContext.perform
    /// write + save and OMITS the trailing `MainActor.run` side-effect
    /// cascade (`isVerified`, `UnitSettings.loadFromCloud`,
    /// `reloadCurrentUser`, `checkAndBreakStreakIfNeeded`).
    ///
    /// The Core Data write body below is byte-identical to the bg.perform
    /// block in `syncUserProfileToCoreData(profile:)` — same fields, same
    /// merge logic, same UserDefaults sidecar writes. The caller
    /// (`syncAllDataFromCloud` Phase 5.E branch) is responsible for
    /// scheduling the MainActor side-effects on a fire-and-forget Task
    /// AFTER the measure block exits, so the StartupWaterfall timeline
    /// reflects pure data work instead of main-thread contention.
    ///
    /// Field-by-field parity audit: see
    /// `Fit33Tests/Phase5ProfileSyncTests.swift::testFieldsPopulatedIdentical`.
    private func applyProfileToCoreDataFast(profile: UserProfileDTO) async {
        let bgContext = PersistenceController.shared.container.newBackgroundContextSafely()
        let isoFormatter = iso8601Formatter

        await bgContext.perform {
            let fetchRequest: NSFetchRequest<User> = User.fetchRequest()

            do {
                let existingUsers = try bgContext.fetch(fetchRequest)
                let user: User

                if let existingUser = existingUsers.first {
                    user = existingUser
                    AppLogger.debug("Updating existing user from cloud profile (fast)", category: .network)

                    // 🩹 SELF-HEAL: keep parity with syncUserProfileToCoreData.
                    if let cloudUUID = UUID(uuidString: profile.id), user.id != cloudUUID {
                        AppLogger.warning("[SYNC] Self-healing User.id mismatch — local=\(user.id?.uuidString ?? "nil") cloud=\(cloudUUID.uuidString). Aligning to auth.uid for RLS.", category: .network)
                        user.id = cloudUUID
                    }
                } else {
                    guard let profileUUID = UUID(uuidString: profile.id) else {
                        AppLogger.error("Cloud profile has malformed UUID '\(profile.id)' — skipping sync to avoid orphaned Core Data row", category: .network)
                        return
                    }
                    user = User(context: bgContext)
                    user.id = profileUUID
                    user.createdAt = Date()
                    AppLogger.debug("Creating new user from cloud profile (fast)", category: .network)
                }

                let cloudName = profile.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let localName = user.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let cloudIsPlaceholder = cloudName.isEmpty || cloudName == "User" || cloudName == "Apple User" || cloudName == "Google User" || cloudName == "Facebook User"
                let localIsPlaceholder = localName.isEmpty || localName == "User" || localName == "Apple User" || localName == "Google User" || localName == "Facebook User"
                if !cloudIsPlaceholder {
                    user.name = profile.name
                } else if localIsPlaceholder {
                    user.name = profile.name
                } else {
                    AppLogger.debug("[SYNC] Skipping name overwrite — cloud='\(cloudName)' is placeholder, local='\(localName)' is real", category: .network)
                }
                user.email = profile.email
                user.fitnessGoal = profile.fitnessGoal
                user.experienceLevel = profile.experienceLevel
                user.hasCompletedOnboarding = profile.hasCompletedOnboarding ?? false

                if let birthday = profile.birthday {
                    user.birthday = birthday
                }
                if let age = profile.age {
                    user.age = Int16(age)
                }
                if let gender = profile.gender {
                    user.gender = gender
                }
                if let height = profile.heightCm {
                    user.height = Int16(height)
                    UserDefaults.standard.set(Int(height), forKey: "userHeight")
                }
                if let heightInches = profile.heightInches {
                    user.heightInches = Int16(heightInches)
                }
                if let weight = profile.weightKg {
                    user.weight = Int16(weight)
                    UserDefaults.standard.set(Int(weight), forKey: "userWeight")
                }
                if let weightLbs = profile.weightLbs {
                    user.weightLbs = weightLbs
                }
                if let equipment = profile.equipment {
                    user.equipment = equipment as NSArray
                }
                if let availableDays = profile.availableDays {
                    user.availableDays = Int16(availableDays)
                }

                let cloudLastWorkoutDate = profile.lastWorkoutDate.flatMap { isoFormatter.date(from: $0) }
                let localLastWorkoutDate = user.lastWorkoutDate

                let cloudIsNewer = {
                    guard let cloudDate = cloudLastWorkoutDate else { return false }
                    guard let localDate = localLastWorkoutDate else { return true }
                    return cloudDate > localDate
                }()

                if cloudIsNewer {
                    user.currentStreak = Int16(profile.currentStreak ?? 0)
                    user.lastWorkoutDate = cloudLastWorkoutDate
                }
                let cloudLongest = Int16(profile.longestStreak ?? 0)
                if cloudLongest > user.longestStreak {
                    user.longestStreak = cloudLongest
                }
                let cloudWorkouts = Int32(profile.totalWorkouts ?? 0)
                if cloudWorkouts > user.totalWorkouts {
                    user.totalWorkouts = cloudWorkouts
                }
                let cloudXP = Int32(profile.xp ?? 0)
                if cloudXP > user.xp {
                    user.xp = cloudXP
                }

                if let gender = profile.gender {
                    UserDefaults.standard.set(gender, forKey: "userGender")
                }

                try bgContext.save()
                AppLogger.info("Full user profile synced from cloud (fast): Name=\(profile.name ?? "nil"), Age=\(profile.age ?? 0), Height=\(profile.heightCm ?? 0)cm, Weight=\(profile.weightKg ?? 0)kg, Goal=\(profile.fitnessGoal ?? "nil"), Level=\(profile.experienceLevel ?? "nil"), Equipment=\(profile.equipment ?? []), Days=\(profile.availableDays ?? 0), XP=\(profile.xp ?? 0), Streak=\(profile.currentStreak ?? 0), Workouts=\(profile.totalWorkouts ?? 0)", category: .network)
            } catch {
                _ = NetworkErrorClassifier.log(
                    error,
                    context: "Error syncing user profile to Core Data (fast)",
                    category: .network,
                    op: PerformanceSignposts.Op.cloudSyncProfile.rawValue,
                    endpoint: "coredata/user(profile save fast)"
                )
            }
        }
        // NOTE: NO trailing `MainActor.run` here — caller schedules the side
        // effects (isVerified, UnitSettings, reloadCurrentUser,
        // checkAndBreakStreakIfNeeded) on a fire-and-forget Task AFTER the
        // measure block exits. See `syncAllDataFromCloud` Phase 5.E branch.
    }

    /// Restores user profile from cloud to Core Data
    private func syncUserProfileToCoreData(profile: UserProfileDTO) async {
        let bgContext = PersistenceController.shared.container.newBackgroundContextSafely()
        let isoFormatter = iso8601Formatter
        
        await bgContext.perform {
            let fetchRequest: NSFetchRequest<User> = User.fetchRequest()
            
            do {
                let existingUsers = try bgContext.fetch(fetchRequest)
                let user: User
                
                if let existingUser = existingUsers.first {
                    user = existingUser
                    AppLogger.debug("Updating existing user from cloud profile", category: .network)

                    // 🩹 SELF-HEAL: If the local User.id drifted from the cloud
                    // profile.id (which is the Supabase auth.uid), repair it.
                    // Otherwise every workout-intelligence write fails RLS
                    // (`WITH CHECK (user_id = auth.uid())`). This recovers
                    // accounts created before the createUser() fix that
                    // assigned a random UUID instead of auth.uid.
                    if let cloudUUID = UUID(uuidString: profile.id), user.id != cloudUUID {
                        AppLogger.warning("[SYNC] Self-healing User.id mismatch — local=\(user.id?.uuidString ?? "nil") cloud=\(cloudUUID.uuidString). Aligning to auth.uid for RLS.", category: .network)
                        user.id = cloudUUID
                    }
                } else {
                    guard let profileUUID = UUID(uuidString: profile.id) else {
                        AppLogger.error("Cloud profile has malformed UUID '\(profile.id)' — skipping sync to avoid orphaned Core Data row", category: .network)
                        return
                    }
                    user = User(context: bgContext)
                    user.id = profileUUID
                    user.createdAt = Date()
                    AppLogger.debug("Creating new user from cloud profile", category: .network)
                }
                
                // Update ALL user fields from cloud.
                //
                // ⚠️ Only overwrite `user.name` when the cloud actually has a
                // real name. Email/password signup writes a placeholder
                // name="User" to the cloud BEFORE the user enters their real
                // name on the username step; if a cloud-pull races against
                // the onboarding write the placeholder must NOT clobber the
                // real local name. (Other fields below already use `if let`
                // for the same reason — name was the lone unconditional
                // assignment and the source of the "Profile shows User"
                // bug.)
                let cloudName = profile.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let localName = user.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let cloudIsPlaceholder = cloudName.isEmpty || cloudName == "User" || cloudName == "Apple User" || cloudName == "Google User" || cloudName == "Facebook User"
                let localIsPlaceholder = localName.isEmpty || localName == "User" || localName == "Apple User" || localName == "Google User" || localName == "Facebook User"
                if !cloudIsPlaceholder {
                    // Cloud has a real name — accept it.
                    user.name = profile.name
                } else if localIsPlaceholder {
                    // Both sides are placeholder — keep cloud's value to stay
                    // consistent with the rest of the profile.
                    user.name = profile.name
                } else {
                    AppLogger.debug("[SYNC] Skipping name overwrite — cloud='\(cloudName)' is placeholder, local='\(localName)' is real", category: .network)
                }
                user.email = profile.email
                user.fitnessGoal = profile.fitnessGoal
                user.experienceLevel = profile.experienceLevel
                
                // Use the cloud's onboarding status - new social users will have this as false
                // Only set to true if the cloud says so (meaning they completed onboarding before)
                user.hasCompletedOnboarding = profile.hasCompletedOnboarding ?? false

                // Sync all profile data
                if let birthday = profile.birthday {
                    user.birthday = birthday
                }
                if let age = profile.age {
                    user.age = Int16(age)
                }
                if let gender = profile.gender {
                    user.gender = gender
                }
                if let height = profile.heightCm {
                    user.height = Int16(height)
                    UserDefaults.standard.set(Int(height), forKey: "userHeight")
                }
                if let heightInches = profile.heightInches {
                    user.heightInches = Int16(heightInches)
                }
                if let weight = profile.weightKg {
                    user.weight = Int16(weight)
                    UserDefaults.standard.set(Int(weight), forKey: "userWeight")
                }
                if let weightLbs = profile.weightLbs {
                    user.weightLbs = weightLbs
                }
                if let equipment = profile.equipment {
                    user.equipment = equipment as NSArray
                }
                if let availableDays = profile.availableDays {
                    user.availableDays = Int16(availableDays)
                }
                
                // Sync progress data - merge strategy: keep the more recent/higher values
                let cloudLastWorkoutDate = profile.lastWorkoutDate.flatMap { isoFormatter.date(from: $0) }
                let localLastWorkoutDate = user.lastWorkoutDate

                // For streak data, use whichever source has the more recent lastWorkoutDate
                let cloudIsNewer = {
                    guard let cloudDate = cloudLastWorkoutDate else { return false }
                    guard let localDate = localLastWorkoutDate else { return true }
                    return cloudDate > localDate
                }()

                if cloudIsNewer {
                    user.currentStreak = Int16(profile.currentStreak ?? 0)
                    user.lastWorkoutDate = cloudLastWorkoutDate
                }
                // longestStreak: always keep the higher value
                let cloudLongest = Int16(profile.longestStreak ?? 0)
                if cloudLongest > user.longestStreak {
                    user.longestStreak = cloudLongest
                }
                // totalWorkouts and XP: keep the higher value
                let cloudWorkouts = Int32(profile.totalWorkouts ?? 0)
                if cloudWorkouts > user.totalWorkouts {
                    user.totalWorkouts = cloudWorkouts
                }
                let cloudXP = Int32(profile.xp ?? 0)
                if cloudXP > user.xp {
                    user.xp = cloudXP
                }
                
                // Sync gender to UserDefaults for nutrition calculations
                if let gender = profile.gender {
                    UserDefaults.standard.set(gender, forKey: "userGender")
                }
                
                try bgContext.save()
                AppLogger.info("Full user profile synced from cloud: Name=\(profile.name ?? "nil"), Age=\(profile.age ?? 0), Height=\(profile.heightCm ?? 0)cm, Weight=\(profile.weightKg ?? 0)kg, Goal=\(profile.fitnessGoal ?? "nil"), Level=\(profile.experienceLevel ?? "nil"), Equipment=\(profile.equipment ?? []), Days=\(profile.availableDays ?? 0), XP=\(profile.xp ?? 0), Streak=\(profile.currentStreak ?? 0), Workouts=\(profile.totalWorkouts ?? 0)", category: .network)
            } catch {
                _ = NetworkErrorClassifier.log(
                    error,
                    context: "Error syncing user profile to Core Data",
                    category: .network,
                    op: PerformanceSignposts.Op.cloudSyncProfile.rawValue,
                    endpoint: "coredata/user(profile save)"
                )
            }
        }
        
        await MainActor.run {
            UserManager.shared.isVerified = profile.isVerified ?? false
            UserManager.shared.isGoldVerified = profile.isGoldVerified ?? false
            UnitSettingsManager.shared.loadFromCloud(
                weightUnit: profile.weightUnit,
                heightUnit: profile.heightUnit,
                distanceUnit: profile.distanceUnit,
                weekStartDay: profile.weekStartDay
            )
            UserManager.shared.reloadCurrentUser()
            UserManager.shared.checkAndBreakStreakIfNeeded()
        }
    }
    
    // MARK: - Workout History Cloud Sync
    
    /// Saves a completed workout to the cloud
    func saveWorkoutToCloud(workout: Workout, quality: WorkoutQualityResult? = nil) async throws {
        guard let userId = currentUser?.id,
              let workoutId = workout.id?.uuidString else { 
            AppLogger.warning("[WORKOUT SAVE] Cannot save - no user or workout ID", category: .network)
            return 
        }
        
        AppLogger.debug("[WORKOUT SAVE] Saving workout '\(workout.name ?? "Unnamed")' for user \(userId.uuidString.prefix(8))...", category: .network)
        
        // Build exercise data
        var exerciseDTOs: [WorkoutExerciseDTO] = []
        
        if let workoutExercises = workout.exercises?.allObjects as? [WorkoutExercise] {
            for we in workoutExercises.sorted(by: { $0.order < $1.order }) {
                var setDTOs: [WorkoutSetDTO] = []
                
                if let sets = we.sets?.allObjects as? [WorkoutSet] {
                    for set in sets.sorted(by: { $0.setNumber < $1.setNumber }) {
                        let setDTO = WorkoutSetDTO(
                            id: set.id?.uuidString ?? UUID().uuidString,
                            setNumber: Int(set.setNumber),
                            reps: Int(set.reps),
                            weight: set.weight,
                            isCompleted: set.isCompleted,
                            setType: set.setType  // Warmup, Dropset, Failure, AMRAP, etc.
                        )
                        setDTOs.append(setDTO)
                    }
                }
                
                let exerciseDTO = WorkoutExerciseDTO(
                    id: we.id?.uuidString ?? UUID().uuidString,
                    exerciseName: we.exercise?.name ?? "Unknown",
                    order: Int(we.order),
                    sets: setDTOs,
                    notes: we.notes
                )
                exerciseDTOs.append(exerciseDTO)
            }
        }
        
        var totalPlanned = 0
        var totalCompleted = 0
        for ex in exerciseDTOs {
            totalPlanned += ex.sets.count
            totalCompleted += ex.sets.filter { $0.isCompleted }.count
        }
        let rate = totalPlanned > 0 ? Double(totalCompleted) / Double(totalPlanned) : 1.0

        // Origin classification (#156). Programmed workouts come from
        // SmartProgram → 'program'; auto-gen has the marker prefix in name;
        // everything else is custom. Cardio detection is V2 (we don't have
        // a clean signal yet — workouts that consist only of duration_based
        // exercises could be inferred but that's noisy).
        let inferredWorkoutType: String = {
            if WorkoutManager.shared.currentSmartProgramId != nil { return "program" }
            let name = (workout.name ?? "").lowercased()
            if name.hasPrefix("auto") || name.hasPrefix("quick") { return "auto_gen" }
            return "custom"
        }()

        let workoutDTO = WorkoutHistoryDTO(
            id: workoutId,
            userId: userId.uuidString,
            name: workout.name ?? "Workout",
            date: dateToISO( workout.date ?? Date()),
            duration: Int(workout.duration),
            isCompleted: workout.isCompleted,
            xpEarned: Int(workout.xpEarned),
            notes: workout.notes,
            exercises: exerciseDTOs,
            completionRate: rate,
            totalSetsPlanned: totalPlanned,
            totalSetsCompleted: totalCompleted,
            caloriesBurned: workout.caloriesBurned > 0 ? workout.caloriesBurned : nil,
            qualityScore: quality?.score,
            qualityBand: quality?.band.rawValue,
            workoutType: inferredWorkoutType
        )
        
        try await client
            .from("workout_history")
            .upsert(workoutDTO)
            .execute()
        
        AppLogger.debug("Workout saved to cloud: \(workout.name ?? "Workout")", category: .network)

        // Migration #154: ask the server to canonicalize the quality score
        // server-side. Client values are optimistic; this RPC is the
        // source-of-truth and updates `quality_reasons` JSONB too.
        // Fire-and-forget — failure here doesn't undo the insert.
        Task { [client] in
            do {
                _ = try await client
                    .rpc("score_workout_quality", params: ["p_workout_id": workoutId])
                    .execute()
            } catch {
                AppLogger.warning("[QUALITY] score_workout_quality RPC failed (non-fatal): \(error.localizedDescription)", category: .network)
            }
        }

        // Migration #156: enqueue the workout for Claude analysis. The RPC
        // only enqueues if the workout has a quality_score (it does, after
        // the score RPC above settles — small race is fine because the
        // pending row gets picked up by the next cron run). Lost-session
        // workouts (60-69) are also enqueued but flagged is_lost_session.
        Task { [client] in
            do {
                _ = try await client
                    .rpc("enqueue_quality_workout_for_analysis", params: ["p_workout_id": workoutId])
                    .execute()
                AppLogger.debug("[INTEL] Workout enqueued for analysis: \(workoutId.prefix(8))", category: .network)
            } catch {
                AppLogger.warning("[INTEL] enqueue RPC failed (non-fatal): \(error.localizedDescription)", category: .network)
            }
        }

        // Migration #156: flush in-flight swap audit rows now that we have
        // a stable workout_id. WorkoutManager captured these during the
        // workout but couldn't write them earlier (FK to workout_history).
        let pending = WorkoutManager.shared.pendingSwapEvents
        if !pending.isEmpty {
            Task { [client, userId] in
                let rows = pending.map { evt in
                    WorkoutSwapEventDTO(
                        userId: userId.uuidString,
                        workoutId: workoutId,
                        swapIndex: evt.swapIndex,
                        originalExerciseId: evt.originalExerciseId?.uuidString,
                        originalExerciseName: evt.originalExerciseName,
                        replacementExerciseId: evt.replacementExerciseId?.uuidString,
                        replacementExerciseName: evt.replacementExerciseName,
                        pickedRank: evt.pickedRank,
                        swapSource: evt.swapSource,
                        completedReplacement: evt.completedReplacement
                    )
                }
                do {
                    try await client.from("workout_swap_events").insert(rows).execute()
                    AppLogger.info("[SWAP AUDIT] Flushed \(rows.count) swap events for workout \(workoutId.prefix(8))", category: .network)
                } catch {
                    AppLogger.warning("[SWAP AUDIT] Failed to flush swap events (non-fatal): \(error.localizedDescription)", category: .network)
                }
            }
            // Clear after the Task captures the array.
            await MainActor.run { WorkoutManager.shared.pendingSwapEvents.removeAll() }
        }
    }

    /// Atomically delete a completed workout AND reverse every server-side
    /// stat side-effect (XP / streak / league / quests / corpus). Migration
    /// #155 (`20260724_delete_workout_and_revert_stats.sql`).
    ///
    /// Returns the structured RPC result so callers can show "+/- N XP"
    /// feedback. Throws if the network/RPC fails — callers should still
    /// proceed with local Core Data deletion to avoid a stuck UI.
    @discardableResult
    func deleteWorkoutAndRevertStats(workoutId: UUID) async throws -> DeleteWorkoutRevertResponse {
        AppLogger.info("[WORKOUT DELETE] Calling delete_workout_and_revert_stats for \(workoutId.uuidString.prefix(8))...", category: .network)
        let response: DeleteWorkoutRevertResponse = try await client
            .rpc("delete_workout_and_revert_stats", params: ["p_workout_id": workoutId.uuidString])
            .execute()
            .value
        AppLogger.info("[WORKOUT DELETE] Server reverted: xp=-\(response.xpReverted ?? 0) league=-\(response.leaguePointsReverted ?? 0) quests=\(response.questRowsUpdated ?? 0)", category: .network)
        return response
    }
    
    /// Updates only the calories_burned field on an existing workout_history row.
    /// Used after HealthKit calorie calculation completes (avoids re-saving the entire workout).
    func updateWorkoutCalories(workoutId: String, calories: Double) async throws {
        guard currentUser != nil else { return }
        
        try await client
            .from("workout_history")
            .update(["calories_burned": calories])
            .eq("id", value: workoutId)
            .execute()
        
        AppLogger.debug("[WORKOUT] Updated calories to \(Int(calories)) for workout \(workoutId.prefix(8))", category: .network)
    }
    
    /// Fetches workout history from cloud
    func fetchWorkoutHistory() async throws -> [WorkoutHistoryDTO] {
        guard let userId = currentUser?.id else { 
            AppLogger.warning("[WORKOUT SYNC] No authenticated user - cannot fetch workout history", category: .network)
            return [] 
        }
        
        AppLogger.debug("[WORKOUT SYNC] Fetching workouts for user: \(userId.uuidString)", category: .network)
        
        let response: [WorkoutHistoryDTO] = try await client
            .from("workout_history")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("date", ascending: false)
            .limit(200)
            .execute()
            .value
        
        AppLogger.debug("[WORKOUT SYNC] Fetched \(response.count) workouts from cloud for user \(userId.uuidString.prefix(8))...", category: .network)
        return response
    }
    
    /// Syncs workout history from cloud to Core Data
    private func syncWorkoutHistoryToCoreData(workouts: [WorkoutHistoryDTO]) async {
        let bgContext = PersistenceController.shared.container.newBackgroundContextSafely()
        bgContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        let isoFormatter = iso8601Formatter
        
        await bgContext.perform {
            let userRequest: NSFetchRequest<User> = User.fetchRequest()
            userRequest.fetchLimit = 1
            
            guard let user = try? bgContext.fetch(userRequest).first else {
                AppLogger.warning("No user found for workout history sync", category: .network)
                return
            }
            
            for workoutDTO in workouts {
                // Skip workouts with malformed UUIDs instead of inserting orphan rows
                // that could never merge with the server copy.
                guard let workoutUUID = UUID(uuidString: workoutDTO.id) else {
                    AppLogger.error("Cloud workout has malformed UUID '\(workoutDTO.id)' — skipping", category: .network)
                    continue
                }
                // Check if workout already exists
                let fetchRequest: NSFetchRequest<Workout> = Workout.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id == %@", workoutUUID as CVarArg)
                
                do {
                    let existing = try bgContext.fetch(fetchRequest)
                    let workout: Workout
                    
                    if let existingWorkout = existing.first {
                        workout = existingWorkout
                        let existingExerciseCount = workout.exercises?.count ?? 0
                        let cloudExerciseCount = workoutDTO.exercises.count
                        
                        if cloudExerciseCount > existingExerciseCount {
                            if let oldExercises = workout.exercises?.allObjects as? [WorkoutExercise] {
                                for oldExercise in oldExercises {
                                    bgContext.delete(oldExercise)
                                }
                            }
                            
                            for exerciseDTO in workoutDTO.exercises {
                                guard let workoutExerciseId = UUID(uuidString: exerciseDTO.id) else {
                                    AppLogger.error("Cloud workout exercise has malformed UUID '\(exerciseDTO.id)' — skipping", category: .network)
                                    continue
                                }
                                let exerciseRequest: NSFetchRequest<Exercise> = Exercise.fetchRequest()
                                exerciseRequest.predicate = NSPredicate(format: "name == %@", exerciseDTO.exerciseName)
                                exerciseRequest.fetchLimit = 1
                                let exercise = try? bgContext.fetch(exerciseRequest).first
                                
                                let workoutExercise = WorkoutExercise(context: bgContext)
                                workoutExercise.id = workoutExerciseId
                                workoutExercise.order = Int16(exerciseDTO.order)
                                workoutExercise.notes = exerciseDTO.notes
                                workoutExercise.workout = workout
                                #if DEBUG
                                exercise?.assertContext(bgContext)
                                #endif
                                workoutExercise.exercise = exercise
                                
                                ExerciseNameCache.shared.cacheName(
                                    exerciseDTO.exerciseName,
                                    forWorkoutExerciseId: workoutExerciseId.uuidString
                                )
                                
                                for setDTO in exerciseDTO.sets {
                                    guard let setUUID = UUID(uuidString: setDTO.id) else {
                                        AppLogger.error("Cloud workout set has malformed UUID '\(setDTO.id)' — skipping", category: .network)
                                        continue
                                    }
                                    let workoutSet = WorkoutSet(context: bgContext)
                                    workoutSet.id = setUUID
                                    workoutSet.setNumber = Int16(setDTO.setNumber)
                                    workoutSet.reps = Int16(setDTO.reps)
                                    workoutSet.weight = setDTO.weight
                                    workoutSet.isCompleted = setDTO.isCompleted
                                    workoutSet.setType = setDTO.setType ?? "Normal"
                                    workoutSet.workoutExercise = workoutExercise
                                }
                            }
                        }
                    } else {
                        workout = Workout(context: bgContext)
                        workout.id = workoutUUID
                        workout.name = workoutDTO.name
                        workout.date = isoFormatter.date(from: workoutDTO.date)
                        workout.duration = Int32(workoutDTO.duration)
                        workout.isCompleted = workoutDTO.isCompleted
                        workout.xpEarned = Int32(workoutDTO.xpEarned)
                        workout.notes = workoutDTO.notes
                        workout.user = user
                        
                        for exerciseDTO in workoutDTO.exercises {
                            guard let workoutExerciseId = UUID(uuidString: exerciseDTO.id) else {
                                AppLogger.error("Cloud workout exercise has malformed UUID '\(exerciseDTO.id)' — skipping", category: .network)
                                continue
                            }
                            let exerciseRequest: NSFetchRequest<Exercise> = Exercise.fetchRequest()
                            exerciseRequest.predicate = NSPredicate(format: "name == %@", exerciseDTO.exerciseName)
                            exerciseRequest.fetchLimit = 1
                            let exercise = try? bgContext.fetch(exerciseRequest).first
                            
                            let workoutExercise = WorkoutExercise(context: bgContext)
                            workoutExercise.id = workoutExerciseId
                            workoutExercise.order = Int16(exerciseDTO.order)
                            workoutExercise.notes = exerciseDTO.notes
                            workoutExercise.workout = workout
                            #if DEBUG
                            exercise?.assertContext(bgContext)
                            #endif
                            workoutExercise.exercise = exercise
                            
                            ExerciseNameCache.shared.cacheName(
                                exerciseDTO.exerciseName,
                                forWorkoutExerciseId: workoutExerciseId.uuidString
                            )
                            
                            for setDTO in exerciseDTO.sets {
                                guard let setUUID = UUID(uuidString: setDTO.id) else {
                                    AppLogger.error("Cloud workout set has malformed UUID '\(setDTO.id)' — skipping", category: .network)
                                    continue
                                }
                                let workoutSet = WorkoutSet(context: bgContext)
                                workoutSet.id = setUUID
                                workoutSet.setNumber = Int16(setDTO.setNumber)
                                workoutSet.reps = Int16(setDTO.reps)
                                workoutSet.weight = setDTO.weight
                                workoutSet.isCompleted = setDTO.isCompleted
                                workoutSet.setType = setDTO.setType ?? "Normal"
                                workoutSet.workoutExercise = workoutExercise
                            }
                        }
                    }
                } catch {
                    _ = NetworkErrorClassifier.log(
                        error,
                        context: "Error checking existing workout during sync",
                        category: .network,
                        op: PerformanceSignposts.Op.cloudSyncWorkout.rawValue,
                        endpoint: "coredata/workout_history(fetch)",
                        userId: self.currentUser?.id
                    )
                }
            }
            
            do {
                try bgContext.save()
                AppLogger.info("Synced \(workouts.count) workouts from cloud", category: .network)
            } catch {
                _ = NetworkErrorClassifier.log(
                    error,
                    context: "Error saving workout history to Core Data",
                    category: .network,
                    op: PerformanceSignposts.Op.cloudSyncWorkout.rawValue,
                    endpoint: "coredata/workout_history(save)",
                    userId: self.currentUser?.id
                )
            }
        }
    }
    
    // MARK: - Meal Logs Cloud Sync
    
    /// Saves a meal entry to the cloud
    func saveMealToCloud(meal: MealEntry) async throws {
        guard let userId = currentUser?.id,
              let mealId = meal.id?.uuidString else { return }
        
        // OFF (Open Food Facts) products use synthetic NEGATIVE bigint fdcIds —
        // we send any non-zero id (positive USDA OR negative OFF) and only
        // strip the sentinel `0` (= "no provenance"). Filtering on `> 0` here
        // would silently drop every OFF meal log from cloud history.
        // The DB column was widened to BIGINT in supabase/20260801…off_barcode.sql
        // and meal_logs in supabase/20260802_meal_logs_off_columns.sql.
        let mealDTO = MealLogDTO(
            id: mealId,
            userId: userId.uuidString,
            date: dateToISO( meal.date ?? Date()),
            mealType: meal.mealType ?? "Other",
            foodName: meal.foodName ?? "Unknown",
            quantity: meal.quantity,
            unit: meal.unit,
            calories: Int(meal.calories),
            protein: Int(meal.protein),
            carbs: Int(meal.carbs),
            fat: Int(meal.fat),
            fdcId: meal.fdcId != 0 ? Int(meal.fdcId) : nil,
            fiber: meal.fiber > 0 ? meal.fiber : nil,
            sugar: meal.sugar > 0 ? meal.sugar : nil,
            sodium: meal.sodium > 0 ? meal.sodium : nil,
            source: meal.source,
            barcode: meal.barcode
        )
        
        try await client
            .from("meal_logs")
            .upsert(mealDTO)
            .execute()
        
        AppLogger.debug("Meal saved to cloud: \(meal.foodName ?? "Unknown")", category: .network)
    }
    
    /// Fetches meal logs from cloud
    func fetchMealLogs() async throws -> [MealLogDTO] {
        guard let userId = currentUser?.id else { return [] }
        
        let response: [MealLogDTO] = try await client
            .from("meal_logs")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("date", ascending: false)
            .limit(100)
            .execute()
            .value
        
        AppLogger.debug("Fetched \(response.count) meals from cloud", category: .network)
        return response
    }
    
    /// Deletes a meal entry from the cloud
    func deleteMealFromCloud(mealId: UUID) async throws {
        guard let userId = currentUser?.id else { 
            AppLogger.warning("[CLOUD] No user - skipping cloud delete", category: .network)
            return 
        }
        
        try await client
            .from("meal_logs")
            .delete()
            .eq("id", value: mealId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()
        
        AppLogger.debug("[CLOUD] Meal deleted from cloud: \(mealId)", category: .network)
    }
    
    /// Syncs meal logs from cloud to Core Data
    private func syncMealLogsToCoreData(meals: [MealLogDTO]) async {
        let bgContext = PersistenceController.shared.container.newBackgroundContextSafely()
        let isoFormatter = iso8601Formatter
        // Track which meals are NEW (vs already-known dedupes) so we can fire
        // daily-quest fan-out for cross-device meal logs. Without this hook,
        // a meal logged on iPhone was invisible to the Apple Watch's quest
        // engine until the device round-tripped through `addMealEntry`.
        // Bug found by 2026-04-30 nutrition pipeline audit.
        var newlyInsertedMealTypes: [String] = []
        
        await bgContext.perform {
            let userRequest: NSFetchRequest<User> = User.fetchRequest()
            userRequest.fetchLimit = 1
            
            guard let user = try? bgContext.fetch(userRequest).first else {
                AppLogger.warning("No user found for meal logs sync", category: .network)
                return
            }
            
            for mealDTO in meals {
                guard let mealUUID = UUID(uuidString: mealDTO.id) else {
                    AppLogger.error("Cloud meal has malformed UUID '\(mealDTO.id)' — skipping", category: .network)
                    continue
                }
                let fetchRequest: NSFetchRequest<MealEntry> = MealEntry.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id == %@", mealUUID as CVarArg)
                
                do {
                    let existing = try bgContext.fetch(fetchRequest)
                    if existing.isEmpty {
                        let meal = MealEntry(context: bgContext)
                        meal.id = mealUUID
                        meal.date = isoFormatter.date(from: mealDTO.date)
                        meal.mealType = mealDTO.mealType
                        meal.foodName = mealDTO.foodName
                        meal.quantity = mealDTO.quantity
                        meal.unit = mealDTO.unit
                        meal.calories = Int32(mealDTO.calories)
                        meal.protein = Int32(mealDTO.protein)
                        meal.carbs = Int32(mealDTO.carbs)
                        meal.fat = Int32(mealDTO.fat)
                        // Int64 cast (was Int32) — required for OFF synthetic
                        // negative bigints from `meal_logs.fdc_id BIGINT`.
                        meal.fdcId = Int64(mealDTO.fdcId ?? 0)
                        meal.fiber = mealDTO.fiber ?? 0
                        meal.sugar = mealDTO.sugar ?? 0
                        meal.sodium = mealDTO.sodium ?? 0
                        meal.source = mealDTO.source
                        meal.barcode = mealDTO.barcode
                        meal.user = user
                        newlyInsertedMealTypes.append(mealDTO.mealType)
                    }
                } catch {
                    _ = NetworkErrorClassifier.log(
                        error,
                        context: "Error checking existing meal during sync",
                        category: .network,
                        op: PerformanceSignposts.Op.cloudSyncMeal.rawValue,
                        endpoint: "coredata/meal_entry(fetch)",
                        userId: self.currentUser?.id
                    )
                }
            }
            
            do {
                try bgContext.save()
                AppLogger.info("Synced \(meals.count) meals from cloud", category: .network)
            } catch {
                _ = NetworkErrorClassifier.log(
                    error,
                    context: "Error saving meal logs to Core Data",
                    category: .network,
                    op: PerformanceSignposts.Op.cloudSyncMeal.rawValue,
                    endpoint: "coredata/meal_entry(save)",
                    userId: self.currentUser?.id
                )
            }
        }
        
        // Daily-quest fan-out for cross-device meal logs (was MISSING).
        // `MealService.addMealEntry` fires per-meal-type quests + log3Meals +
        // protein progress, but ONLY for the local-write path. Until this
        // hook landed, a Watch-logged or web-logged meal never advanced
        // quests on iPhone after sync. Audit caught 2026-04-30.
        if !newlyInsertedMealTypes.isEmpty {
            await MainActor.run {
                // Reload todaysMeals so dashboard + protein-goal recompute
                // reflect the freshly-pulled rows BEFORE quests fan out.
                MealService.shared.loadTodaysMeals()
            }
            for mealType in newlyInsertedMealTypes {
                await DailyQuestService.shared.onMealLogged(mealType: mealType)
            }
            // log3Meals is bumped per-call inside `onMealLogged`, so the
            // loop above already covers it. Protein progress recomputes
            // from `todaysMeals.reduce` on the next addMealEntry; no need
            // to duplicate here (would double-count if the user is also
            // logging locally in the same window).
        }
    }
    
    /// Sync favorites to Core Data - matches by exercise NAME (not ID, since IDs change on sync)
    private func syncFavoritesToCoreData(favoriteNames: [String]) async {
        let bgContext = PersistenceController.shared.container.newBackgroundContextSafely()
        
        let normalizedFavoriteNames = Set(favoriteNames.map { $0.lowercased().trimmingCharacters(in: .whitespaces) })
        
        await bgContext.perform {
            let fetchRequest: NSFetchRequest<Exercise> = Exercise.fetchRequest()
            
            do {
                let allExercises = try bgContext.fetch(fetchRequest)
                var matchedCount = 0
                
                for exercise in allExercises {
                    if let name = exercise.name {
                        let normalizedName = name.lowercased().trimmingCharacters(in: .whitespaces)
                        let isFavorite = normalizedFavoriteNames.contains(normalizedName)
                        if isFavorite {
                            matchedCount += 1
                        }
                        exercise.isFavorite = isFavorite
                    }
                }
                
                try bgContext.save()
                AppLogger.info("Synced \(matchedCount)/\(favoriteNames.count) favorites to Core Data (matched by name)", category: .network)
            } catch {
                _ = NetworkErrorClassifier.log(
                    error,
                    context: "Error syncing favorites to Core Data",
                    category: .network,
                    op: PerformanceSignposts.Op.cloudSyncFavorite.rawValue,
                    endpoint: "coredata/exercise(favorites save)",
                    userId: self.currentUser?.id
                )
            }
        }
    }
    
    private func syncCustomExercisesToCoreData(customExercises: [CustomExerciseDTO]) async {
        let bgContext = PersistenceController.shared.container.newBackgroundContextSafely()
        
        await bgContext.perform {
            for customExercise in customExercises {
                guard let customExerciseUUID = UUID(uuidString: customExercise.id) else {
                    AppLogger.error("Cloud custom exercise has malformed UUID '\(customExercise.id)' — skipping", category: .network)
                    continue
                }
                let fetchRequest: NSFetchRequest<Exercise> = Exercise.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "name == %@", customExercise.name)
                
                do {
                    let existing = try bgContext.fetch(fetchRequest)
                    if existing.isEmpty {
                        let exercise = Exercise(context: bgContext)
                        exercise.id = customExerciseUUID
                        exercise.name = customExercise.name
                        exercise.category = customExercise.category
                        
                        var allMuscles = customExercise.primaryMuscles ?? []
                        if let secondaryMuscles = customExercise.secondaryMuscles {
                            allMuscles.append(contentsOf: secondaryMuscles)
                        }
                        exercise.muscleGroups = allMuscles as NSArray
                        
                        exercise.equipment = customExercise.equipment
                        let customMarker = "[CUSTOM_EXERCISE|ICON:\(customExercise.iconName ?? "figure.walk")]"
                        if let existingInstructions = customExercise.instructions {
                            exercise.instructions = "\(customMarker)\n\(existingInstructions)"
                        } else {
                            exercise.instructions = customMarker
                        }
                        
                        AppLogger.info("Added custom exercise from cloud: \(customExercise.name)", category: .network)
                    }
                } catch {
                    _ = NetworkErrorClassifier.log(
                        error,
                        context: "Error syncing custom exercise from cloud",
                        category: .network,
                        op: PerformanceSignposts.Op.cloudSyncCustomExercise.rawValue,
                        endpoint: "coredata/exercise(custom fetch)",
                        userId: self.currentUser?.id
                    )
                }
            }
            
            do {
                try bgContext.save()
                AppLogger.info("Synced \(customExercises.count) custom exercises to Core Data", category: .network)
            } catch {
                _ = NetworkErrorClassifier.log(
                    error,
                    context: "Error saving custom exercises to Core Data",
                    category: .network,
                    op: PerformanceSignposts.Op.cloudSyncCustomExercise.rawValue,
                    endpoint: "coredata/exercise(custom save)",
                    userId: self.currentUser?.id
                )
            }
        }
    }
    
    private func syncFavoriteWorkoutsToCoreData(favoriteWorkouts: [FavoriteWorkoutDTO]) async {
        let bgContext = PersistenceController.shared.container.newBackgroundContextSafely()
        
        let cloudFavoriteIds = Set(favoriteWorkouts.map { $0.originalWorkoutId })
        
        await bgContext.perform {
            let fetchRequest: NSFetchRequest<Workout> = Workout.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "isCompleted == YES")
            
            do {
                let allWorkouts = try bgContext.fetch(fetchRequest)
                
                for workout in allWorkouts {
                    if let workoutId = workout.id?.uuidString {
                        let shouldBeFavorite = cloudFavoriteIds.contains(workoutId)
                        if workout.isFavorite != shouldBeFavorite {
                            workout.isFavorite = shouldBeFavorite
                        }
                    }
                }
                
                try bgContext.save()
                AppLogger.info("Synced \(favoriteWorkouts.count) favorite workouts to Core Data", category: .network)
            } catch {
                _ = NetworkErrorClassifier.log(
                    error,
                    context: "Error syncing favorite workouts to Core Data",
                    category: .network,
                    op: PerformanceSignposts.Op.cloudSyncFavoriteWorkout.rawValue,
                    endpoint: "coredata/workout(favorites save)",
                    userId: self.currentUser?.id
                )
            }
        }
    }
}
