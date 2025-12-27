import Foundation
import SwiftUI

// MARK: - Streak Shield Service
// Allows users to protect their workout streak when they miss a day

class StreakShieldService: ObservableObject {
    static let shared = StreakShieldService()
    
    // MARK: - Published Properties
    @Published var availableShields: Int = 0
    @Published var shieldsUsedThisMonth: Int = 0
    @Published var lastShieldUsedDate: Date?
    @Published var isStreakAtRisk: Bool = false
    @Published var hoursUntilStreakLost: Int = 0
    
    // MARK: - Constants
    private let maxShieldsPerMonth = 2  // Free users get 2 per month
    private let premiumShieldsPerMonth = 4  // Premium users get 4
    private let shieldEarnedEveryNWorkouts = 10  // Earn 1 shield every 10 workouts
    
    // MARK: - UserDefaults Keys
    private let shieldsKey = "streakShields"
    private let shieldsUsedKey = "streakShieldsUsedThisMonth"
    private let lastShieldDateKey = "lastStreakShieldUsed"
    private let lastResetMonthKey = "streakShieldResetMonth"
    
    private init() {
        loadShieldData()
        checkForMonthlyReset()
    }
    
    // MARK: - Shield Data Management
    
    private func loadShieldData() {
        availableShields = UserDefaults.standard.integer(forKey: shieldsKey)
        shieldsUsedThisMonth = UserDefaults.standard.integer(forKey: shieldsUsedKey)
        lastShieldUsedDate = UserDefaults.standard.object(forKey: lastShieldDateKey) as? Date
        
        // New users start with 1 free shield
        if availableShields == 0 && shieldsUsedThisMonth == 0 {
            availableShields = 1
            saveShieldData()
        }
    }
    
    private func saveShieldData() {
        UserDefaults.standard.set(availableShields, forKey: shieldsKey)
        UserDefaults.standard.set(shieldsUsedThisMonth, forKey: shieldsUsedKey)
        if let date = lastShieldUsedDate {
            UserDefaults.standard.set(date, forKey: lastShieldDateKey)
        }
    }
    
    private func checkForMonthlyReset() {
        let calendar = Calendar.current
        let currentMonth = calendar.component(.month, from: Date())
        let lastResetMonth = UserDefaults.standard.integer(forKey: lastResetMonthKey)
        
        if currentMonth != lastResetMonth {
            // New month - reset shields used count and grant monthly shields
            shieldsUsedThisMonth = 0
            
            // Grant monthly shields based on premium status
            let isPremium = PremiumManager.shared.isPremiumUser
            let monthlyGrant = isPremium ? premiumShieldsPerMonth : maxShieldsPerMonth
            availableShields = min(availableShields + monthlyGrant, 5) // Cap at 5
            
            UserDefaults.standard.set(currentMonth, forKey: lastResetMonthKey)
            saveShieldData()
            
            #if DEBUG
            print("🛡️ Monthly shield reset! Granted \(monthlyGrant) shields. Total: \(availableShields)")
            #endif
        }
    }
    
    // MARK: - Streak Risk Detection
    
    /// Check if user's streak is at risk and update state
    func checkStreakRisk(lastWorkoutDate: Date?, currentStreak: Int) {
        guard currentStreak > 0 else {
            isStreakAtRisk = false
            hoursUntilStreakLost = 0
            return
        }
        
        let calendar = Calendar.current
        let now = Date()
        let lastWorkout = lastWorkoutDate ?? Date.distantPast
        
        // Calculate hours since last workout
        let hoursSinceLastWorkout = calendar.dateComponents([.hour], from: lastWorkout, to: now).hour ?? 0
        
        // Streak breaks after 48 hours (2 days)
        let hoursRemaining = 48 - hoursSinceLastWorkout
        
        if hoursRemaining > 0 && hoursRemaining <= 24 {
            isStreakAtRisk = true
            hoursUntilStreakLost = hoursRemaining
        } else if hoursRemaining <= 0 {
            isStreakAtRisk = true
            hoursUntilStreakLost = 0
        } else {
            isStreakAtRisk = false
            hoursUntilStreakLost = hoursRemaining
        }
    }
    
    // MARK: - Shield Usage
    
    /// Use a streak shield to protect the streak
    /// Returns true if shield was successfully used
    func useShield() -> Bool {
        guard availableShields > 0 else {
            #if DEBUG
            print("🛡️ No shields available!")
            #endif
            return false
        }
        
        // Check if already used a shield today
        if let lastUsed = lastShieldUsedDate,
           Calendar.current.isDateInToday(lastUsed) {
            #if DEBUG
            print("🛡️ Already used a shield today!")
            #endif
            return false
        }
        
        availableShields -= 1
        shieldsUsedThisMonth += 1
        lastShieldUsedDate = Date()
        isStreakAtRisk = false
        
        saveShieldData()
        
        // Log streak saved
        SessionLogManager.shared.logStreakSaved(
            streakDays: WorkoutManager.shared.workoutStreak,
            saveMethod: "shield"
        )
        
        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        #if DEBUG
        print("🛡️ Shield used! Streak protected. Remaining: \(availableShields)")
        #endif
        
        return true
    }
    
    /// Award a shield for workout completion milestone
    func checkAndAwardShield(totalWorkouts: Int) {
        if totalWorkouts > 0 && totalWorkouts % shieldEarnedEveryNWorkouts == 0 {
            availableShields = min(availableShields + 1, 5)
            saveShieldData()
            
            #if DEBUG
            print("🛡️ Earned a shield! Total workouts: \(totalWorkouts). Shields: \(availableShields)")
            #endif
        }
    }
    
    // MARK: - Shield Info
    
    var shieldStatusText: String {
        if availableShields == 0 {
            return "No shields available"
        } else if availableShields == 1 {
            return "1 shield available"
        } else {
            return "\(availableShields) shields available"
        }
    }
    
    var canUseShield: Bool {
        guard availableShields > 0 else { return false }
        
        if let lastUsed = lastShieldUsedDate,
           Calendar.current.isDateInToday(lastUsed) {
            return false
        }
        
        return true
    }
}

// MARK: - Streak Shield Alert View

struct StreakAtRiskAlert: View {
    @ObservedObject var shieldService = StreakShieldService.shared
    @Binding var isPresented: Bool
    let currentStreak: Int
    let onUseShield: () -> Void
    let onWorkoutNow: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // Warning Icon
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.2))
                    .frame(width: 80, height: 80)
                    .blur(radius: 15)
                
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.orange, .red],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)
                
                Image(systemName: "flame.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
            }
            
            // Title
            Text("Streak at Risk!")
                .font(.title2)
                .fontWeight(.bold)
            
            // Message
            VStack(spacing: 8) {
                Text("Your \(currentStreak)-day streak will end in")
                    .foregroundColor(.secondary)
                
                Text("\(shieldService.hoursUntilStreakLost) hours")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.orange)
            }
            
            Divider()
                .padding(.vertical, 8)
            
            // Options
            VStack(spacing: 12) {
                // Use Shield Button
                if shieldService.canUseShield {
                    Button(action: {
                        if shieldService.useShield() {
                            onUseShield()
                            isPresented = false
                        }
                    }) {
                        HStack {
                            Image(systemName: "shield.fill")
                            Text("Use Streak Shield")
                            Spacer()
                            Text("(\(shieldService.availableShields) left)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(12)
                    }
                }
                
                // Workout Now Button
                Button(action: {
                    onWorkoutNow()
                    isPresented = false
                }) {
                    HStack {
                        Image(systemName: "figure.run")
                        Text("Workout Now")
                    }
                    .font(.headline)
                    .foregroundColor(.green)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.green, lineWidth: 2)
                    )
                }
                
                // Dismiss
                Button("Remind Me Later") {
                    isPresented = false
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.top, 8)
            }
            
            // Shield info
            if shieldService.availableShields == 0 {
                Text("Complete \(10 - (UserManager.shared.currentUser?.totalWorkouts ?? 0) % 10) more workouts to earn a shield!")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        )
        .padding(.horizontal, 32)
    }
}

// MARK: - Shield Badge for Home Screen

struct StreakShieldBadge: View {
    @ObservedObject var shieldService = StreakShieldService.shared
    
    var body: some View {
        if shieldService.availableShields > 0 {
            HStack(spacing: 4) {
                Image(systemName: "shield.fill")
                    .font(.system(size: 12))
                Text("\(shieldService.availableShields)")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
        }
    }
}

