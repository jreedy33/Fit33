import SwiftUI
import AVKit
import AVFoundation

struct StretchModeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    // Flow state
    @State private var showingSplash = true
    @State private var selectedArea: String? = nil
    @State private var stretchQueue: [ExerciseDTO] = []
    @State private var currentStretchIndex = 0
    @State private var isLoadingStretches = false
    
    // Timer state
    @State private var totalSeconds: Int = 180 // Default 3:00
    @State private var remainingSeconds: Int = 180
    @State private var isRunning = false
    @State private var timer: Timer?
    
    // Video state
    @State private var player: AVPlayer?
    @State private var queuePlayer: AVQueuePlayer?
    @State private var playerLooper: AVPlayerLooper?
    @State private var currentExerciseName: String = "Loading..."
    @State private var isLoadingVideo = true
    
    // Animation
    @State private var breatheScale: CGFloat = 1.0
    
    private let circleSize: CGFloat = 280
    
    var body: some View {
        ZStack {
            // Ambient background
            backgroundGradient
            
            if showingSplash {
                StretchSplashView(
                    selectedArea: $selectedArea,
                    isLoading: $isLoadingStretches,
                    onStart: loadStretchesForArea,
                    onDismiss: { dismiss() }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                stretchTimerView
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
            }
        }
        .onDisappear {
            stopTimer()
            // Proper cleanup of AVPlayerLooper
            playerLooper?.disableLooping()
            queuePlayer?.pause()
            player?.pause()
            playerLooper = nil
            queuePlayer = nil
            player = nil
        }
    }
    
    // MARK: - Stretch Timer View
    
    private var stretchTimerView: some View {
        VStack(spacing: 0) {
            // Header
            headerView
                .padding(.top, 10)
            
            Spacer()
            
            // Timer above video
            timerBadge
            
            Spacer()
                .frame(height: 24)
            
            // Main circular video
            ZStack {
                // Outer glow when running
                if isRunning {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.green.opacity(0.3), Color.clear],
                                center: .center,
                                startRadius: circleSize / 2,
                                endRadius: circleSize / 2 + 40
                            )
                        )
                        .frame(width: circleSize + 80, height: circleSize + 80)
                        .scaleEffect(breatheScale)
                }
                
                // Progress ring (background)
                Circle()
                    .stroke(
                        Color.white.opacity(0.1),
                        lineWidth: 8
                    )
                    .frame(width: circleSize + 20, height: circleSize + 20)
                
                // Progress ring (foreground)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(
                            colors: [.green, .mint, .teal, .green],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: circleSize + 20, height: circleSize + 20)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: progress)
                
                // Video container (circular)
                ZStack {
                    // Background for video
                    Circle()
                        .fill(Color.black)
                        .frame(width: circleSize, height: circleSize)
                    
                    if isLoadingVideo {
                        // Loading state
                        VStack(spacing: 12) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.2)
                            Text("Loading stretch...")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    } else if let player = player {
                        // Video player
                        VideoPlayerCircle(player: player)
                            .frame(width: circleSize, height: circleSize)
                            .clipShape(Circle())
                    }
                }
            }
            
            Spacer()
            
            // Exercise name + progress
            VStack(spacing: 8) {
                Text(currentExerciseName)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                // Progress dots
                if stretchQueue.count > 1 {
                    HStack(spacing: 8) {
                        ForEach(0..<stretchQueue.count, id: \.self) { index in
                            Circle()
                                .fill(index == currentStretchIndex ? Color.mint : Color.white.opacity(0.3))
                                .frame(width: index == currentStretchIndex ? 10 : 6, height: index == currentStretchIndex ? 10 : 6)
                                .animation(.spring(response: 0.3), value: currentStretchIndex)
                        }
                    }
                    
                    Text("\(currentStretchIndex + 1) of \(stretchQueue.count)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            
            Spacer()
            
            // Controls
            controlsView
            
            Spacer()
            
            // Time adjustment
            timeAdjustmentView
                .padding(.bottom, 50)
        }
        .onAppear {
            startBreathingAnimation()
        }
    }
    
    // MARK: - Subviews
    
    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.1, blue: 0.15),
                Color(red: 0.1, green: 0.15, blue: 0.2),
                Color(red: 0.05, green: 0.12, blue: 0.18)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
    
    private var headerView: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            VStack(spacing: 2) {
                Text("STRETCH MODE")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.mint.opacity(0.8))
                    .tracking(2)
                
                if let area = selectedArea {
                    Text("🧘 \(area)")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            
            Spacer()
            
            // Back to selection
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    stopTimer()
                    player?.pause()
                    showingSplash = true
                }
            }) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
    
    private var timerBadge: some View {
        Text(timeString)
            .font(.system(size: 56, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 2)
    }
    
    private var controlsView: some View {
        HStack(spacing: 40) {
            // Previous button
            Button(action: previousStretch) {
                VStack(spacing: 6) {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                    Text("Prev")
                        .font(.caption2)
                }
                .foregroundColor(currentStretchIndex > 0 ? .white.opacity(0.7) : .white.opacity(0.3))
                .frame(width: 60)
            }
            .disabled(currentStretchIndex == 0)
            
            // Play/Pause button
            Button(action: toggleTimer) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: isRunning ? [.orange, .red] : [.green, .mint],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 72, height: 72)
                        .shadow(color: (isRunning ? Color.orange : Color.green).opacity(0.4), radius: 10)
                    
                    Image(systemName: isRunning ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .offset(x: isRunning ? 0 : 2)
                }
            }
            
            // Next button
            Button(action: nextStretch) {
                VStack(spacing: 6) {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                    Text("Next")
                        .font(.caption2)
                }
                .foregroundColor(currentStretchIndex < stretchQueue.count - 1 ? .white.opacity(0.7) : .white.opacity(0.3))
                .frame(width: 60)
            }
            .disabled(currentStretchIndex >= stretchQueue.count - 1)
        }
    }
    
    private var timeAdjustmentView: some View {
        VStack(spacing: 10) {
            Text("DURATION")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.white.opacity(0.4))
                .tracking(1)
            
            HStack(spacing: 12) {
                ForEach([30, 60, 90, 120], id: \.self) { seconds in
                    Button(action: { setDuration(seconds) }) {
                        Text(formatTime(seconds))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(totalSeconds == seconds ? .black : .white.opacity(0.7))
                            .padding(.horizontal, 14)
                            .padding(.vertical, Spacing.xs)
                            .background(
                                Capsule()
                                    .fill(totalSeconds == seconds ? Color.mint : Color.white.opacity(0.1))
                            )
                    }
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var progress: CGFloat {
        guard totalSeconds > 0 else { return 0 }
        return CGFloat(remainingSeconds) / CGFloat(totalSeconds)
    }
    
    private var timeString: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // MARK: - Methods
    
    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        if secs == 0 {
            return "\(minutes)m"
        }
        return "\(minutes):\(String(format: "%02d", secs))"
    }
    
    private func setDuration(_ seconds: Int) {
        totalSeconds = seconds
        remainingSeconds = seconds
        stopTimer()
    }
    
    private func toggleTimer() {
        if isRunning {
            stopTimer()
        } else {
            startTimer()
        }
    }
    
    private func startTimer() {
        isRunning = true
        player?.play()
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if remainingSeconds > 0 {
                remainingSeconds -= 1
            } else {
                // Timer complete - go to next stretch or loop
                if currentStretchIndex < stretchQueue.count - 1 {
                    nextStretch()
                } else {
                    // All done - restart from beginning
                    currentStretchIndex = 0
                    loadCurrentStretch()
                }
                remainingSeconds = totalSeconds
            }
        }
    }
    
    private func stopTimer() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }
    
    private func startBreathingAnimation() {
        withAnimation(
            .easeInOut(duration: 4)
            .repeatForever(autoreverses: true)
        ) {
            breatheScale = 1.1
        }
    }
    
    private func previousStretch() {
        guard currentStretchIndex > 0 else { return }
        currentStretchIndex -= 1
        remainingSeconds = totalSeconds
        loadCurrentStretch()
    }
    
    private func nextStretch() {
        guard currentStretchIndex < stretchQueue.count - 1 else { return }
        currentStretchIndex += 1
        remainingSeconds = totalSeconds
        loadCurrentStretch()
    }
    
    private func loadStretchesForArea() {
        guard let area = selectedArea else { return }
        isLoadingStretches = true
        
        Task {
            do {
                let allExercises = try await SupabaseManager.shared.fetchAllExercisesRaw()
                
                // Filter for stretching exercises with videos that match the selected area
                let stretchingExercises = allExercises.filter { exercise in
                    guard let videoFilename = exercise.videoFilename, !videoFilename.isEmpty else {
                        return false
                    }
                    
                    let name = exercise.name.lowercased()
                    let category = exercise.category.lowercased()
                    let workoutType = (exercise.workoutType ?? "").lowercased()
                    let primaryMuscles = exercise.primaryMusclesArray.joined(separator: " ").lowercased()
                    let secondaryMuscles = exercise.secondaryMusclesArray.joined(separator: " ").lowercased()
                    let allText = "\(name) \(category) \(primaryMuscles) \(secondaryMuscles)"
                    
                    // Must be a stretch
                    let isStretch = workoutType.contains("stretch") ||
                                   category.contains("stretch") ||
                                   name.contains("stretch")
                    
                    guard isStretch else { return false }
                    
                    // Strict body part filtering - only show stretches for the selected area
                    let areaLower = area.lowercased()
                    
                    switch areaLower {
                    case "upper body":
                        // Upper body: chest, back, shoulders, arms, upper body
                        return ["chest", "back", "shoulder", "arm", "bicep", "tricep", "upper", "pec", "lat", "delt", "trapezius", "rotator"].contains(where: { 
                            allText.contains($0)
                        })
                        
                    case "lower body":
                        // Lower body: legs, hips, glutes, lower body
                        return ["leg", "quad", "hamstring", "calf", "glute", "hip", "thigh", "lower", "adductor", "abductor", "groin", "ankle"].contains(where: { 
                            allText.contains($0)
                        })
                        
                    case "back":
                        // Back: all back muscles
                        return ["back", "lat", "spine", "lumbar", "thoracic", "erector", "rhomboid", "trapezius"].contains(where: { 
                            allText.contains($0)
                        })
                        
                    case "hips":
                        // Hips: hip flexors, glutes, hip area
                        return ["hip", "glute", "groin", "adductor", "abductor", "psoas", "piriformis", "flexor"].contains(where: { 
                            allText.contains($0)
                        })
                        
                    case "shoulders":
                        // Shoulders: deltoids, rotator cuff
                        return ["shoulder", "delt", "rotator", "cuff"].contains(where: { 
                            allText.contains($0)
                        })
                        
                    case "legs":
                        // Legs: quads, hamstrings, calves, thighs - STRICTLY legs only
                        return ["leg", "quad", "hamstring", "calf", "thigh", "gastrocnemius", "soleus", "tibialis", "knee"].contains(where: { 
                            allText.contains($0)
                        }) && !allText.contains("hip") // Exclude hip stretches from leg category
                        
                    case "neck":
                        // Neck: cervical spine, neck muscles, upper traps
                        return ["neck", "cervical", "sternocleidomastoid", "levator scapulae"].contains(where: { 
                            allText.contains($0)
                        }) || (allText.contains("trap") && !allText.contains("lower"))
                        
                    case "full body":
                        // Full body: all stretches qualify
                        return true
                        
                    default:
                        // Fallback: direct name match only
                        return allText.contains(areaLower)
                    }
                }
                
                // Shuffle and take 5-8 stretches for variety
                let numStretches = min(stretchingExercises.count, 8)
                let selectedStretches = Array(stretchingExercises.shuffled().prefix(numStretches))
                
                print("🧘 Selected \(selectedStretches.count) stretches for \(area):")
                selectedStretches.forEach { print("   - \($0.name)") }
                
                await MainActor.run {
                    stretchQueue = selectedStretches
                    currentStretchIndex = 0
                    isLoadingStretches = false
                    
                    if !stretchQueue.isEmpty {
                        // Set shorter duration for stretches (30-60 seconds each)
                        totalSeconds = 60
                        remainingSeconds = 60
                        
                        withAnimation(.easeInOut(duration: 0.4)) {
                            showingSplash = false
                        }
                        loadCurrentStretch()
                    }
                }
            } catch {
                print("❌ Error fetching stretches: \(error)")
                await MainActor.run {
                    isLoadingStretches = false
                }
            }
        }
    }
    
    private func loadCurrentStretch() {
        guard currentStretchIndex < stretchQueue.count else { return }
        
        isLoadingVideo = true
        player?.pause()
        
        let exercise = stretchQueue[currentStretchIndex]
        currentExerciseName = exercise.name
        
        if let videoFilename = exercise.videoFilename {
            let baseURL = "https://pub-7838a3e2cbc24d59a6c4d2b2d6239bea.r2.dev"
            let urlString = "\(baseURL)/\(videoFilename)"
            
            if let encodedURLString = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let url = URL(string: encodedURLString) {
                print("🧘 Loading stretch video: \(url.absoluteString)")
                setupPlayer(with: url)
            }
        }
        
        isLoadingVideo = false
    }
    
    private func setupPlayer(with url: URL) {
        let playerItem = AVPlayerItem(url: url)
        
        // Use AVQueuePlayer + AVPlayerLooper for seamless looping (no gaps)
        let newQueuePlayer = AVQueuePlayer(playerItem: playerItem)
        newQueuePlayer.isMuted = true
        
        // ⚡️ CRITICAL: Store looper reference to prevent deallocation
        playerLooper = AVPlayerLooper(player: newQueuePlayer, templateItem: playerItem)
        
        queuePlayer = newQueuePlayer
        player = newQueuePlayer
        newQueuePlayer.play()
        print("🎬 Video playing: \(url.lastPathComponent)")
    }
}

// MARK: - Splash View

struct StretchSplashView: View {
    @Binding var selectedArea: String?
    @Binding var isLoading: Bool
    let onStart: () -> Void
    let onDismiss: () -> Void
    
    private let stretchAreas: [(name: String, icon: String, color: Color)] = [
        ("Upper Body", "figure.arms.open", .blue),
        ("Lower Body", "figure.run", .green),
        ("Back", "figure.stand", .purple),
        ("Hips", "figure.flexibility", .orange),
        ("Shoulders", "figure.arms.open", .cyan),
        ("Legs", "figure.walk", .mint),
        ("Neck", "person.bust", .pink),
        ("Full Body", "figure.cooldown", .indigo)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.6))
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            Spacer()
            
            // Main content
            VStack(spacing: 32) {
                // Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.teal, Color.mint],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .shadow(color: .teal.opacity(0.3), radius: 12, x: 0, y: 6)
                    
                    Text("🧘")
                        .font(.system(size: 50))
                }
                
                VStack(spacing: 12) {
                    Text("Stretch Mode")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("What area would you like to stretch?")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
            }
            
            Spacer()
                .frame(height: 32)
            
            // Area selection grid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(stretchAreas, id: \.name) { area in
                    StretchAreaCard(
                        name: area.name,
                        icon: area.icon,
                        color: area.color,
                        isSelected: selectedArea == area.name,
                        onTap: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedArea = area.name
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 20)
            
            Spacer()
            
            // Start button
            Button(action: onStart) {
                HStack(spacing: 12) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("Start Stretching")
                            .font(.headline)
                            .fontWeight(.semibold)
                        Image(systemName: "arrow.right")
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    LinearGradient(
                        colors: selectedArea != nil ? [Color.teal, Color.mint] : [Color.gray, Color.gray.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(CornerRadius.lg)
                .shadow(color: selectedArea != nil ? .teal.opacity(0.3) : .clear, radius: 12, x: 0, y: 6)
            }
            .disabled(selectedArea == nil || isLoading)
            .opacity(selectedArea == nil ? 0.5 : 1.0)
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }
}

struct StretchAreaCard: View {
    let name: String
    let icon: String
    let color: Color
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(color.opacity(0.3))
                            .frame(width: 44, height: 44)
                            .blur(radius: 8)
                    }
                    
                    Circle()
                        .fill(
                            isSelected
                                ? LinearGradient(colors: [color, color.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [Color.white.opacity(0.1), Color.white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                }
                
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(isSelected ? color : .white.opacity(0.8))
                
                Spacer()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .stroke(isSelected ? color.opacity(0.6) : Color.white.opacity(0.1), lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: isSelected ? color.opacity(0.3) : .clear, radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Circular Video Player
struct VideoPlayerCircle: UIViewControllerRepresentable {
    let player: AVPlayer
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill
        controller.view.backgroundColor = .clear
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
    }
}

// MARK: - Preview
#Preview {
    StretchModeView()
}
