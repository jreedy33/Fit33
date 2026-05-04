import SwiftUI

// MARK: - Widget Settings Sheet
struct WidgetSettingsSheet: View {
    @Binding var showWeightTracker: Bool
    @Binding var showHydration: Bool
    @Binding var showMacros: Bool
    @Binding var showChallenge: Bool
    @Binding var showRecommended: Bool
    @Binding var showWhoop: Bool
    @Binding var showOura: Bool
    @Binding var showStrava: Bool
    @Binding var showCardio: Bool
    @Binding var showOlympian: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var premiumManager = PremiumManager.shared
    @State private var showingPremiumUpgrade = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedOrbBackground.home(colorScheme: colorScheme)
                
            ScrollView {
                VStack(spacing: 0) {
                    // Subtitle
                    if premiumManager.isPremiumUser {
                        Text("Customize your dashboard with quick-access widgets")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Spacing.lg)
                            .padding(.bottom, 24)
                            .lineLimit(2)
                    } else {
                        VStack(spacing: 8) {
                            Text("Customize your dashboard with quick-access widgets")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            
                            HStack(spacing: 4) {
                                Image(systemName: "crown.fill")
                                    .font(.ds_labelSmall)
                                    .foregroundColor(.yellow)
                                Text("Premium Required")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding(.horizontal, Spacing.lg)
                        .padding(.bottom, 24)
                    }
                    
                    // Widget options
                    VStack(spacing: 12) {
                        widgetOptionRow(
                            icon: "chart.pie.fill",
                            title: "Quick Macros",
                            subtitle: "Today's nutrition at a glance",
                            gradientColors: [Color.teal, Color.mint],
                            isSelected: $showMacros
                        )
                        
                        widgetOptionRow(
                            icon: "scalemass.fill",
                            title: "Weight Tracker",
                            subtitle: "Track your weight progress",
                            gradientColors: [Color.orange, Color.yellow],
                            isSelected: $showWeightTracker
                        )
                        
                        widgetOptionRow(
                            icon: "drop.fill",
                            title: "Hydration Tracker",
                            subtitle: "Track your daily water intake",
                            gradientColors: [Color.cyan, Color.blue],
                            isSelected: $showHydration
                        )
                        
                        widgetOptionRow(
                            icon: "waveform.path.ecg",
                            title: "WHOOP Recovery",
                            subtitle: "Recovery score, HRV & strain",
                            gradientColors: [Color.green, Color.cyan],
                            isSelected: $showWhoop
                        )
                        
                        // Oura Readiness widget — temporarily hidden (Sprint 2026-05-02).
                        // Binding kept on the sheet so DashboardView's call site
                        // still compiles; we'll restore the row when Oura is back.
                        // widgetOptionRow(
                        //     icon: "circle.circle",
                        //     title: "Oura Readiness",
                        //     subtitle: "Readiness score, HRV & sleep",
                        //     gradientColors: [Color.teal, Color.cyan],
                        //     isSelected: $showOura
                        // )

                        widgetOptionRow(
                            icon: "figure.run",
                            title: "Strava Activity",
                            subtitle: "Latest run / ride splits & effort",
                            gradientColors: [Color.stravaOrange, Color.orange],
                            isSelected: $showStrava
                        )

                        widgetOptionRow(
                            icon: "flame.fill",
                            title: "Cardio Streak",
                            subtitle: "Streak status & one-tap walk start",
                            gradientColors: [Color.green, Color.orange],
                            isSelected: $showCardio
                        )

                        // 2026-05-04 — Path to 33 (annual Olympian track).
                        // 100% free, no premium gate per the free-achievability
                        // contract. Toggle ON by default.
                        olympianWidgetOptionRow(
                            isSelected: $showOlympian
                        )

                        // Challenge widget - show for all users, but locked for free users
                        challengeWidgetOptionRow(
                            isSelected: $showChallenge
                        )
                        
                        // Recommended For You widget - premium can hide, free users see it locked
                        recommendedWidgetOptionRow(
                            isSelected: $showRecommended
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                    
                    // Done button
                    Button(action: {
                        HapticManager.tap()
                        dismiss()
                    }) {
                        Text("Done")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.md)
                            .background(
                                LinearGradient(
                                    colors: [.blue, .cyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(14)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
                .padding(.top, 16)
            }
            } // ZStack
            .navigationTitle("Add Widgets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showingPremiumUpgrade) {
            PremiumUpgradeView(triggeringFeature: .homescreenWidgets)
        }
    }
    
    @ViewBuilder
    private func widgetOptionRow(icon: String, title: String, subtitle: String, gradientColors: [Color], isSelected: Binding<Bool>) -> some View {
        Button(action: {
            // Check if user is premium
            if premiumManager.isPremiumUser {
                HapticManager.selectionChanged()
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSelected.wrappedValue.toggle()
                }
            } else {
                // Show premium upgrade for free users
                HapticManager.tap()
                showingPremiumUpgrade = true
            }
        }) {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: icon)
                        .font(.ds_heading3)
                        .foregroundColor(.white)
                }
                
                // Text
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        // PRO badge for free users
                        if !premiumManager.isPremiumUser {
                            HStack(spacing: 3) {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 9, weight: .bold))
                                Text("PRO")
                                    .font(.system(size: 9, weight: .bold))
                                    .tracking(0.5)
                            }
                            .foregroundColor(.black.opacity(0.8))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(red: 1.0, green: 0.84, blue: 0), Color(red: 1.0, green: 0.75, blue: 0.3)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            )
                        }
                    }
                    
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Show lock icon for free users or checkbox for premium users
                if !premiumManager.isPremiumUser {
                    Image(systemName: "lock.fill")
                        .font(.ds_heading3)
                        .foregroundColor(.secondary)
                } else {
                    // Checkbox for premium users
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isSelected.wrappedValue ? LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing) : LinearGradient(colors: [Color.clear], startPoint: .top, endPoint: .bottom))
                            .frame(width: 26, height: 26)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isSelected.wrappedValue ? Color.clear : Color.secondary.opacity(0.4), lineWidth: 2)
                            )
                        
                        if isSelected.wrappedValue {
                            Image(systemName: "checkmark")
                                .font(.ds_bodySmall).fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                    }
                }
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.97))
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .stroke(
                        // Show lock color for free users, or selected color for premium users
                        !premiumManager.isPremiumUser
                            ? LinearGradient(colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : (isSelected.wrappedValue
                                ? LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [Color.clear], startPoint: .top, endPoint: .bottom)),
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .opacity(!premiumManager.isPremiumUser ? 0.8 : 1.0)
    }
    
    // Challenge widget option - shown to all users, locked for free users
    @ViewBuilder
    private func challengeWidgetOptionRow(isSelected: Binding<Bool>) -> some View {
        Button(action: {
            if premiumManager.isPremiumUser {
                HapticManager.selectionChanged()
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSelected.wrappedValue.toggle()
                }
            } else {
                // Show premium upgrade for free users
                HapticManager.tap()
                showingPremiumUpgrade = true
            }
        }) {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.orange, Color.red],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    
                    Text("🏆")
                        .font(.ds_heading3)
                    
                    // Lock overlay for free users
                    if !premiumManager.isPremiumUser {
                        Image(systemName: "lock.fill")
                            .font(.ds_heading3)
                            .foregroundColor(.white)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.5))
                                    .frame(width: 44, height: 44)
                            )
                    }
                }
                
                // Text
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Challenge a Friend")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        // Premium badge for free users
                        if !premiumManager.isPremiumUser {
                            HStack(spacing: 3) {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.yellow)
                                Text("PRO")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.yellow)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.yellow.opacity(0.15))
                            )
                        }
                    }
                    
                    Text(premiumManager.isPremiumUser ? "Hide this widget" : "Unlock to hide this widget")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Toggle indicator or lock
                if premiumManager.isPremiumUser {
                    ZStack {
                        Circle()
                            .fill(isSelected.wrappedValue ? Color.green : Color.gray.opacity(0.3))
                            .frame(width: 28, height: 28)
                        
                        if isSelected.wrappedValue {
                            Image(systemName: "checkmark")
                                .font(.ds_bodySmall).fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                    }
                } else {
                    // Always ON indicator for free users (can't toggle)
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.5))
                            .frame(width: 28, height: 28)
                        
                        Image(systemName: "checkmark")
                            .font(.ds_bodySmall).fontWeight(.bold)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.97))
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .stroke(
                        !premiumManager.isPremiumUser
                            ? LinearGradient(colors: [Color.orange.opacity(0.3), Color.red.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : (isSelected.wrappedValue
                                ? LinearGradient(colors: [Color.orange, Color.red], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [Color.clear], startPoint: .top, endPoint: .bottom)),
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .opacity(!premiumManager.isPremiumUser ? 0.85 : 1.0)
    }
    
    // MARK: - Recommended For You Widget Option Row
    private func recommendedWidgetOptionRow(isSelected: Binding<Bool>) -> some View {
        Button(action: {
            if premiumManager.isPremiumUser {
                HapticManager.selectionChanged()
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSelected.wrappedValue.toggle()
                }
            } else {
                // Show premium upgrade for free users
                HapticManager.tap()
                showingPremiumUpgrade = true
            }
        }) {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.green, Color.teal],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "star.fill")
                        .font(.ds_heading3)
                        .foregroundColor(.white)
                    
                    // Lock overlay for free users
                    if !premiumManager.isPremiumUser {
                        Image(systemName: "lock.fill")
                            .font(.ds_heading3)
                            .foregroundColor(.white)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.5))
                                    .frame(width: 44, height: 44)
                            )
                    }
                }
                
                // Text
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Recommended For You")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        // Premium badge for free users
                        if !premiumManager.isPremiumUser {
                            HStack(spacing: 3) {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.yellow)
                                Text("PRO")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.yellow)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.yellow.opacity(0.15))
                            )
                        }
                    }
                    
                    Text(premiumManager.isPremiumUser ? "Hide this widget" : "Unlock to hide this widget")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Toggle indicator or lock
                if premiumManager.isPremiumUser {
                    ZStack {
                        Circle()
                            .fill(isSelected.wrappedValue ? Color.green : Color.gray.opacity(0.3))
                            .frame(width: 28, height: 28)
                        
                        if isSelected.wrappedValue {
                            Image(systemName: "checkmark")
                                .font(.ds_bodySmall).fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                    }
                } else {
                    // Always ON indicator for free users (can't toggle)
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.5))
                            .frame(width: 28, height: 28)
                        
                        Image(systemName: "checkmark")
                            .font(.ds_bodySmall).fontWeight(.bold)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.97))
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .stroke(
                        !premiumManager.isPremiumUser
                            ? LinearGradient(colors: [Color.green.opacity(0.3), Color.teal.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : (isSelected.wrappedValue
                                ? LinearGradient(colors: [Color.green, Color.teal], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [Color.clear], startPoint: .top, endPoint: .bottom)),
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .opacity(!premiumManager.isPremiumUser ? 0.85 : 1.0)
    }

    // MARK: - Olympian Path Widget (FREE — no premium gate)
    //
    // 2026-05-04 — Per the Path to 33 free-achievability contract, this widget
    // is fully free to view AND toggle. No premium upsell or PRO badge — it is
    // an explicit "free for everyone" surface (Monetization invariant 31:
    // explicit-label rule).
    @ViewBuilder
    private func olympianWidgetOptionRow(isSelected: Binding<Bool>) -> some View {
        Button(action: {
            HapticManager.selectionChanged()
            withAnimation(.easeInOut(duration: 0.2)) {
                isSelected.wrappedValue.toggle()
            }
        }) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    OlympianPathBluePalette.color(for: 2),
                                    OlympianPathBluePalette.color(for: 5)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)

                    Image(systemName: "crown.fill")
                        .font(.ds_heading3)
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Path to Olympian")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)

                        Text("FREE")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.5)
                            .foregroundColor(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(Color.green.opacity(0.15))
                            )
                    }

                    Text("Track 33 goals on your personal 365-day Path (not calendar-year only).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            isSelected.wrappedValue
                                ? LinearGradient(
                                    colors: [
                                        OlympianPathBluePalette.color(for: 2),
                                        OlympianPathBluePalette.color(for: 5)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : LinearGradient(colors: [Color.clear], startPoint: .top, endPoint: .bottom)
                        )
                        .frame(width: 26, height: 26)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isSelected.wrappedValue ? Color.clear : Color.secondary.opacity(0.4), lineWidth: 2)
                        )

                    if isSelected.wrappedValue {
                        Image(systemName: "checkmark")
                            .font(.ds_bodySmall).fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.97))
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .stroke(
                        isSelected.wrappedValue
                            ? LinearGradient(
                                colors: [
                                    Color(red: 1.00, green: 0.84, blue: 0.00),
                                    Color(red: 0.95, green: 0.50, blue: 0.30)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(colors: [Color.clear], startPoint: .top, endPoint: .bottom),
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
