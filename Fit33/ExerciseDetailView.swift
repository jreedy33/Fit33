import SwiftUI
import AVKit
import CoreData
import UIKit

struct ExerciseDetailView: View {
    let exercise: Exercise
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var workoutManager = WorkoutManager.shared
    
    // User history data
    @State private var personalRecord: (weight: Double, reps: Int, date: Date)?
    @State private var lastPerformance: (weight: Double, reps: Int, sets: Int, date: Date)?
    @State private var totalTimesPerformed: Int = 0
    @State private var hasLoadedHistory = false
    
    // Favorite state
    @State private var isFavorite: Bool = false
    
    
    // Extract primary and secondary muscles from exercise data
    private var primaryMuscle: String {
        // Try to get from muscleGroups array first
        if let muscleGroups = exercise.muscleGroups as? [String], let first = muscleGroups.first {
            return first
        }
        return exercise.category ?? "General"
    }
    
    private var secondaryMuscles: [String] {
        if let muscleGroups = exercise.muscleGroups as? [String], muscleGroups.count > 1 {
            // Remove duplicates by converting to Set and back
            // This fixes ForEach "duplicate ID" warnings
            let uniqueMuscles = Array(Set(muscleGroups.dropFirst()))
            return uniqueMuscles.sorted() // Sort for consistent display order
        }
        return []
    }
    
    private var exerciseDescriptionText: String? {
        // First try the new exerciseDescription field
        if let desc = exercise.exerciseDescription, !desc.isEmpty {
            return desc
        }
        
        // Fallback to instructions if no description
        guard let instructions = exercise.instructions, !instructions.isEmpty else { return nil }
        
        // Check if it looks like a description (not numbered steps)
        if !instructions.contains("1.") && !instructions.contains("2.") {
            return instructions
        }
        
        // Try to extract description before numbered steps
        if let range = instructions.range(of: "1.") {
            let beforeSteps = String(instructions[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if beforeSteps.count > 20 {
                return beforeSteps
            }
        }
        
        return nil
    }
    
    // Parse steps from stepsToPerform field
    private var howToSteps: [String] {
        guard let stepsText = exercise.stepsToPerform, !stepsText.isEmpty else {
            return []
        }
        
        // Pattern: "1. Step text 2. Step text" etc.
        // Split using regex to find "N. " patterns
        var steps: [String] = []
        
        // Use a simple approach: split by " N. " where N is 1-9
        var workingText = stepsText
        
        // First, try to split by the pattern "N. " at the start of steps
        let stepPatterns = [" 2. ", " 3. ", " 4. ", " 5. ", " 6. ", " 7. ", " 8. ", " 9. ", " 10. "]
        var segments: [String] = []
        
        // Remove the "1. " prefix if present
        if workingText.hasPrefix("1. ") {
            workingText = String(workingText.dropFirst(3))
        }
        
        // Split by step markers
        for pattern in stepPatterns {
            if let range = workingText.range(of: pattern) {
                let segment = String(workingText[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !segment.isEmpty {
                    segments.append(segment)
                }
                workingText = String(workingText[range.upperBound...])
            }
        }
        
        // Add the remaining text as the last step
        let lastSegment = workingText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !lastSegment.isEmpty {
            segments.append(lastSegment)
        }
        
        // If we got segments, use them
        if !segments.isEmpty {
            steps = segments
        } else {
            // Fallback: if no numbered steps found, return the whole text as one step
            steps = [stepsText]
        }
        
        return steps
    }
    
    private var categoryColor: Color {
        guard let category = exercise.category else { return .cyan }
        switch category.lowercased() {
        case "chest": return .red
        case "back": return .blue
        case "legs": return .green
        case "shoulders": return .orange
        case "arms": return .purple
        case "core": return .pink
        case "neck": return .indigo
        case "full body": return .cyan
        case "cardio": return Color(red: 1.0, green: 0.4, blue: 0.4)
        case "stretching", "plyometrics": return .teal
        default: return .cyan
        }
    }
    
    private var categoryIcon: String {
        guard let category = exercise.category else { return "figure.strengthtraining.traditional" }
        switch category.lowercased() {
        case "chest": return "heart.fill"
        case "back": return "figure.strengthtraining.traditional"
        case "legs": return "figure.walk"
        case "shoulders": return "figure.arms.open"
        case "arms": return "hand.raised.fill"
        case "core": return "circle.circle"
        case "neck": return "person.crop.circle"
        case "full body": return "figure.run"
        case "cardio": return "heart.circle.fill"
        case "stretching": return "figure.flexibility"
        case "plyometrics": return "arrow.up.and.down"
        default: return "figure.strengthtraining.traditional"
        }
    }
    
    // Background color to match video area - pure white to match video content
    private var videoBackgroundColor: Color {
        .white
    }
    
    // Gradient background colors
    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(red: 0.06, green: 0.08, blue: 0.12), Color(red: 0.04, green: 0.05, blue: 0.08)]
                : [Color(red: 0.95, green: 0.97, blue: 1.0), Color.white],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            // Animated blue/cyan orb background (consistent with other tabs)
            AnimatedOrbBackground.exercises(colorScheme: colorScheme)
                .ignoresSafeArea()
            
            // Main content
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Spacer for navigation buttons (back + favorite)
                    Color.clear.frame(height: 56)
                    
                    // Video Section (with stable ID to prevent recreation)
                    videoSection
                    
                    // Content Section
                    VStack(alignment: .leading, spacing: 20) {
                        // Exercise Name & Badges
                        headerSection
                        
                        // User's Personal Stats (if they have history)
                        if hasLoadedHistory && (personalRecord != nil || lastPerformance != nil) {
                            userStatsSection
                        }
                        
                        // Exercise Description
                        if let description = exerciseDescriptionText {
                            descriptionSection(description)
                        }
                        
                        // How To Section
                        if !howToSteps.isEmpty {
                            howToSection
                        }
                        
                        // Target Muscles & Equipment in 2-column grid
                        HStack(alignment: .top, spacing: 12) {
                            muscleSection
                            equipmentSection
                        }
                        
                        // Add to Workout button
                        addToWorkoutButton
                        
                        // Bottom padding for tab bar
                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, 20)
                }
            }
            .scrollIndicators(.hidden)
            
            // Navigation buttons row (back + favorite)
            HStack {
                // Custom back button in safe area with glass effect
                Button(action: {
                    HapticManager.tap()
                    dismiss()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(width: 40, height: 40)
                        .background(
                            ZStack {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                Circle()
                                    .fill(Color.white.opacity(0.9))
                                Circle()
                                    .stroke(Color.white.opacity(0.5), lineWidth: 0.5)
                            }
                        )
                        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 2)
                }
                
                Spacer()
                
                // Favorite star button
                Button(action: toggleFavorite) {
                    ZStack {
                        // Black outline behind the filled star for visibility
                        if isFavorite {
                            Image(systemName: "star.fill")
                                .font(.ds_heading3)
                                .foregroundColor(.black.opacity(0.5))
                                .offset(x: 0.3, y: 0.3) // Slight offset for shadow-like outline
                        }
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(isFavorite ? .yellow : .black)
                    }
                    .frame(width: 40, height: 40)
                    .background(
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                            Circle()
                                .fill(Color.white.opacity(0.9))
                            Circle()
                                .stroke(isFavorite ? Color.yellow.opacity(0.4) : Color.white.opacity(0.5), lineWidth: 0.5)
                        }
                    )
                    .shadow(color: isFavorite ? .yellow.opacity(0.3) : .black.opacity(0.15), radius: 8, x: 0, y: 2)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, 8)
        }
        .ignoresSafeArea(edges: .bottom)
        .navigationBarHidden(true)
        .gesture(
            DragGesture(minimumDistance: 30, coordinateSpace: .local)
                .onEnded { value in
                    if value.startLocation.x < 50 && value.translation.width > 80 {
                        HapticManager.tap()
                        dismiss()
                    }
                }
        )
        .onAppear {
            SessionLogManager.shared.logScreen(.exerciseDetail, metadata: [
                "exercise_name": exercise.name,
                "exercise_id": exercise.id?.uuidString ?? "unknown"
            ])
            loadUserHistory()
            
            // Initialize favorite state
            isFavorite = exercise.isFavorite
            
            if let name = exercise.name {
                VideoPlaybackEngine.shared.priorityPrefetch(exerciseName: name)
                
                if !VideoThumbnailService.shared.hasPosterFrame(for: name),
                   let url = VideoStreamingService.shared.getVideoURL(for: name) {
                    VideoThumbnailService.shared.generatePosterFrame(exerciseName: name, videoURL: url)
                }
            }
        }
    }
    
    // MARK: - Toggle Favorite
    
    private func toggleFavorite() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            isFavorite.toggle()
            HapticManager.impact(.medium)
            
            // Update Core Data
            let fetchRequest: NSFetchRequest<Exercise> = Exercise.fetchRequest()
            if let exerciseId = exercise.id {
                fetchRequest.predicate = NSPredicate(format: "id == %@", exerciseId as CVarArg)
            } else if let exerciseName = exercise.name {
                fetchRequest.predicate = NSPredicate(format: "name == %@", exerciseName)
            }
            fetchRequest.fetchLimit = 1
            
            do {
                if let freshExercise = try viewContext.fetch(fetchRequest).first {
                    freshExercise.isFavorite = isFavorite
                    try viewContext.save()
                    print("⭐ Exercise '\(freshExercise.name ?? "")' favorite status: \(isFavorite)")
                    
                    // Record favorite for variant rotation
                    let exerciseFamily = freshExercise.value(forKey: "exerciseFamily") as? String ?? ""
                    Task { @MainActor in
                        if isFavorite {
                            SmartVariantRotationEngine.shared.recordFavorite(
                                exerciseName: freshExercise.name ?? "",
                                family: exerciseFamily
                            )
                            VideoPlaybackEngine.shared.addToFavorites(freshExercise.name ?? "")
                            ProgressiveExerciseUnlockService.shared.recordFavorite(exerciseName: freshExercise.name ?? "")
                        } else {
                            SmartVariantRotationEngine.shared.recordUnfavorite(
                                exerciseName: freshExercise.name ?? "",
                                family: exerciseFamily
                            )
                            VideoPlaybackEngine.shared.removeFromFavorites(freshExercise.name ?? "")
                        }
                    }
                    
                    // Sync to cloud if authenticated
                    if SupabaseManager.shared.isAuthenticated {
                        Task {
                            do {
                                try await SupabaseManager.shared.toggleFavorite(
                                    exerciseId: freshExercise.id?.uuidString ?? "",
                                    exerciseType: "default",
                                    exerciseName: freshExercise.name
                                )
                            } catch {
                                print("❌ Error syncing favorite to cloud: \(error)")
                            }
                        }
                    }
                }
            } catch {
                print("❌ Error toggling favorite: \(error)")
                // Revert on error
                isFavorite.toggle()
            }
        }
    }
    
    // MARK: - Add to Workout Button
    
    private var addToWorkoutButton: some View {
        Button(action: addToWorkout) {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.ds_heading3).fontWeight(.semibold)
                
                Text("Add to Workout")
                    .font(.system(size: 17, weight: .semibold))
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.ds_labelMedium)
                    .foregroundColor(.white.opacity(0.7))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, Spacing.md)
            .background(
                ZStack {
                    // Gradient background
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [categoryColor, categoryColor.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    // Subtle shine overlay
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.2), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
            )
            .shadow(color: categoryColor.opacity(0.4), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.top, 8)
    }
    
    private func addToWorkout() {
        HapticManager.impact(.medium)
        
        // Set the exercise to be pre-selected in the custom workout builder
        workoutManager.exerciseToAddToCustomWorkout = exercise
        
        // Dismiss this view and navigate to custom workout builder
        // Small delay to ensure smooth transition
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            dismiss()
            // Trigger navigation to custom workout builder via WorkoutManager
            workoutManager.shouldNavigateToCustomWorkoutBuilder = true
        }
        
        print("➕ Adding exercise to custom workout: \(exercise.name ?? "Unknown")")
    }
    
    // MARK: - Video Section
    
    private var videoSection: some View {
        // Video inside a 3D floating card — matches app widget/card style
        RemoteVideoPlayerView(
            exerciseName: exercise.name ?? "",
            categoryColor: categoryColor,
            videoFilename: exercise.videoFilename
        )
        .id(exercise.id) // Stable ID prevents video from being recreated
        .aspectRatio(16/9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.blue.opacity(colorScheme == .dark ? 0.15 : 0.08))
                    .offset(y: 10)
                    .blur(radius: 6)
                
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.25 : 0.05))
                    .offset(y: 5)
                
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color(white: 0.18), Color.cardBackground]
                                : [Color.white, Color.white.opacity(0.95)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color.white.opacity(0.1), Color.white.opacity(0.02), Color.clear]
                                : [Color.white, Color.white.opacity(0.5), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.5
                    )
                
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.blue.opacity(colorScheme == .dark ? 0.4 : 0.25),
                                Color.blue.opacity(colorScheme == .dark ? 0.2 : 0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.blue.opacity(colorScheme == .dark ? 0.35 : 0.2), lineWidth: 1.5)
                .blur(radius: 4)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.1), radius: 16, x: 0, y: 8)
        .shadow(color: Color.blue.opacity(colorScheme == .dark ? 0.35 : 0.2), radius: 20, x: 0, y: 4)
        .shadow(color: Color.blue.opacity(colorScheme == .dark ? 0.25 : 0.15), radius: 30, x: 0, y: 0)
        .padding(.horizontal, Spacing.md)
        .padding(.top, 8)
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Exercise Name with gradient text - auto-sized to fit without truncation
            Text(exercise.displayName)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.primary, .primary.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .lineLimit(2)
            
            // Badges Row
            HStack(spacing: 10) {
                // Category Badge with glow
                categoryBadge
                
                // Equipment Badge
                equipmentBadge
                
                // Times Performed Badge (if any)
                if totalTimesPerformed > 0 {
                    performedBadge
                }
                
                Spacer()
            }
        }
        .padding(.vertical, Spacing.xxs)
    }
    
    private var categoryBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: categoryIcon)
                .font(.ds_labelMedium)
            Text(exercise.category ?? "General")
                .font(.ds_labelMedium)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, Spacing.xs)
        .background(
            ZStack {
                // Glow layer
                Capsule()
                    .fill(categoryColor)
                    .blur(radius: 8)
                    .opacity(0.5)
                
                // Main gradient
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [categoryColor, categoryColor.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .shadow(color: categoryColor.opacity(0.5), radius: 10, x: 0, y: 4)
    }
    
    private var equipmentBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "dumbbell.fill")
                .font(.ds_bodySmall)
            Text(exercise.equipment ?? "Bodyweight")
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundColor(colorScheme == .dark ? .white : .primary)
        .padding(.horizontal, 14)
        .padding(.vertical, Spacing.xs)
        .background(
            Capsule()
                .fill(Color.cardBackground)
                .overlay(
                    Capsule()
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
                )
        )
    }
    
    private var performedBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.ds_bodySmall)
            Text("\(totalTimesPerformed)×")
                .font(.ds_labelMedium)
        }
        .foregroundColor(.green)
        .padding(.horizontal, 14)
        .padding(.vertical, Spacing.xs)
        .background(
            Capsule()
                .fill(Color.green.opacity(0.15))
                .overlay(
                    Capsule()
                        .stroke(Color.green.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    // MARK: - User Stats Section
    
    private var userStatsSection: some View {
        VStack(spacing: 14) {
            // Section Header
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [categoryColor, categoryColor.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)
                        .shadow(color: categoryColor.opacity(0.4), radius: 6, x: 0, y: 3)
                    
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.ds_labelMedium)
                        .foregroundColor(.white)
                }
                
                Text("Your Progress")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                Spacer()
            }
            
            HStack(spacing: 12) {
                // Personal Record Card
                if let pr = personalRecord {
                    prCard(weight: pr.weight, reps: pr.reps, date: pr.date)
                }
                
                // Last Performance Card
                if let last = lastPerformance {
                    lastPerformanceCard(weight: last.weight, reps: last.reps, sets: last.sets, date: last.date)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color(white: 0.14), Color(white: 0.10)]
                            : [Color.white, Color.white.opacity(0.95)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                colors: [categoryColor.opacity(0.35), categoryColor.opacity(0.1), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: categoryColor.opacity(0.2), radius: 20, x: 0, y: 10)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 10, x: 0, y: 5)
        )
    }
    
    private func prCard(weight: Double, reps: Int, date: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // PR Label with flame
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.ds_bodySmall)
                    .foregroundColor(.orange)
                Text("PR")
                    .font(.ds_bodySmall).fontWeight(.bold)
                    .foregroundColor(.orange)
            }
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxs)
            .background(
                Capsule()
                    .fill(Color.orange.opacity(0.15))
            )
            
            // Weight & Reps (preserve decimals like 180.5)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(formatWeight(weight))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("lbs")
                    .font(.ds_bodySmall).fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            
            Text("× \(reps) reps")
                .font(.ds_bodySmall).fontWeight(.medium)
                .foregroundColor(.secondary)
            
            // Date
            Text(formatRelativeDate(date))
                .font(.ds_labelSmall)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    LinearGradient(
                        colors: [Color.orange.opacity(0.1), Color.orange.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    private func lastPerformanceCard(weight: Double, reps: Int, sets: Int, date: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Recent Label
            HStack(spacing: 4) {
                Image(systemName: "clock.fill")
                    .font(.ds_bodySmall)
                    .foregroundColor(categoryColor)
                Text("Recent")
                    .font(.ds_bodySmall).fontWeight(.bold)
                    .foregroundColor(categoryColor)
            }
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxs)
            .background(
                Capsule()
                    .fill(categoryColor.opacity(0.15))
            )
            
            // Weight & Reps (preserve decimals like 180.5)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(formatWeight(weight))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("lbs")
                    .font(.ds_bodySmall).fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            
            Text("\(sets) sets × \(reps) reps")
                .font(.ds_bodySmall).fontWeight(.medium)
                .foregroundColor(.secondary)
            
            // Date
            Text(formatRelativeDate(date))
                .font(.ds_labelSmall)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    LinearGradient(
                        colors: [categoryColor.opacity(0.1), categoryColor.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(categoryColor.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Description Section
    
    private func descriptionSection(_ description: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(categoryColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: "text.alignleft")
                        .font(.ds_labelMedium)
                        .foregroundColor(categoryColor)
                }
                Text("About")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                Spacer()
            }
            
            Text(description)
                .font(.ds_bodyMedium)
                .foregroundColor(.secondary)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color(white: 0.14), Color(white: 0.10)]
                            : [Color.white, Color.white.opacity(0.95)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                colors: [categoryColor.opacity(0.3), categoryColor.opacity(0.1), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: categoryColor.opacity(0.15), radius: 15, x: 0, y: 8)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 10, x: 0, y: 5)
        )
    }
    
    // MARK: - How To Section
    
    private var howToSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section Header
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(categoryColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: "list.number")
                        .font(.ds_labelMedium)
                        .foregroundColor(categoryColor)
                }
                Text("How To Perform")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                Spacer()
            }
            
            // Steps List with gradient connector
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(howToSteps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 14) {
                        // Step Number with gradient
                        VStack(spacing: 0) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [categoryColor, categoryColor.opacity(0.7)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 30, height: 30)
                                    .shadow(color: categoryColor.opacity(0.4), radius: 6, x: 0, y: 3)
                                
                                Text("\(index + 1)")
                                    .font(.ds_bodySmall).fontWeight(.bold).fontDesign(.rounded)
                                    .foregroundColor(.white)
                            }
                            
                            // Connector line (except for last item)
                            if index < howToSteps.count - 1 {
                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            colors: [categoryColor.opacity(0.3), categoryColor.opacity(0.1)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(width: 2)
                                    .frame(maxHeight: .infinity)
                            }
                        }
                        
                        // Step Text
                        Text(step)
                            .font(.ds_bodyMedium)
                            .foregroundColor(.primary.opacity(0.9))
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, index < howToSteps.count - 1 ? 16 : 0)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color(white: 0.14), Color(white: 0.10)]
                            : [Color.white, Color.white.opacity(0.95)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                colors: [categoryColor.opacity(0.25), categoryColor.opacity(0.08), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: categoryColor.opacity(0.12), radius: 15, x: 0, y: 8)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 10, x: 0, y: 5)
        )
    }
    
    // MARK: - Muscle Section
    
    private var muscleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.ds_labelMedium)
                    .foregroundColor(categoryColor)
                Text("Muscles")
                    .font(.ds_bodySmall).fontWeight(.bold)
                    .foregroundColor(.primary)
            }
            
            // Primary
            HStack(spacing: 6) {
                Circle()
                    .fill(categoryColor)
                    .frame(width: 8, height: 8)
                Text(primaryMuscle)
                    .font(.ds_labelMedium)
                    .foregroundColor(.primary)
            }
            
            // Secondary (compact)
            if !secondaryMuscles.isEmpty {
                Text(secondaryMuscles.prefix(2).joined(separator: ", "))
                    .font(.ds_bodySmall)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color(white: 0.14), Color(white: 0.10)]
                            : [Color.white, Color.white.opacity(0.95)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.lg)
                        .stroke(categoryColor.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: categoryColor.opacity(0.1), radius: 8, x: 0, y: 4)
        )
    }
    
    // MARK: - Equipment Section
    
    private var equipmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "dumbbell.fill")
                    .font(.ds_labelMedium)
                    .foregroundColor(categoryColor)
                Text("Equipment")
                    .font(.ds_bodySmall).fontWeight(.bold)
                    .foregroundColor(.primary)
            }
            
            // Icon & Name
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(categoryColor.opacity(0.15))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: equipmentIcon)
                        .font(.ds_bodyRegular)
                        .foregroundColor(categoryColor)
                }
                
                Text(exercise.equipment ?? "Bodyweight")
                    .font(.ds_labelMedium)
                    .foregroundColor(.primary)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color(white: 0.14), Color(white: 0.10)]
                            : [Color.white, Color.white.opacity(0.95)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.lg)
                        .stroke(categoryColor.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: categoryColor.opacity(0.1), radius: 8, x: 0, y: 4)
        )
    }
    
    private var equipmentIcon: String {
        guard let equipment = exercise.equipment?.lowercased() else { return "figure.walk" }
        switch equipment {
        case "bodyweight": return "figure.walk"
        case "dumbbells", "dumbbell": return "dumbbell.fill"
        case "barbell": return "figure.strengthtraining.traditional"
        case "cables", "cable": return "cable.coaxial"
        case "machines", "machine": return "gearshape.2.fill"
        case "kettlebell": return "circle.fill"
        case "resistance bands", "band": return "lines.measurement.horizontal"
        case "bench": return "rectangle.fill"
        case "stability ball", "ball": return "circle"
        case "medicine ball": return "basketball.fill"
        case "foam roller": return "capsule.fill"
        default: return "dumbbell.fill"
        }
    }
    
    private var equipmentDescription: String {
        guard let equipment = exercise.equipment?.lowercased() else { return "No equipment needed" }
        switch equipment {
        case "bodyweight": return "No equipment needed"
        case "dumbbells", "dumbbell": return "Free weights for each hand"
        case "barbell": return "Long bar with weight plates"
        case "cables", "cable": return "Cable machine with attachments"
        case "machines", "machine": return "Gym machines for isolation"
        case "kettlebell": return "Cast iron weight with handle"
        case "resistance bands", "band": return "Elastic resistance training"
        case "bench": return "Flat or adjustable bench"
        case "stability ball", "ball": return "Exercise ball for core work"
        default: return "Standard gym equipment"
        }
    }
    
    // MARK: - Helper Functions
    
    private func loadUserHistory() {
        guard !hasLoadedHistory else { return }
        hasLoadedHistory = true
        
        // Fetch all workout exercises for this exercise
        guard let exerciseName = exercise.name else { return }
        
        let request: NSFetchRequest<WorkoutExercise> = WorkoutExercise.fetchRequest()
        request.predicate = NSPredicate(format: "exercise.name == %@ AND workout.isCompleted == YES", exerciseName)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \WorkoutExercise.workout?.date, ascending: false)]
        
        do {
            let workoutExercises = try viewContext.fetch(request)
            totalTimesPerformed = workoutExercises.count
            
            // Find PR (heaviest weight × reps)
            var bestWeight: Double = 0
            var bestReps: Int = 0
            var bestDate: Date?
            
            // Find most recent performance
            var lastWeight: Double = 0
            var lastReps: Int = 0
            var lastSets: Int = 0
            var lastDate: Date?
            
            for (index, we) in workoutExercises.enumerated() {
                guard let sets = we.sets?.allObjects as? [WorkoutSet] else { continue }
                let completedSets = sets.filter { $0.isCompleted }
                
                for set in completedSets {
                    // Track PR (highest weight with at least 1 rep)
                    if set.weight > bestWeight && set.reps > 0 {
                        bestWeight = set.weight
                        bestReps = Int(set.reps)
                        bestDate = we.workout?.date
                    }
                }
                
                // Track most recent (first in array since sorted by date desc)
                if index == 0, !completedSets.isEmpty {
                    // Get the average/typical performance from the most recent workout
                    if let heaviestSet = completedSets.max(by: { $0.weight < $1.weight }) {
                        lastWeight = heaviestSet.weight
                        lastReps = Int(heaviestSet.reps)
                        lastSets = completedSets.count
                        lastDate = we.workout?.date
                    }
                }
            }
            
            // Set PR if found
            if bestWeight > 0, let date = bestDate {
                personalRecord = (weight: bestWeight, reps: bestReps, date: date)
            }
            
            // Set last performance if found
            if lastWeight > 0, let date = lastDate {
                lastPerformance = (weight: lastWeight, reps: lastReps, sets: lastSets, date: date)
            }
            
        } catch {
            print("❌ Error loading exercise history: \(error)")
        }
    }
    
    /// Format weight preserving decimals when needed (e.g., 180.5 → "180.5", 180.0 → "180")
    private func formatWeight(_ weight: Double) -> String {
        if weight.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(weight))"
        } else {
            return String(format: "%.1f", weight)
        }
    }
    
    private func formatRelativeDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let days = calendar.dateComponents([.day], from: date, to: now).day ?? 0
            if days < 7 {
                return "\(days) days ago"
            } else if days < 30 {
                let weeks = days / 7
                return weeks == 1 ? "1 week ago" : "\(weeks) weeks ago"
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM d"
                return formatter.string(from: date)
            }
        }
    }
}

// MARK: - Video Player Manager

class VideoPlayerManager: ObservableObject {
    @Published var player: AVPlayer?
    
    private var queuePlayer: AVQueuePlayer?
    private var playerLooper: AVPlayerLooper?  // ⚡️ CRITICAL: Must store looper reference or it gets deallocated
    
    func setupPlayer(with url: URL) {
        let asset = AVURLAsset(url: url, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: false
        ])
        
        let playerItem = AVPlayerItem(asset: asset, automaticallyLoadedAssetKeys: ["playable"])
        playerItem.preferredForwardBufferDuration = 3
        
        // Use AVQueuePlayer + AVPlayerLooper for seamless looping
        let qp = AVQueuePlayer(playerItem: playerItem)
        self.playerLooper = AVPlayerLooper(player: qp, templateItem: playerItem)
        
        qp.automaticallyWaitsToMinimizeStalling = false
        qp.play()
        
        self.queuePlayer = qp
        self.player = qp
    }
    
    func pause() {
        player?.pause()
    }
    
    func play() {
        player?.play()
    }
    
    deinit {
        playerLooper?.disableLooping()
        queuePlayer?.pause()
    }
}

// MARK: - Native-Style Back Button (No Blur)

struct NativeStyleBackButton: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Button(action: {
            HapticManager.tap()
            dismiss()
        }) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                Text("Back")
                    .font(.ds_bodyLarge)
            }
            .foregroundColor(.blue) // iOS blue
        }
    }
}

// MARK: - Custom Back Button (Liquid Glass Effect)

struct BackButton: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: {
            HapticManager.tap()
            dismiss()
        }) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .frame(width: 40, height: 40)
                .background(
                    ZStack {
                        // Liquid glass effect
                        Circle()
                            .fill(.ultraThinMaterial)
                        
                        // Subtle border
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                        
                        // Inner glow for depth
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color.white.opacity(0.15),
                                        Color.clear
                                    ],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 20
                                )
                            )
                    }
                )
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 2)
        }
    }
}

// MARK: - Scroll Offset Tracking

struct ExerciseDetailScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Dark Status Bar Area

struct DarkStatusBarArea: View {
    var body: some View {
        Color.white
            .overlay(
                StatusBarStyleSetter()
                    .frame(width: 0, height: 0)
            )
    }
}

struct StatusBarStyleSetter: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> StatusBarHostController {
        StatusBarHostController()
    }
    
    func updateUIViewController(_ uiViewController: StatusBarHostController, context: Context) {
        uiViewController.setNeedsStatusBarAppearanceUpdate()
    }
    
    class StatusBarHostController: UIViewController {
        override var preferredStatusBarStyle: UIStatusBarStyle {
            .darkContent
        }
        
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            setNeedsStatusBarAppearanceUpdate()
            
            // Also try to update the navigation controller
            navigationController?.setNeedsStatusBarAppearanceUpdate()
            
            // And the presenting controller
            presentingViewController?.setNeedsStatusBarAppearanceUpdate()
        }
    }
}

// MARK: - Video Mapping Function

// MARK: - Status Bar Styler

struct StatusBarStyler: UIViewControllerRepresentable {
    let statusBarStyle: UIStatusBarStyle
    
    func makeUIViewController(context: Context) -> StatusBarViewController {
        StatusBarViewController(statusBarStyle: statusBarStyle)
    }
    
    func updateUIViewController(_ uiViewController: StatusBarViewController, context: Context) {
        uiViewController.statusBarStyle = statusBarStyle
    }
}

class StatusBarViewController: UIViewController {
    var statusBarStyle: UIStatusBarStyle {
        didSet {
            print("📊 [STATUS BAR] Style changed to: \(statusBarStyle == .darkContent ? "dark content" : "default")")
            setNeedsStatusBarAppearanceUpdate()
        }
    }
    
    init(statusBarStyle: UIStatusBarStyle) {
        self.statusBarStyle = statusBarStyle
        super.init(nibName: nil, bundle: nil)
        print("📊 [STATUS BAR] Controller init with style: \(statusBarStyle == .darkContent ? "dark content" : "default")")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        print("📊 [STATUS BAR] Returning preferredStatusBarStyle: \(statusBarStyle == .darkContent ? "dark content" : "default")")
        return statusBarStyle
    }
    
    override var prefersStatusBarHidden: Bool {
        return false
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        print("📊 [STATUS BAR] viewDidLoad - requesting update")
        setNeedsStatusBarAppearanceUpdate()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        print("📊 [STATUS BAR] viewDidAppear - requesting update")
        setNeedsStatusBarAppearanceUpdate()
    }
}

func createExerciseVideoMapping() -> [String: String] {
    return [
        "3 4 Sit Up": "00011201-3-4-Sit-up_Waist-FIX_.mp4",
        "Air Bike (Male)": "00031201-Air-Bike-(male)_Waist-FIX_.mp4",
        "Barbell Behind Back Finger Curl": "16101201-Barbell-Behind-Back-Finger-Curl_Forearms-FIX_.mp4",
        // ... keeping existing mapping for legacy videos
    ]
}
