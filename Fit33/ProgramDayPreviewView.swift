//
//  ProgramDayPreviewView.swift
//  GoFit
//
//  Preview screen for a program day - shows exercises and GO! button
//  Identical to AutoWorkoutPreviewView but for Smart Program days
//

import SwiftUI
import CoreData

struct SmartProgramDayPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var workoutManager: WorkoutManager
    @EnvironmentObject var userManager: UserManager
    
    let program: SmartActiveProgram
    let day: SmartProgramDay
    let programName: String
    let totalDays: Int
    
    @State private var showingExerciseDetail = false
    @State private var selectedCoreDataExercise: Exercise? = nil
    @State private var showingExerciseSwap = false
    @State private var selectedExerciseIndex: Int? = nil
    
    // Haptic feedback
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
    
    private let themeColor: Color = .green
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: colorScheme == .dark 
                    ? [themeColor.opacity(0.2), themeColor.opacity(0.05), Color(red: 0.05, green: 0.05, blue: 0.07)]
                    : [themeColor.opacity(0.3), themeColor.opacity(0.1), Color.white]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            if day.exercises.isEmpty {
                restDayView
            } else {
                exerciseListView
            }
        }
        .navigationTitle("Day \(day.dayNumber)")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.ds_labelLarge)
                        .foregroundColor(.primary)
                }
            }
        }
        .sheet(isPresented: $showingExerciseDetail) {
            if let exercise = selectedCoreDataExercise {
                NavigationStack {
                    ExerciseDetailView(exercise: exercise)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") {
                                    showingExerciseDetail = false
                                }
                            }
                        }
                }
            }
        }
        .onAppear {
            if !day.exercises.isEmpty {
                GoButtonState.shared.show(
                    primaryColor: themeColor,
                    secondaryColor: .mint
                ) {
                    let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
                    heavyImpact.impactOccurred()
                    startWorkout()
                }
                
                // Prefetch exercise history
                let exerciseNames = day.exercises.map { $0.exerciseName }
                Task {
                    AppLogger.debug("🔮 [PROGRAM DAY] Pre-loading exercise history for \(exerciseNames.count) exercises...", category: .workout)
                    _ = await ExerciseHistoryService.shared.fetchPreviousSetsForExercises(exerciseNames)
                }
            }
        }
        .onDisappear {
            GoButtonState.shared.hide()
        }
    }
    
    // MARK: - Rest Day View
    
    private var restDayView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.blue)
            }
            
            VStack(spacing: 8) {
                Text("Rest Day")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Take it easy today. Recovery is just as important as training!")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            // Tomorrow preview
            if program.currentDay < totalDays {
                VStack(spacing: 8) {
                    Text("Tomorrow")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundColor(.green)
                        Text("Day \(day.dayNumber + 1)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
                .padding(.top, 20)
            }
            
            Spacer()
            
            // Mark Rest Day Complete button
            Button(action: {
                impactFeedback.impactOccurred()
                completeRestDay()
            }) {
                Text("Mark Rest Day Complete")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                    .background(
                        LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing)
                    )
                    .cornerRadius(CornerRadius.lg)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }
    
    // MARK: - Exercise List View
    
    private var exerciseListView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header card
                workoutHeader
                
                // Exercise list
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Today's Exercises")
                            .font(.headline)
                            .fontWeight(.bold)
                        
                        Spacer()
                        
                        HStack(spacing: 4) {
                            Image(systemName: "hand.tap.fill")
                                .font(.caption2)
                            Text("tap for details")
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, Spacing.xxs)
                    
                    VStack(spacing: 10) {
                        ForEach(Array(day.exercises.enumerated()), id: \.element.id) { index, exercise in
                            SmartProgramExerciseCard(
                                number: index + 1,
                                exercise: exercise,
                                themeColor: themeColor,
                                onTap: {
                                    if let coreDataExercise = ExerciseLibraryService.shared.getExercise(byName: exercise.exerciseName) {
                                        selectedCoreDataExercise = coreDataExercise
                                        showingExerciseDetail = true
                                    }
                                }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .onAppear {
            // ⚡️ MEMORY FIX: Disabled video prefetching — videos load on-demand in detail view.
            // Was creating AVPlayers for all exercises in the program day, contributing to 600MB+ memory.
        }
    }
    
    // MARK: - Workout Header
    
    private var workoutHeader: some View {
        HStack(spacing: 14) {
            // Progress badge
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 4)
                    .frame(width: 46, height: 46)
                
                Circle()
                    .trim(from: 0, to: Double(program.completedDays.count) / Double(totalDays))
                    .stroke(
                        LinearGradient(colors: [themeColor, .mint], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 46, height: 46)
                    .rotationEffect(.degrees(-90))
                
                Text("\(day.dayNumber)")
                    .font(.ds_bodySmall).fontWeight(.bold)
                    .foregroundColor(themeColor)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(day.name)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                HStack(spacing: 8) {
                    Label("\(day.exercises.count) exercises", systemImage: "figure.strengthtraining.traditional")
                    Label("~\(day.targetDuration) min", systemImage: "clock.fill")
                }
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                
                Text(programName)
                    .font(.caption2)
                    .foregroundColor(themeColor)
            }
            
            Spacer()
        }
        .padding(14)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.1), radius: 8, x: 0, y: 3)
    }
    
    // MARK: - Actions
    
    private func startWorkout() {
        guard !day.exercises.isEmpty else { return }
        guard !workoutManager.isWorkoutActive else { return }
        
        let workoutTitle = "\(programName) - Day \(day.dayNumber)"
        
        // Set workout manager properties
        workoutManager.restTimeBetweenSets = day.restBetweenSets
        workoutManager.targetWorkoutDuration = day.targetDuration
        
        // Create Workout entity
        let context = PersistenceController.shared.container.viewContext
        let workout = Workout(context: context)
        workout.id = UUID()
        workout.name = workoutTitle
        workout.date = Date()
        workout.duration = 0
        workout.isCompleted = false
        
        // Lookup Core Data exercises
        let exerciseNames = day.exercises.map { $0.exerciseName }
        let coreDataExercises = ExerciseLibraryService.shared.getExercises(byNames: exerciseNames)
        
        guard !coreDataExercises.isEmpty else {
            AppLogger.warning("⚠️ No Core Data exercises found", category: .workout)
            return
        }
        
        // Create exercise name to Core Data exercise mapping
        var exerciseMap: [String: Exercise] = [:]
        for exercise in coreDataExercises {
            if let name = exercise.name {
                exerciseMap[name.lowercased()] = exercise
            }
        }
        
        // Add exercises to workout in order
        var orderedExercises: [Exercise] = []
        for programExercise in day.exercises {
            if let coreDataExercise = exerciseMap[programExercise.exerciseName.lowercased()] {
                orderedExercises.append(coreDataExercise)
            }
        }
        
        // Save context
        do {
            try context.save()
        } catch {
            AppLogger.error("❌ Failed to save workout: \(error)", category: .workout)
            return
        }
        
        // Start workout via WorkoutManager (pass week for program-aware progressive overload)
        // Derive week from completed days (every ~4-6 workout days ≈ 1 week)
        let completedCount = program.completedDays.count
        let estimatedWeek = (completedCount / 4) + 1
        workoutManager.startWorkout(
            workout: workout,
            exercises: orderedExercises,
            programDay: program.currentDay,
            programDayFocus: day.name,
            smartProgramId: program.id,
            programWeek: min(estimatedWeek, 5)
        )
    }
    
    private func completeRestDay() {
        // Mark the rest day as complete
        SmartProgramEngine.shared.completeDay(
            programId: program.id,
            dayNumber: day.dayNumber,
            actualDuration: 0,
            totalVolume: 0
        )
        dismiss()
    }
}

// MARK: - Smart Program Exercise Card

struct SmartProgramExerciseCard: View {
    let number: Int
    let exercise: SmartProgramExercise
    let themeColor: Color
    let onTap: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var exerciseData: Exercise?
    
    // Category-based gradients matching exercise library style
    private var categoryGradient: [Color] {
        // Use theme color for gradient
        [themeColor, themeColor.opacity(0.7)]
    }
    
    // Category icon based on exercise name patterns
    private var categoryIcon: String {
        let exerciseName = exercise.exerciseName.lowercased()
        
        if exerciseName.contains("dumbbell") {
            return "dumbbell.fill"
        } else if exerciseName.contains("barbell") {
            return "figure.strengthtraining.traditional"
        } else if exerciseName.contains("cable") {
            return "dot.radiowaves.left.and.right"
        } else if exerciseName.contains("push") && exerciseName.contains("up") {
            return "figure.strengthtraining.traditional"
        } else if exerciseName.contains("pull") && (exerciseName.contains("up") || exerciseName.contains("chin")) {
            return "figure.climbing"
        } else if exerciseName.contains("squat") {
            return "figure.strengthtraining.traditional"
        } else if exerciseName.contains("lunge") {
            return "figure.walk"
        } else if exerciseName.contains("thrust") || exerciseName.contains("bridge") {
            return "figure.strengthtraining.functional"
        } else if exerciseName.contains("deadlift") {
            return "figure.strengthtraining.functional"
        } else if exerciseName.contains("curl") {
            return "figure.arms.open"
        } else if exerciseName.contains("press") {
            return "arrow.up.circle.fill"
        } else if exerciseName.contains("row") {
            return "arrow.left.and.right.circle.fill"
        } else if exerciseName.contains("fly") || exerciseName.contains("flye") {
            return "arrow.up.left.and.arrow.down.right.circle.fill"
        } else if exerciseName.contains("raise") {
            return "arrow.up.circle"
        } else if exerciseName.contains("plank") {
            return "figure.core.training"
        }
        
        return "dumbbell.fill"
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Compact exercise icon with vibrant gradient (matching exercise library)
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: categoryGradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                        .shadow(color: categoryGradient[0].opacity(0.25), radius: 4, x: 0, y: 2)
                    
                    Image(systemName: categoryIcon)
                        .font(.ds_labelLarge)
                        .foregroundColor(.white)
                }
                
                // Exercise info
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.exerciseName)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 8) {
                        Text("\(exercise.sets) sets × \(exercise.reps) reps")
                            .font(.caption)
                            .foregroundColor(themeColor)
                            .fontWeight(.medium)
                        
                        if let weight = exercise.suggestedWeight, weight > 0 {
                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            // Preserve decimals (e.g., 180.5 lbs)
                            let weightStr = weight.truncatingRemainder(dividingBy: 1) == 0 
                                ? "\(Int(weight))" 
                                : String(format: "%.1f", weight)
                            Text("\(weightStr) lbs")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                }
                
                Spacer()
                
                // Chevron inside the card
                Image(systemName: "chevron.right")
                    .font(.ds_bodySmall).fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                ZStack {
                    // Bottom shadow layer (deepest) - category colored (subtle)
                    RoundedRectangle(cornerRadius: 28)
                        .fill(categoryGradient[0].opacity(colorScheme == .dark ? 0.06 : 0.03))
                        .offset(y: 4)
                        .blur(radius: 2)
                    
                    // Middle shadow layer (subtle)
                    RoundedRectangle(cornerRadius: 26)
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.08 : 0.02))
                        .offset(y: 2)
                    
                    // Main card background
                    RoundedRectangle(cornerRadius: 25)
                        .fill(
                            LinearGradient(
                                colors: colorScheme == .dark 
                                    ? [Color(white: 0.15), Color.cardBackground]
                                    : [Color.white, Color.white.opacity(0.98)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    // Inner highlight (top edge glow)
                    RoundedRectangle(cornerRadius: 25)
                        .stroke(
                            LinearGradient(
                                colors: colorScheme == .dark 
                                    ? [Color.white.opacity(0.08), Color.clear]
                                    : [Color.white, Color.white.opacity(0.3), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                    
                    // Subtle accent border
                    RoundedRectangle(cornerRadius: 25)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    categoryGradient[0].opacity(colorScheme == .dark ? 0.2 : 0.12),
                                    categoryGradient[1].opacity(colorScheme == .dark ? 0.1 : 0.06)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.12 : 0.05), radius: 6, x: 0, y: 3)
            .shadow(color: categoryGradient[0].opacity(colorScheme == .dark ? 0.08 : 0.04), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            // Load exercise data
            exerciseData = ExerciseLibraryService.shared.getExercise(byName: exercise.exerciseName)
        }
    }
}

// MARK: - Preview

#Preview {
    let testDay = SmartProgramDay(
        id: "test",
        dayNumber: 1,
        name: "Push Day A",
        exercises: [
            SmartProgramExercise(id: "1", exerciseName: "Barbell Bench Press", exerciseId: nil, sets: 4, reps: 8, suggestedWeight: 135, restSeconds: 90, notes: nil, isSuperset: false, supersetWith: nil),
            SmartProgramExercise(id: "2", exerciseName: "Incline Dumbbell Press", exerciseId: nil, sets: 3, reps: 10, suggestedWeight: 50, restSeconds: 60, notes: nil, isSuperset: false, supersetWith: nil),
            SmartProgramExercise(id: "3", exerciseName: "Cable Fly", exerciseId: nil, sets: 3, reps: 12, suggestedWeight: 30, restSeconds: 60, notes: nil, isSuperset: false, supersetWith: nil)
        ],
        targetDuration: 45,
        restBetweenSets: 60,
        isCompleted: false
    )
    
    let testProgram = SmartActiveProgram(
        id: "test",
        templateId: "ppl-classic",
        userId: "user",
        personalizedName: "Classic PPL",
        startDate: Date(),
        currentDay: 1,
        completedDays: [],
        generatedDays: [testDay],
        isCompleted: false,
        completedDate: nil,
        totalVolume: 0,
        averageIntensity: 0,
        consistencyScore: 1.0
    )
    
    NavigationStack {
        SmartProgramDayPreviewView(
            program: testProgram,
            day: testDay,
            programName: "Classic PPL",
            totalDays: 42
        )
        .environmentObject(WorkoutManager.shared)
        .environmentObject(UserManager.shared)
    }
}

