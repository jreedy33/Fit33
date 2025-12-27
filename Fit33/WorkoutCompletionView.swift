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
                    .opacity(piece.y > UIScreen.main.bounds.height * 0.9 ? 0.3 : 1.0)
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
        generateExplosiveBurst(centerX: UIScreen.main.bounds.width * 0.25, count: 25)
        generateExplosiveBurst(centerX: UIScreen.main.bounds.width * 0.5, count: 35)
        generateExplosiveBurst(centerX: UIScreen.main.bounds.width * 0.75, count: 25)
        
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
        let screenWidth = UIScreen.main.bounds.width
        
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
        let screenHeight = UIScreen.main.bounds.height
        
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
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Custom header with celebration styling
                    celebrationCustomHeader
                    
                    // Celebration welcome card
                    celebrationWelcomeCard
                    
                    // Workout achievement stats (home tab style)
                    workoutAchievementSection
                    
                    // Exercise breakdown (home tab cards style)
                    exerciseBreakdownCards
                    
                    // Action buttons (home tab style)
                    homeStyleActionButtons
                    
                    Spacer(minLength: 60)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
            }
            .background(
                // Sophisticated celebratory gradient - matches app aesthetic
                AdaptiveGradient.workout(for: colorScheme)
                    .ignoresSafeArea(.all, edges: .all)
            )
            .navigationBarHidden(true)
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
    
    // MARK: - New Home Tab Style Sections
    private var celebrationCustomHeader: some View {
        HStack {
            Button(action: {
                HapticManager.selectionChanged()
                // Return to active workout - don't finish the workout, just dismiss completion view
                dismiss()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .fontWeight(.medium)
                    
                    Text("Return to Workout")
                        .font(.headline)
                        .fontWeight(.medium)
                }
                .foregroundColor(.blue)
            }
            
            Spacer()
            
            Button(action: {
                HapticManager.notification(.success)
                workoutManager.finishWorkout()
                dismiss()
                // Navigate to home tab after a brief delay to ensure dismiss completes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    workoutManager.navigateToHomeTab()
                }
            }) {
                Text("Done")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
    
    private var celebrationWelcomeCard: some View {
        VStack(spacing: 16) {
            // Elegant trophy icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.green, Color.blue]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .shadow(color: .green.opacity(0.3), radius: 10, x: 0, y: 5)
                
                Image(systemName: "trophy.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.white)
            }
            .scaleEffect(showingCelebration ? 1.0 : 0.8)
            .animation(.spring(response: 0.6, dampingFraction: 0.7), value: showingCelebration)
            
            VStack(spacing: 8) {
                Text("Workout Complete!")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("Excellent Work!")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text("You've successfully completed your workout. Here's what you accomplished:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.white.opacity(0.01), lineWidth: 1)
        )
        .shadow(color: colorScheme == .dark ? .clear : .black.opacity(0.05), radius: 3, x: 0, y: 1)
    }
    
    private var workoutAchievementSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your Achievement")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            // Stats grid - home tab style
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                CompletionStatCard(
                    title: "Duration",
                    value: workoutDurationFormatted,
                    icon: "clock.fill",
                    color: .blue
                )
                
                CompletionStatCard(
                    title: "Exercises",
                    value: "\(exercises.count)",
                    icon: "dumbbell.fill",
                    color: .green
                )
                
                CompletionStatCard(
                    title: "Total Sets",
                    value: "\(totalSets)",
                    icon: "list.number",
                    color: .orange
                )
                
                CompletionStatCard(
                    title: "Total Reps",
                    value: "\(totalReps)",
                    icon: "repeat",
                    color: .purple
                )
            }
        }
    }
    
    private var exerciseBreakdownCards: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Exercise Summary")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            VStack(spacing: 12) {
                ForEach(Array(exercises.enumerated()), id: \.offset) { index, exercise in
                    let sets = exerciseSets[exercise.name ?? ""] ?? []
                    let completedSets = sets.filter { $0.isCompleted }
                    
                    HStack(spacing: 16) {
                        // Exercise icon
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.15))
                                .frame(width: 50, height: 50)
                            
                            Image(systemName: "dumbbell.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exercise.name ?? "Unknown Exercise")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            Text("\(completedSets.count) sets completed")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.green)
                    }
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
        }
    }
    
    private var homeStyleActionButtons: some View {
        VStack(spacing: 16) {
            // Share achievement button - home tab style
            Button(action: {
                HapticManager.impact(.light)
                shareWorkout()
            }) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title2)
                        .foregroundColor(.primary)
                    
                    Text("Share Achievement")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.white.opacity(0.01), lineWidth: 1)
                )
                .shadow(color: colorScheme == .dark ? .clear : .black.opacity(0.05), radius: 3, x: 0, y: 1)
            }
        }
    }
    
    private var celebrationHeader: some View {
        VStack(spacing: 16) {
            // Celebration Icon
            Image(systemName: "trophy.fill")
                .font(.system(size: 60))
                .foregroundColor(.yellow)
                .scaleEffect(showingCelebration ? 1.3 : 0.8)
                .rotationEffect(.degrees(showingCelebration ? 0 : -10))
                .animation(.spring(response: 0.4, dampingFraction: 0.5, blendDuration: 0.1), value: showingCelebration)
                .shadow(color: .yellow.opacity(0.5), radius: showingCelebration ? 10 : 0, x: 0, y: 0)
            
            Text("Workout Complete!")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text("Great job! Here's what you accomplished:")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 10)
    }
    
    private var workoutStatsSection: some View {
        VStack(spacing: 16) {
            // Main Stats Cards
            HStack(spacing: 12) {
                CompletionStatCard(
                    title: "Duration",
                    value: workoutDurationFormatted,
                    icon: "clock.fill",
                    color: .blue
                )
                
                CompletionStatCard(
                    title: "Exercises",
                    value: "\(exercises.count)",
                    icon: "dumbbell.fill",
                    color: .green
                )
            }
            
            HStack(spacing: 12) {
                CompletionStatCard(
                    title: "Total Sets",
                    value: "\(totalSets)",
                    icon: "list.number",
                    color: .orange
                )
                
                CompletionStatCard(
                    title: "Total Reps",
                    value: "\(totalReps)",
                    icon: "repeat",
                    color: .purple
                )
            }
            
            // Total Weight Card (full width)
            HStack {
                CompletionStatCard(
                    title: "Total Weight",
                    value: String(format: "%.0f lbs", totalWeight),
                    icon: "scalemass.fill",
                    color: .red,
                    isWide: true
                )
            }
        }
    }
    
    private var exerciseBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Exercise Breakdown")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal, 4)
            
            VStack(spacing: 12) {
                ForEach(exercises, id: \.id) { exercise in
                    if let exerciseId = exercise.id?.uuidString,
                       let sets = exerciseSets[exerciseId] {
                        ExerciseSummaryCard(exercise: exercise, sets: sets)
                    }
                }
            }
        }
    }
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Done Button
            Button(action: {
                HapticManager.notification(.success)
                workoutManager.finishWorkout()
                workoutManager.navigateToHomeTab()
                dismiss()
            }) {
                Text("Done")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.blue)
                    .cornerRadius(12)
            }
            
            // Share Button
            Button(action: {
                HapticManager.impact(.light)
                shareWorkout()
            }) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share Workout")
                }
                .font(.headline)
                .foregroundColor(.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }
    
    private func shareWorkout() {
        let summary = """
        💪 Just finished my workout!
        
        ⏱ Duration: \(workoutDurationFormatted)
        🏋️ Exercises: \(exercises.count)
        📊 Sets: \(totalSets)
        🔄 Reps: \(totalReps)
        
        #GOFit #FitnessGoals
        """
        
        let activityVC = UIActivityViewController(
            activityItems: [summary],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
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
                Text(exercise.name ?? "Unknown Exercise")
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
