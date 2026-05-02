# Privacy Policy for Fit33

**Last Updated: May 2, 2026**

## Introduction

Fit33 ("we," "our," or "us") is committed to protecting your privacy. This Privacy Policy explains what we collect, how we use it, who we share it with, and the controls you have. It covers our iOS app, Apple Watch companion app, and our cloud services.

By using Fit33, you agree to the collection and use of information described in this policy. If you do not agree, please do not use the app.

---

## Information We Collect

### Account & Identity
- Email address
- Display name and username
- Profile photo (optional; stored in Supabase Storage)
- Phone number (optional; verified via SMS for account recovery and trust)
- Apple ID / Google account identifier (if you sign in with Apple or Google)
- Date of birth and age
- Gender

### Health & Fitness Profile
- Height, weight, and body-composition entries
- Fitness goals (build muscle, lose weight, improve strength, endurance, etc.)
- Experience level and available days per week
- Available equipment and training environment
- Physical limitations, injuries, and exercise contraindications you tell us about

### Workout & Exercise Data
- Workout history, logs, sets, reps, weights, durations
- Active and completed programs (7 / 14 / 21 / 30-day plans)
- Auto-generated workouts, custom workouts you build, and exercise swaps
- Exercise preferences, favorites, and personal records (PRs)
- Rest-day / recovery-day usage
- Quality scores derived from workout intelligence (form/tempo telemetry when using workout replay)

### Cardio & Running Data
- Outdoor-run GPS traces (route, distance, pace, elevation) — only while a run is active, with your permission
- Indoor cardio sessions (treadmill, bike, rower), including equipment telemetry received over Bluetooth
- Cardio goals, pace targets, and session snapshots used for crash-recovery of an in-progress run

### Nutrition & Meal Data
- Meal logs, food entries, and custom foods you create
- Calorie and macronutrient tracking (protein, carbohydrates, fat, fiber, sugar, sodium)
- Favorite foods and search history
- Saved recipes, imported recipes (via URL), and shopping-list items
- Water / hydration intake
- Photos of nutrition-facts labels used for **on-device OCR** — the image is processed locally with Apple's Vision framework and is **not uploaded**

> Note: Fit33 does not currently support true grocery-barcode scanning. Our scanner reads the nutrition-facts panel via OCR.

### Progress, Gamification & Achievements
- Workout streaks and streak shields
- Experience points (XP) and level
- Daily quest completion (3 per day, resets at local midnight)
- Weekly league placement and leaderboard rank (Monday 00:15 UTC placement)
- Achievements, milestones, and personal records
- Progress photos (front / side / back) you choose to capture, stored in your private Supabase Storage bucket

### Social & Community Data
- Friends list, friend requests, and connections
- 1-on-1, group, and community challenges you create or join
- Messages sent inside private challenge chats
- Shared workouts and reactions
- Blocked users and reports you submit
- Privacy Settings choices (profile-photo visibility, friend-activity visibility, weekly-league opt-out, contact-sync opt-out, search visibility, active-status visibility)

### Health Integrations (With Your Explicit Permission)

We only receive data you authorize in each provider's consent screen or the iOS permission dialog. You can revoke access at any time.

| Integration | Data we request | Where to revoke |
|-------------|-----------------|-----------------|
| Apple HealthKit | Steps, active energy, workouts, heart rate, weight, body composition | iOS → Settings → Privacy & Security → Health → Fit33 |
| Strava | Running / cycling activities (route, distance, pace, HR) via OAuth + webhooks | Strava → Settings → My Apps |
| Fitbit | Steps, heart rate, sleep stages, activity summaries | Fitbit dashboard OR Fit33 → Settings → Fitbit |
| WHOOP | Recovery, HRV, strain, sleep stages, SpO2, skin temperature, workouts | WHOOP dashboard OR Fit33 → Settings → WHOOP |
| Oura | Sleep, readiness, HRV, activity summaries | Oura dashboard OR Fit33 → Settings → Oura |
| InBody | Body-composition scans you import | Fit33 → Settings → InBody |
| Bluetooth gym equipment | Live sensor data (speed, distance, cadence, watts, HR) during an active session | Session ends when you stop the workout |

### Device, Diagnostics & Usage Information
- Device type, model, OS version, and app version
- Unique user identifier (server-generated UUID, not the device advertising ID)
- Advertising identifier (IDFA) — **only if** you grant App Tracking Transparency (ATT) consent
- App usage patterns, features opened, and screen telemetry (for bug-intelligence triage)
- Network type (cellular/Wi-Fi) and basic performance metrics
- Timezone, locale, and unit preferences
- Crash reports, including symbolicated stack traces uploaded via dSYM for debugging
- Bug reports you submit manually (description, screenshot, device info)

### Camera, Photos, Contacts & Location
- **Camera:** QR-code scanning (add friends) and nutrition-label OCR. The image is **not** uploaded.
- **Photo Library:** only when you pick a profile or progress photo.
- **Contacts:** only when you opt in to contact-based friend discovery. Hashed identifiers are sent to Supabase to find matches and are not stored in readable form on our servers.
- **Location:** only during an active outdoor run. Background-location permission keeps tracking working when the screen is locked. We do **not** track location outside of an active cardio session.

### Push Notifications & Silent Push
- Apple Push Notification (APNs) device token
- Per-category notification preferences (workouts, hydration, quests, streaks, challenges, readiness, social, marketing)
- Silent pushes coalesce background sync for challenges, quests, and wearable data

### Purchases & Subscriptions
- In-app purchases processed by Apple StoreKit (receipts, transaction IDs, entitlement status)
- We do **not** collect or store your credit-card information — Apple handles billing

### Content Moderation
- Text you send in challenge chats and content you post in social surfaces may be screened for harmful content using the **OpenAI Moderation API**
- **Only the text** is sent to OpenAI. No identifiers, email, or profile data are attached
- Flagged content may be reviewed by our moderation team

---

## How We Use Your Information

- **Provide and maintain the App** — create/manage your account, sync your data across devices
- **Personalize your experience** — workouts, programs, daily quests, meal recommendations, and readiness scoring based on your goals, equipment, limitations, and wearable signals
- **Track your progress** — streaks, XP, achievements, leaderboards, and body-composition trends
- **Calculate nutritional needs** (BMR, TDEE, macros) and merge calorie data across devices without double-counting
- **Record cardio sessions** and award LP / credit uniformly regardless of source (Fit33 native, Strava, HealthKit, Apple Watch)
- **Enable social features** — friends, challenges, shared workouts, reactions, leaderboards
- **Send push notifications** you have opted into
- **Moderate content** for harassment, hate speech, and self-harm signals
- **Detect and investigate** crashes, bugs, and performance regressions
- **Operate the free tier** with Google AdMob advertising (subject to your ATT choice)
- **Comply with legal obligations** and App Store requirements

---

## How We Share Your Information

We **do not sell your personal information**. We share data only in the following circumstances:

### Service Providers

| Provider | Purpose | Data shared | Privacy policy |
|----------|---------|-------------|----------------|
| **Supabase** | Database, authentication, file storage, realtime | Account info, workout data, meal data, profile, chat messages | https://supabase.com/privacy |
| **Apple** (App Store, HealthKit, StoreKit, APNs, Sign in with Apple) | App distribution, health data, billing, notifications | As permitted by each API | https://www.apple.com/legal/privacy/ |
| **Google** (AdMob, Sign-In) | Free-tier advertising; Google sign-in | Device identifiers (with ATT), basic Google profile | https://policies.google.com/privacy |
| **Strava / Fitbit / WHOOP / Oura / InBody** | Optional health data integrations | Only the OAuth scopes you grant | Each provider's privacy policy |
| **USDA FoodData Central** | Food nutrition lookup | Food name you search (no personal data) | https://fdc.nal.usda.gov/ |
| **Open Food Facts** | Enriched product lookup | Barcode / product name (no personal data) | https://world.openfoodfacts.org/terms-of-use |
| **Spoonacular** | Recipe browsing and import | Search query or URL you import (no personal data) | https://spoonacular.com/food-api/terms |
| **OpenAI (Moderation API)** | Text moderation for chat and public posts | Message text only (no identifiers) | https://openai.com/policies/privacy-policy |
| **Twilio** (via Supabase Auth) | SMS phone-number verification | Phone number and OTP | https://www.twilio.com/legal/privacy |

### Legal Requirements
We may disclose your information if required by law, subpoena, or valid government request, or to protect our rights, property, or users.

### Business Transfers
If we are involved in a merger, acquisition, or sale of assets, your information may be transferred as part of that transaction. We will notify you before your data becomes subject to a different privacy policy.

---

## Data Storage and Security

### Cloud Storage
Your data is stored using Supabase:
- TLS/SSL encryption in transit
- Encryption at rest
- Row-level security (RLS) so users can only read their own private data
- Server-side enforcement of your Privacy Settings (a modified client cannot bypass them)
- OAuth token rotation, stored in the iOS Keychain
- Audit logging for health-integration token issuance and revocation

### Local Storage
Some data is cached locally on your device (Core Data) for offline access and performance:
- Recent workout, cardio, and meal data
- Exercise library (6,000+ exercises)
- User preferences
- Auth tokens (iOS Keychain)
- In-progress cardio snapshots (for crash-recovery within a 4-hour window)

### Data Retention
- **Active accounts:** retained as long as the account is active
- **Deleted accounts:** permanently removed from our servers within 30 days
- **Bug / crash reports:** retained up to 90 days for troubleshooting
- **Anonymized aggregate analytics:** may be retained longer

---

## Your Privacy Rights

### Access and Portability
- View your data in the app
- Export your data via **Settings → Download Data**

### Correction
Update your profile information, workout data, and preferences any time in Profile and Settings.

### Deletion
Delete your account and all associated data:
1. Open Fit33
2. Go to **Profile → Delete Account**
3. Confirm — deletion is irreversible

### Revoke Health-Integration Access
Apple Health: iOS → Settings → Privacy & Security → Health → Fit33
Strava / Fitbit / WHOOP / Oura / InBody: Fit33 → Settings → [Integration name], or the provider's own dashboard

### Opt Out of Personalized Advertising
- iOS → Settings → Privacy & Security → Tracking → disable "Allow Apps to Request to Track"
- iOS → Settings → Privacy & Security → Apple Advertising → disable "Personalized Ads"

### Manage Notifications
- iOS → Settings → Notifications → Fit33
- Fit33 → Settings → Notifications (per-category toggles)

### Block and Report Users
- Long-press a message in a private challenge chat OR a post in the friend-activity feed
- Tap **Report & Block**
- Manage blocked users in **Settings → Privacy & Security → Blocked Users**

### In-App Privacy Controls (Settings → Privacy & Security)
- Hide Profile Photo
- Hide Friend Activity
- Hide from Weekly League
- Hide from Contact Sync
- Hide from Search
- Hide Active Status
- Manage Blocked Users

---

## Children's Privacy

Fit33 is not intended for children under 13. We do not knowingly collect personal information from children under 13. If you are a parent or guardian and believe your child has provided us with personal information, please contact us and we will delete it. In the EEA/UK, the minimum age is 16 unless local law specifies a lower age.

---

## International Data Transfers

Your information may be transferred to and processed in the United States and other countries where our service providers operate. By using Fit33, you consent to the transfer.

---

## California Privacy Rights (CCPA / CPRA)

If you are a California resident, you have additional rights:
- **Right to Know** what we collect and why
- **Right to Delete** your personal information
- **Right to Correct** inaccurate information
- **Right to Opt-Out** of the "sale" or "sharing" of personal information (we do **not** sell your data)
- **Right to Non-Discrimination** for exercising your privacy rights

To exercise these rights, contact us using the details below.

---

## European Privacy Rights (GDPR / UK GDPR)

If you are in the EEA, UK, or Switzerland, you have the following rights:
- **Right of Access** — request a copy of your personal data
- **Right to Rectification** — correct inaccurate data
- **Right to Erasure** — request deletion ("right to be forgotten")
- **Right to Restrict Processing**
- **Right to Data Portability**
- **Right to Object** to processing
- **Right to lodge a complaint** with a supervisory authority

Our **legal bases** for processing:
- **Contract** — providing the app functionality
- **Consent** — marketing communications, health-integration OAuth connections, App Tracking Transparency
- **Legitimate Interests** — improving the app, preventing abuse and fraud

---

## Changes to This Privacy Policy

We may update this Privacy Policy from time to time. We will notify you of changes by:
- Posting the new Privacy Policy in the app
- Updating the "Last Updated" date above
- Sending an in-app notification for significant changes

We encourage you to review this Privacy Policy periodically.

---

## App Store Privacy Details

In accordance with Apple's App Privacy requirements, here is a summary of our data practices:

### Data Used to Track You
- Identifiers (Device ID / IDFA) — **only with ATT consent**, for Google AdMob

### Data Linked to You
- **Contact Info** — email, phone number
- **Health & Fitness** — workouts, cardio, nutrition, wearable data
- **User Content** — profile photo, progress photos, challenge messages
- **Identifiers** — User ID
- **Usage Data**

### Data Not Linked to You
- **Diagnostics** — crash data, performance data

---

## Contact Us

If you have questions or concerns about this Privacy Policy or our data practices:

**Email:** support@fit33app.com

---

**Fit33** — Your fitness journey, done right.
