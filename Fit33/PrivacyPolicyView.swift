//
//  PrivacyPolicyView.swift
//  Fit33
//
//  Created on 12/22/24.
//  Last comprehensive rewrite: May 2, 2026 — full audit of every data
//  use-case currently in the app (HealthKit, Strava, Fitbit, WHOOP, Oura,
//  InBody, Bluetooth equipment, running/GPS, contacts, camera OCR, QR
//  codes, progress photos, challenge messaging + block/report, content
//  moderation via OpenAI, AdMob + ATT, StoreKit, phone verification via
//  Twilio/Supabase, push notifications, bug reports + dSYM, and the
//  Privacy Settings surface). If a NEW data-collecting feature ships,
//  update this file in the same PR per `SUPPORT_AGENT.md`.
//

import SwiftUI

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            // Animated orb background (consistent with Profile/Stats screens)
            AnimatedOrbBackground.stats(colorScheme: colorScheme)
                .ignoresSafeArea(.all, edges: .all)
            
            ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Privacy Policy")
                        .font(.largeTitle.bold())
                    Text("Last Updated: May 2, 2026")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 8)
                
                // Introduction
                section(title: "Introduction") {
                    Text("Fit33 (\"we\", \"our\", or \"us\") is committed to protecting your privacy. This Privacy Policy explains what we collect, how we use it, who we share it with, and the controls you have. It covers our iOS app, Apple Watch app, and companion services.")
                    Text("By creating an account or using Fit33, you agree to this policy. If you do not agree, please do not use the app.")
                }
                
                // Information We Collect
                section(title: "Information We Collect") {
                    subsection(title: "Account & Identity") {
                        bulletPoint("Email address (for account creation and sign-in)")
                        bulletPoint("Display name and username")
                        bulletPoint("Profile photo (optional; stored in Supabase Storage)")
                        bulletPoint("Phone number (optional; verified via SMS for account recovery and trust)")
                        bulletPoint("Apple ID / Google account identifier (if you sign in with Apple or Google)")
                        bulletPoint("Date of birth and age")
                        bulletPoint("Gender")
                    }
                    
                    subsection(title: "Health & Fitness Profile") {
                        bulletPoint("Height, weight, and body-composition entries")
                        bulletPoint("Fitness goals (build muscle, lose weight, improve strength, endurance, etc.)")
                        bulletPoint("Experience level and available days per week")
                        bulletPoint("Available equipment and training environment")
                        bulletPoint("Physical limitations, injuries, and exercise contraindications you tell us about")
                    }
                    
                    subsection(title: "Workout & Exercise Data") {
                        bulletPoint("Workout history, logs, sets, reps, weights, and durations")
                        bulletPoint("Active and completed programs (7/14/21/30-day plans)")
                        bulletPoint("Auto-generated workouts, custom workouts you build, and exercise swaps")
                        bulletPoint("Exercise preferences, favorites, and personal records (PRs)")
                        bulletPoint("Rest-day / recovery-day usage")
                        bulletPoint("Quality scores derived from workout intelligence (e.g., form/tempo telemetry when you use workout replay)")
                    }
                    
                    subsection(title: "Cardio & Running Data") {
                        bulletPoint("Outdoor-run GPS traces (route, distance, pace, elevation) — only while a run is active, with your permission")
                        bulletPoint("Indoor cardio sessions (treadmill, bike, rower), including equipment data received over Bluetooth")
                        bulletPoint("Cardio goals, pace targets, and session snapshots used for crash-recovery of an in-progress run")
                    }
                    
                    subsection(title: "Nutrition & Meal Data") {
                        bulletPoint("Meal logs, food entries, and custom foods")
                        bulletPoint("Calorie and macronutrient tracking (protein, carbohydrates, fat, fiber, sugar, sodium)")
                        bulletPoint("Favorite foods and search history")
                        bulletPoint("Saved recipes, recipes you import from a URL, and shopping-list items")
                        bulletPoint("Water / hydration intake")
                        bulletPoint("Photos you take of nutrition-facts labels for on-device OCR (images are processed on-device and are NOT uploaded)")
                    }
                    
                    subsection(title: "Progress, Gamification & Achievements") {
                        bulletPoint("Workout streaks, streak shields, and active-day history")
                        bulletPoint("Experience points (XP) and level")
                        bulletPoint("Daily quest completion (3 per day, resets at local midnight)")
                        bulletPoint("Weekly league placement and leaderboard rank")
                        bulletPoint("Achievements, milestones, and personal records")
                        bulletPoint("Progress photos (front / side / back) you choose to capture, stored on-device and in your private cloud storage")
                    }
                    
                    subsection(title: "Social & Community Data") {
                        bulletPoint("Friends list, friend requests, and connections")
                        bulletPoint("1-on-1, group, and community challenges you create or join")
                        bulletPoint("Messages sent inside private challenge chats")
                        bulletPoint("Shared workouts and reactions")
                        bulletPoint("Blocked users and reports you submit")
                        bulletPoint("Privacy Settings choices (profile-photo visibility, friend-activity visibility, weekly-league opt-out, contact-sync opt-out, search visibility, active-status visibility)")
                    }
                    
                    subsection(title: "Health Integrations (With Your Permission)") {
                        Text("You can connect optional third-party health services. We only receive data you explicitly authorize in each service's OAuth consent screen or iOS permission dialog.")
                        bulletPoint("Apple HealthKit: steps, active energy, workouts, heart rate, weight, body composition, and workout types you permit")
                        bulletPoint("Strava: your running and cycling activities (route, distance, pace, HR, kudos metadata), delivered via Strava webhooks when you publish a new activity")
                        bulletPoint("Fitbit: steps, heart rate, sleep stages, and basic activity summaries")
                        bulletPoint("WHOOP: recovery, HRV, strain, sleep stages, SpO2, skin temperature, and workouts")
                        bulletPoint("Oura: sleep, readiness, HRV, and activity summaries")
                        bulletPoint("InBody: body-composition scans you choose to import")
                        bulletPoint("Bluetooth gym equipment (treadmill, bike, rower): live sensor data (speed, distance, cadence, watts, HR) while you are actively using the equipment")
                    }
                    
                    subsection(title: "Device, Diagnostics & Usage Information") {
                        bulletPoint("Device type, model, OS version, and app version")
                        bulletPoint("Unique user identifier (server-generated UUID, not the device advertising ID)")
                        bulletPoint("Advertising identifier (IDFA) — only if you grant App Tracking Transparency consent")
                        bulletPoint("App usage patterns, features opened, and screen telemetry (for bug-intelligence triage)")
                        bulletPoint("Network type (e.g., cellular/Wi-Fi) and basic performance metrics")
                        bulletPoint("Timezone, locale, and unit preferences (imperial/metric)")
                        bulletPoint("Crash reports, including symbolicated stack traces uploaded via dSYM for debugging")
                        bulletPoint("Bug reports you submit manually (description, screenshot, device info)")
                    }
                    
                    subsection(title: "Camera, Photos, Contacts & Location") {
                        bulletPoint("Camera: used to scan QR codes (to add friends) and to capture nutrition-facts labels for on-device OCR. The image is NOT uploaded.")
                        bulletPoint("Photo Library: used only when you select a profile picture or progress photo")
                        bulletPoint("Contacts: used only when you opt in to contact-based friend discovery; hashed identifiers are sent to Supabase to find matches and are not stored in readable form on our servers")
                        bulletPoint("Location: used only during active outdoor-run tracking (background location permission enables continued tracking while the screen is locked); we do NOT track location outside of an active cardio session")
                    }
                    
                    subsection(title: "Push Notifications & Silent Push") {
                        bulletPoint("Apple Push Notification (APNs) device token")
                        bulletPoint("Notification preferences and opt-ins per category (workout reminders, hydration, quests, streaks, challenges, readiness, social, marketing)")
                        bulletPoint("We use silent pushes to coalesce background sync for challenges, quests, and wearable data")
                    }
                    
                    subsection(title: "Purchases & Subscriptions") {
                        bulletPoint("In-app purchases processed by Apple StoreKit (receipts, transaction IDs, entitlement status)")
                        bulletPoint("We do NOT collect or store your credit-card information — Apple handles billing")
                    }
                    
                    subsection(title: "Content Moderation") {
                        bulletPoint("Text you send in challenge chats and content you post in social surfaces may be screened for harmful content using the OpenAI Moderation API")
                        bulletPoint("Only the text of the message is sent to OpenAI; your identity, email, or profile are not attached")
                        bulletPoint("Flagged content may be reviewed by our moderation team")
                    }
                }
                
                // How We Use Your Information
                section(title: "How We Use Your Information") {
                    bulletPoint("Create and manage your account, authenticate you across devices, and recover access when needed")
                    bulletPoint("Personalize workouts, programs, daily quests, meal recommendations, and readiness scoring based on your goals, equipment, limitations, and wearable signals")
                    bulletPoint("Track your fitness progress, streaks, XP, achievements, and weekly-league placement")
                    bulletPoint("Calculate nutritional needs (BMR, TDEE, macros) and merge calorie data across devices without double-counting")
                    bulletPoint("Record your outdoor runs and indoor cardio sessions, and award LP / credit for cardio regardless of source (Fit33 native, Strava, HealthKit, or Watch)")
                    bulletPoint("Enable social features (friends, challenges, shared workouts, reactions, leaderboards)")
                    bulletPoint("Send push notifications and smart reminders you have opted into")
                    bulletPoint("Screen user-generated text for harmful content (harassment, hate speech, self-harm) via the OpenAI Moderation API")
                    bulletPoint("Detect and investigate crashes, bugs, and performance regressions, and improve app stability")
                    bulletPoint("Operate the free tier with Google AdMob advertising (subject to your ATT choice)")
                    bulletPoint("Comply with legal obligations and App Store requirements")
                }
                
                // Permissions You Control
                section(title: "Permissions You Control") {
                    Text("Each of the following is opt-in. You can grant, revoke, or change any of them at any time in iOS Settings → Privacy & Security, or in the relevant Fit33 Settings screen.")
                    bulletPoint("Apple HealthKit (steps, workouts, heart rate, body comp)")
                    bulletPoint("Location Services (outdoor-run GPS, including background)")
                    bulletPoint("Camera (QR codes, nutrition-label OCR, profile photo)")
                    bulletPoint("Photo Library (profile photo, progress photos)")
                    bulletPoint("Contacts (friend discovery)")
                    bulletPoint("Bluetooth (gym equipment, heart-rate monitors)")
                    bulletPoint("Apple Music / Media Library (in-app playback controls)")
                    bulletPoint("Push Notifications (APNs)")
                    bulletPoint("App Tracking Transparency (AdMob personalized advertising)")
                    bulletPoint("Strava, Fitbit, WHOOP, Oura, InBody (each connected individually in Settings)")
                }
                
                // Third-Party Services
                section(title: "Third-Party Services") {
                    subsection(title: "Supabase (Database, Authentication, Storage, Realtime)") {
                        Text("We use Supabase for our backend, including authenticated database rows protected by row-level security, edge functions, file storage for profile and progress photos, and realtime subscriptions for challenge chat and leaderboards. Data is encrypted in transit (TLS) and at rest.")
                    }
                    
                    subsection(title: "Apple HealthKit, Apple Watch & Sign in with Apple") {
                        Text("With your permission, we read activity data (steps, active energy, heart rate, workouts, weight, body composition) from Apple Health and write workout and cardio sessions back. The Fit33 Apple Watch app records workouts directly on your wrist and syncs them with your account. We never sell or share HealthKit data with third parties for advertising or marketing, and we never use it outside the Fit33 experience. Sign in with Apple shares only the identifiers you authorize (typically name and email, optionally a private relay address).")
                    }
                    
                    subsection(title: "Google Sign-In") {
                        Text("If you choose Continue with Google, we receive only the basic profile information Google returns (email, name, profile picture URL).")
                    }
                    
                    subsection(title: "Strava") {
                        Text("If you connect Strava, we request OAuth access to your activities. Strava sends new activities to us via webhooks. You can revoke access at any time in Strava (Settings → My Apps) or inside Fit33.")
                    }
                    
                    subsection(title: "Fitbit, WHOOP & Oura") {
                        Text("If you connect Fitbit, WHOOP, or Oura, we use OAuth to pull the specific data categories each service exposes (steps, heart rate, sleep, recovery, HRV, strain, SpO2, skin temperature, workouts). You can revoke access at any time in each provider's dashboard or in Fit33 Settings.")
                    }
                    
                    subsection(title: "InBody") {
                        Text("If you connect InBody, we import body-composition scans you authorize.")
                    }
                    
                    subsection(title: "USDA FoodData Central") {
                        Text("Food search is powered by the USDA FoodData Central API. No personal information is shared with the USDA — only the food name you search.")
                    }
                    
                    subsection(title: "Open Food Facts") {
                        Text("When you scan a nutrition-facts label with the camera, the image is processed on-device using Apple's Vision framework for OCR. We may additionally query the Open Food Facts database by barcode or product name to enrich the entry. The image itself is never uploaded.")
                    }
                    
                    subsection(title: "Spoonacular (Recipes)") {
                        Text("Our recipe browser and URL-based recipe import use the Spoonacular API. We do not send any personal information — only the search query or URL you want to import.")
                    }
                    
                    subsection(title: "OpenAI Moderation API") {
                        Text("User-generated text (e.g., challenge chat messages and public posts) may be sent to OpenAI's Moderation endpoint to check for harmful content before it is delivered or displayed. Only the text is sent — no identifiers, profile data, or metadata are attached.")
                    }
                    
                    subsection(title: "Twilio (SMS Phone Verification)") {
                        Text("If you verify your phone number, Supabase delivers a one-time passcode over SMS via Twilio. We retain only the verification state, never the SMS body.")
                    }
                    
                    subsection(title: "Apple StoreKit") {
                        Text("Premium subscriptions and one-time purchases are processed by Apple's App Store. Apple provides us with a receipt we validate to unlock entitlements. We never see your payment method or full billing address.")
                    }
                    
                    subsection(title: "Google AdMob") {
                        Text("The free tier of Fit33 displays native and interstitial advertisements via Google AdMob. AdMob may use your device's advertising identifier (IDFA) — but only if you grant App Tracking Transparency consent. If you decline ATT, you will still see ads, but they will not be personalized based on the IDFA. We never sell your personal data.")
                    }
                    
                    subsection(title: "Apple Push Notifications (APNs)") {
                        Text("We register your device token with Apple to deliver push notifications you have opted into (workout reminders, hydration, quests, streak, challenges, readiness, social updates). You can change these in iOS Settings or Fit33 → Settings → Notifications.")
                    }
                }
                
                // Data Storage & Security
                section(title: "Data Storage & Security") {
                    Text("Your data is stored both locally on your device (Core Data, Keychain for auth tokens) and in the cloud via Supabase. We implement:")
                    bulletPoint("TLS/SSL encryption in transit")
                    bulletPoint("Encryption at rest (Supabase, Apple Keychain)")
                    bulletPoint("Row-level security policies so users can only read their own private data")
                    bulletPoint("Server-side enforcement of Privacy Settings so a modified client cannot bypass them")
                    bulletPoint("OAuth token rotation and secure storage in the iOS Keychain")
                    bulletPoint("OAuth audit logging for health-integration token issuance and revocation")
                    Text("No method of transmission or storage is 100% secure, and we cannot guarantee absolute security.")
                }
                
                // Data Retention
                section(title: "Data Retention") {
                    bulletPoint("Active accounts: we retain your data for as long as your account is active")
                    bulletPoint("Deleted accounts: all personal data is permanently removed from our servers within 30 days of deletion")
                    bulletPoint("Bug reports & crash reports: retained up to 90 days for troubleshooting")
                    bulletPoint("Anonymized, aggregated analytics (e.g., feature-usage counts) may be retained longer")
                }
                
                // Your Rights & Controls
                section(title: "Your Rights & Controls") {
                    Text("You have the right to:")
                    bulletPoint("Access your personal data in the app")
                    bulletPoint("Export your data via Settings → Download Data")
                    bulletPoint("Correct inaccurate information in Profile and Settings")
                    bulletPoint("Delete your account and associated data via Profile → Delete Account")
                    bulletPoint("Revoke any health-integration at any time (Apple Health, Strava, Fitbit, WHOOP, Oura, InBody)")
                    bulletPoint("Opt out of personalized advertising via iOS Settings → Privacy & Security → Tracking")
                    bulletPoint("Opt out of individual push notification categories")
                    bulletPoint("Block other users and report harmful content")
                    bulletPoint("Withdraw consent for any iOS permission at any time")
                }
                
                // Privacy Settings (in-app)
                section(title: "Privacy Settings (In-App)") {
                    Text("Settings → Privacy & Security lets you control what others can see about you. Changes are synced and enforced server-side:")
                    bulletPoint("Hide Profile Photo")
                    bulletPoint("Hide Friend Activity")
                    bulletPoint("Hide from Weekly League")
                    bulletPoint("Hide from Contact Sync")
                    bulletPoint("Hide from Search")
                    bulletPoint("Hide Active Status")
                    bulletPoint("Manage Blocked Users")
                }
                
                // Block, Report & Content Moderation
                section(title: "Block, Report & Moderation") {
                    Text("Long-press a message in a private challenge chat, or a post in the friend-activity feed, to Report & Block the user. Blocked users cannot message you, see your activity, or compete with you. Reports are reviewed by our moderation team and may result in account action.")
                }
                
                // Children's Privacy
                section(title: "Children's Privacy") {
                    Text("Fit33 is not intended for children under 13 years of age. We do not knowingly collect personal information from children under 13. If we discover that a child under 13 has provided us with personal information, we will delete it immediately. In the EEA/UK, the minimum age is 16 unless local law specifies a lower age.")
                }
                
                // International Data Transfers
                section(title: "International Data Transfers") {
                    Text("Your information may be transferred to and processed in the United States and other countries where our service providers operate. These countries may have data-protection laws different from your country of residence. By using Fit33, you consent to the transfer.")
                }
                
                // California (CCPA)
                section(title: "California Privacy Rights (CCPA/CPRA)") {
                    Text("If you are a California resident, you have additional rights, including:")
                    bulletPoint("Right to Know the categories and specific pieces of personal information we collect")
                    bulletPoint("Right to Delete your personal information")
                    bulletPoint("Right to Correct inaccurate personal information")
                    bulletPoint("Right to Opt-Out of sale / sharing of personal information (we do NOT sell your data)")
                    bulletPoint("Right to Non-Discrimination for exercising your privacy rights")
                }
                
                // European (GDPR)
                section(title: "European Privacy Rights (GDPR/UK GDPR)") {
                    Text("If you are in the EEA, UK, or Switzerland, you have additional rights:")
                    bulletPoint("Right of access, rectification, erasure, restriction, and portability")
                    bulletPoint("Right to object to processing")
                    bulletPoint("Right to lodge a complaint with a supervisory authority")
                    Text("Our legal bases for processing are: (a) performance of a contract (providing the app), (b) your consent (marketing emails, health-integration connections, ATT), and (c) legitimate interests (improving the app, preventing abuse).")
                }
                
                // App Store Privacy Details
                section(title: "App Store Privacy Details") {
                    Text("A summary of our data practices for Apple's App Store nutrition label:")
                    subsection(title: "Data Used to Track You") {
                        bulletPoint("Device ID (advertising identifier) — only with ATT consent, for Google AdMob")
                    }
                    subsection(title: "Data Linked to You") {
                        bulletPoint("Contact Info (email, phone)")
                        bulletPoint("Health & Fitness (workouts, cardio, nutrition, wearable data)")
                        bulletPoint("User Content (profile photo, progress photos, challenge messages)")
                        bulletPoint("Identifiers (User ID)")
                        bulletPoint("Usage Data")
                    }
                    subsection(title: "Data Not Linked to You") {
                        bulletPoint("Diagnostics (crash data, performance data)")
                    }
                }
                
                // Changes
                section(title: "Changes to This Policy") {
                    Text("We may update this Privacy Policy from time to time. We will notify you of material changes by posting the new policy in the app, updating the \"Last Updated\" date, and sending an in-app notification for significant changes.")
                }
                
                // Contact Us
                section(title: "Contact Us") {
                    Text("If you have questions about this Privacy Policy or our data practices, please contact us at:")
                    Text("support@fit33app.com")
                        .foregroundColor(.blue)
                }
                
                Spacer(minLength: 40)
            }
            .padding()
        }
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Helper Views
    
    private func section(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.bold())
            content()
        }
    }
    
    private func subsection(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            content()
        }
        .padding(.leading, 8)
    }
    
    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundColor(.secondary)
            Text(text)
                .foregroundColor(.primary)
        }
    }
}

#Preview {
    NavigationStack {
        PrivacyPolicyView()
    }
}
