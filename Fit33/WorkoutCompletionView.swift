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
            AppLogger.error("Failed to setup audio session: \(error)", category: .workout)
        }
    }
    
    func playConfettiPop() {
        // Play system sounds for completion
        playSystemSounds()
        
        // Add haptic feedback for extra impact
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.prepare()
        impactFeedback.impactOccurred()
        
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.1))
            let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
            mediumImpact.impactOccurred()
        }
    }
    
    private func playSystemSounds() {
        // Play multiple layered sounds for explosive effect
        let popSounds: [SystemSoundID] = [1016, 1057, 1107] // Multiple pop/click sounds
        
        // Play sounds with slight delays for layered effect
        for (index, soundID) in popSounds.enumerated() {
            let delay = Double(index) * 0.05
            if delay > 0 {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(delay))
                    AudioServicesPlaySystemSound(soundID)
                }
            } else {
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
    var opacity: CGFloat = 1.0
    
    static let shapeNames = ["circle.fill", "square.fill", "star.fill"]
}

struct ConfettiView: View {
    let isActive: Bool
    
    @StateObject private var engine = ConfettiEngine()
    
    var body: some View {
        TimelineView(.animation(paused: !engine.isAnimating)) { timeline in
            Canvas(rendersAsynchronously: true) { context, size in
                engine.update(size: size, date: timeline.date)
                
                if engine.cachedSymbols.isEmpty {
                    engine.cachedSymbols = ConfettiPiece.shapeNames.map { context.resolve(Image(systemName: $0)) }
                }
                
                let fadeOutStart = size.height * 0.55
                let fadeOutRange = size.height * 0.30
                
                for piece in engine.pieces {
                    var alpha = piece.opacity
                    if piece.y < 40 { alpha *= max(0, piece.y / 40) }
                    if piece.y > fadeOutStart {
                        alpha *= max(0, 1.0 - (piece.y - fadeOutStart) / fadeOutRange)
                    }
                    guard alpha > 0.02 else { continue }
                    
                    let s = piece.scale * 12
                    let symbol = engine.cachedSymbols[piece.shapeIndex % engine.cachedSymbols.count]
                    let color = engine.colors[piece.colorIndex % engine.colors.count]
                    let rect = CGRect(x: -s / 2, y: -s / 2, width: s, height: s)
                    
                    var ctx = context
                    ctx.translateBy(x: piece.x, y: piece.y)
                    ctx.rotate(by: .degrees(piece.rotation))
                    ctx.opacity = Double(alpha)
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
    var cachedSymbols: [GraphicsContext.ResolvedImage] = []
    
    let colors: [Color] = [
        Color(red: 0.0, green: 0.78, blue: 1.0),
        Color(red: 0.3, green: 0.5, blue: 1.0),
        Color(red: 0.6, green: 0.2, blue: 1.0),
        Color(red: 0.0, green: 1.0, blue: 0.65),
        Color(red: 1.0, green: 0.55, blue: 0.0),
    ]
    
    private var lastUpdate: Date?
    private var startTime: Date?
    private var cleanupCounter = 0
    
    private let maxPieces = 70
    private let gravity: CGFloat = 600
    private let terminalVelocity: CGFloat = 550
    
    func start() {
        pieces.removeAll()
        pieces.reserveCapacity(maxPieces)
        cachedSymbols = []
        lastUpdate = nil
        startTime = Date()
        cleanupCounter = 0
        isAnimating = true
        
        SoundEffectManager.shared.playConfettiPop()
        
        let w = OrientationManager.shared.screenWidth
        spawnCannon(originX: w * 0.3, originY: -60, spread: 50, count: 20)
        spawnCannon(originX: w * 0.5, originY: -80, spread: 70, count: 30)
        spawnCannon(originX: w * 0.7, originY: -60, spread: 50, count: 20)
    }
    
    func stop() {
        isAnimating = false
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
        
        let bottom = size.height + 80
        for i in pieces.indices {
            pieces[i].velocity.y = min(pieces[i].velocity.y + gravity * dt, terminalVelocity)
            pieces[i].velocity.x *= 0.992
            pieces[i].x += pieces[i].velocity.x * dt
            pieces[i].y += pieces[i].velocity.y * dt
            pieces[i].rotation += pieces[i].angularVelocity * dt
            pieces[i].scale *= 0.999
        }
        
        cleanupCounter += 1
        if cleanupCounter >= 3 {
            cleanupCounter = 0
            pieces.removeAll { $0.y > bottom }
            if pieces.isEmpty {
                isAnimating = false
                lastUpdate = nil
            }
        }
    }
    
    private func spawnCannon(originX: CGFloat, originY: CGFloat, spread: CGFloat, count: Int) {
        let shapeCount = ConfettiPiece.shapeNames.count
        for _ in 0..<count {
            pieces.append(ConfettiPiece(
                x: originX + .random(in: -spread...spread),
                y: originY + .random(in: -40...0),
                rotation: .random(in: 0...360),
                scale: .random(in: 0.6...1.6),
                colorIndex: .random(in: 0..<colors.count),
                shapeIndex: .random(in: 0..<shapeCount),
                velocity: CGPoint(
                    x: .random(in: -150...150),
                    y: .random(in: -320 ... -150)
                ),
                angularVelocity: .random(in: -280...280)
            ))
        }
    }
}

struct WorkoutCompletionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var workoutManager: WorkoutManager
    @ObservedObject private var friendService = FriendService.shared
    @ObservedObject private var rankingService = FriendRankingService.shared
    
    let workout: Workout
    let exercises: [Exercise]
    let exerciseSets: [String: [WorkoutSetData]]
    let workoutDuration: TimeInterval
    
    @State private var completionNotes: String = ""
    @State private var showingCelebration = false
    @State private var replayInsights: [WorkoutInsightCard] = []
    @State private var showingProgressPhotoCapture = false
    @State private var isCardExpanded = false
    @State private var visibleInsightCards: Set<Int> = []
    @State private var isNotesExpanded = false
    
    // Entrance choreography
    @State private var showCheckmark = false
    @State private var showTitle = false
    @State private var showStats = false
    @State private var showTags = false
    @State private var showPhotoPrompt = false
    @State private var estimatedCalories: Int = 0
    
    // Inline "Send to Friend" selector (replaces the old ShareWorkoutSheet
    // intermediary page — picker + compose + success all live here now).
    @State private var selectedFriendForSend: Friend?
    @State private var friendMessageText: String = ""
    @State private var isSendingToFriend = false
    @State private var sendToFriendError: String?
    @State private var didSendToFriend = false
    @State private var showingFriendSearch = false

    // Delete-workout flow (migration #155). The workout is fully deleted +
    // every server-side stat side-effect is reversed via the
    // `delete_workout_and_revert_stats` RPC. UX guard: blocked when the
    // workout has been shared with a friend (the friend already received
    // the data and we don't have an "un-share" path).
    @State private var showingDeleteConfirmation = false
    @State private var isDeletingWorkout = false
    @State private var deleteWorkoutError: String?
    
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
    
    private var topMuscles: [String] {
        var muscleCount: [String: Int] = [:]
        var firstSeen: [String: Int] = [:]
        var order = 0
        for exercise in exercises {
            if let muscleGroups = exercise.muscleGroups as? [String] {
                for muscle in muscleGroups {
                    let key = muscle.capitalized
                    muscleCount[key, default: 0] += 1
                    if firstSeen[key] == nil {
                        firstSeen[key] = order
                        order += 1
                    }
                }
            }
        }
        return muscleCount.sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            return (firstSeen[$0.key] ?? 0) < (firstSeen[$1.key] ?? 0)
        }.prefix(3).map { $0.key }
    }
    
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
                VStack(spacing: Spacing.md) {
                    // HERO ZONE
                    heroSection
                    
                    // Send to Friend — inlined here (previously lived on a
                    // separate share page that's been removed). Always shown
                    // in build mode; collapses to a "no friends yet" hint if
                    // the user hasn't added anyone.
                    sendToFriendCard
                        .opacity(showStats ? 1 : 0)
                        .offset(y: showStats ? 0 : 12)
                    
                    // INSIGHTS ZONE
                    if !replayInsights.isEmpty {
                        inlineReplaySection
                    }
                    
                    if showPhotoPrompt {
                        progressPhotoPrompt
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    // Delete button lives at the very bottom of the scrollable
                    // content, after Take Photo. Migration #155 — reverses
                    // every server-side stat (XP/streak/league/quests) AND
                    // local Core Data + HealthKit. See
                    // `WorkoutManager.deleteCompletedWorkout`.
                    deleteWorkoutButton

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, Spacing.md)
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
                        HapticManager.impact(.medium)
                        dismiss()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.uturn.left")
                                .font(.ds_bodySmall)
                            Text("Reopen")
                                .font(.ds_labelMedium)
                        }
                        .foregroundColor(.primary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        HapticManager.selectionChanged()
                        finishAndDismiss()
                    }) {
                        Text("Done")
                            .font(.ds_labelMedium)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }
                    .accessibilityLabel("Finish workout")
                }
            }
            .adaptiveToolbarBackground()
        }
        .sheet(isPresented: $showingFriendSearch) {
            // Use the selection-mode picker (NOT FriendsListView, which is the
            // friends-management hub — taps there route to FriendProfileView and
            // break the share-to-friend flow). FriendSelectionSheet returns the
            // chosen friend via `onSelect` so we can drop straight into the
            // inline compose composer below.
            FriendSelectionSheet { friend in
                showingFriendSearch = false
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    selectedFriendForSend = friend
                }
            }
        }
        .alert("Error", isPresented: .init(
            get: { sendToFriendError != nil },
            set: { if !$0 { sendToFriendError = nil } }
        )) {
            Button("OK") { sendToFriendError = nil }
        } message: {
            Text(sendToFriendError ?? "")
        }
        .alert("Delete this workout?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task { await performDeleteWorkout() }
            }
        } message: {
            Text("This permanently removes the workout and reverses XP, streak, league points, and daily quest progress. This cannot be undone.")
        }
        .alert("Couldn't delete", isPresented: .init(
            get: { deleteWorkoutError != nil },
            set: { if !$0 { deleteWorkoutError = nil } }
        )) {
            Button("OK") { deleteWorkoutError = nil }
        } message: {
            Text(deleteWorkoutError ?? "")
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
                isNotesExpanded = true
            }
            replayInsights = WorkoutReplayEngine.shared.generateInsights(
                workout: workout,
                exercises: exercises,
                exerciseSets: exerciseSets,
                workoutDuration: workoutDuration
            )
            startEntranceChoreography()
            loadCalories()
        }
        .task {
            // Populate the inline friend picker — mirrors the fetch
            // `ShareWorkoutSheet` did before it was folded in here.
            await friendService.fetchFriends()
            await rankingService.fetchRankedFriends()
        }
        .fullScreenCover(isPresented: $showingProgressPhotoCapture) {
            ProgressPhotoCaptureView()
        }
    }
    
    // MARK: - Entrance Choreography
    
    private func startEntranceChoreography() {
        showingCelebration = true
        
        withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) {
            showCheckmark = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.15))
            withAnimation(.easeOut(duration: 0.3)) { showTitle = true }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.45))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { showStats = true }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.6))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { showTags = true }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.easeOut(duration: 0.3)) { showPhotoPrompt = true }
        }
    }
    
    // MARK: - Hero Section
    
    private var heroSection: some View {
        VStack(spacing: Spacing.md) {
            // Animated gradient checkmark
            ZStack {
                Circle()
                    .trim(from: 0, to: showCheckmark ? 1 : 0)
                    .stroke(
                        LinearGradient(colors: workoutGradient, startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 64, height: 64)
                    .rotationEffect(.degrees(-90))
                
                Image(systemName: "checkmark")
                    .font(.ds_heading1)
                    .foregroundStyle(
                        LinearGradient(colors: workoutGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .scaleEffect(showCheckmark ? 1 : 0)
                    .animation(.spring(response: 0.4, dampingFraction: 0.6).delay(0.3), value: showCheckmark)
            }
            .padding(.top, Spacing.xxs)
            
            // Title
            VStack(spacing: Spacing.xxs) {
                Text("Workout Complete!")
                    .font(.ds_heading1)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(smartWorkoutName)
                    .font(.ds_bodyLarge)
                    .foregroundColor(.secondary)
            }
            .opacity(showTitle ? 1 : 0)
            .offset(y: showTitle ? 0 : 12)
            
            // Unified stats + breakdown + notes card
            unifiedStatsCard
                .opacity(showStats ? 1 : 0)
                .scaleEffect(showStats ? 1 : 0.95)
        }
    }
    
    /// Inline muscle-tag row used inside `unifiedStatsCard` so the badges
    /// read as part of the card instead of floating awkwardly beneath it.
    private var muscleTagsRow: some View {
        HStack(spacing: 6) {
            ForEach(Array(topMuscles.enumerated()), id: \.element) { index, muscle in
                Text(muscle)
                    .font(.ds_labelSmall)
                    .fontWeight(.medium)
                    .foregroundColor(workoutGradient[0])
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xxs)
                    .background(
                        Capsule()
                            .fill(workoutGradient[0].opacity(0.12))
                    )
                    .opacity(showTags ? 1 : 0)
                    .offset(x: showTags ? 0 : -12)
                    .animation(.spring(response: 0.4, dampingFraction: 0.75).delay(Double(index) * 0.06), value: showTags)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }
    
    // MARK: - Unified Stats Card (stats + exercises + notes)
    
    private var unifiedStatsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Stats row (always visible)
            HStack(spacing: 0) {
                statPill(icon: "clock.fill", value: formatDurationMinutes(workoutDuration), label: "Time")
                Rectangle().fill(Color.gray.opacity(0.2)).frame(width: 1, height: 35)
                statPill(icon: "figure.strengthtraining.traditional", value: "\(exercises.count)", label: "Exercises")
                Rectangle().fill(Color.gray.opacity(0.2)).frame(width: 1, height: 35)
                statPill(icon: "repeat", value: "\(totalSets)", label: "Sets")
                Rectangle().fill(Color.gray.opacity(0.2)).frame(width: 1, height: 35)
                statPill(icon: "flame.fill", value: estimatedCalories > 0 ? "\(estimatedCalories)" : "--", label: "Calories")
            }
            .padding(.vertical, Spacing.sm)
            
            // Muscle tags — integrated inside the card instead of floating
            // below it, so the card reads as one cohesive summary block.
            if !topMuscles.isEmpty {
                Divider().padding(.horizontal, Spacing.xs)
                muscleTagsRow
            }
            
            // Add a note row (when not expanded)
            if !isCardExpanded {
                Divider().padding(.horizontal, Spacing.xs)
                
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isNotesExpanded.toggle()
                    }
                }) {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "note.text")
                            .font(.ds_bodySmall)
                            .foregroundColor(.secondary)
                        Text(completionNotes.isEmpty ? "Add a note..." : completionNotes)
                            .font(.ds_labelMedium)
                            .foregroundColor(completionNotes.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                }
                .buttonStyle(PlainButtonStyle())
                
                if isNotesExpanded {
                    TextEditor(text: $completionNotes)
                        .font(.ds_bodyMedium)
                        .foregroundColor(.primary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 60, maxHeight: 100)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.bottom, Spacing.sm)
                        .overlay(
                            Group {
                                if completionNotes.isEmpty {
                                    Text("Anything you'd like to add?")
                                        .font(.ds_bodyMedium)
                                        .foregroundColor(.secondary.opacity(0.6))
                                        .padding(.leading, Spacing.md)
                                        .padding(.top, Spacing.xxs)
                                        .allowsHitTesting(false)
                                }
                            },
                            alignment: .topLeading
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            
            Divider().padding(.horizontal, Spacing.xs)
            
            // Expand/collapse for exercise breakdown
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isCardExpanded.toggle()
                }
            }) {
                HStack {
                    Image(systemName: "list.bullet")
                        .font(.ds_bodySmall)
                        .foregroundColor(workoutGradient[0])
                    Text("Exercise Breakdown")
                        .font(.ds_labelMedium)
                        .foregroundColor(.primary)
                    Spacer()
                    Text("\(exercises.count)")
                        .font(.ds_bodySmall)
                        .foregroundColor(.secondary)
                    Image(systemName: isCardExpanded ? "chevron.up" : "chevron.down")
                        .font(.ds_bodySmall).fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
            }
            .buttonStyle(PlainButtonStyle())
            
            if isCardExpanded {
                VStack(spacing: Spacing.xs) {
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
                    
                    // Notes inside expanded view
                    Divider().padding(.horizontal, Spacing.xs)
                    
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "note.text")
                                .font(.ds_bodySmall)
                                .foregroundColor(.secondary)
                            Text("Notes")
                                .font(.ds_labelMedium)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, Spacing.md)
                        
                        TextEditor(text: $completionNotes)
                            .font(.ds_bodyMedium)
                            .foregroundColor(.primary)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 60, maxHeight: 100)
                            .padding(Spacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                                    .fill(Color.cardBackground)
                            )
                            .overlay(
                                Group {
                                    if completionNotes.isEmpty {
                                        Text("Anything you'd like to add?")
                                            .font(.ds_bodyMedium)
                                            .foregroundColor(.secondary.opacity(0.6))
                                            .padding(.leading, Spacing.md)
                                            .padding(.top, Spacing.sm + 8)
                                            .allowsHitTesting(false)
                                    }
                                },
                                alignment: .topLeading
                            )
                            .padding(.horizontal, Spacing.sm)
                    }
                    .padding(.bottom, Spacing.sm)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, Spacing.xs)
        .adaptiveSleekCard(cornerRadius: CornerRadius.xl, accentColor: workoutGradient[0])
    }
    
    // MARK: - Send to Friend (inline)
    
    /// Top-N friends ranked by `FriendRankingService`, padded with remaining
    /// friends so we always have something to show. Mirrors the logic that
    /// used to live in `ShareWorkoutSheet` before the share page was folded
    /// into the completion screen.
    private var friendsForPicker: [Friend] {
        let rankedIds = rankingService.rankedFriends.prefix(5).map { $0.friendId }
        var result: [Friend] = []
        for friendId in rankedIds {
            if let friend = friendService.friends.first(where: { $0.friendId == friendId }) {
                result.append(friend)
            }
        }
        let remaining = friendService.friends.filter { f in !result.contains(where: { $0.friendId == f.friendId }) }
        result.append(contentsOf: remaining)
        return Array(result.prefix(5))
    }
    
    private var sendToFriendCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: didSendToFriend ? "checkmark.circle.fill" : "paperplane.fill")
                    .font(.ds_labelMedium)
                    .foregroundColor(didSendToFriend ? .green : workoutGradient[0])
                Text(didSendToFriend ? "Workout Sent" : "Send Workout to Friend")
                    .font(.ds_heading3)
                    .foregroundColor(.primary)
                Spacer()
            }
            
            if didSendToFriend {
                sendToFriendSuccessBody
            } else if let friend = selectedFriendForSend {
                sendToFriendComposeBody(friend: friend)
            } else if friendService.friends.isEmpty {
                sendToFriendEmptyBody
            } else {
                sendToFriendPickerBody
            }
        }
    }
    
    private var sendToFriendPickerBody: some View {
        // Extend edge-to-edge by cancelling the parent VStack's horizontal
        // padding so the friend avatars "float" past the normal content
        // margin and can scroll naturally to either edge of the screen.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.md) {
                // Search/browse all friends
                Button(action: {
                    HapticManager.impact(.light)
                    showingFriendSearch = true
                }) {
                    VStack(spacing: Spacing.xs) {
                        ZStack {
                            Circle()
                                .fill(Color.cardBackground)
                                .frame(width: 56, height: 56)
                                .overlay(
                                    Circle()
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1.5)
                                )
                            Image(systemName: "magnifyingglass")
                                .font(.ds_heading3)
                                .foregroundColor(.secondary)
                        }
                        Text("Search")
                            .font(.ds_bodySmall)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .frame(width: 64)
                }
                .buttonStyle(PlainButtonStyle())
                
                ForEach(friendsForPicker) { friend in
                    Button(action: {
                        HapticManager.impact(.light)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            selectedFriendForSend = friend
                        }
                    }) {
                        VStack(spacing: Spacing.xs) {
                            CachedFriendPhoto(
                                friendId: friend.friendId.uuidString,
                                photoUrl: friend.profilePhotoUrl,
                                name: friend.friendName ?? friend.friendUsername ?? "Friend",
                                size: 56,
                                showGradientRing: false,
                                gradientColors: [workoutGradient[0], workoutGradient[0].opacity(0.7)]
                            )
                            Text(friend.displayName.components(separatedBy: " ").first ?? friend.displayName)
                                .font(.ds_bodySmall)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }
                        .frame(width: 64)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xxs)
        }
        .padding(.horizontal, -Spacing.md)
    }
    
    private func sendToFriendComposeBody(friend: Friend) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                CachedFriendPhoto(
                    friendId: friend.friendId.uuidString,
                    photoUrl: friend.profilePhotoUrl,
                    name: friend.friendName ?? friend.friendUsername ?? "Friend",
                    size: 44,
                    showGradientRing: true,
                    gradientColors: [workoutGradient[0], workoutGradient[0].opacity(0.7)]
                )
                VStack(alignment: .leading, spacing: Spacing.xxxs) {
                    Text("Sending to")
                        .font(.ds_bodySmall)
                        .foregroundColor(.secondary)
                    Text(friend.displayName)
                        .font(.ds_labelLarge)
                        .foregroundColor(.primary)
                }
                Spacer()
                Button(action: {
                    HapticManager.selectionChanged()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        selectedFriendForSend = nil
                        friendMessageText = ""
                    }
                }) {
                    Text("Change")
                        .font(.ds_labelMedium)
                        .foregroundColor(workoutGradient[0])
                }
            }
            
            TextField("Add a message (optional)", text: $friendMessageText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.ds_bodyMedium)
                .padding(Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                        .fill(Color.cardBackground)
                )
                .lineLimit(2...4)
            
            Button(action: sendWorkoutToSelectedFriend) {
                HStack(spacing: Spacing.xs) {
                    if isSendingToFriend {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.ds_labelLarge)
                        Text("Send Workout")
                            .font(.ds_labelLarge)
                            .fontWeight(.bold)
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
                .background(
                    LinearGradient(
                        colors: workoutGradient,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
            }
            .disabled(isSendingToFriend)
            .buttonStyle(UniversalScaleButtonStyle(scale: .standard))
        }
        .padding(.horizontal, Spacing.md)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
    
    private var sendToFriendSuccessBody: some View {
        HStack(spacing: Spacing.sm) {
            if let friend = selectedFriendForSend {
                CachedFriendPhoto(
                    friendId: friend.friendId.uuidString,
                    photoUrl: friend.profilePhotoUrl,
                    name: friend.friendName ?? friend.friendUsername ?? "Friend",
                    size: 40,
                    showGradientRing: true,
                    gradientColors: [.green, .teal]
                )
                VStack(alignment: .leading, spacing: Spacing.xxxs) {
                    Text("Sent to \(friend.displayName)")
                        .font(.ds_labelMedium)
                        .foregroundColor(.primary)
                    Text("They'll see it in their activity feed")
                        .font(.ds_bodySmall)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
        .padding(.horizontal, Spacing.md)
        .transition(.opacity)
    }
    
    private var sendToFriendEmptyBody: some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: "person.2.slash")
                .font(.ds_heading3)
                .foregroundColor(.secondary)
            Text("Add friends from the Friends tab to share workouts in-app")
                .font(.ds_bodySmall)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.md)
        .padding(.bottom, Spacing.sm)
    }
    
    private func sendWorkoutToSelectedFriend() {
        guard let friend = selectedFriendForSend else { return }
        isSendingToFriend = true
        
        // Snapshot the completed workout's exercises/sets so we can build
        // `SharedExercise` payloads off-main without touching the managed
        // context later. We use the `WorkoutExercise` relation on the
        // Core Data `workout` to recover completed set counts and best reps.
        let workoutExercises = (workout.exercises?.allObjects as? [WorkoutExercise] ?? [])
            .sorted { $0.order < $1.order }
        
        let sharedExercises: [SharedExercise] = workoutExercises.compactMap { we in
            guard let name = we.exercise?.name ?? we.exercise?.displayName else { return nil }
            let sets = we.sets?.allObjects as? [WorkoutSet] ?? []
            let completedSets = sets.filter { $0.isCompleted }
            let repsString: String
            if let bestSet = completedSets.max(by: { $0.reps < $1.reps }) {
                repsString = "\(bestSet.reps)"
            } else {
                repsString = "8-12"
            }
            return SharedExercise(
                exerciseId: we.exercise?.id?.uuidString,
                name: name,
                sets: completedSets.count,
                reps: repsString,
                restSeconds: nil,
                notes: nil
            )
        }
        
        let nameToSend = workout.name ?? "Workout"
        let durationMinutes = Int(workoutDuration) / 60
        let message = friendMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        Task {
            let success = await friendService.sendWorkoutToFriend(
                toUserId: friend.friendId,
                workoutName: nameToSend,
                exercises: sharedExercises,
                description: "Shared from completed workout",
                message: message.isEmpty ? nil : message,
                duration: durationMinutes,
                difficulty: "Custom"
            )
            await MainActor.run {
                isSendingToFriend = false
                if success {
                    HapticManager.notification(.success)
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        didSendToFriend = true
                    }
                } else {
                    HapticManager.notification(.error)
                    sendToFriendError = "Failed to send workout. Please try again."
                }
            }
        }
    }
    
    private func statPill(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.ds_bodySmall)
                    .foregroundColor(workoutGradient[0])
                Text(value)
                    .font(.ds_statSmall)
                    .foregroundColor(.primary)
            }
            Text(label)
                .font(.ds_labelSmall)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func finishAndDismiss() {
        HapticManager.notification(.success)
        if !completionNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            workout.notes = completionNotes
            try? workout.managedObjectContext?.save()
        }
        workoutManager.finishWorkout()
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.3))
            guard !Task.isCancelled else { return }
            workoutManager.navigateToHomeTab()
        }
    }
    
    // MARK: - Inline Replay Insights
    private var inlineReplaySection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "sparkles")
                    .font(.ds_labelLarge)
                    .foregroundStyle(
                        LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                Text("Workout Replay")
                    .font(.ds_heading3)
                    .foregroundColor(.primary)
                Spacer()
            }
            
            ForEach(Array(replayInsights.enumerated()), id: \.element.id) { index, insight in
                completionInsightCard(insight)
                    .onAppear {
                        let delay = Double(index) * 0.1
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8).delay(delay)) {
                            visibleInsightCards.insert(index)
                        }
                    }
                    .opacity(visibleInsightCards.contains(index) ? 1 : 0)
                    .offset(y: visibleInsightCards.contains(index) ? 0 : 20)
            }
        }
    }
    
    private func completionInsightCard(_ insight: WorkoutInsightCard) -> some View {
        HStack(spacing: Spacing.sm) {
            ZStack {
                Circle()
                    .fill(insight.iconColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: insight.icon)
                    .font(.ds_labelLarge)
                    .foregroundColor(insight.iconColor)
            }
            
            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                Text(insight.headline)
                    .font(.ds_labelMedium)
                    .foregroundColor(.primary)
                Text(insight.detail)
                    .font(.ds_bodySmall)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .adaptiveSleekCard(cornerRadius: CornerRadius.lg, accentColor: insight.iconColor)
    }
    
    // exerciseBreakdownCard and collapsedNotesSection merged into unifiedStatsCard
    
    // MARK: - Progress Photo Prompt
    private var progressPhotoPrompt: some View {
        Group {
            let days = ProgressPhotoService.shared.daysSinceLastPhoto
            if days == nil || (days ?? 0) >= 14 {
                Button(action: {
                    HapticManager.impact(.light)
                    showingProgressPhotoCapture = true
                }) {
                    HStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(LinearGradient(colors: [.purple, .pink], startPoint: .top, endPoint: .bottom))
                            .frame(width: 3)
                            .padding(.vertical, Spacing.xs)
                        
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "camera.fill")
                                .font(.ds_bodyRegular)
                                .foregroundColor(.purple)
                            
                            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                                Text("Take a Progress Photo")
                                    .font(.ds_labelMedium)
                                    .foregroundColor(.primary)
                                Text(days.map { "It's been \($0) days since your last photo" } ?? "Start tracking your transformation")
                                    .font(.ds_bodySmall)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.ds_labelMedium)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                            .fill(Color.cardBackground)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Delete Workout (Migration #155)

    /// Always-visible button anchored at the very bottom of the completion
    /// flow. Tapping triggers `showingDeleteConfirmation`; on confirm we
    /// call `WorkoutManager.deleteCompletedWorkout` which atomically
    /// reverses every server-side AND local stat side-effect.
    ///
    /// UX guard: if the workout has been shared with a friend
    /// (`didSendToFriend == true`) the button is disabled with explanatory
    /// secondary text, because the friend already received the data and
    /// we don't have an "un-share" path. Cancel-the-friend-message is the
    /// user's recourse there.
    private var deleteWorkoutButton: some View {
        Group {
            if didSendToFriend {
                VStack(alignment: .leading, spacing: Spacing.xxxs) {
                    Text("Delete unavailable")
                        .font(.ds_labelMedium)
                        .foregroundColor(.secondary)
                    Text("Already shared with a friend — they have the workout details.")
                        .font(.ds_bodySmall)
                        .foregroundColor(.secondary.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                        .fill(Color.cardBackground.opacity(0.5))
                )
            } else {
                Button(action: {
                    HapticManager.impact(.medium)
                    showingDeleteConfirmation = true
                }) {
                    HStack(spacing: Spacing.sm) {
                        if isDeletingWorkout {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.red)
                        } else {
                            Image(systemName: "trash")
                                .font(.ds_bodyRegular)
                                .foregroundColor(.red)
                        }
                        Text(isDeletingWorkout ? "Deleting…" : "Delete Workout")
                            .font(.ds_labelMedium)
                            .foregroundColor(.red)
                        Spacer()
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                            .stroke(Color.red.opacity(0.3), lineWidth: 1)
                            .background(
                                RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                                    .fill(Color.red.opacity(0.06))
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(isDeletingWorkout)
                .accessibilityLabel("Delete workout")
                .accessibilityHint("Permanently removes this workout and reverses all stats")
            }
        }
    }

    /// Perform the delete + revert flow. Called from the confirmation
    /// alert. Dismisses the completion view + navigates home on success.
    @MainActor
    private func performDeleteWorkout() async {
        guard !isDeletingWorkout else { return }
        isDeletingWorkout = true
        defer { isDeletingWorkout = false }

        let outcome = await workoutManager.deleteCompletedWorkout(workout)

        guard outcome.success else {
            deleteWorkoutError = outcome.errorMessage ?? "Something went wrong while deleting this workout. Please try again."
            return
        }

        HapticManager.notification(.success)
        // Dismiss the completion view, then navigate home on the next tick
        // so the dismiss animation completes before the tab switch.
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.3))
            guard !Task.isCancelled else { return }
            workoutManager.navigateToHomeTab()
        }
    }

    // doneButton replaced by stickyActionBar
    
    // MARK: - Helper Functions
    
    private func loadCalories() {
        // If calories are already on the workout (from saveWorkoutToAppleHealth), use them
        if workout.caloriesBurned > 0 {
            estimatedCalories = Int(workout.caloriesBurned)
            return
        }
        
        // Otherwise calculate asynchronously and poll for the value
        Task {
            // Brief delay to let the async calorie save from finishWorkout() complete
            for _ in 0..<10 {
                try? await Task.sleep(for: .seconds(0.5))
                let cal = workout.caloriesBurned
                if cal > 0 {
                    await MainActor.run { estimatedCalories = Int(cal) }
                    return
                }
            }
        }
    }
    
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
        var xp = 50
        xp += exercises.count * 10
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
        .cornerRadius(CornerRadius.sm)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
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
        case "back": return "figure.rower"
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
                .fill(Color.cardBackground)
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
