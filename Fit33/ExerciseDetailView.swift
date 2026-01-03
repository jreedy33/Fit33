import SwiftUI
import AVKit
import CoreData

struct ExerciseDetailView: View {
    let exercise: Exercise
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.managedObjectContext) private var viewContext
    
    // User history data
    @State private var personalRecord: (weight: Double, reps: Int, date: Date)?
    @State private var lastPerformance: (weight: Double, reps: Int, sets: Int, date: Date)?
    @State private var totalTimesPerformed: Int = 0
    @State private var hasLoadedHistory = false
    
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
            return Array(muscleGroups.dropFirst())
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
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Status bar spacer - pushes video below Dynamic Island/notch
                Color.clear
                    .frame(height: 40)
                
                // Video Section with white background
                videoSection
                    .background(videoBackgroundColor)
                
                // Content Section with dark background
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
                    
                    // Target Muscles
                    muscleSection
                    
                    // Equipment Info
                    equipmentSection
                    
                    // Bottom padding for tab bar
                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .background(Color(.systemBackground))
            }
        }
        .background(
            // White background for video area at top
            VStack(spacing: 0) {
                videoBackgroundColor
                    .frame(height: 400)
                Color(.systemBackground)
            }
            .ignoresSafeArea()
        )
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                BackButton()
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar) // Dark status bar text for white video background
        .onAppear {
            SessionLogManager.shared.logScreen(.exerciseDetail, metadata: [
                "exercise_name": exercise.name,
                "exercise_id": exercise.id?.uuidString ?? "unknown"
            ])
            loadUserHistory()
            
            // 🚀 Priority prefetch for this exercise video
            if let name = exercise.name {
                VideoPlaybackEngine.shared.priorityPrefetch(exerciseName: name)
            }
        }
    }
    
    // MARK: - Video Section
    
    private var videoSection: some View {
        RemoteVideoPlayerView(
            exerciseName: exercise.name ?? "",
            categoryColor: categoryColor,
            videoFilename: exercise.videoFilename
        )
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Exercise Name
            Text(exercise.name ?? "Exercise")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(2)
            
            // Badges Row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    // Category Badge
                    categoryBadge
                    
                    // Equipment Badge
                    equipmentBadge
                    
                    // Times Performed Badge (if any)
                    if totalTimesPerformed > 0 {
                        performedBadge
                    }
                }
            }
        }
        .padding(.top, 20)
    }
    
    private var categoryBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: categoryIcon)
                .font(.system(size: 12, weight: .semibold))
            Text(exercise.category ?? "General")
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                colors: [categoryColor, categoryColor.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(Capsule())
        .shadow(color: categoryColor.opacity(0.4), radius: 8, x: 0, y: 4)
    }
    
    private var equipmentBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 12))
            Text(exercise.equipment ?? "Bodyweight")
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundColor(colorScheme == .dark ? .white : .primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
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
                .font(.system(size: 12))
            Text("\(totalTimesPerformed)×")
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundColor(.green)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
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
        VStack(spacing: 12) {
            // Section Header
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(categoryColor)
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
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.cardBackground)
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
                .shadow(color: categoryColor.opacity(0.1), radius: 15, x: 0, y: 8)
        )
    }
    
    private func prCard(weight: Double, reps: Int, date: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // PR Label with flame
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
                Text("PR")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.orange)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.orange.opacity(0.15))
            )
            
            // Weight & Reps
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(weight))")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("lbs")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            Text("× \(reps) reps")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
            
            // Date
            Text(formatRelativeDate(date))
                .font(.system(size: 11))
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
                    .font(.system(size: 12))
                    .foregroundColor(categoryColor)
                Text("Recent")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(categoryColor)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(categoryColor.opacity(0.15))
            )
            
            // Weight & Reps
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(weight))")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("lbs")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            Text("\(sets) sets × \(reps) reps")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
            
            // Date
            Text(formatRelativeDate(date))
                .font(.system(size: 11))
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
                Image(systemName: "text.alignleft")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(categoryColor)
                Text("About")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
            }
            
            Text(description)
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.05), radius: 10, x: 0, y: 5)
        )
    }
    
    // MARK: - How To Section
    
    private var howToSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Section Header
            HStack(spacing: 8) {
                Image(systemName: "list.number")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(categoryColor)
                Text("How To Perform")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
            }
            
            // Steps List
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(howToSteps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 14) {
                        // Step Number Circle
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [categoryColor, categoryColor.opacity(0.7)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 28, height: 28)
                                .shadow(color: categoryColor.opacity(0.3), radius: 4, x: 0, y: 2)
                            
                            Text("\(index + 1)")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        
                        // Step Text
                        Text(step)
                            .font(.system(size: 15))
                            .foregroundColor(.primary.opacity(0.85))
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    // Divider (except for last item)
                    if index < howToSteps.count - 1 {
                        Rectangle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                            .frame(height: 1)
                            .padding(.leading, 42)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(
                            LinearGradient(
                                colors: [categoryColor.opacity(0.2), categoryColor.opacity(0.05), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.05), radius: 10, x: 0, y: 5)
        )
    }
    
    // MARK: - Muscle Section
    
    private var muscleSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(categoryColor)
                Text("Target Muscles")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                // Primary Muscle
                VStack(alignment: .leading, spacing: 6) {
                    Text("PRIMARY")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .tracking(1)
                    
                    primaryMuscleTag
                }
                
                // Secondary Muscles
                if !secondaryMuscles.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SECONDARY")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .tracking(1)
                        
                        FlowLayout(spacing: 8) {
                            ForEach(secondaryMuscles, id: \.self) { muscle in
                                secondaryMuscleTag(muscle)
                            }
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.05), radius: 10, x: 0, y: 5)
        )
    }
    
    private var primaryMuscleTag: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(categoryColor)
                .frame(width: 10, height: 10)
                .shadow(color: categoryColor.opacity(0.5), radius: 4, x: 0, y: 0)
            
            Text(primaryMuscle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [categoryColor, categoryColor.opacity(0.8)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(Capsule())
        .shadow(color: categoryColor.opacity(0.3), radius: 6, x: 0, y: 3)
    }
    
    private func secondaryMuscleTag(_ muscle: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(categoryColor.opacity(0.6))
                .frame(width: 8, height: 8)
            
            Text(muscle)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(categoryColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(categoryColor.opacity(0.12))
                .overlay(
                    Capsule()
                        .stroke(categoryColor.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Equipment Section
    
    private var equipmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(categoryColor)
                Text("Equipment")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
            }
            
            HStack(spacing: 12) {
                // Equipment Icon
                ZStack {
                    Circle()
                        .fill(categoryColor.opacity(0.15))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: equipmentIcon)
                        .font(.system(size: 22))
                        .foregroundColor(categoryColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.equipment ?? "Bodyweight")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text(equipmentDescription)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.05), radius: 10, x: 0, y: 5)
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
    
    func setupPlayer(with url: URL) {
        player = AVPlayer(url: url)
        player?.play()
        
        // Loop video
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { [weak self] _ in
            self?.player?.seek(to: .zero)
            self?.player?.play()
        }
    }
    
    func pause() {
        player?.pause()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Custom Back Button (Reduced Blur)

struct BackButton: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Button(action: {
            HapticManager.tap()
            dismiss()
        }) {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(Color(.systemGray5).opacity(0.9)) // Solid, less blurry
                )
        }
    }
}

// MARK: - Video Mapping Function

func createExerciseVideoMapping() -> [String: String] {
    return [
        "3 4 Sit Up": "00011201-3-4-Sit-up_Waist-FIX_.mp4",
        "Air Bike (Male)": "00031201-Air-Bike-(male)_Waist-FIX_.mp4",
        "Barbell Behind Back Finger Curl": "16101201-Barbell-Behind-Back-Finger-Curl_Forearms-FIX_.mp4",
        // ... keeping existing mapping for legacy videos
    ]
}
