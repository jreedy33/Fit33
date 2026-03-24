import SwiftUI

// MARK: - Streak Info Sheet
struct StreakInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    @StateObject private var premiumManager = PremiumManager.shared
    @State private var showingEditStreak = false
    @State private var showingPremiumUpgrade = false
    
    private var currentStreak: Int {
        Int(userManager.currentUser?.currentStreak ?? 0)
    }
    
    private var longestStreak: Int {
        Int(userManager.currentUser?.longestStreak ?? 0)
    }
    
    private var daysPerWeek: Int {
        max(2, Int(userManager.currentUser?.availableDays ?? 4))
    }
    
    private var maxRestDays: Int {
        userManager.getMaxAllowedRestDays()
    }
    
    private var streakStatus: (isAtRisk: Bool, daysRemaining: Int, message: String) {
        userManager.getStreakStatus()
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Big flame with current streak
                    streakHeroSection

                    // Real-time streak status (at risk / safe)
                    statusSection

                    // How it works
                    howItWorksSection

                    // Your schedule
                    yourScheduleSection

                    // Tips
                    tipsSection
                }
                .padding()
            }
            .background(
                LinearGradient(
                    colors: colorScheme == .dark 
                        ? [Color(white: 0.08), Color(white: 0.05)]
                        : [Color(white: 0.98), Color(white: 0.95)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Your Streak")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingEditStreak) {
                EditStreakSheet(currentStreak: currentStreak)
                    .environmentObject(userManager)
                    .presentationDetents([.height(320)])
                    .presentationDragIndicator(.visible)
            }
            .fullScreenCover(isPresented: $showingPremiumUpgrade) {
                PremiumUpgradeView(triggeringFeature: .streakEdit)
            }
        }
    }
    
    // MARK: - Streak Hero
    private var streakHeroSection: some View {
        VStack(spacing: 16) {
            ZStack {
                // Glow effect
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.orange.opacity(0.3), Color.clear],
                            center: .center,
                            startRadius: 40,
                            endRadius: 100
                        )
                    )
                    .frame(width: 200, height: 200)
                
                // Solid fill behind the flame to fill the hole
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.orange, Color.red.opacity(0.9)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 68, height: 68)
                    .offset(y: 10)
                
                // Flame
                Image(systemName: "flame.fill")
                    .font(.system(size: 100))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange, .red],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: .orange.opacity(0.5), radius: 20)
                
                // Streak number
                Text("\(currentStreak)")
                    .font(.system(size: 48, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.3), radius: 2)
                    .offset(y: 10)
            }
            
            Text(currentStreak == 1 ? "Workout Streak" : "Workout Streak")
                .font(.title2)
                .fontWeight(.bold)
            
            // Edit Streak button (Premium feature)
            Button(action: {
                HapticManager.tap()
                if premiumManager.isPremiumUser {
                    showingEditStreak = true
                } else {
                    showingPremiumUpgrade = true
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.ds_bodySmall)
                    Text("Edit Streak")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if !premiumManager.isPremiumUser {
                        Image(systemName: "crown.fill")
                            .font(.ds_caption)
                            .foregroundColor(.yellow)
                    }
                }
                .foregroundColor(.orange)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .background(
                    Capsule()
                        .fill(Color.orange.opacity(0.15))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
                .accessibilityHint(premiumManager.isPremiumUser ? "Opens streak editor" : "Requires premium subscription")
            }
            
            // Best streak
            if longestStreak > currentStreak {
                HStack(spacing: 4) {
                    Image(systemName: "trophy.fill")
                        .foregroundColor(.yellow)
                    Text("Best: \(longestStreak)")
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Current workout streak: \(currentStreak) days")
        .padding(.vertical, 20)
    }
    
    // MARK: - Status Section
    private var statusSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: streakStatus.isAtRisk ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(streakStatus.isAtRisk ? .orange : .green)
                
                Text(streakStatus.message)
                    .font(.headline)
                    .foregroundColor(streakStatus.isAtRisk ? .orange : .primary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(streakStatus.isAtRisk ? Color.orange.opacity(0.15) : Color.green.opacity(0.15))
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(streakStatus.isAtRisk ? "Warning: \(streakStatus.message)" : "Status: \(streakStatus.message)")
    }
    
    // MARK: - How It Works Section
    private var howItWorksSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("How Streaks Work", systemImage: "lightbulb.fill")
                .font(.headline)
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 12) {
                streakRuleRow(
                    icon: "checkmark.circle.fill",
                    color: .green,
                    title: "Rest days don't break your streak!",
                    subtitle: "Recovery is part of training"
                )
                
                streakRuleRow(
                    icon: "calendar",
                    color: .blue,
                    title: "Based on YOUR schedule",
                    subtitle: "You work out \(daysPerWeek) days/week"
                )
                
                streakRuleRow(
                    icon: "clock.fill",
                    color: .purple,
                    title: "Up to \(maxRestDays) rest days allowed",
                    subtitle: "Between workouts without losing streak"
                )
                
                streakRuleRow(
                    icon: "xmark.circle.fill",
                    color: .red,
                    title: "Streak resets after \(maxRestDays + 2)+ days",
                    subtitle: "Without completing a workout"
                )
            }
            .padding()
            .frame(minHeight: 240)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(Color(.systemGray6))
            )
        }
    }
    
    // MARK: - Your Schedule Section
    private var yourScheduleSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Your Training Schedule", systemImage: "figure.strengthtraining.traditional")
                .font(.headline)
                .foregroundColor(.blue)
            
            HStack(spacing: 16) {
                scheduleStatCard(
                    value: "\(daysPerWeek)",
                    label: "Days/Week",
                    icon: "calendar.badge.clock",
                    color: .blue
                )
                
                scheduleStatCard(
                    value: "\(maxRestDays)",
                    label: "Max Rest Days",
                    icon: "bed.double.fill",
                    color: .purple
                )
                
                scheduleStatCard(
                    value: "\(currentStreak)",
                    label: "Current",
                    icon: "flame.fill",
                    color: .orange
                )
            }
        }
    }
    
    // MARK: - Tips Section
    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Pro Tips", systemImage: "star.fill")
                .font(.headline)
                .foregroundColor(.yellow)
            
            VStack(alignment: .leading, spacing: 12) {
                tipRow("🏋️", "Any completed workout counts toward your streak")
                tipRow("😴", "Rest days are essential for muscle recovery")
                tipRow("📅", "Consistency > Intensity for building habits")
                tipRow("🔔", "Enable notifications to never miss a workout")
            }
            .padding()
            .frame(minHeight: 240)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(Color(.systemGray6))
            )
        }
    }
    
    // MARK: - Helper Views
    private func streakRuleRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func scheduleStatCard(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(Color(.systemGray6))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
    
    private func tipRow(_ emoji: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(emoji)
                .font(.title3)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
    }
}

// MARK: - Edit Streak Sheet
struct EditStreakSheet: View {
    let currentStreak: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    @State private var newStreak: Int
    @State private var isSaving = false
    
    init(currentStreak: Int) {
        self.currentStreak = currentStreak
        _newStreak = State(initialValue: currentStreak)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Edit Streak")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            // Streak input
            VStack(spacing: 12) {
                ZStack {
                    // Glow
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.orange.opacity(0.3), Color.clear],
                                center: .center,
                                startRadius: 20,
                                endRadius: 60
                            )
                        )
                        .frame(width: 120, height: 120)
                    
                    // Flame
                    Image(systemName: "flame.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(
                            LinearGradient(colors: [.orange, .red], startPoint: .top, endPoint: .bottom)
                        )
                }
                
                // Stepper for streak
                HStack(spacing: 20) {
                    Button(action: {
                        if newStreak > 0 {
                            HapticManager.selectionChanged()
                            newStreak -= 1
                        }
                    }) {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(newStreak > 0 ? .orange : .gray.opacity(0.3))
                    }
                    .disabled(newStreak <= 0)
                    .accessibilityLabel("Decrease streak")
                    
                    Text("\(newStreak)")
                        .font(.system(size: 48, weight: .black, design: .rounded))
                        .foregroundColor(.primary)
                        .frame(minWidth: 80)
                        .accessibilityLabel("Streak value: \(newStreak) days")
                    
                    Button(action: {
                        HapticManager.selectionChanged()
                        newStreak += 1
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.orange)
                    }
                    .accessibilityLabel("Increase streak")
                }
                
                Text("days")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Save button
            Button(action: saveStreak) {
                HStack {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Save Streak")
                            .fontWeight(.semibold)
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background(
                    LinearGradient(
                        colors: [.orange, .red],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(14)
            }
            .disabled(isSaving || newStreak == currentStreak)
            .opacity(newStreak == currentStreak ? 0.5 : 1)
            .padding(.horizontal, 20)
            
            Spacer()
        }
    }
    
    private func saveStreak() {
        isSaving = true
        HapticManager.success()
        
        // Update the streak in Core Data
        if let user = userManager.currentUser {
            user.currentStreak = Int16(newStreak)
            
            // Update longest streak if needed
            if newStreak > user.longestStreak {
                user.longestStreak = Int16(newStreak)
            }
            
            // Save context
            do {
                try user.managedObjectContext?.save()
                
                // Sync to Supabase
                Task {
                    do {
                        try await SupabaseManager.shared.syncCoreDataProfile(from: user)
                    } catch {
                        AppLogger.error("Failed to sync streak to cloud: \(error.localizedDescription)", category: .ui)
                    }
                }
            } catch {
                AppLogger.error("Failed to save streak: \(error.localizedDescription)", category: .ui)
            }
        }
        
        dismiss()
    }
}
