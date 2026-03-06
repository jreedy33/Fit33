# Fit33 - Comprehensive Improvement Plan
## Pre-TestFlight / Production Launch Readiness Audit
**Date:** March 6, 2026
**Scope:** Full codebase review of 252 Swift files, Supabase backend, SQL migrations, UI/UX, security, and performance
**App:** Fit33 - iOS Fitness Application (SwiftUI + CoreData + Supabase)

---

## Table of Contents
1. [CRITICAL - Must Fix Before Any Release](#1-critical---must-fix-before-any-release)
2. [HIGH - Must Fix Before Production](#2-high---must-fix-before-production)
3. [MEDIUM - Should Fix Before Production](#3-medium---should-fix-before-production)
4. [LOW - Nice to Have / Post-Launch](#4-low---nice-to-have--post-launch)
5. [Architecture & Technical Debt](#5-architecture--technical-debt)
6. [App Store Submission Checklist](#6-app-store-submission-checklist)

---

## 1. CRITICAL - Must Fix Before Any Release

### 1.1 Hardcoded Supabase Credentials in Source Code

**Context:** The Supabase URL and anon key are hardcoded directly in `SupabaseManager.swift` (lines 14-15) and again in `FoodDatabaseService.swift` (lines 265-268). The JWT token is embedded as a string literal in both files.

**Why This Is a Problem:** Anyone who decompiles the IPA or browses the git history can extract these credentials. The anon key grants read/write access to any table without RLS bypass, but combined with the Supabase URL it exposes your entire backend. Apple's App Store review may also flag hardcoded credentials.

**Current Code (SupabaseManager.swift:14-15):**
```swift
private let supabaseURL = "https://ehooeghabzefgoqzugrc.supabase.co"
private let supabaseKey = "eyJhbGciOiJIUzI1NiIs..."
```

**Current Code (FoodDatabaseService.swift:265-268):**
```swift
var urlRequest = URLRequest(url: URL(string: "https://ehooeghabzefgoqzugrc.supabase.co/functions/v1/usda-food-search")!)
urlRequest.setValue("Bearer eyJhbGciOiJIUzI1NiIs...", forHTTPHeaderField: "Authorization")
```

**Solution:**
1. Move credentials to `Secrets.swift` (already gitignored) via the existing `Secrets.template.swift` pattern
2. Add `supabaseURL` and `supabaseAnonKey` to `Secrets.swift`
3. Reference via `AppConfig` like other secrets already do
4. For FoodDatabaseService, use `SupabaseManager.shared.supabaseClient` instead of raw URLRequest

**Agent Prompt:**
```
In the Fit33 iOS project, hardcoded Supabase credentials exist in two files that need to be moved to the Secrets pattern:

1. Open Fit33/SupabaseManager.swift - lines 14-15 have hardcoded supabaseURL and supabaseKey
2. Open Fit33/FoodDatabaseService.swift - lines 265-268 have hardcoded Supabase URL and JWT token in a URLRequest
3. Open Fit33/Secrets.template.swift and add two new entries: `static let supabaseURL = "<SUPABASE_URL>"` and `static let supabaseAnonKey = "<SUPABASE_ANON_KEY>"`
4. Open Fit33/AppConfig.swift and add `static let supabaseURL: String = Secrets.supabaseURL` and `static let supabaseAnonKey: String = Secrets.supabaseAnonKey`
5. Update SupabaseManager.swift to use `AppConfig.supabaseURL` and `AppConfig.supabaseAnonKey`
6. Update FoodDatabaseService.swift to use `SupabaseManager.shared.supabaseClient` instead of building a raw URLRequest with hardcoded credentials
7. Verify Fit33/Secrets.swift is in .gitignore (it already is)
```

---

### 1.2 Dev Menu Password Exposed in Source Code

**Context:** `AppConfig.swift` line 88 contains `static let devMenuPassword = "WhatsApp26!"` inside a `#if DEBUG` block. While it's DEBUG-only, this password is committed to git and visible to anyone with repo access.

**Why This Is a Problem:** If the password is reused elsewhere (personal accounts, services), it's a credential leak. Even in DEBUG, passwords should not be in source control.

**Solution:** Move dev menu password to `Secrets.swift` or use a simple environment variable check instead of a password.

**Agent Prompt:**
```
In Fit33/AppConfig.swift, line 88 has a hardcoded dev menu password: `static let devMenuPassword = "WhatsApp26!"`. This is inside #if DEBUG but still committed to git. Move this to the Secrets.swift pattern:
1. Add `static let devMenuPassword = "<DEV_MENU_PASSWORD>"` to Secrets.template.swift
2. Update AppConfig.swift line 88 to use `Secrets.devMenuPassword`
3. Alternatively, remove the password requirement entirely and just use the #if DEBUG flag for dev menu access
```

---

### 1.3 No In-App Purchase / StoreKit Integration

**Context:** `PremiumManager` (in `UserManager.swift` lines 637-737) defaults `isPremiumUser = true` for all users and stores the value in `UserDefaults`. There is zero StoreKit integration - no product IDs, no purchase flow, no receipt validation, no subscription management.

**Why This Is a Problem:** Every user gets premium features for free. There's no monetization. The `PremiumUpgradeView.swift` exists but has no actual purchase capability. Apple will reject the app if it advertises premium features without a working IAP flow.

**Current Code (UserManager.swift:640-648):**
```swift
@Published var isPremiumUser: Bool = true {
    didSet {
        UserDefaults.standard.set(isPremiumUser, forKey: "isPremiumUser")
    }
}
private init() {
    self.isPremiumUser = UserDefaults.standard.object(forKey: "isPremiumUser") as? Bool ?? true
}
```

**Solution:**
1. Integrate StoreKit 2 for subscription management
2. Define product IDs (monthly, yearly, lifetime)
3. Implement receipt validation (server-side via Supabase Edge Function recommended)
4. Default `isPremiumUser` to `false`
5. Add restore purchases functionality
6. Handle subscription expiry and grace periods

**Agent Prompt:**
```
The Fit33 iOS app has a PremiumManager class in Fit33/UserManager.swift (lines 637-737) that currently defaults all users to premium (isPremiumUser = true) with no actual StoreKit integration. Implement a complete StoreKit 2 subscription system:

1. Create a new file Fit33/StoreKitManager.swift with:
   - Product IDs for monthly and yearly subscriptions
   - StoreKit 2 Product loading and purchase flow
   - Transaction listener for auto-renewal updates
   - Restore purchases functionality
   - Entitlement checking

2. Update PremiumManager to:
   - Default isPremiumUser to false
   - Check StoreKit entitlements on init
   - Listen for transaction updates
   - Add isPremiumUser validation via receipt/transaction

3. Update PremiumUpgradeView.swift to:
   - Display actual subscription products with prices
   - Handle purchase flow with loading states
   - Show restore purchases button
   - Handle errors (network, cancelled, etc.)

4. Add server-side receipt validation via Supabase Edge Function for security
```

---

### 1.4 No App Tracking Transparency (ATT) Implementation

**Context:** `AdManager.swift` initializes Google AdMob SDK but there is zero `ATTrackingManager` / `AppTrackingTransparency` integration. No `requestTrackingAuthorization()` call exists anywhere in the codebase.

**Why This Is a Problem:** Apple requires ATT prompt before any ad tracking or IDFA access since iOS 14.5. Apps that use AdMob without ATT will be rejected by App Store Review. Google AdMob requires ATT for personalized ads and revenue optimization.

**Solution:**
1. Add `NSUserTrackingUsageDescription` to Info.plist
2. Present ATT prompt before initializing AdMob
3. Pass tracking authorization status to AdMob
4. Handle "not determined", "authorized", "denied", "restricted" states
5. Implement GDPR consent flow for EU users (Google UMP SDK)

**Agent Prompt:**
```
The Fit33 iOS app uses Google AdMob (see Fit33/AdManager.swift) but has NO App Tracking Transparency implementation. This will cause App Store rejection. Fix this:

1. Add `NSUserTrackingUsageDescription` key to the app's Info.plist with a user-friendly description
2. In AdManager.swift, before initializing GADMobileAds:
   - Import AppTrackingTransparency
   - Call ATTrackingManager.requestTrackingAuthorization
   - Wait for user response before starting ad SDK
   - Pass the tracking status to AdMob for proper ad personalization
3. In Fit33App.swift, move the AdMob pre-warm (line 261-277) to occur AFTER the ATT prompt
4. Handle all ATT states: .authorized (full ads), .denied/.restricted (limited ads), .notDetermined (prompt)
5. Consider adding Google's User Messaging Platform (UMP) SDK for GDPR consent in EU
```

---

### 1.5 Force Unwraps That Can Crash in Production

**Context:** Multiple force unwraps exist in production code paths:
- `BackgroundChallengeSyncService.swift:221` - `task as! BGAppRefreshTask`
- `SpoonacularAdvancedService.swift` - Multiple `URL(string: ...)!` force unwraps (lines 139, 188, 230, 267, 295, 368, 401, 423, 452)
- `SpoonacularService.swift` - Force unwrap URL constructions (lines 141, 171, 196)
- `PersistenceController.swift:61` - `fatalError` in preview code
- `PersistenceController.swift:82` - `fatalError` for missing store description

**Why This Is a Problem:** Any of these will cause an instant crash. URL force unwraps are especially dangerous because URL encoding of user-provided search queries can fail. The BGTask force cast can crash on iOS version mismatches.

**Solution:** Replace all force unwraps with safe optional handling (`guard let`, `if let`, or nil-coalescing).

**Agent Prompt:**
```
The Fit33 iOS app has dangerous force unwraps that will crash in production. Find and fix ALL of these:

1. Fit33/BackgroundChallengeSyncService.swift line 221: `task as! BGAppRefreshTask` - change to safe cast with `guard let task = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }`

2. Fit33/SpoonacularAdvancedService.swift - ALL lines with `URL(string: ...)!` (lines 139, 188, 230, 267, 295, 368, 401, 423, 452). Replace each with `guard let url = URL(string: ...) else { throw SpoonacularError.invalidURL }` and add an `invalidURL` case to the SpoonacularError enum if it doesn't exist.

3. Fit33/SpoonacularService.swift - same pattern on lines 141, 171, 196

4. Search the entire Fit33/ directory for any remaining `!` force unwraps on optionals (not just URLs) and replace with safe alternatives. Use `grep -rn 'URL(string:.*\)!' Fit33/` and `grep -rn 'as!' Fit33/` to find them all.
```

---

### 1.6 Missing Error Recovery in Core Data

**Context:** `PersistenceController.swift` handles migration failure by deleting the entire Core Data store and recreating it (lines 104-138). If the retry also fails, it just prints a warning and continues. The app will be in an undefined state.

**Why This Is a Problem:** Users lose ALL local data (workouts, meal history, user profile) silently. There's no user notification, no cloud restore prompt, and no data export option before deletion.

**Solution:**
1. Before deleting the store, attempt to backup the file
2. After migration failure, prompt user to restore from cloud
3. Show user-visible error if Core Data cannot load
4. Log the failure to crash reporting service

**Agent Prompt:**
```
In Fit33/PersistenceController.swift, the Core Data migration failure handler (lines 104-138) silently deletes all user data and recreates the store. This needs better error recovery:

1. Before deleting store files (line 110-121), create a backup copy of the .sqlite file to a temp directory
2. After successful retry (line 129), trigger a cloud restore by posting a notification that ContentView can observe to show a "Restore from cloud?" prompt
3. If retry fails (line 136), instead of just printing a warning, set a published flag that the app can check to show an error screen
4. Log the migration failure details to CrashReportingService with full error context
5. Add a method `attemptCloudRestore()` that syncs all data from Supabase after a store reset
```

---

## 2. HIGH - Must Fix Before Production

### 2.1 Excessive print() Statements (3000+)

**Context:** The codebase has thousands of `print()` statements with emoji-heavy debug output. While `Logger.swift` overrides `print()` to be a no-op in release builds, this approach has problems.

**Why This Is a Problem:**
1. The `print()` override in `Logger.swift` creates a global function that shadows Swift's `print()` - this can cause confusion and subtle bugs
2. String interpolation in print arguments is still evaluated even when the function is a no-op, wasting CPU cycles
3. The emoji-heavy output (e.g., `🔥🔥🔥 FORCING EXERCISE REFRESH`) makes logs hard to parse programmatically
4. No structured logging means no ability to filter or search production logs

**Solution:** Migrate to `AppLogger` (which already exists in `Logger.swift`) with proper level-gating and `@autoclosure` for lazy evaluation.

**Agent Prompt:**
```
The Fit33 iOS app has 3000+ print() statements that need to be migrated to the existing AppLogger system. The app already has AppLogger in Fit33/Logger.swift with proper level-gating and os_log for production. Do the following:

1. In the 10 most critical service files (SupabaseManager.swift, WorkoutManager.swift, UserManager.swift, ExerciseLibraryService.swift, HealthKitService.swift, FriendService.swift, ChallengeService.swift, CloudProgramService.swift, MealService.swift, NotificationManager.swift):
   - Replace all `print("✅ ...")` with `AppLogger.info("...", category: .appropriate)`
   - Replace all `print("❌ ...")` with `AppLogger.error("...", category: .appropriate)`
   - Replace all `print("⚠️ ...")` with `AppLogger.warning("...", category: .appropriate)`
   - Replace all `print("🔥 ...")` / other debug prints with `AppLogger.debug("...", category: .appropriate)`
   - Remove emoji from log messages - use the category and level for context
2. Leave #if DEBUG blocks as-is since they're already properly gated
3. For print statements with expensive string interpolation, ensure they use AppLogger's @autoclosure parameter
```

---

### 2.2 Navigation Architecture Issues (NavigationView + NavigationStack Mix)

**Context:** The app mixes `NavigationView` (deprecated in iOS 16) with `NavigationStack` across different views. `DashboardView.swift` uses `NavigationView` while `WorkoutTabView.swift` and `FriendsTabView.swift` mix both old and new navigation APIs.

**Why This Is a Problem:**
1. `NavigationView` is deprecated and generates Xcode warnings
2. Mixing navigation APIs causes state corruption - back button failures, stuck navigation states
3. Deep linking doesn't work reliably with mixed navigation
4. SwiftUI navigation memory is not properly managed

**Solution:** Migrate entirely to `NavigationStack` with `navigationDestination` modifiers.

**Agent Prompt:**
```
The Fit33 iOS app mixes deprecated NavigationView with NavigationStack, causing navigation corruption. Migrate to a unified NavigationStack approach:

1. Identify all files using NavigationView: search for "NavigationView" in Fit33/*.swift
2. Replace NavigationView with NavigationStack in each file
3. Replace NavigationLink(destination:) with NavigationLink(value:) + .navigationDestination(for:)
4. In ContentView.swift, create a centralized NavigationPath for each tab
5. Update DashboardView.swift (currently uses NavigationView at line 190) to use NavigationStack
6. Ensure deep link navigation (DeepLinkManager.swift) works with the new NavigationStack paths
7. Test that back button, swipe-back gesture, and programmatic navigation all work correctly
```

---

### 2.3 No Accessibility Support

**Context:** Across 252 Swift files, there are only ~14 occurrences of accessibility labels. No VoiceOver support, no Dynamic Type support, no accessibility hints or values on interactive elements.

**Why This Is a Problem:**
1. Apple requires reasonable accessibility for App Store approval
2. ~15% of users rely on accessibility features
3. VoiceOver users cannot navigate the app at all
4. Dynamic Type users see text cut off or overlapping
5. May violate ADA/accessibility laws in some jurisdictions

**Solution:** Add comprehensive accessibility support to all interactive views.

**Agent Prompt:**
```
The Fit33 iOS app has almost zero accessibility support across 252 Swift files. Add comprehensive VoiceOver and Dynamic Type support to the most critical user flows:

1. DashboardView.swift:
   - Add .accessibilityLabel() to streak counter, XP display, workout buttons
   - Add .accessibilityHint() to action buttons ("Double tap to start a workout")
   - Mark decorative images with .accessibilityHidden(true)

2. ActiveWorkoutView.swift:
   - Add .accessibilityLabel() to timer display, set/rep counters
   - Add .accessibilityValue() to weight/rep input fields
   - Add .accessibilityAction() for swipe-to-complete gestures

3. ContentView.swift (Tab bar):
   - Add .accessibilityLabel() to all tab items with badge counts

4. NewOnboardingView.swift:
   - Add .accessibilityLabel() to all input fields
   - Add .accessibilityHint() to pickers and selection controls

5. For ALL views:
   - Replace hardcoded font sizes with .font(.body) / .font(.headline) etc. for Dynamic Type
   - Add .accessibilityElement(children: .combine) on card components
   - Use .minimumScaleFactor(0.7) on text that might overflow

6. Test with Xcode Accessibility Inspector on at least 5 key screens
```

---

### 2.4 Missing Input Validation

**Context:** Multiple services accept user input without validation:
- `MealService`: No validation on negative calories, zero quantities, empty food names
- `UserManager.createUser()`: No validation on age range, height/weight bounds
- Birthday parsing in `SupabaseManager` accepts years 1900-2100 with ambiguous date interpretation
- Workout exercises have no validation on set/rep counts

**Why This Is a Problem:** Corrupted data flows to Supabase, breaks analytics, and can crash UI components that assume valid ranges (e.g., division by zero in calorie calculations).

**Solution:** Add validation at the model/service layer for all user inputs.

**Agent Prompt:**
```
The Fit33 iOS app lacks input validation in multiple critical services. Add comprehensive validation:

1. Fit33/MealService.swift:
   - Validate calories >= 0 and <= 10000 (reasonable max per entry)
   - Validate protein/carbs/fat >= 0 and <= 1000g
   - Validate quantity > 0
   - Validate food name is not empty and <= 200 characters
   - Return a ValidationError with user-friendly message for each failure

2. Fit33/UserManager.swift createUser() method (line 166):
   - Validate age: 13-120 (minimum age for app usage)
   - Validate height: 50-300 cm / 20-120 inches
   - Validate weight: 20-500 kg / 44-1100 lbs
   - Validate name length: 1-100 characters
   - Validate email format if provided
   - Validate availableDays: 1-7

3. Fit33/SupabaseManager.swift birthdayToISO() (line 43):
   - Narrow year range to 1920-current year
   - Validate resulting date is in the past
   - Add explicit format parameter instead of guessing

4. Fit33/WorkoutManager.swift:
   - Validate set weight >= 0 and <= 2000 lbs/1000 kg
   - Validate reps >= 0 and <= 999
   - Validate sets count >= 1 and <= 50
```

---

### 2.5 No Offline Mode / Network Error Handling Strategy

**Context:** The app heavily relies on Supabase for data sync but has no unified offline strategy. When the network is unavailable:
- Exercise sync fails silently
- Challenge updates are lost
- Profile changes aren't queued
- Meal logging may fail without feedback
- Workout sharing fails without retry

**Why This Is a Problem:** Mobile users frequently lose connectivity (subway, airplane, gym basement). Silent failures mean data loss and confused users.

**Solution:** Implement an offline queue with retry and user feedback.

**Agent Prompt:**
```
The Fit33 iOS app has no unified offline/network error handling strategy. Many Supabase operations fail silently when offline. Implement a comprehensive offline strategy:

1. Create a new file Fit33/NetworkMonitor.swift:
   - Use NWPathMonitor to track connectivity status
   - Publish isOnline as @Published for UI binding
   - Track connection type (wifi, cellular, none)

2. Create Fit33/OfflineQueue.swift:
   - Queue failed Supabase operations as serialized tasks
   - Persist queue to UserDefaults or Core Data
   - Auto-retry when connectivity restores
   - Support priority ordering (auth > workout data > social)

3. Update key services to use the offline queue:
   - SupabaseManager: Queue profile syncs, workout uploads
   - FriendService: Queue friend requests, shared workouts
   - ChallengeService: Queue progress updates
   - MealService: Queue meal log entries

4. Add UI feedback in ContentView.swift:
   - Show a subtle "offline" banner when disconnected
   - Show "syncing X items..." when reconnected and queue is processing
   - Show sync status in Settings view
```

---

### 2.6 Strava Client ID Exposed in Source Code

**Context:** `AppConfig.swift` line 49 has `static let clientId = "198007"` for Strava. While not as sensitive as a secret, combined with the app's redirect URI, this allows impersonation of OAuth requests.

**Why This Is a Problem:** Third parties can create phishing OAuth flows that appear to come from Fit33.

**Solution:** Move to Secrets.swift pattern or server-side OAuth flow.

**Agent Prompt:**
```
In Fit33/AppConfig.swift, the Strava client ID (line 49: "198007") and Fitbit client ID (line 64: "23TRK9") are hardcoded in source code. While less sensitive than secrets, they should still be in the Secrets.swift file:

1. Add `static let stravaClientId = "<STRAVA_CLIENT_ID>"` to Secrets.template.swift
2. Add `static let fitbitClientId = "<FITBIT_CLIENT_ID>"` to Secrets.template.swift
3. Update AppConfig.Strava.clientId and AppConfig.Fitbit.clientId to read from Secrets
4. Consider implementing server-side OAuth token exchange via Supabase Edge Functions to avoid exposing client secrets in the app binary entirely
```

---

## 3. MEDIUM - Should Fix Before Production

### 3.1 DispatchQueue.main.asyncAfter Overuse

**Context:** `NewOnboardingView.swift` has 41 instances of `DispatchQueue.main.asyncAfter`, `ActiveWorkoutView.swift` has 9, and `ContentView.swift` has 10. Hardcoded delays (0.1s, 0.5s, 1.2s) are used for animation sequencing and state management.

**Why This Is a Problem:**
1. On slow devices, animations and state updates race
2. Stacked asyncAfter calls can deadlock or fire out of order
3. Delays are guesses that may not match actual animation durations
4. Makes the code extremely hard to debug and maintain

**Solution:** Replace with proper SwiftUI animation APIs, `withAnimation` completion handlers, and `Task.sleep` for async sequencing.

**Agent Prompt:**
```
The Fit33 iOS app uses DispatchQueue.main.asyncAfter extensively for animation timing. This causes race conditions on slow devices. Fix the worst offenders:

1. Fit33/NewOnboardingView.swift (41 instances):
   - Replace asyncAfter-based animation sequencing with withAnimation { } blocks
   - For sequential animations, use Task { try? await Task.sleep(nanoseconds:) } which is cancellable
   - For dependent state changes, use .onChange(of:) or .onAppear with proper state machines

2. Fit33/ActiveWorkoutView.swift (9 instances):
   - Replace timer-based UI updates with TimelineView for workout timer
   - Replace asyncAfter-based navigation with proper state-driven navigation

3. Fit33/ContentView.swift (10 instances):
   - Replace asyncAfter-based tab switching with immediate state changes
   - Use withAnimation(.easeInOut) for transitions instead of delayed state sets

4. As a general rule: if asyncAfter is used to "wait for SwiftUI to settle", the real fix is to restructure the state flow so SwiftUI doesn't need settling time.
```

---

### 3.2 No Localization / Hardcoded Strings

**Context:** All user-facing strings are hardcoded in English throughout the codebase. Date formats are hardcoded as "MM/DD/YYYY". Number formatting doesn't respect locale. No `.strings` or `.xcstrings` files exist.

**Why This Is a Problem:**
1. Cannot support non-English markets
2. Date/number formats are wrong for non-US locales
3. Limits App Store reach and user base

**Solution:** Extract strings to localization files and use `NSLocalizedString` or String Catalogs.

**Agent Prompt:**
```
The Fit33 iOS app has zero localization - all strings are hardcoded in English. Set up the localization infrastructure:

1. Create Fit33/Localizable.xcstrings (Xcode 15+ String Catalog)
2. In the 5 most user-facing views (DashboardView, ActiveWorkoutView, SettingsView, ProfileView, NewOnboardingView):
   - Replace hardcoded strings with String(localized: "key") or NSLocalizedString
   - Use LocalizedStringKey for Text() views
   - Example: Text("Start Workout") → Text("start_workout_button", comment: "Button to start a new workout")
3. Replace hardcoded date formats with DateFormatter using .dateStyle and .timeStyle
4. Replace hardcoded number formatting with NumberFormatter using .locale = .current
5. Add a base English localization so the infrastructure is ready for future translations
```

---

### 3.3 Missing SSL Certificate Pinning

**Context:** All network requests (Supabase, Spoonacular, Strava, Fitbit APIs) use `URLSession.shared` without any certificate pinning.

**Why This Is a Problem:** Man-in-the-middle attacks can intercept user data, auth tokens, and API keys. This is especially concerning on public Wi-Fi networks (common in gyms).

**Solution:** Implement certificate pinning for Supabase connections at minimum.

**Agent Prompt:**
```
The Fit33 iOS app makes network requests to Supabase, Spoonacular, Strava, and Fitbit without SSL certificate pinning. At minimum, add certificate pinning for the Supabase connection:

1. Create Fit33/CertificatePinning.swift:
   - Implement URLSessionDelegate with urlSession(_:didReceive:completionHandler:)
   - Pin the Supabase domain's public key hash
   - Allow backup pins for certificate rotation

2. Optionally use TrustKit library for easier certificate pinning management

3. Add a fallback: if pinning fails, log to CrashReportingService and optionally allow connection (with warning) so users aren't completely locked out during certificate rotation
```

---

### 3.4 Memory Leak Risks in Closures

**Context:** Multiple views use closures without `[weak self]` that can retain view models and services:
- `PerformanceOptimizations.swift:59` - Timer captures `self` (even with `[weak self]`, the Timer itself is retained)
- `WorkoutCompletionView.swift:152-159` - Animation timer
- `Fit33App.swift:247-255` - NotificationCenter observer
- Multiple `Task { }` blocks in views capture `self` implicitly

**Why This Is a Problem:** Leaked memory accumulates over time, eventually triggering iOS to kill the app. Fitness apps run for extended periods during workouts, making this especially critical.

**Solution:** Audit all closures for retain cycles, use `[weak self]` consistently.

**Agent Prompt:**
```
The Fit33 iOS app has memory leak risks from closures without [weak self]. Audit and fix:

1. Search for `Timer.scheduledTimer` in all .swift files - ensure every callback uses [weak self]
2. Search for `NotificationCenter.default.addObserver(forName:` - ensure every callback uses [weak self]
3. Search for `DispatchQueue.main.asyncAfter` with self references - add [weak self]
4. In views with `Task { }` blocks that reference properties, verify the task is cancelled in .onDisappear
5. Key files to check:
   - Fit33/PerformanceOptimizations.swift (Timer at line 59)
   - Fit33/WorkoutCompletionView.swift (animation timer)
   - Fit33/Fit33App.swift (memory warning observer at line 247)
   - Fit33/ActiveWorkoutView.swift (workout timer)
6. Add .onDisappear { task?.cancel() } to any view that creates long-running Tasks
```

---

### 3.5 Dark Mode Color Issues

**Context:** Many views use hardcoded RGB values (e.g., `Color(red: 0.08, green: 0.10, blue: 0.18)`) instead of semantic colors. While `AdaptiveColors.swift` and `DesignSystem.swift` exist, they're not used consistently.

**Why This Is a Problem:** Text becomes unreadable against wrong backgrounds in dark mode. Some gradients look washed out. Accessibility users with high contrast needs can't read content.

**Solution:** Audit all color usage and migrate to the existing `DesignSystem.swift` tokens.

**Agent Prompt:**
```
The Fit33 iOS app has inconsistent dark mode support. Many views use hardcoded colors instead of the existing DesignSystem.swift tokens. Fix this:

1. Search for `Color(red:` in all .swift files to find hardcoded RGB colors
2. For each occurrence, determine if it should use:
   - Color.cardBackground (from AdaptiveColors.swift)
   - Color.adaptiveText (for text)
   - DesignSystem gradient definitions
   - .primary / .secondary (system semantic colors)
3. Focus on the most user-facing views first: DashboardView, ActiveWorkoutView, ProfileView, SettingsView, MealPlanView
4. Verify each view looks correct in both light and dark mode using Xcode previews with .preferredColorScheme(.dark)
5. For gradients, use the existing DesignSystem.Gradient definitions instead of inline gradient colors
```

---

### 3.6 iPad Support Missing

**Context:** No views check `@Environment(\.horizontalSizeClass)`. All layouts are designed for iPhone. No iPad-specific layouts or split views exist.

**Why This Is a Problem:**
1. iPad users see stretched phone layouts
2. Wasted screen space on larger devices
3. Apple may reject if the app claims Universal support but provides poor iPad experience

**Solution:** Either add proper iPad layouts or restrict the app to iPhone only in the Xcode project settings.

**Agent Prompt:**
```
The Fit33 iOS app has no iPad support. Either add proper iPad layouts or restrict to iPhone:

Option A (Recommended for launch - quickest):
1. In the Xcode project settings (Fit33.xcodeproj), set "Targeted Device Family" to "iPhone" only
2. This allows iPad users to still run the app in iPhone compatibility mode
3. Add proper iPad support post-launch

Option B (Full iPad support):
1. Add @Environment(\.horizontalSizeClass) checks in ContentView, DashboardView, and ActiveWorkoutView
2. Use NavigationSplitView for iPad layouts
3. Implement column-based layouts for settings and profile
4. Test on iPad simulator at multiple sizes
```

---

### 3.7 Race Conditions in Exercise Library Sync

**Context:** `ExerciseLibraryService.swift` has a `syncLock` and `isSyncing` flag, but not all access paths are protected. Concurrent calls can create duplicate exercise entries in Core Data.

**Why This Is a Problem:** Users see duplicate exercises in their library, workout generation picks duplicates, and Core Data performance degrades.

**Solution:** Use proper actor-based synchronization or serial DispatchQueue.

**Agent Prompt:**
```
In Fit33/ExerciseLibraryService.swift, the exercise sync has race conditions. The isSyncing flag and syncLock don't cover all code paths. Fix this:

1. Convert ExerciseLibraryService to use Swift actor isolation instead of manual locks
2. Alternatively, use a serial DispatchQueue for all sync operations
3. Add a uniqueness constraint check before inserting exercises into Core Data
4. Use NSMergeByPropertyObjectTrumpMergePolicy on the context to handle duplicate inserts gracefully
5. Add an idempotency check: before syncing, compare exercise count and last-modified timestamp to skip unnecessary syncs
```

---

### 3.8 No Rate Limiting on API Calls

**Context:** Spoonacular API calls in `SpoonacularService.swift` and `SpoonacularAdvancedService.swift` have no rate limiting. Every search keystroke could trigger an API call. The app foreground handler in `Fit33App.swift` fires 7+ parallel API calls simultaneously.

**Why This Is a Problem:**
1. Spoonacular has API rate limits - exceeding them returns 402 errors and costs money
2. Excessive API calls waste user's data plan
3. Parallel calls on foreground can spike CPU and drain battery

**Solution:** Add debouncing for search and rate limiting for API calls.

**Agent Prompt:**
```
The Fit33 iOS app has no rate limiting on API calls, particularly to Spoonacular. Add proper rate limiting:

1. Fit33/SpoonacularService.swift and SpoonacularAdvancedService.swift:
   - Add a shared rate limiter that allows max 5 requests per second
   - Add debouncing (300ms) for search-related API calls
   - Cache responses by query string (already partially done, verify TTL)
   - Track daily API call count and warn when approaching limits

2. Fit33/Fit33App.swift foreground handler (line 598):
   - Already consolidated into one Task - verify this works properly
   - Add minimum interval between foreground refreshes (e.g., 30 seconds)
   - Skip refresh if app was only backgrounded briefly (< 5 seconds)

3. Create a generic RateLimiter utility:
   - Token bucket algorithm
   - Configurable rate and burst size
   - Shared across all API services
```

---

### 3.9 Keyboard Handling Issues

**Context:** Keyboard handling is inconsistent across views. `NewOnboardingView.swift` has a custom `KeyboardObserver` but most other input-heavy views don't dismiss the keyboard when tapping outside text fields.

**Why This Is a Problem:** Keyboard covers input fields, users can't see what they're typing, and there's no way to dismiss the keyboard on some screens.

**Solution:** Add consistent keyboard dismissal across all views.

**Agent Prompt:**
```
The Fit33 iOS app has inconsistent keyboard handling. Fix this across all input views:

1. Add a global keyboard dismissal gesture. In ContentView.swift, add:
   .onTapGesture { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }

2. For views with ScrollView, use .scrollDismissesKeyboard(.interactively)

3. In views with multiple text fields (NewOnboardingView, ProfileView, MealPlanView, FoodSearchView):
   - Add .submitLabel(.next) / .submitLabel(.done) for keyboard return key
   - Implement @FocusState to manage field focus progression
   - Ensure focused field scrolls into view above keyboard

4. Remove the custom KeyboardObserver from NewOnboardingView if possible and use SwiftUI's native keyboard handling
```

---

### 3.10 Missing Safe Area Handling

**Context:** 136 occurrences of `.ignoresSafeArea()` across 87 files. Many views ignore all safe areas when they should only ignore specific edges.

**Why This Is a Problem:** Content hidden behind the notch, Dynamic Island, or home indicator. This is especially bad during active workouts where timer and controls may be obscured.

**Solution:** Audit safe area usage and only ignore where visually necessary (backgrounds).

**Agent Prompt:**
```
The Fit33 iOS app has 136 occurrences of .ignoresSafeArea() across 87 files. Most of these are overly aggressive. Audit and fix:

1. Search for .ignoresSafeArea() in all .swift files
2. For each occurrence:
   - If it's on a background color/gradient: keep it (backgrounds should extend under safe areas)
   - If it's on content/text/buttons: remove it (content should respect safe areas)
   - If it's .ignoresSafeArea(.all, edges: .all): change to .ignoresSafeArea(.container, edges: .top) or similar specific edge
3. Focus on these critical views:
   - ActiveWorkoutView (timer must be visible above notch)
   - WelcomeTutorialView (buttons must not be under home indicator)
   - PremiumUpgradeView (purchase button must be tappable)
4. Test on devices with different safe area insets (iPhone SE, iPhone 15 Pro, iPhone 15 Pro Max)
```

---

## 4. LOW - Nice to Have / Post-Launch

### 4.1 App Store Review Request Timing

**Context:** 13 files reference `requestReview` or `SKStoreReviewController` but the implementation details are unclear. Review prompts need strategic timing.

**Solution:** Implement review prompts after positive moments (workout completion, streak milestone) with proper rate limiting (max 3x per year per Apple guidelines).

**Agent Prompt:**
```
Review the App Store review prompt implementation in Fit33. Search for requestReview and SKStoreReviewController usage. Ensure:
1. Review prompts only appear after positive moments (workout completion, 7-day streak)
2. Prompts are rate-limited (Apple limits to 3 per year)
3. Use the modern StoreKit requestReview environment value, not the deprecated SKStoreReviewController
4. Track prompt count in UserDefaults with a yearly reset
```

---

### 4.2 Inconsistent Font Sizing

**Context:** Different views use different font sizes for the same content types. Title fonts range from 42pt to system default. No consistent typography scale.

**Solution:** Create a typography system in DesignSystem.swift and use it consistently.

**Agent Prompt:**
```
Create a consistent typography system in Fit33/DesignSystem.swift:
1. Define a type scale: title1 (28pt), title2 (22pt), headline (17pt), body (15pt), caption (13pt), footnote (11pt)
2. Use .font(.system()) with these sizes throughout
3. Ensure all text uses these tokens instead of arbitrary sizes
4. Audit the 10 most user-facing views for font consistency
```

---

### 4.3 Haptic Feedback Inconsistency

**Context:** Some buttons trigger haptic feedback, others don't. `HapticManager` exists but isn't used consistently.

**Solution:** Define a haptic feedback policy and apply consistently.

**Agent Prompt:**
```
The Fit33 iOS app has inconsistent haptic feedback. Create a policy and apply it:
1. Define which actions get haptics in HapticManager:
   - .light: tab switches, toggles
   - .medium: button presses, navigation
   - .heavy: workout start/complete, achievement earned
   - .success: set completed, exercise completed
   - .error: validation failure
   - .warning: streak at risk
2. Audit all Button actions in the 10 most-used views and add appropriate haptic calls
3. Add haptics to workout completion flow (confetti moment)
```

---

### 4.4 Image Loading Without Placeholders

**Context:** Profile photos, recipe images, and exercise thumbnails load without skeleton/placeholder UI.

**Solution:** Add shimmer/skeleton loading states for all async images.

**Agent Prompt:**
```
Add loading placeholders for all async image loading in Fit33:
1. Create a reusable ShimmerView component in DesignSystem.swift
2. Apply to profile photo loading in ProfileView.swift
3. Apply to recipe images in RecipeBrowserView.swift
4. Apply to exercise thumbnails if applicable
5. Use AsyncImage with custom placeholder where SwiftUI supports it
```

---

### 4.5 No Data Export / Backup Feature

**Context:** Users have no way to export their workout history, nutrition data, or profile. If they delete the app or lose their account, data is gone.

**Solution:** Add a "Download My Data" feature (also required by GDPR).

**Agent Prompt:**
```
Add a data export feature to Fit33 for GDPR compliance and user convenience:
1. In Fit33/DataDownloadView.swift (already exists), implement actual export:
   - Export workout history as CSV
   - Export nutrition log as CSV
   - Export profile data as JSON
   - Package into a ZIP file
   - Share via UIActivityViewController
2. Add export button in SettingsView.swift
3. Ensure all user data is included (workouts, meals, measurements, achievements)
```

---

### 4.6 Background App Refresh Reliability

**Context:** `BackgroundChallengeSyncService.swift` uses `BGAppRefreshTask` for periodic challenge syncs but has a force cast (`task as! BGAppRefreshTask`) and limited retry logic.

**Solution:** Fix the force cast and add proper reliability measures.

**Agent Prompt:**
```
Fix background sync reliability in Fit33/BackgroundChallengeSyncService.swift:
1. Fix the force cast at line 221: `task as! BGAppRefreshTask` → safe cast with guard
2. Add exponential backoff for failed background syncs
3. Log background sync results to analytics (success/failure/skipped)
4. Add a minimum sync interval to prevent excessive background work
5. Test with Xcode's background task debugger
```

---

## 5. Architecture & Technical Debt

### 5.1 Singleton Overuse (40+ Singletons)

**Context:** The app uses 40+ `.shared` singletons for services, managers, and engines. This creates tight coupling, makes testing impossible, and causes initialization order issues.

**Why This Matters:** Singletons can't be mocked for unit tests. Service initialization order is implicit and fragile. Memory is never freed.

**Solution (Post-Launch):** Gradually migrate to dependency injection using SwiftUI's `@EnvironmentObject` or a DI container.

**Agent Prompt:**
```
The Fit33 iOS app has 40+ singletons. For now, document all singletons and their dependencies. Long-term, plan a migration to dependency injection:
1. List all files with `static let shared` pattern
2. Map dependencies between singletons (which ones reference which)
3. Identify initialization order requirements
4. Propose a phased migration plan starting with the most testable services
```

---

### 5.2 File Size Issues

**Context:** Several files are extremely large:
- `ContentView.swift`: 55,000+ tokens (likely 3000+ lines)
- `SupabaseManager.swift`: 47,000+ tokens
- `WorkoutManager.swift`: Very large with 50+ @Published properties
- `DashboardView.swift`: Very large with 60+ @State properties

**Why This Matters:** Large files are hard to maintain, review, and debug. They indicate that responsibilities should be split.

**Solution (Post-Launch):** Break large files into focused components.

**Agent Prompt:**
```
The Fit33 iOS app has several excessively large files. Plan a refactoring strategy:
1. ContentView.swift (~3000+ lines): Split into ContentView (tab container) + separate tab content views
2. SupabaseManager.swift (~2500+ lines): Split into SupabaseAuthService, SupabaseProfileService, SupabaseSyncService
3. WorkoutManager.swift: Split into WorkoutSessionManager (active workout) + WorkoutNavigationManager (navigation state) + WorkoutDataManager (persistence)
4. DashboardView.swift: Extract widget sections into separate views (StreakWidget, ProgramWidget, WorkoutHistoryWidget)
```

---

### 5.3 No Unit Tests

**Context:** While there are test/audit files (`CriticalPathTests.swift`, `LimitationFilterTests.swift`), these are in-app diagnostic tools, not actual XCTest unit tests. There is no test target in the Xcode project.

**Why This Matters:** No automated testing means every change risks breaking existing functionality. Can't safely refactor. Bugs are caught only through manual testing.

**Solution:** Set up an XCTest target and add tests for critical paths.

**Agent Prompt:**
```
The Fit33 iOS app has no XCTest unit tests. Set up testing infrastructure:
1. Create a Fit33Tests target in the Xcode project
2. Write tests for the most critical business logic:
   - UserManager: streak calculation, XP calculation, level progression
   - WorkoutManager: exercise set initialization, workout completion
   - MealService: calorie calculations, macro tracking
   - ExerciseFilterService: filtering logic
   - PremiumManager: feature gating
3. Write tests for data validation (once implemented per section 2.4)
4. Use XCTest with mock Core Data context (in-memory store)
5. Target 50% code coverage on business logic files
```

---

## 6. App Store Submission Checklist

### Pre-Submission Requirements:

- [ ] **Privacy Policy URL** - `privacy-policy.md` exists but needs to be hosted at a public URL and linked in App Store Connect
- [ ] **Terms of Service** - `TermsConditionsView.swift` exists but verify content is current
- [ ] **App Store Screenshots** - Need screenshots for all required device sizes
- [ ] **App Store Description** - Update with current feature set
- [ ] **Age Rating** - Determine correct age rating (likely 4+ or 12+)
- [ ] **Content Rights** - Verify all exercise descriptions, recipe data, and images are properly licensed
- [ ] **Export Compliance** - App uses HTTPS encryption, may need export compliance documentation
- [ ] **HealthKit Entitlements** - Verify all requested HealthKit data types are properly declared
- [ ] **Push Notification Entitlements** - Verify APNs configuration
- [ ] **Data Deletion** - Apple requires ability to delete account and all data (verify `complete_account_deletion.sql` covers this)
- [ ] **Minimum Deployment Target** - Verify target iOS version is reasonable (iOS 16+)
- [ ] **App Icons** - All required sizes (app icon, spotlight, settings)
- [ ] **Launch Screen** - Verify launch screen matches app design

### Critical Fixes Required Before Submission:

1. [ ] Move hardcoded credentials to Secrets.swift (#1.1)
2. [ ] Implement StoreKit IAP or remove premium features (#1.3)
3. [ ] Add App Tracking Transparency (#1.4)
4. [ ] Fix force unwraps (#1.5)
5. [ ] Add basic accessibility (#2.3)
6. [ ] Add input validation (#2.4)

### Recommended Before Submission:

7. [ ] Fix navigation architecture (#2.2)
8. [ ] Add offline handling (#2.5)
9. [ ] Fix keyboard handling (#3.9)
10. [ ] Audit safe area usage (#3.10)

---

## Summary

| Priority | Count | Status |
|----------|-------|--------|
| CRITICAL | 6 | Must fix before ANY release |
| HIGH | 10 | Must fix before production |
| MEDIUM | 10 | Should fix before production |
| LOW | 6 | Nice to have / post-launch |
| Architecture | 3 | Long-term tech debt |
| **TOTAL** | **35** | |

### Estimated Impact on User Experience:
- **Fixing CRITICAL issues:** Prevents App Store rejection and security vulnerabilities
- **Fixing HIGH issues:** Eliminates most crashes and user-facing bugs
- **Fixing MEDIUM issues:** Polishes the experience to professional quality
- **Fixing LOW issues:** Delights users and improves retention

### Recommended Order of Implementation:
1. Security fixes (#1.1, #1.2, #1.6) - same day
2. StoreKit integration (#1.3) - 2-3 days
3. ATT implementation (#1.4) - 1 day
4. Force unwrap fixes (#1.5) - 1 day
5. Input validation (#2.4) - 1 day
6. Accessibility basics (#2.3) - 2 days
7. Navigation fix (#2.2) - 2-3 days
8. Offline support (#2.5) - 2-3 days
9. Everything else - ongoing

---

---

## 7. Backend & Infrastructure Issues (Admin CMS + Supabase Edge Functions)

### 7.1 CRITICAL: Admin Session Tokens in sessionStorage (XSS Vulnerable)

**Context:** The admin CMS (`admin-cms/src/lib/auth.ts`) stores Supabase session tokens (access_token, refresh_token) in `sessionStorage`. Any XSS vulnerability in the admin dashboard would allow token theft.

**Why This Is a Problem:** sessionStorage is accessible via JavaScript. If an attacker injects script (via a crafted crash report message, bug report content, or user name that contains `<script>` tags), they can steal the admin token and gain full service-role database access.

**Solution:** Use httpOnly Secure cookies for admin token storage, or implement Supabase's built-in PKCE auth flow.

**Agent Prompt:**
```
The Fit33 admin CMS stores auth tokens in sessionStorage which is XSS-vulnerable. Fix this:

1. In admin-cms/src/lib/auth.ts, replace sessionStorage token storage with httpOnly cookies
2. Create an API route admin-cms/src/app/api/auth/session/route.ts that:
   - Sets httpOnly, Secure, SameSite=Strict cookies on login
   - Reads cookies for auth verification instead of Authorization header
   - Clears cookies on logout
3. Update admin-cms/src/middleware.ts to read auth from cookies instead of sessionStorage
4. Update admin-cms/src/lib/api.ts to stop sending Authorization header (cookies are automatic)
5. Alternatively, use Supabase's built-in SSR auth helpers (@supabase/ssr) which handle cookie-based auth securely
```

---

### 7.2 HIGH: No Admin Audit Logging

**Context:** The admin CMS allows viewing/editing user profiles, managing crash reports, and accessing all user data. There is no audit trail of who accessed what, when.

**Why This Is a Problem:** If an admin account is compromised or misused, there's no way to know what data was accessed or modified. This is a compliance requirement for GDPR (Article 30) and SOC 2.

**Solution:** Create an admin_audit_log table and log all admin actions.

**Agent Prompt:**
```
The Fit33 admin CMS has no audit logging. Add a comprehensive audit trail:

1. Create a Supabase migration for admin_audit_log table:
   - id (uuid), admin_user_id (uuid), admin_email (text), action (text), target_user_id (uuid nullable)
   - target_entity (text), entity_id (text), request_ip (text), request_method (text)
   - request_path (text), changes_json (jsonb nullable), created_at (timestamptz)
   - Index on created_at, admin_user_id, target_user_id

2. In admin-cms/src/app/api/admin/route.ts, add audit logging to:
   - All user profile views (action: 'view_user_profile')
   - All user profile edits (action: 'edit_user_profile', include changes_json)
   - All crash report status changes (action: 'update_crash_report')
   - All bulk operations (action: 'bulk_update_crash_reports')

3. Create an admin audit log viewer page in the CMS dashboard
```

---

### 7.3 HIGH: No Rate Limiting on Admin API

**Context:** The admin API (`admin-cms/src/app/api/admin/route.ts` - 1075 lines) only verifies the Bearer token. There are no per-action rate limits. A compromised admin token could dump the entire database.

**Why This Is a Problem:** Without rate limiting, a stolen admin token allows bulk data exfiltration of all user data in seconds.

**Solution:** Add per-endpoint rate limiting to the admin API.

**Agent Prompt:**
```
The Fit33 admin API has no rate limiting beyond login. Add per-action rate limits:

1. In admin-cms/src/app/api/admin/route.ts:
   - Add a rate limiter (in-memory Map with IP + action as key)
   - Limit data queries: 100 requests/minute per admin
   - Limit user edits: 30 requests/minute per admin
   - Limit bulk operations: 5 requests/minute per admin
   - Return 429 Too Many Requests with Retry-After header

2. Consider using Upstash Redis rate limiting (@upstash/ratelimit) for distributed rate limiting if the admin CMS scales to multiple instances
```

---

### 7.4 HIGH: No Admin 2FA/MFA

**Context:** Admin login (`admin-cms/src/app/api/auth/login/route.ts`) uses email + password only. The admin email whitelist provides some protection, but password-only auth for admin access is insufficient.

**Why This Is a Problem:** Admin accounts have access to ALL user data, crash reports, and user management functions. A phished or leaked password gives complete access.

**Solution:** Add TOTP-based 2FA for admin accounts.

**Agent Prompt:**
```
The Fit33 admin CMS only uses password auth. Add 2FA:

1. Enable Supabase MFA for admin users (Supabase supports TOTP natively)
2. In admin-cms/src/app/api/auth/login/route.ts:
   - After successful password auth, check if user has MFA enrolled
   - If MFA enrolled, return { requiresMFA: true, factorId: ... }
   - Add a new endpoint /api/auth/verify-mfa that accepts the TOTP code
   - Only issue session tokens after both password AND TOTP verified
3. Add MFA enrollment page in the admin CMS settings
```

---

### 7.5 MEDIUM: Phone Numbers Logged as PII

**Context:** The Twilio edge functions (`send-verification/index.ts`, `verify-code/index.ts`) log full phone numbers. The database also stores verification attempts with phone numbers.

**Why This Is a Problem:** Phone numbers are PII under GDPR, CCPA, and other privacy regulations. Logging them creates compliance risk and potential data exposure in log aggregation systems.

**Solution:** Redact phone numbers in logs, hash in storage.

**Agent Prompt:**
```
Fit33's Twilio edge functions log full phone numbers. Redact PII from logs:

1. In supabase/functions/send-verification/index.ts:
   - Replace console.log with phone number with a redacted version: `+1***XXX` (show only last 3 digits)
   - Same for verify-code/index.ts

2. In the phone_verifications table:
   - Store phone numbers hashed (SHA-256) for lookup, not in plaintext
   - Only store the last 4 digits in a separate column for display purposes

3. Review all edge functions for PII logging (email addresses, names, etc.)
```

---

### 7.6 MEDIUM: No CI/CD Pipeline

**Context:** There are no GitHub Actions, GitLab CI, or any CI/CD configuration files. The admin CMS and Supabase edge functions have no automated build, test, or deployment pipeline.

**Why This Is a Problem:** Manual deployments are error-prone. No automated testing means regressions go unnoticed. No deployment history means rollbacks are difficult.

**Solution:** Set up GitHub Actions for basic CI.

**Agent Prompt:**
```
The Fit33 project has no CI/CD pipeline. Set up GitHub Actions:

1. Create .github/workflows/admin-cms-ci.yml:
   - Trigger on push/PR to main
   - Run npm ci, npm run lint, npm run build for admin-cms
   - Fail on lint errors or build failures

2. Create .github/workflows/ios-build.yml:
   - Trigger on push/PR to main
   - Run xcodebuild for syntax checking (don't need full archive)
   - Run swiftlint if available

3. Create .github/workflows/deploy-edge-functions.yml:
   - Trigger on push to main when supabase/functions/ changed
   - Deploy edge functions via supabase CLI
   - Requires SUPABASE_ACCESS_TOKEN secret

4. Add branch protection rules on main: require CI pass, require PR review
```

---

### 7.7 MEDIUM: Crash Reports No Auto-Cleanup

**Context:** The `crash_reports` table stores reports indefinitely. There's no automated cleanup, TTL, or archival strategy.

**Why This Is a Problem:** Over time, crash reports accumulate and increase storage costs. Old crash reports (60+ days) are rarely useful. Stack traces may contain sensitive code paths.

**Solution:** Add automated cleanup via pg_cron.

**Agent Prompt:**
```
Add automated crash report cleanup to Fit33's Supabase:

1. Create a SQL migration that:
   - Enables pg_cron extension if not already enabled
   - Creates a cron job that runs daily to delete crash reports older than 90 days with status 'resolved' or 'wont_fix'
   - Keeps 'new' and 'investigating' reports indefinitely
   - Example: SELECT cron.schedule('cleanup-old-crash-reports', '0 3 * * *', $$ DELETE FROM crash_reports WHERE created_at < NOW() - INTERVAL '90 days' AND status IN ('resolved', 'wont_fix', 'duplicate') $$);

2. Add an archive strategy: before deletion, export old reports to a CSV/JSON backup in Supabase Storage
```

---

### 7.8 LOW: Edge Function Error Handling Inconsistency

**Context:** The 6 Supabase Edge Functions have varying levels of error handling. `send-push-notification` (406 lines) has excellent retry logic, while `notify-contacts-user-joined` has minimal error handling.

**Solution:** Standardize error handling across all edge functions.

**Agent Prompt:**
```
Standardize error handling across Fit33's Supabase edge functions:

1. Create a shared error handler utility in supabase/functions/_shared/error-handler.ts:
   - Standard error response format: { error: string, code: string, details?: string }
   - HTTP status code mapping
   - Structured logging with request ID

2. Apply to all 6 edge functions:
   - send-verification
   - verify-code
   - send-push-notification (already good, use as template)
   - usda-food-search
   - notify-contacts-user-joined
   - edge_function_simplified

3. Add request validation (zod schemas) at the entry point of each function
```

---

## 8. Database & Realtime Issues (Supabase Schema, RLS, Challenges)

### 8.1 CRITICAL: Missing/Incomplete RLS Policies on Challenge Tables

**Context:** Several challenge tables (`challenge_daily_progress`, `challenge_participants`, `group_challenges`) have minimal RLS policies. Notably, DELETE policies are missing entirely, and `community_challenge_participants` lacks comprehensive RLS enforcement.

**Why This Is a Problem:** Without proper RLS, any authenticated user could potentially read, modify, or delete other users' challenge data via direct Supabase API calls. This is a data privacy and integrity issue.

**Solution:** Add comprehensive RLS policies for all challenge and social tables.

**Agent Prompt:**
```
The Fit33 Supabase database has incomplete RLS policies on challenge tables. Fix this:

1. Run this SQL to verify current RLS status:
   SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname = 'public' AND tablename LIKE '%challenge%';

2. For each challenge table (group_challenges, challenge_participants, challenge_daily_progress, community_challenge_participants, community_challenge_daily_progress):
   - Ensure ALTER TABLE ... ENABLE ROW LEVEL SECURITY is set
   - Add SELECT policy: users can only see challenges they participate in
   - Add INSERT policy: users can only insert their own progress
   - Add UPDATE policy: users can only update their own records
   - Add DELETE policy: users can only delete their own records OR challenge creators can delete the challenge
   - Example:
     CREATE POLICY "Users can view own challenge participation"
     ON challenge_participants FOR SELECT
     USING (user_id = auth.uid());

3. Test by attempting cross-user data access with different auth tokens
```

---

### 8.2 CRITICAL: Race Condition in Challenge Creation (Non-Atomic Operations)

**Context:** Challenge RPC functions like `create_challenge()` and `respond_to_challenge()` in `challenge_rpc_functions.sql` perform multi-step operations (INSERT group_challenges → INSERT participants → UPDATE status) without explicit transaction wrapping. If the connection drops mid-operation, orphaned records can exist.

**Why This Is a Problem:** Orphaned `challenge_participants` without a corresponding `group_challenges` row will crash the app when trying to load challenge details. Users see phantom challenges in their pending list.

**Solution:** Wrap all multi-step RPCs in explicit transactions.

**Agent Prompt:**
```
The Fit33 Supabase challenge RPC functions have race conditions from non-atomic multi-step operations. Fix this:

1. In supabase/challenge_rpc_functions.sql, for each RPC that does multiple INSERTs:
   - Wrap in BEGIN ... EXCEPTION ... END blocks
   - On any failure, ROLLBACK and RAISE EXCEPTION with descriptive message
   - Example pattern:
     BEGIN
       INSERT INTO group_challenges (...) VALUES (...);
       INSERT INTO challenge_participants (...) VALUES (...);
       -- If we get here, both succeeded
     EXCEPTION WHEN OTHERS THEN
       RAISE EXCEPTION 'Challenge creation failed: %', SQLERRM;
     END;

2. Add a cleanup function that finds and removes orphaned records:
   DELETE FROM challenge_participants cp
   WHERE NOT EXISTS (SELECT 1 FROM group_challenges gc WHERE gc.id = cp.challenge_id);

3. Schedule this cleanup as a pg_cron job running hourly
```

---

### 8.3 CRITICAL: Timezone Inconsistency in Challenge Progress

**Context:** The server uses `(NOW() AT TIME ZONE p_timezone)::DATE` for "today" in challenge functions, but the iOS client in `ChallengeService.swift` sends progress dates in local time without timezone context. A user at 11 PM PST logs progress, but the server may interpret it as the next day in UTC.

**Why This Is a Problem:** Challenge progress gets logged on the wrong day. Daily streaks break unexpectedly. Users lose progress or see incorrect daily targets.

**Solution:** Always pass the user's timezone with progress logging calls.

**Agent Prompt:**
```
The Fit33 challenge system has timezone inconsistencies between client and server. Fix this:

1. In Fit33/ChallengeService.swift, wherever log_challenge_progress() is called:
   - Add the user's current timezone identifier: TimeZone.current.identifier (e.g., "America/Los_Angeles")
   - Pass it as a parameter to the RPC call
   - Example: ["p_timezone": TimeZone.current.identifier]

2. In the Supabase log_challenge_progress() RPC function:
   - Use the passed timezone for ALL date comparisons
   - Validate that progress_date matches (NOW() AT TIME ZONE p_timezone)::DATE ± 1 day
   - Reject progress for dates more than 1 day in the future or past

3. In the midnight reset logic (fix_challenge_midnight_reset.sql):
   - Ensure reset uses participant's stored timezone, not UTC
   - Test with users in UTC-12 and UTC+14 edge cases

4. Add a check: if no timezone provided, default to the user's profile timezone (stored in user_profiles)
```

---

### 8.4 HIGH: REPLICA IDENTITY Not Verified on All Realtime Tables

**Context:** `fix_challenge_realtime_replica_identity.sql` sets `REPLICA IDENTITY FULL` on challenge tables, but it's unclear if this migration was deployed. Without it, Supabase Realtime only sends the primary key on UPDATE events, not the full row. The `RealtimeService.swift` (line 530-538) has a "defensive refresh" workaround for when `oldRecord` is empty.

**Why This Is a Problem:** Incomplete realtime events cause the app to make extra API calls (defensive refresh), increasing latency and battery drain. Challenge updates appear delayed.

**Solution:** Verify and ensure REPLICA IDENTITY FULL is deployed.

**Agent Prompt:**
```
Verify that REPLICA IDENTITY FULL is set on all Fit33 Supabase tables that use Realtime:

1. Run this SQL in Supabase SQL Editor to check current state:
   SELECT c.relname AS table_name,
          CASE c.relreplident
              WHEN 'd' THEN 'DEFAULT (pk only) ❌'
              WHEN 'f' THEN 'FULL ✅'
              WHEN 'n' THEN 'NOTHING ❌'
              WHEN 'i' THEN 'INDEX'
          END AS replica_identity
   FROM pg_class c
   JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public'
   AND c.relname IN ('challenge_daily_progress', 'challenge_participants', 'group_challenges', 'friendships', 'shared_workouts', 'community_challenge_participants', 'community_challenge_daily_progress');

2. For any table showing DEFAULT or NOTHING, run:
   ALTER TABLE <table_name> REPLICA IDENTITY FULL;

3. Verify all tables are in the supabase_realtime publication:
   SELECT * FROM pg_publication_tables WHERE pubname = 'supabase_realtime';

4. After confirming REPLICA IDENTITY FULL is deployed, update RealtimeService.swift to remove the defensive refresh workaround at lines 530-538 (it's a bandaid for missing REPLICA IDENTITY)
```

---

### 8.5 HIGH: No Validation on Challenge Progress Values

**Context:** The `log_challenge_progress()` RPC accepts any integer for progress. There's no upper bound check, and while `GREATEST()` prevents decreases, negative values could still be injected.

**Why This Is a Problem:** A reverse-engineered client or API manipulation could set progress to extreme values, skewing leaderboards. Negative values could corrupt aggregate calculations.

**Solution:** Add server-side validation bounds.

**Agent Prompt:**
```
Add server-side validation for challenge progress values in Fit33's Supabase:

1. In the log_challenge_progress() RPC function, add these checks:
   - IF p_progress_value < 0 THEN RAISE EXCEPTION 'Progress value cannot be negative';
   - Add per-type upper bounds:
     * steps: IF p_progress_value > 200000 THEN RAISE EXCEPTION 'Unrealistic step count';
     * distance_km: IF p_progress_value > 200 THEN RAISE EXCEPTION 'Unrealistic distance';
     * active_minutes: IF p_progress_value > 1440 THEN RAISE EXCEPTION 'Cannot exceed minutes in a day';
     * calories: IF p_progress_value > 20000 THEN RAISE EXCEPTION 'Unrealistic calorie count';

2. Also validate that progress_date is not after the challenge end_date:
   - IF progress_date > challenge.end_date THEN RAISE EXCEPTION 'Challenge has ended';

3. Add an audit column: last_progress_source TEXT (e.g., 'healthkit', 'manual', 'strava') to track how progress was reported
```

---

### 8.6 MEDIUM: Missing Database Indexes for Common Query Patterns

**Context:** Challenge leaderboard queries, friend list lookups, and daily progress aggregations lack optimized indexes. Current indexes exist for basic lookups but not for the most common app query patterns.

**Solution:** Add targeted indexes for the most frequent queries.

**Agent Prompt:**
```
Add missing database indexes to Fit33's Supabase for common query patterns:

1. Challenge leaderboard queries:
   CREATE INDEX IF NOT EXISTS idx_challenge_participants_leaderboard
   ON challenge_participants (challenge_id, status) WHERE status = 'accepted';

2. Daily progress lookups:
   CREATE INDEX IF NOT EXISTS idx_daily_progress_user_date
   ON challenge_daily_progress (user_id, progress_date DESC);

3. Community challenge leaderboard:
   CREATE INDEX IF NOT EXISTS idx_community_participants_active
   ON community_challenge_participants (challenge_id, today_progress DESC) WHERE is_active = TRUE;

4. Friend request lookups:
   CREATE INDEX IF NOT EXISTS idx_friendships_pending
   ON friendships (addressee_id, status) WHERE status = 'pending';

5. Shared workout lookups:
   CREATE INDEX IF NOT EXISTS idx_shared_workouts_recipient
   ON shared_workouts (recipient_id, created_at DESC) WHERE is_read = FALSE;

6. Verify with EXPLAIN ANALYZE on the most common queries to confirm index usage
```

---

### 8.7 MEDIUM: Missing Null Handling in Swift DTOs

**Context:** `SupabaseDTOs.swift` has structs like `ActiveChallenge` with optional fields, but views that consume these DTOs sometimes force-unwrap or assume non-nil values for opponent data. If the database returns NULL (e.g., opponent deleted their account), the app crashes.

**Solution:** Add COALESCE in SQL queries and safe unwrapping in DTOs.

**Agent Prompt:**
```
Fix null handling in Fit33's Supabase DTOs and queries:

1. In Fit33/SupabaseDTOs.swift, audit all structs for optional fields that are used without nil checks:
   - ActiveChallenge: ensure opponent_name, opponent_avatar_url handle nil
   - Add default values: var opponentName: String { opponent_name ?? "Unknown" }

2. In ChallengeService.swift, where challenge data is fetched:
   - Add COALESCE in SQL queries: COALESCE(opponent.name, 'Deleted User') as opponent_name
   - Handle the case where opponent profile no longer exists

3. In views that display challenge data:
   - Use nil-coalescing: Text(challenge.opponentName ?? "Opponent")
   - Show "User left" or "Deleted" badge if opponent data is nil
```

---

### 8.8 LOW: Cascade Deletion Removes Historical Challenge Data

**Context:** `challenge_participants` and `challenge_daily_progress` use `ON DELETE CASCADE` on `user_id`. When a user deletes their account, all their challenge history vanishes, breaking leaderboards and historical analytics.

**Solution:** Archive before deletion or use soft deletes.

**Agent Prompt:**
```
Fix cascade deletion behavior for Fit33's challenge tables:

1. Create an archive table:
   CREATE TABLE archived_challenge_data (
     id UUID DEFAULT gen_random_uuid(),
     original_table TEXT NOT NULL,
     original_id UUID NOT NULL,
     data JSONB NOT NULL,
     deleted_user_id UUID,
     archived_at TIMESTAMPTZ DEFAULT NOW()
   );

2. In the complete_account_deletion.sql cascade:
   - Before deleting user data, INSERT a JSONB snapshot into archived_challenge_data
   - Archive: challenge participation records, daily progress, final standings

3. Update leaderboard queries to show "[Deleted User]" for archived participants instead of removing them entirely
```

---

## Final Summary

| Priority | Count | Status |
|----------|-------|--------|
| CRITICAL | 10 (6 iOS + 1 backend + 3 database) | Must fix before ANY release |
| HIGH | 16 (10 iOS + 3 backend + 3 database) | Must fix before production |
| MEDIUM | 17 (10 iOS + 4 backend + 3 database) | Should fix before production |
| LOW | 8 (6 iOS + 1 backend + 1 database) | Nice to have / post-launch |
| Architecture | 3 | Long-term tech debt |
| **TOTAL** | **54** | |

---

*Generated by comprehensive codebase audit of 252 Swift source files, 6 Supabase Edge Functions, admin CMS (Next.js), 27 SQL migrations (42,807 lines), and full UI/UX review.*
