import SwiftUI

// MARK: - Program Customization View

struct ProgramCustomizationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var customizationService = ProgramCustomizationService.shared
    
    let baseProgram: CloudProgram
    let programColor: Color
    let onCustomizationComplete: (UserCustomProgram) -> Void
    
    // Customization state
    @State private var selectedEquipment: Set<String> = []
    @State private var daysPerWeek: Int = 4
    @State private var workoutDuration: Int = 45
    @State private var avoidExercises: [String] = []
    @State private var showingPreview = false
    @State private var generatedProgram: UserCustomProgram?
    
    private let allEquipment = EquipmentCategory.allCases
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    customizationHeader
                    
                    // Equipment Selection
                    equipmentSection
                    
                    // Schedule Preferences
                    scheduleSection
                    
                    // Quick Options
                    quickOptionsSection
                    
                    // Generate Button
                    generateButton
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .padding(.bottom, 40)
            }
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        programColor.opacity(0.15),
                        programColor.opacity(0.05),
                        colorScheme == .dark ? Color(red: 0.05, green: 0.05, blue: 0.07) : Color.white
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Customize Program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingPreview) {
                if let program = generatedProgram {
                    CustomProgramPreviewView(
                        program: program,
                        programColor: programColor,
                        onConfirm: {
                            onCustomizationComplete(program)
                            dismiss()
                        }
                    )
                }
            }
        }
        .onAppear {
            // Pre-select equipment from base program
            selectedEquipment = Set(baseProgram.equipment.map { $0.capitalized })
            daysPerWeek = baseProgram.workoutsPerWeek
            workoutDuration = baseProgram.avgWorkoutDurationMin
        }
    }
    
    // MARK: - Header
    
    private var customizationHeader: some View {
        VStack(spacing: 12) {
            // Program icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [programColor, programColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)
                
                Image(systemName: baseProgram.icon)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
            }
            
            Text("Customizing")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text(baseProgram.name)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            Text("Adjust the options below to create your perfect program")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Equipment Section
    
    private var equipmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Available Equipment", systemImage: "dumbbell.fill")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("Select what you have access to")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Equipment grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 10) {
                ForEach(allEquipment, id: \.rawValue) { equipment in
                    EquipmentChip(
                        equipment: equipment,
                        isSelected: selectedEquipment.contains(equipment.rawValue),
                        accentColor: programColor
                    ) {
                        toggleEquipment(equipment.rawValue)
                    }
                }
            }
            
            // Quick presets
            HStack(spacing: 8) {
                PresetButton(title: "Home Gym", icon: "house.fill") {
                    selectedEquipment = Set(["Bodyweight", "Dumbbells", "Resistance Bands", "Pull-Up Bar"])
                }
                
                PresetButton(title: "Full Gym", icon: "building.2.fill") {
                    selectedEquipment = Set(allEquipment.map { $0.rawValue })
                }
                
                PresetButton(title: "Minimal", icon: "figure.walk") {
                    selectedEquipment = Set(["Bodyweight"])
                }
            }
        }
        .padding(16)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Schedule Section
    
    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Schedule Preferences", systemImage: "calendar")
                .font(.headline)
                .foregroundColor(.primary)
            
            // Days per week
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Days Per Week")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(daysPerWeek) days")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(programColor)
                }
                
                HStack(spacing: 8) {
                    ForEach(2...7, id: \.self) { day in
                        DayButton(
                            day: day,
                            isSelected: daysPerWeek == day,
                            color: programColor
                        ) {
                            daysPerWeek = day
                        }
                    }
                }
            }
            
            Divider()
            
            // Workout duration
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Workout Duration")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(workoutDuration) min")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(programColor)
                }
                
                Slider(value: Binding(
                    get: { Double(workoutDuration) },
                    set: { workoutDuration = Int($0) }
                ), in: 20...90, step: 5)
                .tint(programColor)
                
                HStack {
                    Text("20 min")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("90 min")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Quick Options
    
    private var quickOptionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Quick Adjustments", systemImage: "slider.horizontal.3")
                .font(.headline)
                .foregroundColor(.primary)
            
            // Quick option chips
            FlowLayout(spacing: 8) {
                QuickOptionChip(title: "No Barbell", icon: "xmark.circle") {
                    selectedEquipment.remove("Barbell")
                }
                
                QuickOptionChip(title: "Shorter Rest", icon: "clock.arrow.circlepath") {
                    // Would adjust rest times in generation
                }
                
                QuickOptionChip(title: "More Core", icon: "figure.core.training") {
                    // Would add focus adjustment
                }
                
                QuickOptionChip(title: "Less Legs", icon: "figure.walk") {
                    // Would reduce leg focus
                }
            }
        }
        .padding(16)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Generate Button
    
    private var generateButton: some View {
        Button {
            generateCustomProgram()
        } label: {
            HStack(spacing: 12) {
                if customizationService.isGenerating {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 18, weight: .semibold))
                }
                
                Text(customizationService.isGenerating ? "Generating..." : "Generate My Program")
                    .font(.headline)
                    .fontWeight(.bold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [programColor, programColor.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: programColor.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .disabled(customizationService.isGenerating || selectedEquipment.isEmpty)
        .opacity(selectedEquipment.isEmpty ? 0.5 : 1)
    }
    
    // MARK: - Actions
    
    private func toggleEquipment(_ equipment: String) {
        if selectedEquipment.contains(equipment) {
            selectedEquipment.remove(equipment)
        } else {
            selectedEquipment.insert(equipment)
        }
    }
    
    private func generateCustomProgram() {
        let request = ProgramCustomizationRequest(
            baseProgramId: baseProgram.id,
            baseProgramName: baseProgram.name,
            availableEquipment: selectedEquipment,
            daysPerWeek: daysPerWeek,
            maxWorkoutMinutes: workoutDuration,
            focusAdjustments: [:],
            avoidExercises: avoidExercises,
            specialInstructions: nil
        )
        
        Task {
            if let program = await customizationService.generateCustomProgram(from: request) {
                generatedProgram = program
                showingPreview = true
            }
        }
    }
}

// MARK: - Supporting Views

struct EquipmentChip: View {
    let equipment: EquipmentCategory
    let isSelected: Bool
    let accentColor: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: equipment.icon)
                    .font(.system(size: 18))
                
                Text(equipment.rawValue)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(isSelected ? .white : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? accentColor : Color.gray.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? accentColor : Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct PresetButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .foregroundColor(.blue)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.blue.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct DayButton: View {
    let day: Int
    let isSelected: Bool
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text("\(day)")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(isSelected ? .white : .primary)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(isSelected ? color : Color.gray.opacity(0.1))
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct QuickOptionChip: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    @State private var isActive = false
    
    var body: some View {
        Button {
            isActive.toggle()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundColor(isActive ? .white : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isActive ? Color.orange : Color.gray.opacity(0.1))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Custom Program Preview View

struct CustomProgramPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    
    let program: UserCustomProgram
    let programColor: Color
    let onConfirm: () -> Void
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(programColor.opacity(0.15))
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: program.icon)
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(programColor)
                        }
                        
                        Text(program.customName)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text(program.customizationSummary)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        // Stats
                        HStack(spacing: 20) {
                            StatBadge(value: "\(program.durationDays)", label: "Days", color: programColor)
                            StatBadge(value: "\(program.workoutsPerWeek)", label: "Per Week", color: programColor)
                            StatBadge(value: "\(program.avgWorkoutDurationMin)", label: "Minutes", color: programColor)
                        }
                    }
                    .padding()
                    .background(Color.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    
                    // Sample days preview
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Preview")
                            .font(.headline)
                            .padding(.horizontal, 4)
                        
                        ForEach(program.days.prefix(7)) { day in
                            DayPreviewCard(day: day, programColor: programColor)
                        }
                        
                        if program.days.count > 7 {
                            Text("+ \(program.days.count - 7) more days...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .padding(.bottom, 100)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Your Custom Program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Edit") {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    onConfirm()
                } label: {
                    Text("Start This Program")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(programColor)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
            }
        }
    }
}

struct StatBadge: View {
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(width: 70)
    }
}

struct DayPreviewCard: View {
    let day: CustomProgramDay
    let programColor: Color
    
    var body: some View {
        HStack(spacing: 12) {
            // Day number
            ZStack {
                Circle()
                    .fill(day.isRestDay ? Color.gray.opacity(0.2) : programColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                if day.isRestDay {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                } else {
                    Text("\(day.dayNumber)")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(programColor)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(day.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                if !day.isRestDay {
                    Text("\(day.exercises.count) exercises • \(day.estimatedDurationMin) min")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if !day.isRestDay {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Preview

#Preview {
    ProgramCustomizationView(
        baseProgram: CloudProgram(
            id: "test",
            name: "30-Day Push/Pull/Legs",
            description: "Test program",
            preview: "Test",
            durationDays: 30,
            difficulty: "intermediate",
            programType: "push_pull_legs",
            targetGoals: ["bulk"],
            requiredExperience: "intermediate",
            requiredEquipment: ["barbell", "dumbbells"],
            minDaysPerWeek: 5,
            maxDaysPerWeek: 6,
            workoutsPerWeek: 6,
            avgWorkoutDurationMin: 60,
            restDays: [7, 14, 21, 28],
            icon: "figure.strengthtraining.traditional",
            color: "red",
            benefits: ["Test"],
            equipment: ["Barbell", "Dumbbells"],
            popularityScore: 90,
            ratingAvg: 4.5,
            ratingCount: 100,
            isFeatured: true
        ),
        programColor: .red
    ) { _ in }
}

