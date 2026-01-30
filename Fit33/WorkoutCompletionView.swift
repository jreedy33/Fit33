import SwiftUI
import CoreData
import AVFoundation

// MARK: - Sound Effect Manager
class SoundEffectManager {
    static let shared = SoundEffectManager()
    private var audioPlayer: AVAudioPlayer?
    
    private init() {
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
    
    func playConfettiPop() {
        // Play system sounds for completion
        playSystemSounds()
        
        // Add haptic feedback for extra impact
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.prepare()
        impactFeedback.impactOccurred()
        
        // Add a second haptic burst
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
            mediumImpact.impactOccurred()
        }
    }
    
    private func playSystemSounds() {
        // Play multiple layered sounds for explosive effect
        let popSounds: [SystemSoundID] = [1016, 1057, 1107] // Multiple pop/click sounds
        
        // Play sounds with slight delays for layered effect
        for (index, soundID) in popSounds.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.05) {
                AudioServicesPlaySystemSound(soundID)
            }
        }
    }
}

// MARK: - Confetti Animation System
struct ConfettiPiece: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var rotation: Double
    var scale: CGFloat
    var color: Color
    var shape: ConfettiShape
    var velocity: CGPoint
    var angularVelocity: Double
    
    enum ConfettiShape: CaseIterable {
        case circle, square, triangle, star, dumbbell, trophy, flame, heart
        
        var systemImage: String {
            switch self {
            case .circle: return "circle.fill"
            case .square: return "square.fill"
            case .triangle: return "triangle.fill"
            case .star: return "star.fill"
            case .dumbbell: return "dumbbell.fill"
            case .trophy: return "trophy.fill"
            case .flame: return "flame.fill"
            case .heart: return "heart.fill"
            }
        }
    }
}

struct ConfettiView: View {
    @State private var confettiPieces: [ConfettiPiece] = []
    @State private var animationTimer: Timer?
    
    let isActive: Bool
    
    private let confettiColors: [Color] = [
        // Sophisticated app-matching colors
        Color.blue.opacity(0.8),           // App blue
        Color.green.opacity(0.8),          // Success green  
        Color.cyan.opacity(0.7),           // Teal accent
        Color.indigo.opacity(0.6),         // Deep blue
        Color.mint.opacity(0.7),           // Soft mint
        Color.teal.opacity(0.8),           // App teal
        Color.purple.opacity(0.6),         // Subtle purple
        Color.orange.opacity(0.7),         // Warm accent
        Color.pink.opacity(0.5),           // Soft pink
        Color.gray.opacity(0.6)            // Neutral gray
    ]
    
    var body: some View {
        ZStack {
            ForEach(confettiPieces) { piece in
                Image(systemName: piece.shape.systemImage)
                    .font(.system(size: piece.scale * 12))
                    .foregroundColor(piece.color)
                    .rotationEffect(.degrees(piece.rotation))
                    .position(x: piece.x, y: piece.y)
                    .opacity(piece.y > OrientationManager.shared.screenHeight * 0.9 ? 0.3 : 1.0)
                    .animation(.easeInOut(duration: 0.05), value: piece.x)
                    .animation(.easeInOut(duration: 0.05), value: piece.y)
                    .animation(.easeOut(duration: 0.2), value: piece.y)
            }
        }
        .onAppear {
            if isActive {
                DispatchQueue.main.async {
                    startConfetti()
                }
            }
        }
        .onChange(of: isActive) { newValue in
            if newValue {
                startConfetti()
            } else {
                stopConfetti()
            }
        }
        .onDisappear {
            stopConfetti()
        }
    }
    
    private func startConfetti() {
        // Play confetti pop sound immediately
        SoundEffectManager.shared.playConfettiPop()
        
        // Initial explosive burst of confetti
        generateConfettiBurst()
        
        // Add secondary bursts for more explosive effect
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.generateConfettiPieces(count: 20)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.generateConfettiPieces(count: 15)
        }
        
        // Continue generating confetti for a few seconds
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            updateConfetti()
            
            // Add new pieces occasionally for sustained effect
            if Double.random(in: 0...1) < 0.4 {
                generateConfettiPieces(count: 3)
            }
        }
        
        // Stop after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            stopConfetti()
        }
    }
    
    private func stopConfetti() {
        animationTimer?.invalidate()
        animationTimer = nil
        
        // Fade out remaining pieces
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            confettiPieces.removeAll()
        }
    }
    
    private func generateConfettiBurst() {
        // Create elegant explosion points across screen
        let screenWidth = OrientationManager.shared.screenWidth
        generateExplosiveBurst(centerX: screenWidth * 0.25, count: 25)
        generateExplosiveBurst(centerX: screenWidth * 0.5, count: 35)
        generateExplosiveBurst(centerX: screenWidth * 0.75, count: 25)
        
        // Add some scattered pieces for natural look
        generateConfettiPieces(count: 15)
    }
    
    private func generateExplosiveBurst(centerX: CGFloat, count: Int) {
        for _ in 0..<count {
            let piece = ConfettiPiece(
                x: centerX + CGFloat.random(in: -50...50),
                y: CGFloat.random(in: -100...50),
                rotation: Double.random(in: 0...360),
                scale: CGFloat.random(in: 0.8...2.0), // Bigger pieces for more impact
                color: confettiColors.randomElement() ?? .blue,
                shape: ConfettiPiece.ConfettiShape.allCases.randomElement() ?? .circle,
                velocity: CGPoint(
                    x: CGFloat.random(in: -4...4), // Smoother horizontal drift
                    y: CGFloat.random(in: 3...8)   // More controlled falling speed
                ),
                angularVelocity: Double.random(in: -8...8) // Gentler rotation
            )
            confettiPieces.append(piece)
        }
    }
    
    private func generateConfettiPieces(count: Int) {
        let screenWidth = OrientationManager.shared.screenWidth
        
        for _ in 0..<count {
            let piece = ConfettiPiece(
                x: CGFloat.random(in: 0...screenWidth),
                y: -50,
                rotation: Double.random(in: 0...360),
                scale: CGFloat.random(in: 0.5...1.5),
                color: confettiColors.randomElement() ?? .blue,
                shape: ConfettiPiece.ConfettiShape.allCases.randomElement() ?? .circle,
                velocity: CGPoint(
                    x: CGFloat.random(in: -3...3),
                    y: CGFloat.random(in: 2...6)
                ),
                angularVelocity: Double.random(in: -10...10)
            )
            confettiPieces.append(piece)
        }
    }
    
    private func updateConfetti() {
        let screenHeight = OrientationManager.shared.screenHeight
        
        for i in confettiPieces.indices.reversed() {
            confettiPieces[i].x += confettiPieces[i].velocity.x
            confettiPieces[i].y += confettiPieces[i].velocity.y
            confettiPieces[i].rotation += confettiPieces[i].angularVelocity
            
            // Add natural gravity effect
            confettiPieces[i].velocity.y += 0.3
            
            // Add subtle air resistance for realism
            confettiPieces[i].velocity.x *= 0.98
            
            // Remove pieces that have completely faded out
            if confettiPieces[i].y > screenHeight + 50 {
                confettiPieces.remove(at: i)
            }
        }
    }
}

struct WorkoutCompletionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var workoutManager: WorkoutManager
    
    let workout: Workout
    let exercises: [Exercise]
    let exerciseSets: [String: [WorkoutSetData]]
    let workoutDuration: TimeInterval
    
    @State private var showingCelebration = false
    @State private var showingShareSheet = false
    @State private var showingShareOptions = false
    
    var totalSets: Int {
        exerciseSets.values.reduce(0) { total, sets in
            total + sets.filter { $0.isCompleted }.count
        }
    }
    
    var totalReps: Int {
        exerciseSets.values.reduce(0) { total, sets in
            total + sets.filter { $0.isCompleted }.reduce(0) { $0 + $1.reps }
        }
    }
    
    var totalWeight: Double {
        exerciseSets.values.reduce(0) { total, sets in
            total + sets.filter { $0.isCompleted }.reduce(0) { $0 + ($1.weight * Double($1.reps)) }
        }
    }
    
    var workoutDurationFormatted: String {
        let minutes = Int(workoutDuration) / 60
        let seconds = Int(workoutDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // Workout gradient based on muscles worked
    private var workoutGradient: [Color] {
        guard let firstExercise = exercises.first,
              let muscleGroups = firstExercise.muscleGroups as? [String],
              let primaryMuscle = muscleGroups.first?.lowercased() else {
            return [.green, .teal]
        }
        
        switch primaryMuscle {
        case "chest": return [.red, .orange]
        case "back": return [.blue, .cyan]
        case "legs", "quads", "hamstrings", "glutes": return [.green, .teal]
        case "shoulders": return [.orange, .yellow]
        case "biceps", "triceps", "arms": return [.purple, .pink]
        case "core", "abs": return [.yellow, .orange]
        default: return [.green, .teal]
        }
    }
    
    // Top muscles worked
    private var topMuscles: [String] {
        var muscleCount: [String: Int] = [:]
        for exercise in exercises {
            if let muscleGroups = exercise.muscleGroups as? [String] {
                for muscle in muscleGroups {
                    muscleCount[muscle.capitalized, default: 0] += 1
                }
            }
        }
        return muscleCount.sorted { $0.value > $1.value }.prefix(3).map { $0.key }
    }
    
    // Smart workout name
    private var smartWorkoutName: String {
        if let name = workout.name, !name.isEmpty, !name.lowercased().contains("workout") {
            return name
        }
        
        let hour = Calendar.current.component(.hour, from: Date())
        let timeOfDay: String
        if hour >= 5 && hour < 12 {
            timeOfDay = "Morning"
        } else if hour >= 12 && hour < 17 {
            timeOfDay = "Afternoon"
        } else {
            timeOfDay = "Evening"
        }
        
        if let topMuscle = topMuscles.first {
            return "\(timeOfDay) \(topMuscle)"
        }
        return "\(timeOfDay) Workout"
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // "Workout Complete!" celebration text
                    VStack(spacing: 8) {
                        Text("🎉")
                            .font(.system(size: 50))
                            .scaleEffect(showingCelebration ? 1.0 : 0.5)
                            .animation(.spring(response: 0.6, dampingFraction: 0.6), value: showingCelebration)
                        
                        Text("Workout Complete!")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                    }
                    .padding(.top, 20)
                    
                    // Main workout overview card (matches RecentWorkoutCard style)
                    workoutOverviewCard
                    
                    // Exercise breakdown
                    exerciseBreakdownSection
                    
                    // Done button
                    doneButton
                    
                    Spacer(minLength: 60)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
            }
            .background(
                AdaptiveGradient.workout(for: colorScheme)
                    .ignoresSafeArea(.all, edges: .all)
            )
            .navigationTitle("Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        HapticManager.selectionChanged()
                        dismiss()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        HapticManager.selectionChanged()
                        showingShareOptions = true
                    }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(
                colorScheme == .dark ? Color(white: 0.1).opacity(0.9) : Color.white.opacity(0.9),
                for: .navigationBar
            )
        }
        .sheet(isPresented: $showingShareOptions) {
            ShareWorkoutSheet(workout: workout, accentColor: workoutGradient[0])
        }
        .overlay(
            ConfettiView(isActive: showingCelebration)
                .allowsHitTesting(false)
        )
        .onAppear {
            SessionLogManager.shared.logScreen(.workoutComplete, metadata: [
                "duration_minutes": Int(workoutDuration / 60),
                "exercise_count": exercises.count,
                "total_sets": totalSets
            ])
            DispatchQueue.main.async {
                showingCelebration = true
            }
        }
    }
    
    // MARK: - Workout Overview Card (RecentWorkoutCard Style)
    private var workoutOverviewCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top section - Icon, Title, Date
            HStack(alignment: .top, spacing: 12) {
                // Hollow transparent icon with gradient ring and checkmark
                ZStack {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: workoutGradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2.5
                        )
                        .frame(width: 52, height: 52)
                    
                    Image(systemName: "checkmark")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: workoutGradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(smartWorkoutName)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text("Just now")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            Divider()
                .padding(.vertical, 12)
            
            // Bottom section - Stats row (Duration, Exercises, Sets, XP)
            HStack(spacing: 0) {
                // Duration
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 12))
                            .foregroundColor(workoutGradient[0])
                        Text(formatDurationMinutes(workoutDuration))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    Text("Duration")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 1, height: 35)
                
                // Exercises
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.system(size: 12))
                            .foregroundColor(workoutGradient[0])
                        Text("\(exercises.count)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    Text("Exercises")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 1, height: 35)
                
                // Sets
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "repeat")
                            .font(.system(size: 12))
                            .foregroundColor(workoutGradient[0])
                        Text("\(totalSets)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    Text("Sets")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 1, height: 35)
                
                // XP
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                        Text("+\(calculateXP())")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    Text("XP")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            
            // Muscle tags
            if !topMuscles.isEmpty {
                HStack(spacing: 6) {
                    ForEach(topMuscles, id: \.self) { muscle in
                        Text(muscle)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(workoutGradient[0])
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(workoutGradient[0].opacity(0.12))
                            )
                    }
                    Spacer()
                }
                .padding(.top, 12)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .dark ? Color(white: 0.18) : Color.white)
        )
        .shadow(color: colorScheme == .dark ? .clear : .black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Exercise Breakdown
    private var exerciseBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Exercise Summary")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            VStack(spacing: 8) {
                ForEach(Array(exercises.enumerated()), id: \.offset) { index, exercise in
                    let exerciseId = exercise.id?.uuidString ?? exercise.name ?? ""
                    let sets = exerciseSets[exerciseId] ?? exerciseSets[exercise.name ?? ""] ?? []
                    let completedSets = sets.filter { $0.isCompleted }
                    
                    HStack(spacing: 12) {
                        // Small checkmark circle
                        ZStack {
                            Circle()
                                .stroke(workoutGradient[0], lineWidth: 1.5)
                                .frame(width: 24, height: 24)
                            
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(workoutGradient[0])
                        }
                        
                        Text(exercise.displayName)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Text("\(completedSets.count) sets")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(colorScheme == .dark ? Color(white: 0.15) : Color.gray.opacity(0.08))
                    )
                }
            }
        }
    }
    
    // MARK: - Done Button
    private var doneButton: some View {
        Button(action: {
            HapticManager.notification(.success)
            workoutManager.finishWorkout()
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                workoutManager.navigateToHomeTab()
            }
        }) {
            Text("Done")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: workoutGradient,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .padding(.top, 8)
    }
    
    // MARK: - Helper Functions
    private func formatDurationMinutes(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        if minutes < 60 {
            return "\(minutes)m"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours)h \(remainingMinutes)m"
        }
    }
    
    private func calculateXP() -> Int {
        // Base XP for completing a workout
        var xp = 50
        // Add XP per exercise
        xp += exercises.count * 10
        // Add XP per set
        xp += totalSets * 5
        return xp
    }
}

struct CompletionStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    var isWide: Bool = false
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 12) {
            // Icon with home tab styling
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 50, height: 50)
                
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
            }
            
            VStack(spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140)
        .padding(16)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.white.opacity(0.01), lineWidth: 1)
        )
        .shadow(color: colorScheme == .dark ? .clear : .black.opacity(0.05), radius: 3, x: 0, y: 1)
    }
}

struct ExerciseSummaryCard: View {
    let exercise: Exercise
    let sets: [WorkoutSetData]
    
    @Environment(\.colorScheme) private var colorScheme
    
    var completedSets: [WorkoutSetData] {
        sets.filter { $0.isCompleted }
    }
    
    var totalReps: Int {
        completedSets.reduce(0) { $0 + $1.reps }
    }
    
    var totalWeight: Double {
        completedSets.reduce(0) { $0 + ($1.weight * Double($1.reps)) }
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.displayName)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("\(completedSets.count) sets • \(totalReps) reps")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(String(format: "%.0f lbs", totalWeight))
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text("total volume")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.cardBackground)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.white.opacity(0.01), lineWidth: 1)
        )
        .shadow(color: colorScheme == .dark ? .clear : .black.opacity(0.05), radius: 1, x: 0, y: 1)
    }
}

#Preview {
    let context = PersistenceController.shared.container.viewContext
    
    // Create sample workout
    let workout = Workout(context: context)
    workout.name = "Push Day"
    workout.date = Date()
    
    // Create sample exercises
    let exercise1 = Exercise(context: context)
    exercise1.name = "Bench Press"
    exercise1.category = "Chest"
    
    let exercise2 = Exercise(context: context)
    exercise2.name = "Shoulder Press"
    exercise2.category = "Shoulders"
    
    let exercises = [exercise1, exercise2]
    
    // Create sample sets data
    let sampleSets: [String: [WorkoutSetData]] = [
        exercise1.id?.uuidString ?? "": [
            WorkoutSetData(weight: 100, reps: 8, isCompleted: true),
            WorkoutSetData(weight: 100, reps: 6, isCompleted: true),
            WorkoutSetData(weight: 90, reps: 8, isCompleted: true)
        ],
        exercise2.id?.uuidString ?? "": [
            WorkoutSetData(weight: 60, reps: 10, isCompleted: true),
            WorkoutSetData(weight: 60, reps: 8, isCompleted: true)
        ]
    ]
    
    return WorkoutCompletionView(
        workout: workout,
        exercises: exercises,
        exerciseSets: sampleSets,
        workoutDuration: 2580 // 43 minutes
    )
    .environmentObject(WorkoutManager.shared)
}

// Helper extension for WorkoutSetData initializer
extension WorkoutSetData {
    convenience init(weight: Double, reps: Int, isCompleted: Bool) {
        self.init()
        self.weight = weight
        self.reps = reps
        self.isCompleted = isCompleted
    }
}
