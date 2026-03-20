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
    var colorIndex: Int
    var shapeIndex: Int
    var velocity: CGPoint
    var angularVelocity: Double
    
    static let shapeNames = [
        "circle.fill", "square.fill", "triangle.fill", "star.fill",
        "dumbbell.fill", "trophy.fill", "flame.fill", "heart.fill"
    ]
}

struct ConfettiView: View {
    let isActive: Bool
    
    @StateObject private var engine = ConfettiEngine()
    
    var body: some View {
        TimelineView(.animation(paused: !engine.isAnimating)) { timeline in
            Canvas(rendersAsynchronously: true) { context, size in
                engine.update(size: size, date: timeline.date)
                
                // Pre-resolve each shape symbol ONCE per frame (8 resolves, not 120)
                let resolved = ConfettiPiece.shapeNames.map { context.resolve(Image(systemName: $0)) }
                
                let fadeStart = size.height * 0.8
                let fadeRange = size.height * 0.2
                
                for piece in engine.pieces {
                    let alpha = piece.y > fadeStart
                        ? max(0, 1.0 - (piece.y - fadeStart) / fadeRange)
                        : 1.0
                    guard alpha > 0.02 else { continue }
                    
                    let s = piece.scale * 12
                    let symbol = resolved[piece.shapeIndex % resolved.count]
                    let color = engine.colors[piece.colorIndex % engine.colors.count]
                    let rect = CGRect(x: -s / 2, y: -s / 2, width: s, height: s)
                    
                    var ctx = context
                    ctx.translateBy(x: piece.x, y: piece.y)
                    ctx.rotate(by: .degrees(piece.rotation))
                    ctx.opacity = alpha
                    ctx.drawLayer { layer in
                        layer.draw(symbol, in: rect)
                        layer.blendMode = .sourceIn
                        layer.fill(Path(rect.insetBy(dx: -1, dy: -1)), with: .color(color))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            if isActive { engine.start() }
        }
        .onChange(of: isActive) { newValue in
            if newValue { engine.start() } else { engine.stop() }
        }
        .onDisappear { engine.stop() }
    }
}

@MainActor
private class ConfettiEngine: ObservableObject {
    @Published var isAnimating = false
    var pieces: [ConfettiPiece] = []
    
    let colors: [Color] = [
        Color(red: 0.0, green: 0.78, blue: 1.0),    // electric cyan
        Color(red: 0.3, green: 0.5, blue: 1.0),      // vivid blue
        Color(red: 0.6, green: 0.2, blue: 1.0),      // electric purple
        Color(red: 1.0, green: 0.2, blue: 0.55),     // hot pink
        Color(red: 0.0, green: 1.0, blue: 0.65),     // neon mint
        Color(red: 1.0, green: 0.55, blue: 0.0),     // electric orange
        Color(red: 0.2, green: 0.95, blue: 0.3),     // neon green
        Color(red: 1.0, green: 0.82, blue: 0.0),     // bright gold
        Color(red: 0.0, green: 0.85, blue: 0.85),    // bright teal
    ]
    
    private var isSpawning = false
    private var lastUpdate: Date?
    private var startTime: Date?
    private var spawnAccumulator: TimeInterval = 0
    private var cleanupCounter = 0
    
    private let maxPieces = 120
    private let gravity: CGFloat = 100
    private let terminalVelocity: CGFloat = 320
    
    func start() {
        pieces.removeAll()
        pieces.reserveCapacity(maxPieces)
        lastUpdate = nil
        startTime = Date()
        spawnAccumulator = 0
        cleanupCounter = 0
        isSpawning = true
        isAnimating = true
        
        SoundEffectManager.shared.playConfettiPop()
        
        let w = OrientationManager.shared.screenWidth
        spawnBurst(centerX: w * 0.25, count: 15)
        spawnBurst(centerX: w * 0.5, count: 20)
        spawnBurst(centerX: w * 0.75, count: 15)
        spawnFromTop(count: 10)
    }
    
    func stop() {
        isSpawning = false
    }
    
    func update(size: CGSize, date: Date) {
        guard isAnimating else { return }
        
        let dt: CGFloat
        if let last = lastUpdate {
            dt = min(CGFloat(date.timeIntervalSince(last)), 0.033)
        } else {
            dt = 0.016
        }
        lastUpdate = date
        
        let elapsed = startTime.map { date.timeIntervalSince($0) } ?? 0
        
        if isSpawning && elapsed < 2.5 && pieces.count < maxPieces {
            spawnAccumulator += Double(dt)
            let interval: TimeInterval = elapsed < 0.4 ? 0.04 : 0.1
            while spawnAccumulator >= interval && pieces.count < maxPieces {
                spawnAccumulator -= interval
                spawnFromTop(count: elapsed < 0.4 ? 3 : 1)
            }
        }
        
        if elapsed > 3.0 { isSpawning = false }
        
        let bottom = size.height + 60
        for i in pieces.indices {
            pieces[i].velocity.y = min(pieces[i].velocity.y + gravity * dt, terminalVelocity)
            pieces[i].velocity.x *= 0.995
            let wobble = sin(CGFloat(elapsed) * 2.5 + pieces[i].x * 0.04) * 12.0 * dt
            pieces[i].x += pieces[i].velocity.x * dt + wobble
            pieces[i].y += pieces[i].velocity.y * dt
            pieces[i].rotation += pieces[i].angularVelocity * dt
        }
        
        cleanupCounter += 1
        if cleanupCounter >= 6 {
            cleanupCounter = 0
            pieces.removeAll { $0.y > bottom }
            if pieces.isEmpty && !isSpawning {
                isAnimating = false
                lastUpdate = nil
            }
        }
    }
    
    private func spawnBurst(centerX: CGFloat, count: Int) {
        let shapeCount = ConfettiPiece.shapeNames.count
        for _ in 0..<count {
            pieces.append(ConfettiPiece(
                x: centerX + .random(in: -50...50),
                y: .random(in: -60...30),
                rotation: .random(in: 0...360),
                scale: .random(in: 0.8...1.8),
                colorIndex: .random(in: 0..<colors.count),
                shapeIndex: .random(in: 0..<shapeCount),
                velocity: CGPoint(x: .random(in: -70...70), y: .random(in: 30...140)),
                angularVelocity: .random(in: -180...180)
            ))
        }
    }
    
    private func spawnFromTop(count: Int) {
        let w = OrientationManager.shared.screenWidth
        let shapeCount = ConfettiPiece.shapeNames.count
        for _ in 0..<count {
            pieces.append(ConfettiPiece(
                x: .random(in: 0...w),
                y: .random(in: -50 ... -5),
                rotation: .random(in: 0...360),
                scale: .random(in: 0.5...1.5),
                colorIndex: .random(in: 0..<colors.count),
                shapeIndex: .random(in: 0..<shapeCount),
                velocity: CGPoint(x: .random(in: -40...40), y: .random(in: 20...90)),
                angularVelocity: .random(in: -200...200)
            ))
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
    
    @State private var completionNotes: String = ""
    @State private var showingCelebration = false
    @State private var showingShareSheet = false
    @State private var showingShareOptions = false
    @State private var showingReplay = false
    @State private var replayInsights: [WorkoutInsightCard] = []
    @State private var showingProgressPhotoCapture = false
    
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
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 6) {
                        Text("🎉")
                            .font(.system(size: 44))
                            .scaleEffect(showingCelebration ? 1.0 : 0.5)
                            .animation(.spring(response: 0.6, dampingFraction: 0.6), value: showingCelebration)
                        
                        Text("Workout Complete!")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                    }
                    .padding(.top, 4)
                    
                    workoutOverviewCard
                    
                    exerciseBreakdownSection
                    
                    workoutNotesSection
                    
                    if !replayInsights.isEmpty {
                        replayButton
                    }
                    
                    progressPhotoPrompt
                    
                    doneButton
                    
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
            }
            .background(
                AnimatedOrbBackground.workout(colorScheme: colorScheme)
                    .ignoresSafeArea(.all, edges: .all)
            )
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        HapticManager.selectionChanged()
                        showingShareOptions = true
                    }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.ds_labelLarge)
                            .foregroundColor(.primary)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        HapticManager.notification(.success)
                        if !completionNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            workout.notes = completionNotes
                            try? workout.managedObjectContext?.save()
                        }
                        workoutManager.finishWorkout()
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            workoutManager.navigateToHomeTab()
                        }
                    }) {
                        Text("Done")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarBackground(
                Color.clear,
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
            if let existingNotes = workout.notes, !existingNotes.isEmpty {
                completionNotes = existingNotes
            }
            replayInsights = WorkoutReplayEngine.shared.generateInsights(
                workout: workout,
                exercises: exercises,
                exerciseSets: exerciseSets,
                workoutDuration: workoutDuration
            )
            DispatchQueue.main.async {
                showingCelebration = true
            }
        }
        .sheet(isPresented: $showingReplay) {
            WorkoutReplayView(insights: replayInsights)
        }
        .fullScreenCover(isPresented: $showingProgressPhotoCapture) {
            ProgressPhotoCaptureView()
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
                        .font(.ds_heading2)
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
                .padding(.vertical, Spacing.sm)
            
            // Bottom section - Stats row (Duration, Exercises, Sets, XP)
            HStack(spacing: 0) {
                // Duration
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.ds_bodySmall)
                            .foregroundColor(workoutGradient[0])
                        Text(formatDurationMinutes(workoutDuration))
                            .font(.ds_bodyRegular).fontWeight(.bold).fontDesign(.rounded)
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
                            .font(.ds_bodySmall)
                            .foregroundColor(workoutGradient[0])
                        Text("\(exercises.count)")
                            .font(.ds_bodyRegular).fontWeight(.bold).fontDesign(.rounded)
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
                            .font(.ds_bodySmall)
                            .foregroundColor(workoutGradient[0])
                        Text("\(totalSets)")
                            .font(.ds_bodyRegular).fontWeight(.bold).fontDesign(.rounded)
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
                            .font(.ds_bodySmall)
                            .foregroundColor(.orange)
                        Text("+\(calculateXP())")
                            .font(.ds_bodyRegular).fontWeight(.bold).fontDesign(.rounded)
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
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, Spacing.xxs)
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
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .dark ? Color(white: 0.18) : Color.white)
        )
        .shadow(color: colorScheme == .dark ? .clear : .black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Exercise Breakdown
    private var exerciseBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.rectangle.fill")
                    .font(.ds_labelMedium)
                    .foregroundColor(workoutGradient[0])
                Text("Exercises")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                Text("\(exercises.count)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(workoutGradient[0])
            }
            
            VStack(spacing: 8) {
                ForEach(Array(exercises.enumerated()), id: \.offset) { index, exercise in
                    let exerciseId = exercise.id?.uuidString ?? exercise.name ?? ""
                    let sets = exerciseSets[exerciseId] ?? exerciseSets[exercise.name ?? ""] ?? []
                    let completedSets = sets.filter { $0.isCompleted }
                    
                    CompletionExerciseRow(
                        exercise: exercise,
                        completedSets: completedSets,
                        accentColor: workoutGradient[0]
                    )
                }
            }
        }
    }
    
    // MARK: - Workout Notes
    private var workoutNotesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "note.text")
                    .font(.ds_bodySmall)
                    .foregroundColor(.secondary)
                Text("Workout Notes")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }
            
            TextEditor(text: $completionNotes)
                .font(.subheadline)
                .foregroundColor(.primary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 60, maxHeight: 100)
                .padding(Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(colorScheme == .dark ? Color(white: 0.15) : Color.gray.opacity(0.08))
                )
                .overlay(
                    Group {
                        if completionNotes.isEmpty {
                            Text("How did your workout feel?")
                                .font(.subheadline)
                                .foregroundColor(.secondary.opacity(0.6))
                                .padding(.leading, Spacing.md)
                                .padding(.top, Spacing.sm + 8)
                                .allowsHitTesting(false)
                        }
                    },
                    alignment: .topLeading
                )
        }
    }
    
    // MARK: - Progress Photo Prompt
    private var progressPhotoPrompt: some View {
        Group {
            let days = ProgressPhotoService.shared.daysSinceLastPhoto
            if days == nil || (days ?? 0) >= 14 {
                Button(action: {
                    HapticManager.impact(.light)
                    showingProgressPhotoCapture = true
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "camera.fill")
                            .font(.ds_bodyRegular)
                            .foregroundColor(.purple)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Take a Progress Photo")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            Text(days == nil ? "Start tracking your transformation" : "It's been \(days!) days since your last photo")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.ds_labelMedium)
                            .foregroundColor(.secondary)
                    }
                    .padding(Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(colorScheme == .dark ? Color(white: 0.15) : Color.gray.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Replay Button
    private var replayButton: some View {
        Button(action: {
            HapticManager.impact(.medium)
            showingReplay = true
        }) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.ds_labelLarge)
                Text("See Your Workout Replay")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Image(systemName: "chevron.right")
                    .font(.ds_labelMedium)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .background(
                LinearGradient(
                    colors: [.blue, .purple],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            )
        }
    }
    
    // MARK: - Reopen Workout Button
    private var doneButton: some View {
        Button(action: {
            HapticManager.impact(.medium)
            dismiss()
        }) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.uturn.left")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("Reopen Workout")
                    .font(.headline)
                    .fontWeight(.bold)
            }
            .foregroundColor(workoutGradient[0])
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        LinearGradient(colors: workoutGradient, startPoint: .leading, endPoint: .trailing),
                        lineWidth: 2
                    )
            )
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
        .padding(Spacing.md)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
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
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
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

// MARK: - Expandable Exercise Row (matches WorkoutHistoryDetailView)
struct CompletionExerciseRow: View {
    let exercise: Exercise
    let completedSets: [WorkoutSetData]
    let accentColor: Color
    @State private var isExpanded = false
    @Environment(\.colorScheme) private var colorScheme
    
    private var bestSet: WorkoutSetData? {
        completedSets.max { ($0.weight * Double($0.reps)) < ($1.weight * Double($1.reps)) }
    }
    
    private var categoryColor: Color {
        switch exercise.category?.lowercased() {
        case "chest": return .red
        case "back": return .blue
        case "legs", "quadriceps", "hamstrings", "calves", "glutes": return .green
        case "shoulders": return .purple
        case "biceps", "triceps", "arms": return .orange
        case "core", "abs": return .yellow
        default: return .cyan
        }
    }
    
    private var categoryIcon: String {
        switch exercise.category?.lowercased() {
        case "chest": return "figure.strengthtraining.traditional"
        case "back": return "figure.rowing"
        case "legs", "quadriceps", "hamstrings", "calves", "glutes": return "figure.walk"
        case "shoulders": return "figure.boxing"
        case "biceps", "triceps", "arms": return "figure.cooldown"
        case "core", "abs": return "figure.core.training"
        default: return "figure.mixed.cardio"
        }
    }
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        }) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [categoryColor, categoryColor.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: categoryIcon)
                            .font(.ds_labelLarge)
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.displayName)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        HStack(spacing: 8) {
                            Text(exercise.category?.capitalized ?? "")
                                .font(.caption)
                                .foregroundColor(categoryColor)
                                .fontWeight(.medium)
                            
                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text("\(completedSets.count) sets")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.ds_bodySmall).fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                
                if isExpanded {
                    VStack(spacing: 0) {
                        Divider()
                            .padding(.horizontal, Spacing.md)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                Text("This Workout")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.secondary)
                            .padding(.horizontal, Spacing.md)
                            .padding(.top, 8)
                            
                            VStack(spacing: 4) {
                                ForEach(Array(completedSets.enumerated()), id: \.offset) { index, set in
                                    let isBest = bestSet?.id == set.id
                                    
                                    HStack {
                                        Text("Set \(index + 1)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .frame(width: 50, alignment: .leading)
                                        
                                        Spacer()
                                        
                                        if set.weight > 0 {
                                            Text("\(formatWeight(set.weight)) lbs")
                                                .font(.caption)
                                                .fontWeight(isBest ? .bold : .medium)
                                        }
                                        
                                        Text("×")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        
                                        Text("\(set.reps) reps")
                                            .font(.caption)
                                            .fontWeight(isBest ? .bold : .medium)
                                        
                                        if isBest {
                                            Image(systemName: "star.fill")
                                                .font(.system(size: 9))
                                                .foregroundColor(accentColor)
                                        }
                                    }
                                    .foregroundColor(isBest ? accentColor : .primary)
                                    .padding(.horizontal, Spacing.md)
                                    .padding(.vertical, 6)
                                    .background(
                                        isBest ? AnyView(RoundedRectangle(cornerRadius: 6).fill(accentColor.opacity(0.1))) : AnyView(EmptyView())
                                    )
                                }
                            }
                        }
                        .padding(.bottom, 8)
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(colorScheme == .dark ? Color(white: 0.15) : Color.gray.opacity(0.08))
        )
    }
    
    private func formatWeight(_ weight: Double) -> String {
        weight.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(weight))" : String(format: "%.1f", weight)
    }
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
