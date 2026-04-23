import SwiftUI
import AVKit
import AVFoundation
import Combine

struct StretchModeView: View {
    @Binding var isPresented: Bool
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    
    // Flow state
    @State private var showingSplash = true
    @State private var selectedArea: String? = nil
    @State private var stretchQueue: [ExerciseDTO] = []
    @State private var currentStretchIndex = 0
    @State private var isLoadingStretches = false
    @State private var showCompletion = false
    @State private var fetchError: String?
    
    // Timer state
    @State private var totalSeconds: Int = 60
    @State private var remainingSeconds: Int = 60
    @State private var isRunning = false
    @State private var timerTask: Task<Void, Never>?
    @State private var totalStretchesCompleted: Int = 0
    @State private var sessionStartTime: Date?
    
    // Video state
    @State private var player: AVPlayer?
    @State private var queuePlayer: AVQueuePlayer?
    @State private var playerLooper: AVPlayerLooper?
    @State private var currentExerciseName: String = "Loading..."
    @State private var isLoadingVideo = true
    @State private var videoStatusObserver: NSKeyValueObservation?
    
    // Animation
    @State private var breatheScale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.05, blue: 0.07)
                .ignoresSafeArea()
            
            AnimatedOrbBackground.stretch(colorScheme: colorScheme)
            
            GeometryReader { geometry in
                let circleSize = min(240, geometry.size.width - 80)
                
                if showCompletion {
                    completionView
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else if showingSplash {
                    StretchSplashView(
                        selectedArea: $selectedArea,
                        isLoading: $isLoadingStretches,
                        fetchError: $fetchError,
                        onStart: loadStretchesForArea,
                        onDismiss: { dismissStretchMode() }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    stretchTimerView(circleSize: circleSize)
                        .transition(.opacity.combined(with: .scale(scale: 1.02)))
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .onDisappear {
            cleanupResources()
        }
    }
    
    private func dismissStretchMode() {
        cleanupResources()
        withAnimation(.easeInOut(duration: 0.3)) {
            isPresented = false
        }
    }
    
    private func cleanupResources() {
        stopTimer()
        videoStatusObserver?.invalidate()
        videoStatusObserver = nil
        playerLooper?.disableLooping()
        queuePlayer?.pause()
        player?.pause()
        playerLooper = nil
        queuePlayer = nil
        player = nil
    }
    
    // MARK: - Stretch Timer View
    
    private func stretchTimerView(circleSize: CGFloat) -> some View {
        VStack(spacing: 0) {
            headerView
            
            Spacer(minLength: Spacing.xs)
            
            timerBadge
                .padding(.bottom, Spacing.sm)
            
            videoCircleView(circleSize: circleSize)
            
            exerciseInfoView
                .padding(.top, Spacing.sm)
            
            Spacer(minLength: Spacing.xs)
            
            controlsView
                .padding(.bottom, Spacing.sm)
            
            timeAdjustmentView
                .padding(.bottom, Spacing.md)
        }
        .onAppear {
            startBreathingAnimation()
        }
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        HStack {
            Button(action: { dismissStretchMode() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.ds_heading2)
                    .foregroundColor(.white.opacity(0.6))
            }
            .accessibilityLabel("Close stretch mode")
            .accessibilityHint("Double tap to end stretch session")
            
            Spacer()
            
            VStack(spacing: Spacing.xxxs) {
                Text("STRETCH MODE")
                    .font(.ds_caption)
                    .fontWeight(.bold)
                    .foregroundColor(.mint.opacity(0.8))
                    .tracking(2)
                
                if let area = selectedArea {
                    Text("\(area)")
                        .font(.ds_caption)
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .accessibilityElement(children: .combine)
            
            Spacer()
            
            Button(action: {
                HapticManager.impact(.light)
                withAnimation(.easeInOut(duration: 0.3)) {
                    stopTimer()
                    player?.pause()
                    showingSplash = true
                }
            }) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.ds_heading2)
                    .foregroundColor(.white.opacity(0.6))
            }
            .accessibilityLabel("Back to area selection")
            .accessibilityHint("Double tap to choose a different stretch area")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.sm)
    }
    
    private var timerBadge: some View {
        Text(timeString)
            .font(.ds_timer)
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.3), radius: Spacing.xs, x: 0, y: Spacing.xxxs)
            .accessibilityLabel("\(remainingSeconds) seconds remaining")
            .accessibilityValue(timeString)
    }
    
    private func videoCircleView(circleSize: CGFloat) -> some View {
        ZStack {
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
                    .accessibilityHidden(true)
            }
            
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 8)
                .frame(width: circleSize + 20, height: circleSize + 20)
                .accessibilityHidden(true)
            
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
                .accessibilityHidden(true)
            
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: circleSize, height: circleSize)
                
                if isLoadingVideo {
                    VStack(spacing: Spacing.sm) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .gray))
                            .scaleEffect(1.2)
                        Text("Loading stretch...")
                            .font(.ds_caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                } else if let player = player {
                    VideoPlayerCircle(player: player)
                        .frame(width: circleSize, height: circleSize)
                        .clipShape(Circle())
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stretch video for \(currentExerciseName)")
    }
    
    private var exerciseInfoView: some View {
        VStack(spacing: Spacing.xs) {
            Text(currentExerciseName)
                .font(.ds_heading2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl + Spacing.xs)
            
            if stretchQueue.count > 1 {
                HStack(spacing: Spacing.xs) {
                    ForEach(0..<stretchQueue.count, id: \.self) { index in
                        Circle()
                            .fill(index == currentStretchIndex ? Color.mint : Color.white.opacity(0.3))
                            .frame(
                                width: index == currentStretchIndex ? 10 : 6,
                                height: index == currentStretchIndex ? 10 : 6
                            )
                            .animation(.spring(response: 0.3), value: currentStretchIndex)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Stretch \(currentStretchIndex + 1) of \(stretchQueue.count)")
                
                Text("\(currentStretchIndex + 1) of \(stretchQueue.count)")
                    .font(.ds_caption)
                    .foregroundColor(.white.opacity(0.5))
                    .accessibilityHidden(true)
            }
        }
    }
    
    private var controlsView: some View {
        HStack(spacing: Spacing.xl + Spacing.xs) {
            Button(action: {
                HapticManager.impact(.light)
                previousStretch()
            }) {
                VStack(spacing: Spacing.xxs + Spacing.xxxs) {
                    Image(systemName: "backward.fill")
                        .font(.ds_heading2)
                    Text("Prev")
                        .font(.ds_labelSmall)
                }
                .foregroundColor(currentStretchIndex > 0 ? .white.opacity(0.7) : .white.opacity(0.3))
                .frame(width: 60)
            }
            .disabled(currentStretchIndex == 0)
            .accessibilityLabel("Previous stretch")
            .accessibilityHint(currentStretchIndex > 0 ? "Double tap to go to previous stretch" : "No previous stretch available")
            
            Button(action: {
                HapticManager.impact(.light)
                toggleTimer()
            }) {
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
                        .font(.ds_heading2)
                        .foregroundColor(.white)
                        .offset(x: isRunning ? 0 : 2)
                }
            }
            .accessibilityLabel(isRunning ? "Pause stretch" : "Resume stretch")
            .accessibilityHint("Double tap to \(isRunning ? "pause" : "start") the timer")
            
            Button(action: {
                HapticManager.impact(.light)
                nextStretch()
            }) {
                VStack(spacing: Spacing.xxs + Spacing.xxxs) {
                    Image(systemName: "forward.fill")
                        .font(.ds_heading2)
                    Text("Next")
                        .font(.ds_labelSmall)
                }
                .foregroundColor(currentStretchIndex < stretchQueue.count - 1 ? .white.opacity(0.7) : .white.opacity(0.3))
                .frame(width: 60)
            }
            .disabled(currentStretchIndex >= stretchQueue.count - 1)
            .accessibilityLabel("Next stretch")
            .accessibilityHint(currentStretchIndex < stretchQueue.count - 1 ? "Double tap to skip to next stretch" : "No more stretches available")
        }
    }
    
    private var timeAdjustmentView: some View {
        VStack(spacing: Spacing.xs + Spacing.xxxs) {
            Text("DURATION")
                .font(.ds_labelSmall)
                .fontWeight(.medium)
                .foregroundColor(.white.opacity(0.4))
                .tracking(1)
                .accessibilityHidden(true)
            
            HStack(spacing: Spacing.sm) {
                ForEach([30, 60, 90, 120], id: \.self) { seconds in
                    Button(action: {
                        HapticManager.impact(.light)
                        setDuration(seconds)
                    }) {
                        Text(formatTime(seconds))
                            .font(.ds_bodyMedium)
                            .fontWeight(.semibold)
                            .foregroundColor(totalSeconds == seconds ? .black : .white.opacity(0.7))
                            .padding(.horizontal, Spacing.sm + Spacing.xxxs)
                            .padding(.vertical, Spacing.xs)
                            .background(
                                Capsule()
                                    .fill(totalSeconds == seconds ? Color.mint : Color.white.opacity(0.1))
                            )
                    }
                    .accessibilityLabel("Set duration to \(formatTime(seconds))")
                    .accessibilityAddTraits(totalSeconds == seconds ? .isSelected : [])
                }
            }
        }
    }
    
    // MARK: - Completion View
    
    private var completionView: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.teal, Color.mint],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                    .shadow(color: .teal.opacity(0.4), radius: Spacing.md, x: 0, y: Spacing.xs)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.white)
            }
            .accessibilityHidden(true)
            
            VStack(spacing: Spacing.sm) {
                Text("Session Complete!")
                    .font(.ds_displayMedium)
                    .foregroundColor(.white)
                
                Text("Great stretch session")
                    .font(.ds_bodyLarge)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            HStack(spacing: Spacing.xl) {
                VStack(spacing: Spacing.xxs) {
                    Text("\(totalStretchesCompleted)")
                        .font(.ds_stat)
                        .foregroundColor(.mint)
                    Text("Stretches")
                        .font(.ds_labelSmall)
                        .foregroundColor(.white.opacity(0.6))
                }
                
                if let startTime = sessionStartTime {
                    VStack(spacing: Spacing.xxs) {
                        Text(sessionDurationString(from: startTime))
                            .font(.ds_stat)
                            .foregroundColor(.mint)
                        Text("Total Time")
                            .font(.ds_labelSmall)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                
                if let area = selectedArea {
                    VStack(spacing: Spacing.xxs) {
                        Text(area)
                            .font(.ds_statSmall)
                            .foregroundColor(.mint)
                        Text("Area")
                            .font(.ds_labelSmall)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
            .padding(.vertical, Spacing.lg)
            .accessibilityElement(children: .combine)
            
            Spacer()
            
            VStack(spacing: Spacing.sm) {
                Button(action: {
                    HapticManager.impact(.medium)
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showCompletion = false
                        currentStretchIndex = 0
                        totalStretchesCompleted = 0
                        sessionStartTime = Date()
                        loadCurrentStretch()
                    }
                }) {
                    Text("Restart Session")
                        .font(.ds_labelLarge)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                                .fill(
                                    LinearGradient(colors: [.teal, .mint], startPoint: .leading, endPoint: .trailing)
                                )
                        )
                }
                .accessibilityLabel("Restart stretch session")
                
                Button(action: {
                    HapticManager.impact(.light)
                    dismissStretchMode()
                }) {
                    Text("Done")
                        .font(.ds_labelLarge)
                        .fontWeight(.bold)
                        .foregroundColor(.white.opacity(0.8))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                }
                .accessibilityLabel("Done, close stretch mode")
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.md)
        }
    }
    
    private func sessionDurationString(from startTime: Date) -> String {
        let elapsed = Int(Date().timeIntervalSince(startTime))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        return String(format: "%d:%02d", minutes, seconds)
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
        if sessionStartTime == nil {
            sessionStartTime = Date()
        }
        
        timerTask = Task { @MainActor in
            while !Task.isCancelled && remainingSeconds > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                remainingSeconds -= 1
            }
            guard !Task.isCancelled else { return }
            handleTimerComplete()
        }
    }
    
    private func handleTimerComplete() {
        totalStretchesCompleted += 1
        HapticManager.notification(.success)
        
        if currentStretchIndex < stretchQueue.count - 1 {
            currentStretchIndex += 1
            remainingSeconds = totalSeconds
            loadCurrentStretch()
            startTimer()
        } else {
            stopTimer()
            let totalTime = sessionStartTime.map { Int(Date().timeIntervalSince($0)) } ?? 0
            Task {
                await DailyQuestService.shared.onStretchCompleted(durationSeconds: totalTime)
            }
            withAnimation(.easeInOut(duration: 0.4)) {
                showCompletion = true
            }
        }
    }
    
    private func stopTimer() {
        isRunning = false
        timerTask?.cancel()
        timerTask = nil
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
    
    // MARK: - Area-to-exerciseFamily Mapping
    
    private static let areaFamilyMapping: [String: [String]] = [
        "upper body": ["stretch_chest", "chest_stretch", "stretch_arm", "arm_stretch", "stretch_bicep", "bicep_stretch", "stretch_tricep", "tricep_stretch", "stretch_pec", "pec_stretch"],
        "lower body": ["stretch_leg", "leg_stretch", "stretch_quad", "quad_stretch", "stretch_hamstring", "hamstring_stretch", "stretch_calf", "calf_stretch", "stretch_glute", "glute_stretch", "stretch_thigh", "thigh_stretch"],
        "back": ["stretch_back", "back_stretch", "stretch_lat", "lat_stretch", "stretch_spine", "spine_stretch"],
        "hips": ["stretch_hip", "hip_stretch", "stretch_groin", "groin_stretch", "stretch_psoas", "psoas_stretch", "stretch_piriformis", "piriformis_stretch"],
        "shoulders": ["stretch_shoulder", "shoulder_stretch", "stretch_delt", "delt_stretch", "stretch_rotator", "rotator_stretch"],
        "legs": ["stretch_quad", "quad_stretch", "stretch_hamstring", "hamstring_stretch", "stretch_calf", "calf_stretch", "stretch_thigh", "thigh_stretch", "stretch_knee", "knee_stretch"],
        "neck": ["stretch_neck", "neck_stretch", "stretch_cervical", "cervical_stretch", "stretch_trap", "trap_stretch"],
        "full body": []
    ]
    
    private static let areaMuscleMapping: [String: [String]] = [
        "upper body": ["chest", "pectoralis", "bicep", "tricep", "forearm"],
        "lower body": ["quadriceps", "hamstrings", "calves", "glutes", "adductors", "abductors"],
        "back": ["latissimus", "erector", "rhomboid", "trapezius", "lumbar", "thoracic"],
        "hips": ["hip flexor", "psoas", "piriformis", "glute", "adductor", "abductor", "groin"],
        "shoulders": ["deltoid", "rotator cuff", "anterior delt", "posterior delt", "lateral delt"],
        "legs": ["quadriceps", "hamstrings", "calves", "gastrocnemius", "soleus", "tibialis"],
        "neck": ["sternocleidomastoid", "levator scapulae", "scalene", "upper trapezius"],
        "full body": []
    ]
    
    private func exerciseMatchesArea(_ exercise: ExerciseDTO, area: String) -> Bool {
        let areaLower = area.lowercased()
        
        if areaLower == "full body" { return true }
        
        // Primary: match by exerciseFamily
        if let family = exercise.exerciseFamily?.lowercased(),
           let families = Self.areaFamilyMapping[areaLower] {
            for prefix in families {
                if family.contains(prefix) { return true }
            }
        }
        
        // Fallback: match by primaryMusclesArray only (not name, to avoid false positives)
        if let muscles = Self.areaMuscleMapping[areaLower] {
            let primaryMuscles = exercise.primaryMusclesArray.joined(separator: " ").lowercased()
            for muscle in muscles {
                if primaryMuscles.contains(muscle) { return true }
            }
        }
        
        return false
    }
    
    // MARK: - Data Loading
    
    private func loadStretchesForArea() {
        guard let area = selectedArea else { return }
        isLoadingStretches = true
        fetchError = nil
        
        Task {
            do {
                let stretches = try await fetchStretchesForArea(area)
                
                await MainActor.run {
                    stretchQueue = stretches
                    currentStretchIndex = 0
                    isLoadingStretches = false
                    
                    if stretchQueue.isEmpty {
                        fetchError = "No stretches found for \(area). Try Full Body instead."
                        AppLogger.warning("No stretches found for area: \(area)", category: .workout)
                        return
                    }
                    
                    totalSeconds = 60
                    remainingSeconds = 60
                    totalStretchesCompleted = 0
                    sessionStartTime = nil
                    
                    withAnimation(.easeInOut(duration: 0.4)) {
                        showingSplash = false
                    }
                    loadCurrentStretch()
                }
            } catch {
                AppLogger.error("Error fetching stretches: \(error)", category: .workout)
                await MainActor.run {
                    isLoadingStretches = false
                    fetchError = "Couldn't load stretches. Check your connection and try again."
                }
            }
        }
    }
    
    private func fetchStretchesForArea(_ area: String) async throws -> [ExerciseDTO] {
        // Try server-side RPC first
        do {
            let stretches: [ExerciseDTO] = try await SupabaseManager.shared.fetchStretchesForArea(area)
            if !stretches.isEmpty {
                cacheStretches(stretches, for: area)
                return stretches
            }
        } catch {
            AppLogger.warning("RPC fetch_stretches_for_area failed, falling back: \(error)", category: .network)
        }
        
        // Fallback: fetch all and filter client-side
        do {
            let allExercises = try await SupabaseManager.shared.fetchAllExercisesRaw()
            let filtered = allExercises.filter { exercise in
                guard let videoFilename = exercise.videoFilename, !videoFilename.isEmpty else { return false }
                let workoutType = (exercise.workoutType ?? "").lowercased()
                let category = exercise.category.lowercased()
                let name = exercise.name.lowercased()
                let isStretch = workoutType.contains("stretch") || category.contains("stretch") || name.contains("stretch")
                guard isStretch else { return false }
                return exerciseMatchesArea(exercise, area: area)
            }
            let selected = Array(filtered.shuffled().prefix(8))
            if !selected.isEmpty {
                cacheStretches(selected, for: area)
            }
            AppLogger.debug("Selected \(selected.count) stretches for \(area) (client-side fallback)", category: .workout)
            return selected
        } catch {
            // Last resort: try cached data
            if let cached = loadCachedStretches(for: area), !cached.isEmpty {
                AppLogger.info("Using cached stretches for \(area)", category: .workout)
                return cached
            }
            throw error
        }
    }
    
    // MARK: - Stretch Cache
    
    private func cacheStretches(_ stretches: [ExerciseDTO], for area: String) {
        guard let data = try? JSONEncoder().encode(stretches) else { return }
        UserDefaults.standard.set(data, forKey: "cached_stretches_\(area.lowercased())")
        AppLogger.debug("Cached \(stretches.count) stretches for \(area)", category: .data)
    }
    
    private func loadCachedStretches(for area: String) -> [ExerciseDTO]? {
        guard let data = UserDefaults.standard.data(forKey: "cached_stretches_\(area.lowercased())"),
              let stretches = try? JSONDecoder().decode([ExerciseDTO].self, from: data) else {
            return nil
        }
        return Array(stretches.shuffled())
    }
    
    // MARK: - Video Loading
    
    private func loadCurrentStretch() {
        guard currentStretchIndex < stretchQueue.count else { return }
        
        isLoadingVideo = true
        videoStatusObserver?.invalidate()
        videoStatusObserver = nil
        player?.pause()
        
        let exercise = stretchQueue[currentStretchIndex]
        currentExerciseName = exercise.name
        
        guard let url = VideoStreamingService.shared.getVideoURL(
            for: exercise.name, videoFilename: exercise.videoFilename
        ) else {
            isLoadingVideo = false
            return
        }
        
        AppLogger.debug("Loading stretch video: \(url.lastPathComponent)", category: .workout)
        setupPlayer(with: url)
    }
    
    // Q2-76 (Sprint 9 2026-04-28): AVPlayerItem(url:) triggers synchronous
    // asset/header parsing. Move it to a detached userInitiated Task and hop
    // back to @MainActor only to wire the queue player + assign @State.
    private func setupPlayer(with url: URL) {
        Task.detached(priority: .userInitiated) {
            let playerItem = AVPlayerItem(url: url)

            await MainActor.run {
                let newQueuePlayer = AVQueuePlayer(playerItem: playerItem)
                newQueuePlayer.isMuted = true

                playerLooper = AVPlayerLooper(player: newQueuePlayer, templateItem: playerItem)
                queuePlayer = newQueuePlayer
                player = newQueuePlayer
                newQueuePlayer.play()

                videoStatusObserver = playerItem.observe(\.status, options: [.new]) { [weak playerItem] item, _ in
                    Task { @MainActor in
                        guard item === playerItem else { return }
                        switch item.status {
                        case .readyToPlay:
                            self.isLoadingVideo = false
                        case .failed:
                            AppLogger.error("Video failed to load: \(item.error?.localizedDescription ?? "unknown")", category: .workout)
                            self.isLoadingVideo = false
                        default:
                            break
                        }
                    }
                }

                // Timeout fallback so the spinner doesn't hang indefinitely
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(5))
                    if self.isLoadingVideo {
                        self.isLoadingVideo = false
                    }
                }
            }
        }
    }
}

// MARK: - Splash View

struct StretchSplashView: View {
    @Binding var selectedArea: String?
    @Binding var isLoading: Bool
    @Binding var fetchError: String?
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
            // Header bar
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.ds_heading2)
                        .foregroundColor(.white.opacity(0.6))
                }
                .accessibilityLabel("Close stretch mode")
                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xs)
            
            // Scrollable content
            ScrollView(showsIndicators: false) {
                VStack(spacing: Spacing.lg) {
                    // Hero
                    VStack(spacing: Spacing.lg) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.teal, Color.mint],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)
                                .shadow(color: .teal.opacity(0.3), radius: Spacing.sm, x: 0, y: 6)
                            
                            Text("🧘")
                                .font(.system(size: 40))
                        }
                        .accessibilityHidden(true)
                        
                        VStack(spacing: Spacing.xs) {
                            Text("Stretch Mode")
                                .font(.ds_displayMedium)
                                .foregroundColor(.white)
                            
                            Text("What area would you like to stretch?")
                                .font(.ds_bodyLarge)
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.top, Spacing.sm)
                    
                    // Area grid
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: Spacing.sm),
                        GridItem(.flexible(), spacing: Spacing.sm)
                    ], spacing: Spacing.sm) {
                        ForEach(stretchAreas, id: \.name) { area in
                            StretchAreaCard(
                                name: area.name,
                                icon: area.icon,
                                color: area.color,
                                isSelected: selectedArea == area.name,
                                onTap: {
                                    HapticManager.selectionChanged()
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        selectedArea = area.name
                                    }
                                }
                            )
                        }
                    }
                    
                    if let error = fetchError {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.ds_bodySmall)
                                .foregroundColor(.orange)
                                .multilineTextAlignment(.leading)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Error: \(error)")
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.md)
            }
            
            // Pinned CTA below scroll
            Button(action: {
                HapticManager.impact(.medium)
                onStart()
            }) {
                HStack(spacing: Spacing.sm) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("Start Stretching")
                            .font(.ds_heading3)
                            .fontWeight(.semibold)
                        Image(systemName: "arrow.right")
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background(
                    LinearGradient(
                        colors: selectedArea != nil ? [Color.teal, Color.mint] : [Color.gray, Color.gray.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(CornerRadius.lg)
                .shadow(color: selectedArea != nil ? .teal.opacity(0.3) : .clear, radius: Spacing.sm, x: 0, y: 6)
            }
            .disabled(selectedArea == nil || isLoading)
            .opacity(selectedArea == nil ? 0.5 : 1.0)
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.md)
            .accessibilityLabel(isLoading ? "Loading stretches" : "Start stretching")
            .accessibilityHint(selectedArea == nil ? "Select an area first" : "Double tap to begin \(selectedArea ?? "") stretches")
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
            HStack(spacing: Spacing.sm) {
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
                        .font(.ds_heading3)
                        .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                }
                .accessibilityHidden(true)
                
                Text(name)
                    .font(.ds_bodyMedium)
                    .fontWeight(.semibold)
                    .foregroundColor(isSelected ? color : .white.opacity(0.8))
                
                Spacer()
            }
            .padding(Spacing.sm + Spacing.xxxs)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .stroke(isSelected ? color.opacity(0.6) : Color.white.opacity(0.1), lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: isSelected ? color.opacity(0.3) : .clear, radius: Spacing.xs, x: 0, y: Spacing.xxs)
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .accessibilityLabel(name)
        .accessibilityHint("Double tap to select \(name) stretches")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Circular Video Player (AVPlayerLayer for clean centering)
struct VideoPlayerCircle: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerCircleContainerView {
        let view = PlayerCircleContainerView()
        view.backgroundColor = .white

        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = view.bounds
        view.layer.addSublayer(playerLayer)
        view.playerLayer = playerLayer

        return view
    }

    func updateUIView(_ uiView: PlayerCircleContainerView, context: Context) {
        uiView.playerLayer?.player = player
    }

    class PlayerCircleContainerView: UIView {
        var playerLayer: AVPlayerLayer?

        override func layoutSubviews() {
            super.layoutSubviews()
            // Scale down the layer transform to "zoom out" and show more of the video
            playerLayer?.frame = bounds
            playerLayer?.setAffineTransform(CGAffineTransform(scaleX: 0.85, y: 0.85))
        }
    }
}

// MARK: - Preview
#Preview {
    StretchModeView(isPresented: .constant(true))
}
