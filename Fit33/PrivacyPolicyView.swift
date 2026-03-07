//
//  PrivacyPolicyView.swift
//  GoFit
//
//  Created on 12/22/24.
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
                    Text("Last Updated: December 22, 2024")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 8)
                
                // Introduction
                section(title: "Introduction") {
                    Text("Fit33 (\"we\", \"our\", or \"us\") is committed to protecting your privacy. This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you use our mobile application.")
                    Text("By using Fit33, you agree to the collection and use of information in accordance with this policy.")
                }
                
                // Information We Collect
                section(title: "Information We Collect") {
                    subsection(title: "Personal Information") {
                        bulletPoint("Name and email address (for account creation)")
                        bulletPoint("Date of birth and age")
                        bulletPoint("Gender")
                        bulletPoint("Height and weight measurements")
                        bulletPoint("Fitness goals and experience level")
                    }
                    
                    subsection(title: "Health & Fitness Data") {
                        bulletPoint("Workout history and exercise performance")
                        bulletPoint("Step count and daily activity (via Apple HealthKit)")
                        bulletPoint("Body measurements and weight tracking")
                        bulletPoint("Meal logs and nutritional intake")
                        bulletPoint("Water/hydration intake")
                        bulletPoint("Physical limitations and injury information")
                    }
                    
                    subsection(title: "Device & Usage Information") {
                        bulletPoint("Device type, model, and operating system")
                        bulletPoint("App usage patterns and session data")
                        bulletPoint("Timezone and locale settings")
                        bulletPoint("Unit preferences (imperial/metric)")
                    }
                }
                
                // How We Use Your Information
                section(title: "How We Use Your Information") {
                    bulletPoint("To create and manage your account")
                    bulletPoint("To personalize workout recommendations based on your goals, equipment, and limitations")
                    bulletPoint("To track your fitness progress over time")
                    bulletPoint("To calculate nutritional needs (BMR, TDEE, macros)")
                    bulletPoint("To sync your data across devices")
                    bulletPoint("To send workout reminders and notifications (with your permission)")
                    bulletPoint("To improve our app and develop new features")
                    bulletPoint("To display relevant advertisements")
                }
                
                // Third-Party Services
                section(title: "Third-Party Services") {
                    subsection(title: "Supabase") {
                        Text("We use Supabase for secure cloud storage and authentication. Your data is stored on Supabase servers with encryption at rest and in transit.")
                    }
                    
                    subsection(title: "Apple HealthKit") {
                        Text("With your permission, we read step count data and write workout data to Apple Health. We never sell or share your HealthKit data with third parties for advertising or marketing purposes.")
                    }
                    
                    subsection(title: "USDA FoodData Central") {
                        Text("We use the USDA API to provide nutritional information for foods you log. No personal data is shared with the USDA.")
                    }
                    
                    subsection(title: "Open Food Facts") {
                        Text("For barcode scanning, we may query the Open Food Facts database to retrieve product information.")
                    }
                    
                    subsection(title: "Google AdMob") {
                        Text("We display advertisements through Google AdMob. Google may collect device identifiers and usage data to serve personalized ads. You can opt out of personalized advertising in your device settings.")
                    }
                    
                    subsection(title: "Apple & Google Sign-In") {
                        Text("If you choose to sign in with Apple or Google, we receive only the information you authorize (typically name and email).")
                    }
                }
                
                // Data Storage & Security
                section(title: "Data Storage & Security") {
                    Text("Your data is stored both locally on your device (using Core Data) and in the cloud (using Supabase). We implement industry-standard security measures including:")
                    bulletPoint("Encryption in transit (TLS/SSL)")
                    bulletPoint("Encryption at rest")
                    bulletPoint("Secure authentication tokens")
                    bulletPoint("Row-level security policies")
                    Text("However, no method of transmission over the internet is 100% secure, and we cannot guarantee absolute security.")
                }
                
                // Data Retention
                section(title: "Data Retention") {
                    Text("We retain your personal data for as long as your account is active. You can request deletion of your data at any time by contacting us or using the account deletion feature in the app.")
                    Text("Some anonymized, aggregated data may be retained for analytics purposes.")
                }
                
                // Your Rights
                section(title: "Your Rights") {
                    Text("You have the right to:")
                    bulletPoint("Access your personal data")
                    bulletPoint("Export your data (via the Download Data feature)")
                    bulletPoint("Correct inaccurate information")
                    bulletPoint("Delete your account and associated data")
                    bulletPoint("Opt out of marketing communications")
                    bulletPoint("Withdraw consent for HealthKit access")
                }
                
                // Children's Privacy
                section(title: "Children's Privacy") {
                    Text("Fit33 is not intended for children under 13 years of age. We do not knowingly collect personal information from children under 13. If we discover that a child under 13 has provided us with personal information, we will delete it immediately.")
                }
                
                // Changes to This Policy
                section(title: "Changes to This Policy") {
                    Text("We may update this Privacy Policy from time to time. We will notify you of any changes by posting the new Privacy Policy in the app and updating the \"Last Updated\" date.")
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

