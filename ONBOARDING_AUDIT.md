# Onboarding Flow - Comprehensive Audit & Specification

> Generated: March 7, 2026
> Branch: `claude/improve-onboarding-flow-69u03`
> Status: Audit complete, fixes applied, test suite built

---

## Table of Contents

1. [Flow Overview](#1-flow-overview)
2. [File Map](#2-file-map)
3. [17-Step Flow Detail](#3-17-step-flow-detail)
4. [Bugs Found & Fixed](#4-bugs-found--fixed)
5. [Country Code & Internationalization](#5-country-code--internationalization)
6. [Phone Verification Infrastructure](#6-phone-verification-infrastructure)
7. [Contact Sync Pipeline](#7-contact-sync-pipeline)
8. [Unit Conversion System](#8-unit-conversion-system)
9. [Responsive Layout & Screen Sizing](#9-responsive-layout--screen-sizing)
10. [Text Field Styling Reference](#10-text-field-styling-reference)
11. [Keyboard & Focus Management](#11-keyboard--focus-management)
12. [Design System Tokens](#12-design-system-tokens)
13. [Onboarding Components Library](#13-onboarding-components-library)
14. [Auth & OAuth Flow](#14-auth--oauth-flow)
15. [Test Suite](#15-test-suite)
16. [Remaining Gaps & Recommendations](#16-remaining-gaps--recommendations)
17. [Validation Checklist](#17-validation-checklist)

---

## 1. Flow Overview

The Fit33 onboarding is a 17-step sequential flow that collects user profile data, verifies identity, and connects social contacts. It supports new signups (email/password), OAuth (Apple/Google), and returning users.

**Entry**: `ContentView.swift` routes to `NewOnboardingView` when `hasCompletedOnboarding == false`
**Exit**: Step 17 (complete) sets `hasCompletedOnboarding = true` and transitions to main app

**Architecture**: Single-file monolith (`NewOnboardingView.swift`, ~8,615 lines) containing all 17 step views, validation logic, state management, and helper types.

---

## 2. File Map

### Primary Files (Modified in Audit)

| File | Path | Lines | Role |
|------|------|-------|------|
| NewOnboardingView.swift | `/home/user/Fit33/Fit33/NewOnboardingView.swift` | ~8,615 | Main flow controller, all 17 steps, CountryCode enum, validation |
| OnboardingTestHelper.swift | `/home/user/Fit33/Fit33/OnboardingTestHelper.swift` | ~620 | Test suite with 8 profiles, 50+ unit tests, E2E tests |

### Supporting Files (Read, Not Modified)

| File | Path | Role |
|------|------|------|
| OnboardingComponents.swift | `/home/user/Fit33/Fit33/OnboardingComponents.swift` | Reusable cards, buttons, progress bar, step container |
| PhoneVerificationService.swift | `/home/user/Fit33/Fit33/PhoneVerificationService.swift` | Twilio SMS wrapper (166 lines) |
| PhoneVerificationSheet.swift | `/home/user/Fit33/Fit33/PhoneVerificationSheet.swift` | Standalone 2FA sheet (548 lines, used in Settings) |
| ContactsService.swift | `/home/user/Fit33/Fit33/ContactsService.swift` | Device contact fetch, phone/email matching (786 lines) |
| UnitSettingsManager.swift | `/home/user/Fit33/Fit33/UnitSettingsManager.swift` | Locale-aware imperial/metric defaults |
| UserManager.swift | `/home/user/Fit33/Fit33/UserManager.swift` | User creation, profile sync (859 lines) |
| SupabaseManager.swift | `/home/user/Fit33/Fit33/SupabaseManager.swift` | Auth, cloud sync, profile CRUD (4,382 lines) |
| ContentView.swift | `/home/user/Fit33/Fit33/ContentView.swift` | Root routing (onboarding vs main app) |
| Fit33App.swift | `/home/user/Fit33/Fit33/Fit33App.swift` | App entry point |
| DesignSystem.swift | `/home/user/Fit33/Fit33/DesignSystem.swift` | Typography, spacing, gradients, buttons |
| AdaptiveColors.swift | `/home/user/Fit33/Fit33/AdaptiveColors.swift` | Dark/light mode colors, animated backgrounds |
| OrientationManager.swift | `/home/user/Fit33/Fit33/OrientationManager.swift` | Screen size tracking singleton |
| AuthView.swift | `/home/user/Fit33/Fit33/AuthView.swift` | Standalone auth screen (used outside onboarding) |

### Supabase Edge Functions

| File | Path | Role |
|------|------|------|
| send-verification/index.ts | `/home/user/Fit33/supabase/functions/send-verification/index.ts` | Twilio Verify SMS send (127 lines) |
| verify-code/index.ts | `/home/user/Fit33/supabase/functions/verify-code/index.ts` | Twilio Verify code check (137 lines) |
| notify-contacts-user-joined/index.ts | `/home/user/Fit33/supabase/functions/notify-contacts-user-joined/index.ts` | Push notifications to existing users (249 lines) |

---

## 3. 17-Step Flow Detail

```
Step 0:  auth               → Email/password signup OR OAuth (Apple/Google)
Step 1:  username            → Unique username with async availability check
Step 2:  phoneNumber         → Country code picker + phone input + SMS verification
Step 3:  basics              → Name, birthday (MM/DD/YYYY or DD/MM/YYYY), gender (optional)
Step 4:  body                → Height (ft/in or cm), weight (lbs or kg)
Step 5:  goal                → Fitness goal selection (multi-select cards)
Step 6:  experience          → Experience level (beginner/intermediate/advanced)
Step 7:  strengthAssessment  → Self-assessed strength benchmarks
Step 8:  workoutLocation     → Home, gym, or both
Step 9:  equipment           → Available equipment (multi-select)
Step 10: limitations         → Physical limitations/injuries (multi-select)
Step 11: schedule            → Preferred workout days and times
Step 12: profilePhoto        → Optional photo upload
Step 13: contacts            → Request contact access, sync to database
Step 14: addFriends          → Show matched contacts, send friend requests
Step 15: confirmation        → Review all selections
Step 16: complete            → Save profile, set hasCompletedOnboarding = true
```

### Step Validation Rules

| Step | Required to Continue |
|------|---------------------|
| auth | Valid email + password (8+ chars, 1 uppercase, 1 number) OR successful OAuth |
| username | Non-empty, 3-20 chars, alphanumeric + underscore only, available in DB |
| phoneNumber | Valid phone for country (10+ digits US), verified via SMS code |
| basics | Valid birthday (age 13-120), Calendar roundtrip validated. Gender is optional |
| body | Height > 0, weight > 0 |
| goal | At least 1 goal selected |
| experience | Selection made |
| strengthAssessment | Selection made |
| workoutLocation | Selection made |
| equipment | At least 1 item selected |
| limitations | Can skip (none selected = no limitations) |
| schedule | At least 1 day selected |
| profilePhoto | Can skip |
| contacts | Can skip (decline permission) |
| addFriends | Can skip |
| confirmation | Tap confirm |
| complete | Auto-proceeds |

---

## 4. Bugs Found & Fixed

### Critical Fixes Applied

| Bug | Impact | Fix |
|-----|--------|-----|
| **Invalid birthday acceptance** | Feb 30, Apr 31 passed validation | Added Calendar roundtrip: parse → format → compare month/day/year |
| **Gender required but labeled optional** | Users stuck if they skipped gender | Removed `selectedGender != nil` from basics validation |
| **Phone max attempts = 2** | Users locked out after 2 tries | Changed `maxPhoneVerificationAttempts` from 2 to 3 |
| **Height zero-padded inches** | 5'8" displayed as 5'08" | Removed zero-padding in `formatHeightDisplay()` |
| **Timer memory leak** | Timers never invalidated on view dismiss | Added `sendCodeTimer?.invalidate()` in `onDisappear` |
| **Hardcoded safe area (70pt)** | Broken on iPhone SE and 15 Pro Max | Replaced with dynamic `UIWindowScene` safe area calculation |
| **Verification tiles overflow** | 50pt fixed tiles overflow 320pt iPhone SE | Replaced with `GeometryReader`-based responsive sizing |
| **Country always defaults to US** | Non-US users must manually switch | Added `CountryCode.fromLocale()` reading device region |
| **Canada phone code conflict** | Canada and US both use +1 | Added `dialingCode` property; `rawValue` uses "+1CA" for enum ID |
| **Phone formatting US-only** | International numbers unformatted | Added country-specific formatting for India, Brazil, Japan, Australia, Singapore, HK, Canada |

---

## 5. Country Code & Internationalization

### CountryCode Enum (45 Countries)

Located in `NewOnboardingView.swift`. Expanded from 16 to 45 countries.

```swift
enum CountryCode: String, CaseIterable, Identifiable {
    // North America
    case us = "+1"
    case canada = "+1CA"  // Special: shares +1 with US

    // Europe
    case uk = "+44"
    case ireland = "+353"
    case france = "+33"
    case germany = "+49"
    case spain = "+34"
    case italy = "+39"
    case netherlands = "+31"
    case belgium = "+32"
    case portugal = "+351"
    case austria = "+43"
    case switzerland = "+41"
    case sweden = "+46"
    case norway = "+47"
    case denmark = "+45"
    case poland = "+48"
    case finland = "+358"
    case greece = "+30"
    case czech = "+420"
    case romania = "+40"
    case hungary = "+36"

    // Asia Pacific
    case japan = "+81"
    case southKorea = "+82"
    case india = "+91"
    case singapore = "+65"
    case hongKong = "+852"
    case philippines = "+63"
    case thailand = "+66"
    case malaysia = "+60"
    case indonesia = "+62"
    case australia = "+61"
    case newZealand = "+64"

    // Americas
    case mexico = "+52"
    case brazil = "+55"
    case argentina = "+54"
    case colombia = "+57"
    case chile = "+56"

    // Middle East & Africa
    case uae = "+971"
    case saudiArabia = "+966"
    case southAfrica = "+27"
    case israel = "+972"
    case turkey = "+90"
    case nigeria = "+234"
    case egypt = "+20"
}
```

### Key Properties

| Property | Description |
|----------|-------------|
| `flag` | Emoji flag for each country |
| `displayName` | Full country name |
| `dialingCode` | Actual dialing code (Canada returns "+1", not "+1CA") |
| `minDigits` / `maxDigits` | Valid phone number length for country |
| `placeholder` | Formatted placeholder (e.g., "(555) 123-4567" for US) |
| `static func fromLocale()` | Auto-detects country from `Locale.current.region?.identifier` |

### Phone Formatting

`formatPhoneNumberForCountry(_ number: String) -> String` applies country-specific formatting:

| Country | Format Example |
|---------|---------------|
| US/Canada | (555) 123-4567 |
| UK | 7911 123456 |
| India | 98765 43210 |
| Brazil | (11) 98765-4321 |
| Japan | 90-1234-5678 |
| Australia | 412 345 678 |
| Singapore/HK | 9123 4567 |

### International Display

`formatInternationalNumber()` combines `dialingCode` + formatted number for display:
- US: +1 (555) 123-4567
- UK: +44 7911 123456
- India: +91 98765 43210

---

## 6. Phone Verification Infrastructure

### Flow

```
User selects country → enters phone → taps "Send Code"
    ↓
PhoneVerificationService.sendVerificationCode(to: fullPhoneNumber)
    ↓
Supabase Edge Function: send-verification
    ↓
Twilio Verify API → SMS sent to user
    ↓
User enters 6-digit code → taps "Verify"
    ↓
PhoneVerificationService.verifyCode(code, for: fullPhoneNumber)
    ↓
Supabase Edge Function: verify-code
    ↓
Twilio Verify API → returns "approved" or "pending"
    ↓
Database RPC: confirm_phone_verification → marks phone_verified = true
```

### Configuration

**Environment Variables Required (Supabase):**
- `TWILIO_ACCOUNT_SID`
- `TWILIO_AUTH_TOKEN`
- `TWILIO_VERIFY_SERVICE_SID`

**Limits:**
- Max verification attempts: 3 (was 2, fixed)
- Resend countdown: 30 seconds
- Code length: 6 digits
- Auto-fill support: `.textContentType(.oneTimeCode)`

### Edge Function: send-verification

```
POST /send-verification
Body: { "phoneNumber": "+15551234567" }
→ Calls Twilio: POST https://verify.twilio.com/v2/Services/{sid}/Verifications
→ Logs to DB via RPC: start_phone_verification
→ Returns: { "success": true }
```

### Edge Function: verify-code

```
POST /verify-code
Body: { "phoneNumber": "+15551234567", "code": "123456" }
→ Calls Twilio: POST https://verify.twilio.com/v2/Services/{sid}/VerificationCheck
→ On success: RPC confirm_phone_verification
→ Returns: { "success": true, "status": "approved" }
```

---

## 7. Contact Sync Pipeline

### Flow

```
Step 13 (contacts): Request CNContactStore permission
    ↓
ContactsService.fetchContactInfo() [background thread]
    → Extract emails (lowercased)
    → Extract phone numbers (normalized to last 10 digits for US)
    ↓
ContactsService.syncContactsToDatabase()
    → RPC: sync_user_contacts with contact emails
    ↓
ContactsService.findMatchingUsersDirect()
    → Query user_profiles for matching emails
    → Query user_profiles for matching phones (3 strategies)
    → Populate suggestedFriends and peopleYouMayKnow
    ↓
Step 14 (addFriends): Display matched contacts for friend requests
    ↓
Step 16 (complete): ContactsService.notifyExistingUsersOfNewJoin()
    → Edge function: notify-contacts-user-joined
    → Finds existing users who have new user's contact info
    → Queues push notifications via push_notification_queue
    → Creates contact_joined_notifications records
```

### Phone Matching Strategies

1. **Last 10 digits** — strips country code, compares trailing digits
2. **Full number** — exact match with country code
3. **Country code prefix** — prepends +1 and matches

### Known Gaps

- Phone normalization always uses last 10 digits — may fail for countries with shorter numbers (Singapore: 8 digits, HK: 8 digits)
- No deduplication between email-matched and phone-matched users
- Contact sync only stores emails, not phone numbers to the cloud table

---

## 8. Unit Conversion System

### UnitSettingsManager

Located at `/home/user/Fit33/Fit33/UnitSettingsManager.swift`

**Locale-Aware Defaults:**
- US, Liberia, Myanmar → Imperial (lbs, ft/in, miles)
- All other countries → Metric (kg, cm, km)

**Supported Units:**

| Category | Imperial | Metric |
|----------|----------|--------|
| Weight | lbs | kg |
| Height | ft/in | cm |
| Distance | miles | km |

### Height Conversion

```swift
// Imperial to metric
func heightToCm(feet: Int, inches: Int) -> Double {
    return Double(feet * 12 + inches) * 2.54
}

// Metric to imperial
func cmToFeetInches(cm: Double) -> (feet: Int, inches: Int) {
    let totalInches = cm / 2.54
    let feet = Int(totalInches) / 12
    let inches = Int(totalInches) % 12
    return (feet, inches)
}
```

### Weight Conversion

```swift
// lbs to kg
func lbsToKg(_ lbs: Double) -> Double { lbs * 0.453592 }

// kg to lbs
func kgToLbs(_ kg: Double) -> Double { kg / 0.453592 }
```

### Height Input Parsing (Onboarding)

The `heightFeetInchesDigits` field accepts raw digits:
- "510" → 5 feet 10 inches
- "61" → 6 feet 1 inch

Display: `formatHeightDisplay()` → "5'10\"" (no zero-padding on inches, fixed)

### Birthday Parsing

Format determined by locale:
- US/Canada: MM/DD/YYYY
- Most other countries: DD/MM/YYYY

**Auto-formatting**: Slashes inserted automatically at positions 2 and 5

**Validation (fixed):**
```swift
// Calendar roundtrip to catch invalid dates
guard let date = Calendar.current.date(from: components),
      Calendar.current.component(.month, from: date) == month,
      Calendar.current.component(.day, from: date) == day,
      Calendar.current.component(.year, from: date) == year
else { return nil }

// Age range
calculatedAge >= 13 && calculatedAge <= 120
```

---

## 9. Responsive Layout & Screen Sizing

### OrientationManager Singleton

Located at `/home/user/Fit33/Fit33/OrientationManager.swift`

```swift
class OrientationManager: ObservableObject {
    static let shared = OrientationManager()

    @Published var screenWidth: CGFloat = 393   // iPhone 15 Pro default
    @Published var screenHeight: CGFloat = 852
    @Published var screenSize: CGSize
    @Published var isLandscape: Bool
    @Published var safeAreaInsets: EdgeInsets
}
```

**Update triggers:**
- `UIDevice.orientationDidChangeNotification` (50ms debounce)
- `UIApplication.didBecomeActiveNotification`
- `UIApplication.willEnterForegroundNotification`
- `UIScene.willEnterForegroundNotification`

**View extensions:**
- `.observeOrientation()` — force re-render on size change
- `.responsiveWidth(_ percentage: CGFloat)` — percentage-based sizing

### Safe Area Handling (Fixed)

Previously hardcoded `70pt` top padding. Now uses dynamic calculation:

```swift
let safeAreaTop = UIApplication.shared.connectedScenes
    .compactMap { $0 as? UIWindowScene }
    .flatMap { $0.windows }
    .first { $0.isKeyWindow }?
    .safeAreaInsets.top ?? 47
```

### iPhone Screen Widths Reference

| Device | Width | Notes |
|--------|-------|-------|
| iPhone SE (3rd gen) | 375pt | Smallest current iPhone |
| iPhone 8 | 375pt | Legacy but still common |
| iPhone 12/13 mini | 375pt | Compact |
| iPhone 14/15 | 390pt | Standard |
| iPhone 14/15 Pro | 393pt | Default in OrientationManager |
| iPhone 14/15 Plus | 428pt | Large |
| iPhone 14/15 Pro Max | 430pt | Largest |

### Verification Code Tiles (Fixed)

Previously: Fixed 50pt width per tile (6 tiles = 300pt + spacing, overflows on 375pt screens)

Now: GeometryReader-based responsive sizing:
```swift
GeometryReader { geometry in
    let tileWidth = (geometry.size.width - 5 * spacing) / 6
    // tiles use tileWidth instead of fixed 50pt
}
```

---

## 10. Text Field Styling Reference

### OnboardingTextField (Generic)

Located at `NewOnboardingView.swift` ~line 6470

```
┌─────────────────────────────────────────────┐
│  [icon]  [placeholder text]     [checkmark] │
└─────────────────────────────────────────────┘
```

| Property | Value |
|----------|-------|
| HStack spacing | 16 |
| Icon width | 26pt, system size 20 |
| Icon color (valid) | `[Color.blue, Color.cyan]` gradient |
| Icon color (invalid) | `[Color.gray.opacity(0.6), Color.gray.opacity(0.5)]` gradient |
| Padding | `.horizontal(22), .vertical(18)` |
| Corner radius | 20 |
| Background (dark) | `[Color(white: 0.14), Color(white: 0.10)]` |
| Background (light) | `[Color.white, Color(red: 0.97, green: 0.98, blue: 1.0)]` |
| Shadow (unfocused) | radius 8, offset (0, 3) |
| Shadow (focused) | radius 12, offset (0, 6) |
| Border (focused) | `[Color.blue.opacity(0.4), Color.cyan.opacity(0.3)]`, lineWidth 2 |
| Border (valid) | `[Color.blue.opacity(0.6), Color.cyan.opacity(0.5)]`, lineWidth 2 |
| Border (unfocused) | `[Color.gray.opacity(0.15), Color.clear]`, lineWidth 1 |
| Checkmark | "checkmark.circle.fill", `.ds_heading3`, `.blue` |
| Animation | `.easeInOut(duration: 0.25)` on isValid, `.easeInOut(duration: 0.2)` on focus |

### PasswordTextField (Generic)

Located at `NewOnboardingView.swift` ~line 6590

| Property | Value |
|----------|-------|
| Lock icon | size 18, width 24pt |
| Padding | `.horizontal(20), .vertical(Spacing.md)` |
| Eye toggle | `.plain` buttonStyle (preserves keyboard) |
| Match indicator | checkmark when valid + passwordsMatch |

### VerificationCodeBox

Located at `NewOnboardingView.swift` ~line 6701

| Property | Value |
|----------|-------|
| Frame | 48 x 56 (now responsive via GeometryReader) |
| Shadow (focused) | radius 8 |
| Shadow (unfocused) | radius 4 |
| Font | `.title2.bold()` |

### Text Input Configurations

| Field | Keyboard | Autocap | Autocorrect | Content Type | Focus Field |
|-------|----------|---------|-------------|--------------|-------------|
| Email | `.emailAddress` | `.never` | disabled | — | `.email` |
| Password | default | `.never` | disabled | — | `.password` |
| Confirm Password | default | `.never` | disabled | — | `.confirmPassword` |
| Name | default | `.words` | disabled | — | `.name` |
| Username | default | `.never` | disabled | — | `.username` |
| Phone | `.phonePad` | — | — | `.telephoneNumber` | `.phoneNumber` |
| Verification Code | `.numberPad` | — | — | `.oneTimeCode` | `.verificationCode` |
| Birthday | `.numberPad` | — | — | — | `.birthday` |
| Height | `.numberPad` | — | — | — | `.height` |
| Weight | `.numberPad` | — | — | — | `.weight` |

---

## 11. Keyboard & Focus Management

### KeyboardObserver

```swift
class KeyboardObserver: ObservableObject {
    @Published var keyboardHeight: CGFloat = 0
    // Observes UIResponder.keyboardWillShowNotification
    // 250ms debounce, animated with .easeOut(duration: 0.25)
}
```

### FocusedField Enum

```swift
enum FocusedField: Hashable {
    case email, password, confirmPassword, name
    case phoneNumber, verificationCode, username
    case birthday, height, weight
}
```

### Focus Management Patterns

```swift
// Programmatic focus with delay (allows view transition to complete)
DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
    self.focusedField = .verificationCode
}

// Auto-focus on step appearance
.onAppear {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        focusedField = .email
    }
}
```

---

## 12. Design System Tokens

### Typography

| Token | Size | Weight |
|-------|------|--------|
| `ds_displayLarge` | 42pt | bold |
| `ds_heading1` | 28pt | bold |
| `ds_heading2` | 22pt | bold |
| `ds_heading3` | 18pt | semibold |
| `ds_bodyLarge` | 17pt | regular |
| `ds_bodyMedium` | 15pt | regular |
| `ds_bodySmall` | 13pt | regular |
| `ds_labelLarge` | 15pt | semibold |
| `ds_labelMedium` | 13pt | semibold |
| `ds_caption` | 10pt | medium |
| `ds_stat` | 24pt | bold, rounded |

### Spacing (8px Base)

| Token | Value |
|-------|-------|
| `Spacing.xxxs` | 2px |
| `Spacing.xxs` | 4px |
| `Spacing.xs` | 8px |
| `Spacing.sm` | 12px |
| `Spacing.md` | 16px |
| `Spacing.lg` | 24px |
| `Spacing.xl` | 32px |
| `Spacing.xxl` | 48px |

### Corner Radius

| Token | Value |
|-------|-------|
| `CornerRadius.sm` | 8px |
| `CornerRadius.md` | 12px |
| `CornerRadius.lg` | 16px |
| `CornerRadius.xl` | 24px |
| `CornerRadius.pill` | 999px |

### Gradients

| Name | Colors | Usage |
|------|--------|-------|
| `ds_primaryAccent` | Blue → Purple | Buttons, headers |
| `ds_socialAccent` | Cyan → Blue | Friends, challenges |
| `ds_successAccent` | Green shades | Completions |
| `ds_energyAccent` | Orange → Red | Calories, activities |

### Haptics

```swift
HapticManager.lightTap()    // Light impact
HapticManager.tap()         // Medium impact
HapticManager.heavyTap()    // Heavy impact
HapticManager.success()     // Success notification
HapticManager.warning()     // Warning notification
HapticManager.error()       // Error notification
```

---

## 13. Onboarding Components Library

Located at `/home/user/Fit33/Fit33/OnboardingComponents.swift`

### OnboardingCardBackgroundStyle

5-layer card design:
1. Colored shadow glow (accent with opacity)
2. Depth shadow (black with opacity)
3. Main gradient fill (white or dark gradient)
4. Inner highlight (top edge glow)
5. Accent border (colored gradient stroke)

### Reusable Components

| Component | Purpose | Key Props |
|-----------|---------|-----------|
| `OnboardingSelectionCard` | Icon card for multi-select | icon, title, subtitle, isSelected, accentColor |
| `OnboardingLargeCard` | Emoji card (130pt height) | emoji, title, subtitle, isSelected |
| `OnboardingWideCard` | Full-width horizontal card | icon, title, subtitle, isSelected |
| `OnboardingNavBar` | Back/Continue buttons | showBack, canContinue, onBack, onContinue |
| `OnboardingProgressBar` | Linear progress (4pt) | currentStep, totalSteps |
| `OnboardingQuestionHeader` | Step title + subtitle | question, subtitle |
| `OnboardingStepContainer` | Universal step wrapper | navBar + progress + header + content |
| `OnboardingBackground` | Gradient backdrop | ignoresSafeArea |

### Selection Card Animation

```swift
.scaleEffect(isSelected ? 1.03 : 1.0)
.animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
// UISelectionFeedbackGenerator haptic on tap
```

---

## 14. Auth & OAuth Flow

### Email/Password Signup

```
1. User enters email + password + confirm password
2. Validation: email format, password 8+ chars with 1 uppercase + 1 number
3. Supabase.auth.signUp(email:, password:)
4. On success → proceed to username step
```

### OAuth (Apple/Google)

```
1. User taps "Sign in with Apple" or "Sign in with Google"
2. Supabase handles OAuth flow
3. On success → pre-fill name from OAuth profile
4. Skip to username step (auth step completed)
```

### Returning User Detection

```
1. If user has existing session → check hasCompletedOnboarding
2. If onboarding incomplete → resume at last completed step
3. If onboarding complete → skip to main app
```

### Password Validation Rules

```swift
func validatePassword(_ password: String) -> (isValid: Bool, errors: [String]) {
    // Minimum 8 characters
    // At least 1 uppercase letter
    // At least 1 number
    // Returns array of specific error messages
}
```

---

## 15. Test Suite

Located at `/home/user/Fit33/Fit33/OnboardingTestHelper.swift` (DEBUG only)

### Test User Profiles (8 Total)

| Profile | Country | Units | Gender | Age | Special |
|---------|---------|-------|--------|-----|---------|
| US Standard | US | Imperial | Male | 28 | Baseline |
| UK User | UK | Metric | Female | 35 | DD/MM/YYYY birthday |
| Australian | Australia | Metric | Male | 42 | AU phone format |
| Indian | India | Metric | Female | 25 | +91 phone |
| Canadian | Canada | Imperial | Male | 31 | +1CA code |
| Brazilian | Brazil | Metric | Female | 29 | +55 phone |
| Edge Case 1 | US | Imperial | Other | 18 | Gender: Other |
| Edge Case 2 | UK | Metric | nil | 65 | No gender selected |

### Offline Validation Tests (50+)

Run with: `OnboardingValidationTests.runAll()`

| Test Group | Count | What It Validates |
|------------|-------|-------------------|
| Birthday Edge Cases | 11 | Leap year, Feb 30, Apr 31, future dates, age boundaries |
| Height Conversion | 8 | Imperial ↔ metric roundtrip accuracy |
| Weight Conversion | 6 | lbs ↔ kg roundtrip accuracy |
| Password Validation | 8 | Length, uppercase, number, edge cases |
| Username Validation | 11 | Length, characters, spaces, special chars |

### E2E Tests

Run with: `await OnboardingTestHelper.shared.runComprehensiveTestSuite()`

For each test profile:
1. Sign up with random email/password/username
2. Verify authentication state in Supabase
3. Set username and verify in database
4. Update profile with all onboarding data
5. Read back from database and verify field-by-field integrity
6. Verify unit conversions stored correctly
7. Verify phone number stored with correct country code
8. Clean up test user

### Country Code Tests

`testAllCountryCodes()` validates all 45 countries have:
- Non-empty flag emoji
- Non-empty display name
- Valid dialing code (starts with "+")
- minDigits > 0
- maxDigits >= minDigits
- Non-empty placeholder

---

## 16. Remaining Gaps & Recommendations

### High Priority

| Gap | Description | Recommendation |
|-----|-------------|----------------|
| **Dead code** | Both `basicsStep` and `basicsStepContent` exist | Remove the unused duplicate |
| **File size** | NewOnboardingView.swift is 8,615 lines | Consider splitting into per-step files |
| **No progress save** | App close during onboarding loses all progress | Save progress to UserDefaults/Core Data per step |
| **Contact phone normalization** | Always uses last-10-digits strategy | Add country-specific normalization for non-US numbers |
| **PhoneVerificationSheet mismatch** | Sheet has 16 countries, onboarding has 45 | Sync both to use the same 45-country CountryCode enum |

### Medium Priority

| Gap | Description | Recommendation |
|-----|-------------|----------------|
| **No email verification** | Signup doesn't verify email ownership | Add email verification step or link |
| **No password recovery** | No forgot-password flow during onboarding | Add "Forgot password?" link on auth step |
| **Birthday locale edge case** | No explicit toggle for date format | Auto-detect but allow user to switch MM/DD ↔ DD/MM |
| **Accessibility** | No VoiceOver labels on custom components | Add `.accessibilityLabel()` to cards, tiles, buttons |
| **Onboarding analytics** | OnboardingSessionManager logs but doesn't track drop-off | Add per-step completion events to identify drop-off points |

### Low Priority

| Gap | Description | Recommendation |
|-----|-------------|----------------|
| **No landscape support** | Onboarding doesn't adapt to landscape | Lock to portrait or add landscape layouts |
| **No iPad optimization** | Fixed sizing may look sparse on iPad | Add size class-based layouts |
| **No dark mode preview testing** | Components tested in one mode | Add light/dark mode preview variants |
| **Step count** | 17 steps is lengthy | Consider condensing: merge body+basics, merge equipment+location |

---

## 17. Validation Checklist

Use this checklist to verify the onboarding flow is complete and correct.

### Auth Step
- [ ] Email validation rejects invalid formats
- [ ] Password requires 8+ chars, 1 uppercase, 1 number
- [ ] Confirm password must match
- [ ] Apple OAuth signs in and pre-fills name
- [ ] Google OAuth signs in and pre-fills name
- [ ] Error messages display for all failure cases
- [ ] Keyboard auto-focuses email field on appear

### Username Step
- [ ] 3-20 character limit enforced
- [ ] Only alphanumeric + underscore allowed
- [ ] Async availability check works
- [ ] Duplicate username shows error
- [ ] Username saved to Supabase

### Phone Verification Step
- [ ] Country code defaults to device locale
- [ ] All 45 countries appear in picker
- [ ] Phone formatting applies per country
- [ ] SMS sends via Twilio
- [ ] 6-digit code entry works
- [ ] Auto-fill from SMS works (.oneTimeCode)
- [ ] Max 3 attempts enforced
- [ ] Resend countdown works (30s)
- [ ] Timer cleanup on dismiss

### Basics Step
- [ ] Name field auto-capitalizes words
- [ ] Birthday auto-formats with slashes
- [ ] MM/DD/YYYY for US, DD/MM/YYYY for others
- [ ] Invalid dates rejected (Feb 30, Apr 31)
- [ ] Age 13-120 enforced
- [ ] Gender is optional
- [ ] Can continue without gender

### Body Step
- [ ] Height input in ft/in (imperial) or cm (metric)
- [ ] Weight input in lbs (imperial) or kg (metric)
- [ ] Unit toggle works
- [ ] Conversions accurate (roundtrip tested)
- [ ] Height display doesn't zero-pad inches

### Selection Steps (Goal, Experience, Strength, Location, Equipment, Limitations, Schedule)
- [ ] Cards display correctly on all screen sizes
- [ ] Selection haptic feedback fires
- [ ] Multi-select works where applicable
- [ ] Can skip limitations (optional)
- [ ] Spring animation on selection

### Photo Step
- [ ] Camera permission request
- [ ] Photo library permission request
- [ ] Can skip without photo
- [ ] Photo uploads to storage

### Contacts & Friends Steps
- [ ] Contact permission request
- [ ] Graceful handling of permission denied
- [ ] Contact sync runs on background thread
- [ ] Matched users display correctly
- [ ] Friend requests send correctly
- [ ] Can skip both steps

### Confirmation & Complete
- [ ] All selections displayed for review
- [ ] Profile saves to Core Data
- [ ] Profile syncs to Supabase
- [ ] hasCompletedOnboarding set to true
- [ ] Transition to main app works
- [ ] notify-contacts-user-joined fires

### Cross-Cutting
- [ ] Works on iPhone SE (375pt width)
- [ ] Works on iPhone 15 Pro Max (430pt width)
- [ ] Safe area padding is dynamic
- [ ] Verification tiles don't overflow
- [ ] All text fields have correct keyboard type
- [ ] Focus management works across all steps
- [ ] Back button works on all steps
- [ ] Progress bar updates correctly
- [ ] No timer memory leaks
- [ ] Dark mode renders correctly
- [ ] Light mode renders correctly

---

## Appendix: Running the Tests

### Offline Validation (No Network Required)

```swift
#if DEBUG
// Run all 50+ unit tests
let results = OnboardingValidationTests.runAll()
print("Passed: \(results.filter { $0.passed }.count)")
print("Failed: \(results.filter { !$0.passed }.count)")
for result in results.filter({ !$0.passed }) {
    print("FAIL: \(result.name) - \(result.message)")
}
#endif
```

### Full E2E Suite (Requires Network + Supabase)

```swift
#if DEBUG
Task {
    let results = await OnboardingTestHelper.shared.runComprehensiveTestSuite()
    for result in results {
        print("\(result.profileName): \(result.overallSuccess ? "PASS" : "FAIL")")
        if !result.errors.isEmpty {
            result.errors.forEach { print("  Error: \($0)") }
        }
    }
}
#endif
```

### Country Code Validation

```swift
#if DEBUG
let countryResults = OnboardingTestHelper.shared.testAllCountryCodes()
print("All 45 countries valid: \(countryResults.allSatisfy { $0.passed })")
#endif
```
