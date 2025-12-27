//
//  TermsConditionsView.swift
//  GoFit
//
//  Created on 12/22/24.
//

import SwiftUI

struct TermsConditionsView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Terms & Conditions")
                        .font(.largeTitle.bold())
                    Text("Last Updated: December 22, 2024")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 8)
                
                // Agreement
                section(title: "Agreement to Terms") {
                    Text("By downloading, installing, or using Fit33 (\"the App\"), you agree to be bound by these Terms and Conditions. If you do not agree with any part of these terms, you must not use the App.")
                }
                
                // Description of Service
                section(title: "Description of Service") {
                    Text("Fit33 is a fitness and wellness application that provides:")
                    bulletPoint("Personalized workout generation and tracking")
                    bulletPoint("Exercise library with video demonstrations")
                    bulletPoint("Meal and nutrition logging")
                    bulletPoint("Hydration tracking")
                    bulletPoint("Step counting and activity monitoring")
                    bulletPoint("Progress tracking and statistics")
                    bulletPoint("Fitness program recommendations")
                }
                
                // Account Registration
                section(title: "Account Registration") {
                    Text("To use certain features of the App, you must create an account. You agree to:")
                    bulletPoint("Provide accurate and complete information")
                    bulletPoint("Maintain the security of your account credentials")
                    bulletPoint("Notify us immediately of any unauthorized access")
                    bulletPoint("Accept responsibility for all activities under your account")
                    Text("You must be at least 13 years old to create an account and use the App.")
                }
                
                // Health Disclaimer
                section(title: "Health & Fitness Disclaimer") {
                    Text("IMPORTANT: Fit33 is designed for general fitness information and tracking purposes only. It is NOT a substitute for professional medical advice, diagnosis, or treatment.")
                        .fontWeight(.semibold)
                    
                    Text("Before starting any exercise program, you should:")
                    bulletPoint("Consult with a qualified healthcare provider")
                    bulletPoint("Get medical clearance, especially if you have pre-existing conditions")
                    bulletPoint("Understand your physical limitations")
                    
                    Text("You acknowledge that:")
                    bulletPoint("Exercise carries inherent risks of injury")
                    bulletPoint("You voluntarily assume all risks associated with using the App")
                    bulletPoint("Workout recommendations are generated algorithmically and may not be suitable for everyone")
                    bulletPoint("Nutritional information is estimated and should not replace professional dietary advice")
                    bulletPoint("The App's injury/limitation filtering is a safety aid, not a medical recommendation")
                }
                
                // User Conduct
                section(title: "User Conduct") {
                    Text("You agree not to:")
                    bulletPoint("Use the App for any unlawful purpose")
                    bulletPoint("Attempt to gain unauthorized access to our systems")
                    bulletPoint("Interfere with or disrupt the App's functionality")
                    bulletPoint("Upload malicious content or code")
                    bulletPoint("Impersonate others or provide false information")
                    bulletPoint("Use the App to harm or exploit others")
                    bulletPoint("Reverse engineer or decompile the App")
                }
                
                // Intellectual Property
                section(title: "Intellectual Property") {
                    Text("The App and its content, including but not limited to:")
                    bulletPoint("Exercise videos and demonstrations")
                    bulletPoint("Workout algorithms and recommendations")
                    bulletPoint("User interface design and graphics")
                    bulletPoint("Text, logos, and branding")
                    
                    Text("are owned by or licensed to Fit33 and are protected by copyright, trademark, and other intellectual property laws. You may not reproduce, distribute, or create derivative works without our express written permission.")
                }
                
                // User Content
                section(title: "User Content") {
                    Text("You retain ownership of any content you create within the App (custom workouts, meal logs, etc.). By using the App, you grant us a non-exclusive license to store, process, and display this content to provide our services.")
                    Text("You are solely responsible for the accuracy of any information you input.")
                }
                
                // Third-Party Services
                section(title: "Third-Party Services") {
                    Text("The App integrates with third-party services including:")
                    bulletPoint("Apple HealthKit - for health data sync")
                    bulletPoint("Supabase - for cloud storage")
                    bulletPoint("Google AdMob - for advertisements")
                    bulletPoint("USDA FoodData Central - for nutrition data")
                    bulletPoint("Open Food Facts - for barcode scanning")
                    
                    Text("Your use of these services is subject to their respective terms and privacy policies. We are not responsible for third-party service availability or content.")
                }
                
                // Advertisements
                section(title: "Advertisements") {
                    Text("The App displays advertisements through Google AdMob. You acknowledge that:")
                    bulletPoint("Ads may be personalized based on your device data")
                    bulletPoint("We are not responsible for third-party ad content")
                    bulletPoint("You can adjust ad personalization in your device settings")
                }
                
                // Subscriptions & Payments
                section(title: "Subscriptions & Payments") {
                    Text("Certain features may require a subscription. If applicable:")
                    bulletPoint("Payments are processed through Apple's App Store")
                    bulletPoint("Subscriptions auto-renew unless cancelled")
                    bulletPoint("Refunds are subject to Apple's refund policy")
                    bulletPoint("Prices may change with notice")
                }
                
                // Disclaimers
                section(title: "Disclaimers") {
                    Text("THE APP IS PROVIDED \"AS IS\" WITHOUT WARRANTIES OF ANY KIND. WE DISCLAIM ALL WARRANTIES, EXPRESS OR IMPLIED, INCLUDING:")
                        .fontWeight(.semibold)
                    bulletPoint("Merchantability and fitness for a particular purpose")
                    bulletPoint("Accuracy or reliability of workout recommendations")
                    bulletPoint("Uninterrupted or error-free operation")
                    bulletPoint("Results from using the App")
                }
                
                // Limitation of Liability
                section(title: "Limitation of Liability") {
                    Text("TO THE MAXIMUM EXTENT PERMITTED BY LAW, FIT33 SHALL NOT BE LIABLE FOR:")
                        .fontWeight(.semibold)
                    bulletPoint("Any indirect, incidental, or consequential damages")
                    bulletPoint("Personal injury or health issues arising from exercise")
                    bulletPoint("Loss of data or unauthorized access")
                    bulletPoint("Any damages exceeding the amount you paid for the App")
                }
                
                // Indemnification
                section(title: "Indemnification") {
                    Text("You agree to indemnify and hold harmless Fit33, its officers, directors, and employees from any claims, damages, or expenses arising from your use of the App or violation of these Terms.")
                }
                
                // Termination
                section(title: "Termination") {
                    Text("We reserve the right to terminate or suspend your account at any time for violations of these Terms or for any other reason at our discretion.")
                    Text("Upon termination, your right to use the App ceases immediately. You may request deletion of your data in accordance with our Privacy Policy.")
                }
                
                // Governing Law
                section(title: "Governing Law") {
                    Text("These Terms shall be governed by and construed in accordance with the laws of the United States, without regard to conflict of law principles.")
                }
                
                // Changes to Terms
                section(title: "Changes to Terms") {
                    Text("We may modify these Terms at any time. Continued use of the App after changes constitutes acceptance of the modified Terms. We will notify you of significant changes through the App.")
                }
                
                // Severability
                section(title: "Severability") {
                    Text("If any provision of these Terms is found to be unenforceable, the remaining provisions will continue in full force and effect.")
                }
                
                // Contact
                section(title: "Contact Information") {
                    Text("For questions about these Terms, please contact us at:")
                    Text("support@fit33app.com")
                        .foregroundColor(.blue)
                }
                
                Spacer(minLength: 40)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Terms & Conditions")
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
        TermsConditionsView()
    }
}

