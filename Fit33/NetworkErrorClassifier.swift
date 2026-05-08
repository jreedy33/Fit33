import Foundation

// MARK: - Network Error Classifier
//
// Shared helper for correctly classifying Foundation / NSURLError / Supabase
// errors into log levels that match the QUALITY_PERFORMANCE_AGENT invariants:
//
//   #15 — HealthKit "protected health data" / "no data available" /
//         "authorization not determined" → .debug (EXPECTED, device state).
//   #25 — Normal user actions / transient network / cancelled ops → .debug
//         or .warning; `.error` is reserved for actual malfunctions.
//
// The previous pattern — `AppLogger.error("Save failed: \(error.localizedDescription)")`
// in every Supabase catch block — was responsible for 25+ bug-intelligence
// fingerprints per rollup, because every `AppLogger.error(...)` call:
//   1. writes an `entries[type=error]` row into `dev_session_logs`
//   2. (conditionally) posts a `crash_reports` row via
//      `CrashReportingService.reportError`
// and the `compute_daily_bug_rollup()` pg function captures both as bugs.
//
// The classifier keeps the catch blocks honest: transient / expected errors
// log at `.debug` or `.warning`, real bugs stay at `.error`. Call sites use:
//
//     } catch {
//         NetworkErrorClassifier.log(
//             error,
//             context: "Saving HealthKit activity",
//             category: .health
//         )
//     }
//
// If you need to suppress a specific transient class entirely (e.g. the
// offline retry queue already owns recovery, so surfacing the first failure
// at `.warning` is noise), pass `transientLevel: .debug`.

enum NetworkErrorClassifier {

    // MARK: - Classification
    enum Classification {
        case expectedHealthKit     // HK-permissioning, device-locked, no-data
        case transientNetwork      // timeout, connection lost, not connected, cancelled
        case authExpired           // Supabase session invalid / no auth
        case rlsViolation          // RLS rejected the row (usually auth-expired + user_id set)
        case expectedUserState     // duplicate signup, IDOR forbidden during onboarding race, user-driven not-bugs
        case realError             // anything else
    }

    static func classify(_ error: Error) -> Classification {
        if error is CancellationError { return .transientNetwork }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorTimedOut,
                 NSURLErrorCancelled,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorNotConnectedToInternet,
                 NSURLErrorInternationalRoamingOff,
                 NSURLErrorDataNotAllowed,
                 // NSURLErrorCannotParseResponse (-1017): server returned a
                 // body PostgREST / our edge functions couldn't decode —
                 // almost always a Cloudflare flap mid-restart returning
                 // truncated JSON or an HTML error page. Pairs with the
                 // `Status Code: 502/503` HTML matchers below. Retry queue
                 // recovers automatically. (Bug-intel Phase 12 denylist —
                 // server-side filter `nsurl_cannot_parse_response`,
                 // migration `20260713_…`.)
                 NSURLErrorCannotParseResponse:
                return .transientNetwork
            default:
                break
            }
        }

        // BGTaskSchedulerErrorDomain — every code in this domain reflects
        // device / scheduler state, never an app malfunction:
        //   1 unavailable   — Low Power Mode, "Background App Refresh"
        //                     disabled in Settings, simulator, or scheduler
        //                     rate-limit. Apple-documented expected state.
        //   2 tooManyPendingTaskRequests — `submit()` called more than once
        //                     for the same identifier without `cancel()`.
        //                     Self-healing on next launch.
        //   3 notPermitted   — task identifier not in `Info.plist`
        //                     `BGTaskSchedulerPermittedIdentifiers`. Real
        //                     misconfig — but caught at first launch in
        //                     internal builds and not a per-device bug.
        // Bucket the entire domain at `.transientNetwork` (warning, no
        // fingerprint) so wrapped/alternate codes don't refingerprint.
        // Pairs with `bg_sync_schedule_failure` server-side filter and
        // resolves bug-intel `90369817` / `2fe2cbd7` clusters.
        if nsError.domain == "BGTaskSchedulerErrorDomain" {
            return .transientNetwork
        }

        // ASAuthorizationError (Apple Sign In) — every code in this domain
        // is user-state, not an app malfunction:
        //   1000 unknown    — device-side error (auth service down, network
        //                     during the credential request). User can
        //                     retry; don't fingerprint.
        //   1001 canceled   — user tapped "Cancel" on the sheet. Pure user
        //                     action, never a bug.
        //   1002 invalidResponse / 1003 notHandled / 1004 failed — Apple
        //                     server-side flap; recovery is "tap again".
        //   1005 notInteractive — only fires inside ASCredentialIdentity
        //                     refresh flows we don't use.
        // Bucket all of them at .expectedUserState (debug log + no
        // fingerprint). (Bug-intel `8622fc3a`, `94944900`, `e5986611`,
        // `a22cd96f` — Apple Sign In + password-reset rate-limit cluster.)
        if nsError.domain == "com.apple.AuthenticationServices.AuthorizationError" {
            return .expectedUserState
        }

        let lower = nsError.localizedDescription.lowercased()

        // HealthKit expected states — QP invariant #15
        if lower.contains("protected health data")
            || lower.contains("no data available")
            || lower.contains("authorization not determined") {
            return .expectedHealthKit
        }

        // Supabase / PostgREST transient + auth patterns
        if lower.contains("the network connection was lost")
            || lower.contains("not connected to the internet")
            || lower.contains("request timed out")
            || lower.contains("the operation couldn’t be completed. (\(nsError.domain) error -999)")
            || lower.contains("cancelled")
            // PostgreSQL `statement_timeout` (SQLSTATE 57014) — query exceeded
            // the per-session timeout limit. PostgREST surfaces the message
            // verbatim; on the iOS side it can wear different domains
            // depending on whether it traverses URLSession or Postgres-Swift's
            // own decoder. Bucket as transient — the same query rerun under
            // less DB load typically succeeds. (Bug-intel `97ec4ac4` —
            // ExerciseIntelligenceEngine catalogue load timeout.)
            || lower.contains("canceling statement due to statement timeout")
            || lower.contains("statement timeout")
            || (lower.contains("57014") && lower.contains("statement")) {
            return .transientNetwork
        }

        // Cloudflare / edge gateway flaps — the proxy in front of Supabase
        // periodically returns 502/503/504 for a few seconds during rolling
        // restarts. The iOS retry queue recovers these automatically, so
        // surfacing them as .error creates a bug_intelligence_fingerprint
        // every deploy. Treat as transient. (QP invariant #25a, #25b)
        if lower.contains("502 bad gateway")
            || lower.contains("bad gateway")
            || lower.contains("503 service unavailable")
            || lower.contains("service unavailable")
            || lower.contains("504 gateway time-out")
            || lower.contains("gateway timeout")
            || lower.contains("gateway time-out")
            || lower.contains("status code: 502")
            || lower.contains("status code: 503")
            || lower.contains("status code: 504") {
            return .transientNetwork
        }

        if lower.contains("not authenticated")
            || lower.contains("jwt expired")
            || lower.contains("invalid jwt")
            // Edge-function `requireUserAuth` returns 401 with body
            // `{"error":"Unauthorized"}` when the user JWT failed to validate
            // (most often: app backgrounded long enough for access_token to
            // expire BEFORE the SDK's auto-refresh fired, or refresh failed
            // due to no network). The thrown `Error.localizedDescription`
            // is just `"Unauthorized"` — match the exact lowercase form
            // (NOT a substring, because real RLS / forbidden messages may
            // legitimately contain "unauthorized" with more context, and
            // those should fall through to .rlsViolation / .realError).
            // Treat as authExpired so the SDK's next refresh + retry
            // handles it instead of fingerprinting. (Bug-intel `e6aaf4bb`,
            // `64639cbd`, `1298d708`, `ebe9f665` — Nutrition USDA
            // Unauthorized cluster, 70+ occ × 8 users on build 63.)
            || lower == "unauthorized" {
            return .authExpired
        }

        if lower.contains("row-level security policy") || lower.contains("42501") {
            return .rlsViolation
        }

        // Expected user-driven failures that are NOT app malfunctions:
        //   • "User already registered" — duplicate sign-up; the onboarding
        //     UI recovers by signing in instead, so this is a normal branch
        //     not a bug. (Bug-intel fingerprint 00bd6a62.)
        //   • "Forbidden: new_user_id must match caller" — IDOR guard on
        //     notify-contacts-user-joined fires during the brief window
        //     between auth.signUp and the new JWT propagating; the daily
        //     `check_pending_join_notifications` job catches up. Treat as
        //     transient + expected. (Bug-intel fingerprints b242269c, 65f3c668.)
        if lower.contains("user already registered")
            || lower.contains("user already exists")
            || lower.contains("email already registered")
            || lower.contains("forbidden: new_user_id must match caller")
            // Private-challenge invite send: the iOS UI optimistically
            // re-tries an "Invite" tap; the second hit lands a
            // PRE-existing pending row → server returns
            // "User already has a pending invite". This is the desired
            // idempotent outcome, not a bug. (Bug-intel `60158c57`,
            // `de033a16`, 2 occ each.)
            || lower.contains("user already has a pending invite")
            || lower.contains("already has a pending invite")
            // Server-side idempotency falling through to the client:
            // duplicate-key on user_daily_quests / user_achievements /
            // similar (UPSERT failure shapes), 23505 SQLSTATE. Catch
            // sites already fall back to the existing row. Surfacing
            // these as .error inflates the rollup despite zero user
            // impact. Server should be using ON CONFLICT DO NOTHING —
            // when it isn't, the iOS catch path treats it as expected
            // user state. (Bug-intel `bb8db6c1`, `da16c5c1`, `015bf5a8`,
            // `84138481` — daily-quest seed cluster.)
            || lower.contains("duplicate key value violates unique constraint")
            || (lower.contains("23505") && lower.contains("duplicate"))
            // Apple Sign In: Apple's NSError lowercased description
            // sometimes drops the canonical domain string and just renders
            // "(error 1001.)". The domain check above catches the typed
            // case; this is the belt-and-suspenders fallback for cases
            // where the error has been wrapped in a Swift error type
            // that flattens the domain.
            || lower.contains("authorizationerror error 1001") {
            return .expectedUserState
        }

        // Auth rate-limit responses (HTTP 429 / "rate limit exceeded" /
        // "email rate limit exceeded" / "too many requests") are transient
        // by definition — the user can retry after the window. Bucketing
        // them at the same level as a real malfunction would surface a
        // bug-intelligence fingerprint per signup attempt during a burst.
        // (Bug-intel Reports 10 + 13.)
        if lower.contains("rate limit")
            || lower.contains("too many requests")
            || lower.contains("status code: 429") {
            return .transientNetwork
        }

        // PostgREST schema-cache misses (PGRST202 / PGRST204) — fired in the
        // 5-12min window between a migration committing a new function /
        // column and PostgREST's API-node cache rebuilding from `pg_catalog`
        // (Supabase invariant 19b). The migration's trailing `NOTIFY pgrst,
        // 'reload schema'` normally collapses this window to <1s, but a
        // user who opens the app DURING propagation hits PGRST202 once,
        // then never again. Bucket as transient so a one-shot deploy
        // race doesn't manufacture a per-build fingerprint. Mirrors the
        // server-side `bug_intel_noise_filter` row `pgrst_schema_cache_miss`.
        // (Bug-intel `840673f1` — batch_check_achievements PGRST202, single
        // occurrence on 2026-05-08 deploy.)
        if lower.contains("could not find the function")
            || lower.contains("could not find the '") // PGRST204 column form
            || lower.contains("pgrst202")
            || lower.contains("pgrst204")
            || lower.contains("schema cache") {
            return .transientNetwork
        }

        // Friend request server-side idempotency — when `accept_friend_request`
        // RPC raises P0001 ("Friend request not found or already processed")
        // it means a previous accept call already won (network flap, double-tap,
        // multi-device race). The local `pendingRequests.removeAll` already
        // dropped the row from the UI, so the user's intent is satisfied.
        // Mirrors the server-side `bug_intel_noise_filter` row
        // `friend_request_already_processed`. (Bug-intel `d1d2767a`.)
        if lower.contains("friend request not found or already processed")
            || lower.contains("friend request already processed") {
            return .expectedUserState
        }

        return .realError
    }

    static func isTransient(_ error: Error) -> Bool {
        switch classify(error) {
        case .transientNetwork, .expectedHealthKit, .authExpired, .expectedUserState:
            return true
        case .rlsViolation, .realError:
            return false
        }
    }

    // MARK: - Logging
    //
    // `context` should describe the operation (“Saving HealthKit activity”,
    // “Syncing steps to cloud”). The classifier composes:
    //   "<context>: <localizedDescription>"
    // and picks a log level:
    //   transient/expected → `transientLevel` (default `.warning`)
    //   auth-expired       → `.warning`  + category `.auth`
    //   rls-violation      → `.warning`  + category `.auth` (same root cause)
    //   real-error         → `.error`
    //
    // Returns the classification so the caller can decide to retry, queue for
    // offline replay, etc.

    @discardableResult
    static func log(
        _ error: Error,
        context: String,
        category: AppLogger.Category = .general,
        transientLevel: AppLogger.Level = .warning,
        op: String? = nil,
        endpoint: String? = nil,
        startedAt: Date? = nil,
        userId: UUID? = nil,
        retryAttempt: Int? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) -> Classification {
        let classification = classify(error)
        let msg = "\(context): \(error.localizedDescription)"

        // When any structured context field is supplied, build a
        // DiagnosticContext so downstream fingerprinting can pivot by
        // pg_code / http_status / op. Existing call sites that omit all
        // optional args still work exactly as before (context = nil).
        let diag: DiagnosticContext? = {
            guard op != nil || endpoint != nil || startedAt != nil || userId != nil else {
                return nil
            }
            return DiagnosticContext.from(
                error: error,
                op: op ?? "unknown",
                endpoint: endpoint,
                startedAt: startedAt,
                userId: userId,
                retryAttempt: retryAttempt
            )
        }()

        switch classification {
        case .transientNetwork, .expectedHealthKit:
            AppLogger.log(msg, level: transientLevel, category: category, context: diag, file: file, function: function, line: line)
        case .authExpired, .rlsViolation:
            // Route auth/RLS at .warning with category `.auth` so the catch-all
            // rollup can separate "user needs to re-auth" from "network flapped"
            // without spamming crash_reports.
            AppLogger.log(msg, level: .warning, category: .auth, context: diag, file: file, function: function, line: line)
        case .expectedUserState:
            // Expected user-driven branches (duplicate signup, IDOR onboarding
            // race). Stay at .debug so they don't hit crash_reports or the
            // bug-intelligence rollup.
            AppLogger.log(msg, level: .debug, category: category, context: diag, file: file, function: function, line: line)
        case .realError:
            AppLogger.log(msg, level: .error, category: category, context: diag, file: file, function: function, line: line)
        }

        return classification
    }
}
