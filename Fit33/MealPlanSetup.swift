import SwiftUI


// NOTE: Legacy meal components removed (MealWidgetCard, MealItemRow, MealQuickStat, MealSectionWithItems)
// Active meal tracking uses the newer components in MealPlanView.swift

struct SimpleProfileSetupView: View {
    @EnvironmentObject var userManager: UserManager
    @Binding var showingProfileSetup: Bool
    @State private var weight: String = ""
    @State private var height: String = ""
    @State private var gender: String = "Male"
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 16) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)
                        
                        Text("Complete Your Profile")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("We'll calculate your nutrition goals based on your fitness goal: \"\(userManager.currentUser?.fitnessGoal ?? "Build Muscle")\"")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    VStack(spacing: 20) {
                        SimpleInputField(title: "Weight (lbs)", value: $weight, placeholder: "150")
                        SimpleInputField(title: "Height (inches)", value: $height, placeholder: "70")
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Gender")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Picker("Gender", selection: $gender) {
                                Text("Male").tag("Male")
                                Text("Female").tag("Female")
                            }
                            .pickerStyle(SegmentedPickerStyle())
                        }
                    }
                    .padding(.horizontal)
                    
                    Button(action: { HapticManager.impact(.medium); saveProfile() }) {
                        Text("Calculate My Nutrition Goals")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.md)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.green, Color.mint]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .cornerRadius(CornerRadius.md)
                    }
                    .padding(.horizontal)
                    .disabled(!isFormValid)
                }
                .padding(.vertical)
            }
            .navigationTitle("Profile Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        showingProfileSetup = false
                    }
                }
            }
        }
    }
    
    private var isFormValid: Bool {
        !weight.isEmpty && !height.isEmpty &&
        Int(weight) != nil && Int(height) != nil
    }
    
    private func saveProfile() {
        guard let weightValue = Int(weight),
              let heightValue = Int(height),
              let user = userManager.currentUser else { return }
        
        // Save to Core Data (primary storage)
        user.weight = Int16(weightValue)
        user.height = Int16(heightValue)
        user.gender = gender
        
        // Also save to UserDefaults for backwards compatibility
        UserDefaults.standard.set(weightValue, forKey: "userWeight")
        UserDefaults.standard.set(heightValue, forKey: "userHeight")
        UserDefaults.standard.set(gender, forKey: "userGender")
        
        do {
            try PersistenceController.shared.container.viewContext.save()
            AppLogger.info("[PROFILE] Saved weight: \(weightValue), height: \(heightValue)", category: .ui)
        } catch {
            AppLogger.error("[PROFILE] Error saving: \(error.localizedDescription)", category: .ui)
        }
        
        showingProfileSetup = false
    }
}

struct SimpleInputField: View {
    let title: String
    @Binding var value: String
    let placeholder: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            
            TextField(placeholder, text: $value)
                .keyboardType(.numberPad)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
}

// MARK: - Workout Timer Indicator

struct WorkoutTimerIndicator: View {
    @ObservedObject var workoutManager: WorkoutManager
    
    var body: some View {
        Button(action: {
            // Tap to navigate to workout tab - could add this functionality
        }) {
            Text(workoutManager.formattedDuration)
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, Spacing.xxs)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .fill(.ultraThinMaterial)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
