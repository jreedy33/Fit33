import SwiftUI
import CoreData

// MARK: - Smart Workout Preview View
/// Shows a preview of a dynamically generated workout day with the option to start

struct SmartWorkoutPreviewView: View {
    let day: DynamicProgramGenerator.GeneratedProgramDay
    let program: DynamicProgramGenerator.GeneratedProgram
    
    @EnvironmentObject var generatedProgramService: GeneratedProgramService
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    @State private var navigateToActiveWorkout = false
    @State private var createdWorkout: Workout?
    @State private var createdExercises: [Exercise] = []
    
    private var programColor: Color {
        switch program.programType {
        case .hypertrophy: return .blue
        case .strength: return .red
        case .fatLoss: return .orange
        case .toning: return .purple
        case .generalFitness: return .green
        case .powerbuilding: return .yellow
        }
    }
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: colorScheme == .dark
                    ? [programColor.opacity(0.2), programColor.opacity(0.05), Color(red: 0.05, green: 0.05, blue: 0.07)]
                    : [programColor.opacity(0.3), programColor.opacity(0.1), Color.white]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    headerSection
                    
                    // Workout Info
                    workoutInfoCard
                    
                    // Exercise List
                    exerciseListSection
                    
                    // Spacer for bottom button
                    Spacer().frame(height: 80)
                }
                .padding()
            }
            
            // Start Button at bottom
            VStack {
                Spacer()
                startButton
            }
        }
        .navigationTitle("Day \(day.dayNumber)")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToActiveWorkout) {
            if let workout = createdWorkout {
                ActiveWorkoutView(isPresented: $navigateToActiveWorkout, workout: workout, exercises: createdExercises)
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            // Day badge
            HStack {
                Text("Day \(day.dayNumber)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 6)
                    .background(programColor)
                    .clipShape(Capsule())
                
                if day.weekNumber > 1 {
                    Text("Week \(day.weekNumber)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // Workout name
            Text(day.name)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Focus muscles
            HStack {
                ForEach(day.focusMuscles.prefix(3), id: \.self) { muscle in
                    Text(muscle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, Spacing.xxs)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                }
                Spacer()
            }
        }
    }
    
    // MARK: - Workout Info Card
    
    private var workoutInfoCard: some View {
        HStack(spacing: 20) {
            // Exercises count
            VStack(spacing: 4) {
                Image(systemName: "dumbbell.fill")
                    .font(.title2)
                    .foregroundColor(programColor)
                Text("\(day.exercises.count)")
                    .font(.title3)
                    .fontWeight(.bold)
                Text("Exercises")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            
            Divider()
                .frame(height: 50)
            
            // Duration
            VStack(spacing: 4) {
                Image(systemName: "clock.fill")
                    .font(.title2)
                    .foregroundColor(programColor)
                Text("~\(day.estimatedDuration)")
                    .font(.title3)
                    .fontWeight(.bold)
                Text("Minutes")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            
            Divider()
                .frame(height: 50)
            
            // Intensity
            VStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.title2)
                    .foregroundColor(programColor)
                Text(day.intensity)
                    .font(.title3)
                    .fontWeight(.bold)
                Text("Intensity")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.cardBackground)
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        )
    }
    
    // MARK: - Exercise List Section
    
    private var exerciseListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Exercises")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            ForEach(Array(day.exercises.enumerated()), id: \.element.id) { index, exercise in
                SmartExercisePreviewRow(
                    exercise: exercise,
                    index: index + 1,
                    color: programColor
                )
            }
        }
    }
    
    // MARK: - Start Button
    
    private var startButton: some View {
        Button(action: startWorkout) {
            HStack {
                Image(systemName: "play.fill")
                    .font(.headline)
                Text("GO!")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .background(
                LinearGradient(
                    colors: [programColor, programColor.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: programColor.opacity(0.4), radius: 12, x: 0, y: 6)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
    
    // MARK: - Start Workout Action
    
    private func startWorkout() {
        // Convert generated day to Core Data workout
        let (workout, exercises) = generatedProgramService.createWorkout(from: day, context: viewContext)
        
        // Save context
        do {
            try viewContext.save()
            createdWorkout = workout
            createdExercises = exercises
            navigateToActiveWorkout = true
        } catch {
            AppLogger.error("❌ Error creating workout: \(error)", category: .workout)
        }
    }
}

// MARK: - Exercise Preview Row

struct SmartExercisePreviewRow: View {
    let exercise: DynamicProgramGenerator.GeneratedExercise
    let index: Int
    let color: Color
    @Environment(\.colorScheme) private var colorScheme
    
    // Category-based gradients matching exercise library style
    private var categoryGradient: [Color] {
        [color, color.opacity(0.7)]
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
                    Text("\(exercise.sets) sets × \(exercise.repsMin)-\(exercise.repsMax) reps")
                        .font(.caption)
                        .foregroundColor(color)
                        .fontWeight(.medium)
                    
                    if let rpe = exercise.targetRPE {
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("RPE \(rpe)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
            }
            
            Spacer()
            
            // Rest time badge
            HStack(spacing: 4) {
                Image(systemName: "timer")
                    .font(.ds_caption)
                Text("\(exercise.restSeconds)s")
                    .font(.caption)
            }
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
}

// MARK: - Preview

#if DEBUG
struct SmartWorkoutPreviewView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            SmartWorkoutPreviewView(
                day: DynamicProgramGenerator.GeneratedProgramDay(
                    id: "test",
                    dayNumber: 1,
                    weekNumber: 1,
                    name: "Push Day",
                    focusMuscles: ["Chest", "Shoulders", "Triceps"],
                    exercises: [
                        DynamicProgramGenerator.GeneratedExercise(
                            id: "1",
                            exerciseName: "Barbell Bench Press",
                            exerciseId: nil,
                            order: 1,
                            sets: 4,
                            repsMin: 8,
                            repsMax: 12,
                            restSeconds: 90,
                            targetRPE: 8,
                            notes: nil,
                            isWarmup: false,
                            supersetGroup: nil,
                            isAnchor: true,
                            movementPattern: "horizontal_press"
                        )
                    ],
                    estimatedDuration: 45,
                    intensity: "Moderate",
                    isCompleted: false,
                    completedAt: nil,
                    notes: nil
                ),
                program: DynamicProgramGenerator.GeneratedProgram(
                    id: "test",
                    name: "Test Program",
                    description: "Test",
                    icon: "dumbbell.fill",
                    color: "blue",
                    programType: .hypertrophy,
                    splitType: .pushPullLegs,
                    durationWeeks: 4,
                    daysPerWeek: 4,
                    difficulty: "Intermediate",
                    targetGoals: ["Build Muscle"],
                    requiredEquipment: ["Dumbbells"],
                    benefits: [],
                    muscleGroupRotation: [],
                    generatedDays: [],
                    isActive: true,
                    createdAt: Date()
                )
            )
        }
    }
}
#endif

