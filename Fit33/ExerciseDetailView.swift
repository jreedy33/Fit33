import SwiftUI
import AVKit
import CoreData
import UIKit

struct ExerciseDetailView: View {
    // @ObservedObject so CMS realtime edits (ExerciseLibraryService
    // .upsertExerciseFromCloud → ctx.save()) re-render this view
    // instantly instead of only on next navigation. NSManagedObject
    // conforms to ObservableObject via KVO; a plain `let` capture
    // swallows the change notification.
    @ObservedObject var exercise: Exercise
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
    
    var body: some View {
        ZStack(alignment: .top) {
            // Animated orb background consistent with Exercises tab
            AnimatedOrbBackground.exercises(colorScheme: colorScheme)
                .ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    // Reserve space for floating toolbar (back + favorite)
                    Color.clear.frame(height: 52)
                    
                    videoSection
                    
                    headerSection
                        .padding(.top, Spacing.xxs)
                    
                    addToWorkoutButton
                    
                    if hasLoadedHistory && (personalRecord != nil || lastPerformance != nil) {
                        userStatsSection
                    }
                    
                    if let description = exerciseDescriptionText {
                        descriptionSection(description)
                    }
                    
                    if !howToSteps.isEmpty {
                        howToSection
                    }
                    
                    Spacer(minLength: 100)
                }
                .padding(.horizontal, Spacing.md)
            }
            .scrollIndicators(.hidden)
            
            floatingToolbar
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
            
            // Q2-84 (Sprint 9 2026-04-28): Route through ExerciseLibraryService
            // so name/id normalization lives in one place. The service is
            // viewContext-backed so the returned object is mutable + save-able
            // against `viewContext` without cross-context plumbing.
            let resolved: Exercise? = {
                if let exerciseId = exercise.id {
                    return ExerciseLibraryService.shared.getExercise(byId: exerciseId)
                }
                if let exerciseName = exercise.name {
                    return ExerciseLibraryService.shared.getExercise(byName: exerciseName)
                }
                return nil
            }()

            do {
                if let freshExercise = resolved {
                    freshExercise.isFavorite = isFavorite
                    try viewContext.save()
                    AppLogger.debug("⭐ Exercise '\(freshExercise.name ?? "")' favorite status: \(isFavorite)", category: .workout)
                    
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
                                AppLogger.error("❌ Error syncing favorite to cloud: \(error)", category: .workout)
                            }
                        }
                    }
                }
            } catch {
                AppLogger.error("❌ Error toggling favorite: \(error)", category: .workout)
                // Revert on error
                isFavorite.toggle()
            }
        }
    }
    
    // MARK: - Floating Toolbar (back + favorite)
    
    private var floatingToolbar: some View {
        HStack {
            Button {
                HapticManager.tap()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.ds_labelLarge)
                    .foregroundColor(colorScheme == .dark ? .white : .primary)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Circle()
                                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                            )
                    )
                    .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 2)
            }
            .accessibilityLabel("Back")
            
            Spacer()
            
            Button(action: toggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.ds_labelLarge)
                    .foregroundColor(isFavorite ? .yellow : (colorScheme == .dark ? .white : .primary))
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Circle()
                                    .stroke(
                                        isFavorite ? Color.yellow.opacity(0.4) : Color.primary.opacity(0.1),
                                        lineWidth: 0.5
                                    )
                            )
                    )
                    .shadow(
                        color: isFavorite ? .yellow.opacity(0.28) : .black.opacity(0.12),
                        radius: 6, x: 0, y: 2
                    )
            }
            .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.xs)
    }
    
    // MARK: - Add to Workout Button
    
    private var addToWorkoutButton: some View {
        Button(action: addToWorkout) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "plus.circle.fill")
                    .font(.ds_heading3)
                Text("Add to Workout")
                    .font(.ds_labelLarge)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.ds_labelMedium)
                    .foregroundColor(.white.opacity(0.75))
            }
            .foregroundColor(.white)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [categoryColor, categoryColor.opacity(0.82)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .shadow(color: categoryColor.opacity(0.35), radius: 10, x: 0, y: 5)
        }
        .scaleButtonStyle(.standard, withHaptic: false)
        .accessibilityLabel("Add \(exercise.displayName) to workout")
    }
    
    private func addToWorkout() {
        HapticManager.impact(.medium)
        
        // Set the exercise to be pre-selected in the custom workout builder
        workoutManager.exerciseToAddToCustomWorkout = exercise
        
        // Dismiss this view and navigate to custom workout builder
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.1))
            guard !Task.isCancelled else { return }
            dismiss()
            workoutManager.shouldNavigateToCustomWorkoutBuilder = true
        }
        
        AppLogger.debug("➕ Adding exercise to custom workout: \(exercise.name ?? "Unknown")", category: .workout)
    }
    
    // MARK: - Video Section
    
    private var videoSection: some View {
        RemoteVideoPlayerView(
            exerciseName: exercise.name ?? "",
            categoryColor: categoryColor,
            videoFilename: exercise.videoFilename
        )
        .id(exercise.id) // Stable ID prevents video from being recreated
        .aspectRatio(16/9, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
                .stroke(categoryColor.opacity(colorScheme == .dark ? 0.35 : 0.18), lineWidth: 1)
        )
        .shadow(
            color: categoryColor.opacity(colorScheme == .dark ? 0.30 : 0.18),
            radius: 18, x: 0, y: 8
        )
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.35 : 0.08),
            radius: 10, x: 0, y: 4
        )
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(exercise.displayName)
                .font(.ds_heading1)
                .foregroundColor(.primary)
                .minimumScaleFactor(0.7)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            
            // Primary meta pills: muscle target + equipment + optional history
            HStack(spacing: Spacing.xs) {
                muscleBadge
                equipmentBadge
                if totalTimesPerformed > 0 {
                    performedBadge
                }
                Spacer(minLength: 0)
            }
            
            // Secondary muscles inline (only if present) — compact "also targets" line
            if !secondaryMuscles.isEmpty {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.ds_labelSmall)
                        .foregroundColor(.secondary)
                    Text("also ")
                        .font(.ds_bodySmall)
                        .foregroundColor(.secondary) +
                    Text(secondaryMuscles.prefix(3).joined(separator: ", "))
                        .font(.ds_bodySmall)
                        .foregroundColor(.secondary.opacity(0.85))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            }
        }
    }
    
    /// Primary muscle badge — replaces the redundant category pill.
    /// Category (e.g. "Legs") was duplicating what the muscle name already
    /// conveys ("Calves" → obviously legs). Collapsing into one targeted pill.
    private var muscleBadge: some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: categoryIcon)
                .font(.ds_labelSmall)
            Text(primaryMuscle)
                .font(.ds_labelMedium)
        }
        .foregroundColor(.white)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xxs)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [categoryColor, categoryColor.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .shadow(color: categoryColor.opacity(0.35), radius: 6, x: 0, y: 3)
    }
    
    private var equipmentBadge: some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: equipmentIcon)
                .font(.ds_labelSmall)
            Text(exercise.equipment ?? "Bodyweight")
                .font(.ds_labelMedium)
        }
        .foregroundColor(colorScheme == .dark ? .white : .primary)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xxs)
        .background(
            Capsule()
                .fill(Color.cardBackground)
                .overlay(
                    Capsule()
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                )
        )
    }
    
    private var performedBadge: some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: "checkmark.circle.fill")
                .font(.ds_labelSmall)
            Text("\(totalTimesPerformed)×")
                .font(.ds_labelMedium)
        }
        .foregroundColor(.green)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xxs)
        .background(
            Capsule()
                .fill(Color.green.opacity(0.12))
                .overlay(
                    Capsule()
                        .stroke(Color.green.opacity(0.25), lineWidth: 1)
                )
        )
    }
    
    // MARK: - User Stats Section
    
    private var userStatsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(
                title: "Your Progress",
                icon: "chart.line.uptrend.xyaxis",
                iconColor: categoryColor
            )
            
            HStack(spacing: Spacing.sm) {
                if let pr = personalRecord {
                    prCard(weight: pr.weight, reps: pr.reps, date: pr.date)
                }
                if let last = lastPerformance {
                    lastPerformanceCard(weight: last.weight, reps: last.reps, sets: last.sets, date: last.date)
                }
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sleekCard(cornerRadius: CornerRadius.xl, accentColor: categoryColor)
    }
    
    private func prCard(weight: Double, reps: Int, date: Date) -> some View {
        statBlock(
            tintColor: .orange,
            tintIcon: "flame.fill",
            tintLabel: "PR",
            weight: weight,
            subtitle: "× \(reps) reps",
            date: date
        )
    }
    
    private func lastPerformanceCard(weight: Double, reps: Int, sets: Int, date: Date) -> some View {
        statBlock(
            tintColor: categoryColor,
            tintIcon: "clock.fill",
            tintLabel: "Recent",
            weight: weight,
            subtitle: "\(sets) sets × \(reps) reps",
            date: date
        )
    }
    
    private func statBlock(
        tintColor: Color,
        tintIcon: String,
        tintLabel: String,
        weight: Double,
        subtitle: String,
        date: Date
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xxs) {
                Image(systemName: tintIcon)
                    .font(.ds_labelSmall)
                Text(tintLabel)
                    .font(.ds_labelSmall)
            }
            .foregroundColor(tintColor)
            
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(formatWeight(weight))
                    .font(.ds_stat)
                    .foregroundColor(.primary)
                Text("lbs")
                    .font(.ds_labelSmall)
                    .foregroundColor(.secondary)
            }
            
            Text(subtitle)
                .font(.ds_bodySmall)
                .foregroundColor(.secondary)
            
            Text(formatRelativeDate(date))
                .font(.ds_labelSmall)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                .fill(tintColor.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                        .stroke(tintColor.opacity(0.18), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Description Section
    
    private func descriptionSection(_ description: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(
                title: "About",
                icon: "text.alignleft",
                iconColor: categoryColor
            )
            
            Text(description)
                .font(.ds_bodyMedium)
                .foregroundColor(.secondary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sleekCard(cornerRadius: CornerRadius.xl, accentColor: categoryColor)
    }
    
    // MARK: - How To Section
    
    private var howToSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(
                title: "How To Perform",
                icon: "list.number",
                iconColor: categoryColor
            )
            
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(Array(howToSteps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        ZStack {
                            Circle()
                                .fill(categoryColor.opacity(0.18))
                                .frame(width: 26, height: 26)
                            Text("\(index + 1)")
                                .font(.ds_labelMedium)
                                .foregroundColor(categoryColor)
                        }
                        
                        Text(step)
                            .font(.ds_bodyMedium)
                            .foregroundColor(.primary)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sleekCard(cornerRadius: CornerRadius.xl, accentColor: categoryColor)
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
        
        guard let exerciseName = exercise.name else { return }
        
        let bgContext = PersistenceController.shared.container.newBackgroundContext()
        Task {
            let result: (total: Int, pr: (weight: Double, reps: Int, date: Date)?, last: (weight: Double, reps: Int, sets: Int, date: Date)?)? = await bgContext.perform {
                let request: NSFetchRequest<WorkoutExercise> = WorkoutExercise.fetchRequest()
                request.predicate = NSPredicate(format: "exercise.name == %@ AND workout.isCompleted == YES", exerciseName)
                request.sortDescriptors = [NSSortDescriptor(keyPath: \WorkoutExercise.workout?.date, ascending: false)]
                
                guard let workoutExercises = try? bgContext.fetch(request) else { return nil }
                let total = workoutExercises.count
                
                var bestWeight: Double = 0
                var bestReps: Int = 0
                var bestDate: Date?
                var lastWeight: Double = 0
                var lastReps: Int = 0
                var lastSets: Int = 0
                var lastDate: Date?
                
                for (index, we) in workoutExercises.enumerated() {
                    guard let sets = we.sets?.allObjects as? [WorkoutSet] else { continue }
                    let completedSets = sets.filter { $0.isCompleted }
                    
                    for set in completedSets {
                        if set.weight > bestWeight && set.reps > 0 {
                            bestWeight = set.weight
                            bestReps = Int(set.reps)
                            bestDate = we.workout?.date
                        }
                    }
                    
                    if index == 0, !completedSets.isEmpty {
                        if let heaviestSet = completedSets.max(by: { $0.weight < $1.weight }) {
                            lastWeight = heaviestSet.weight
                            lastReps = Int(heaviestSet.reps)
                            lastSets = completedSets.count
                            lastDate = we.workout?.date
                        }
                    }
                }
                
                let pr: (weight: Double, reps: Int, date: Date)? = bestWeight > 0 && bestDate != nil ? (bestWeight, bestReps, bestDate!) : nil
                let last: (weight: Double, reps: Int, sets: Int, date: Date)? = lastWeight > 0 && lastDate != nil ? (lastWeight, lastReps, lastSets, lastDate!) : nil
                return (total, pr, last)
            }
            
            if let result = result {
                await MainActor.run {
                    self.totalTimesPerformed = result.total
                    if let pr = result.pr {
                        self.personalRecord = (weight: pr.weight, reps: pr.reps, date: pr.date)
                    }
                    if let last = result.last {
                        self.lastPerformance = (weight: last.weight, reps: last.reps, sets: last.sets, date: last.date)
                    }
                }
            }
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

    // Q2-76 (Sprint 9 2026-04-28): AVURLAsset + AVPlayerItem construction is
    // synchronous I/O (header parse); doing it on main stalls scroll + tap.
    // Move the heavy work to a detached userInitiated Task and hop back to
    // @MainActor only to create the AVQueuePlayer / AVPlayerLooper (cheap)
    // and assign `@Published player`.
    func setupPlayer(with url: URL) {
        Task.detached(priority: .userInitiated) { [weak self] in
            let asset = AVURLAsset(url: url, options: [
                AVURLAssetPreferPreciseDurationAndTimingKey: false
            ])

            let playerItem = AVPlayerItem(asset: asset, automaticallyLoadedAssetKeys: ["playable"])
            playerItem.preferredForwardBufferDuration = 3

            await MainActor.run {
                guard let self = self else { return }
                let qp = AVQueuePlayer(playerItem: playerItem)
                self.playerLooper = AVPlayerLooper(player: qp, templateItem: playerItem)

                qp.automaticallyWaitsToMinimizeStalling = false
                qp.play()

                self.queuePlayer = qp
                self.player = qp
            }
        }
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
                    .font(.ds_labelLarge)
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
                .font(.ds_labelLarge)
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
            AppLogger.debug("📊 [STATUS BAR] Style changed to: \(statusBarStyle == .darkContent ? "dark content" : "default")", category: .workout)
            setNeedsStatusBarAppearanceUpdate()
        }
    }
    
    init(statusBarStyle: UIStatusBarStyle) {
        self.statusBarStyle = statusBarStyle
        super.init(nibName: nil, bundle: nil)
        AppLogger.debug("📊 [STATUS BAR] Controller init with style: \(statusBarStyle == .darkContent ? "dark content" : "default")", category: .workout)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        AppLogger.debug("📊 [STATUS BAR] Returning preferredStatusBarStyle: \(statusBarStyle == .darkContent ? "dark content" : "default")", category: .workout)
        return statusBarStyle
    }
    
    override var prefersStatusBarHidden: Bool {
        return false
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        AppLogger.debug("📊 [STATUS BAR] viewDidLoad - requesting update", category: .workout)
        setNeedsStatusBarAppearanceUpdate()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        AppLogger.debug("📊 [STATUS BAR] viewDidAppear - requesting update", category: .workout)
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
