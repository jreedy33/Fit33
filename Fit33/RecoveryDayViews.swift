import SwiftUI

// MARK: - Recovery Day View (Guided Session)

struct RecoveryDayView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    let routine: RecoveryRoutine
    
    @State private var isActive = false
    @State private var currentIndex = 0
    @State private var timeRemaining: Int = 0
    @State private var timer: Timer?
    @State private var isComplete = false
    
    private var currentExercise: RecoveryExercise? {
        guard currentIndex < routine.exercises.count else { return nil }
        return routine.exercises[currentIndex]
    }
    
    private var progress: Double {
        guard !routine.exercises.isEmpty else { return 0 }
        return Double(currentIndex) / Double(routine.exercises.count)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedOrbBackground.home(colorScheme: colorScheme)
                    .ignoresSafeArea(.all, edges: .all)
                
                if isComplete {
                    completionView
                } else if isActive {
                    activeSessionView
                } else {
                    routinePreview
                }
            }
            .navigationTitle(routine.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { stopAndDismiss() }) {
                        Image(systemName: "xmark")
                            .font(.ds_labelMedium)
                    }
                }
            }
        }
        .onDisappear { timer?.invalidate() }
    }
    
    // MARK: - Preview (before starting)
    
    private var routinePreview: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(
                            LinearGradient(colors: [.teal, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    
                    Text(routine.title)
                        .font(.title3)
                        .fontWeight(.bold)
                    
                    HStack(spacing: 16) {
                        Label("\(routine.totalDurationMinutes) min", systemImage: "clock")
                        Label("\(routine.exercises.count) exercises", systemImage: "list.bullet")
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
                .padding(.vertical, Spacing.md)
                
                if !routine.targetMuscles.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(routine.targetMuscles, id: \.self) { muscle in
                            Text(muscle)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.teal)
                                .padding(.horizontal, 10)
                                .padding(.vertical, Spacing.xxs)
                                .background(Capsule().fill(Color.teal.opacity(0.12)))
                        }
                    }
                }
                
                ForEach(Array(routine.exercises.enumerated()), id: \.element.id) { index, exercise in
                    exercisePreviewRow(exercise, index: index)
                }
                
                Button(action: startSession) {
                    Label("Start Recovery Session", systemImage: "play.fill")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .background(
                            LinearGradient(colors: [.teal, .blue], startPoint: .leading, endPoint: .trailing)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        )
                }
                .padding(.top, 8)
                
                Spacer(minLength: 60)
            }
            .padding(.horizontal, Spacing.md)
        }
    }
    
    private func exercisePreviewRow(_ exercise: RecoveryExercise, index: Int) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.teal.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: exercise.sfSymbol)
                    .font(.ds_bodySmall)
                    .foregroundColor(.teal)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("\(exercise.durationSeconds)s • \(exercise.category.rawValue)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("\(index + 1)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(colorScheme == .dark ? Color(white: 0.14) : Color.white)
        )
    }
    
    // MARK: - Active Session
    
    private var activeSessionView: some View {
        VStack(spacing: 24) {
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.2)).frame(height: 6)
                    Capsule().fill(LinearGradient(colors: [.teal, .blue], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * progress, height: 6)
                }
            }
            .frame(height: 6)
            .padding(.horizontal, Spacing.md)
            .padding(.top, 8)
            
            Text("\(currentIndex + 1) of \(routine.exercises.count)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            if let exercise = currentExercise {
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color.teal.opacity(0.12))
                            .frame(width: 80, height: 80)
                        Image(systemName: exercise.sfSymbol)
                            .font(.ds_heading1)
                            .foregroundColor(.teal)
                    }
                    
                    Text(exercise.name)
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    
                    Text(exercise.category.rawValue)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    // Timer
                    Text(formatTime(timeRemaining))
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: [.teal, .blue], startPoint: .leading, endPoint: .trailing)
                        )
                    
                    // Instructions
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(exercise.instructions, id: \.self) { step in
                            HStack(alignment: .top, spacing: 8) {
                                Circle().fill(Color.teal).frame(width: 6, height: 6).padding(.top, 6)
                                Text(step)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                }
            }
            
            Spacer()
            
            // Controls
            HStack(spacing: 24) {
                Button(action: previousExercise) {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(Color.cardBackground))
                }
                .disabled(currentIndex == 0)
                .opacity(currentIndex == 0 ? 0.4 : 1)
                
                Button(action: nextExercise) {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(LinearGradient(colors: [.teal, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)))
                }
            }
            .padding(.bottom, 40)
        }
    }
    
    // MARK: - Completion
    
    private var completionView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(colors: [.teal, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            
            Text("Recovery Complete")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Great job taking care of your body. Rest and recovery are just as important as training.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)
            
            HStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text("\(routine.totalDurationMinutes)")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("Minutes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(spacing: 4) {
                    Text("\(routine.exercises.count)")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("Exercises")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(spacing: 4) {
                    Text("\(routine.targetMuscles.count)")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("Muscles")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, Spacing.md)
            
            Spacer()
            
            Button(action: { dismiss() }) {
                Text("Done")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.sm)
                    .background(
                        LinearGradient(colors: [.teal, .blue], startPoint: .leading, endPoint: .trailing)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    )
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, 40)
        }
    }
    
    // MARK: - Actions
    
    private func startSession() {
        isActive = true
        currentIndex = 0
        startTimer()
        HapticManager.impact(.medium)
    }
    
    private func startTimer() {
        timer?.invalidate()
        guard let exercise = currentExercise else { return }
        timeRemaining = exercise.durationSeconds
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [self] _ in
            if timeRemaining > 0 {
                timeRemaining -= 1
                if timeRemaining == 0 {
                    HapticManager.notification(.success)
                    nextExercise()
                }
            }
        }
    }
    
    private func nextExercise() {
        if currentIndex + 1 >= routine.exercises.count {
            timer?.invalidate()
            withAnimation(.spring(response: 0.5)) { isComplete = true }
            HapticManager.notification(.success)
        } else {
            currentIndex += 1
            startTimer()
            HapticManager.impact(.light)
        }
    }
    
    private func previousExercise() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
        startTimer()
        HapticManager.impact(.light)
    }
    
    private func stopAndDismiss() {
        timer?.invalidate()
        dismiss()
    }
    
    private func formatTime(_ seconds: Int) -> String {
        let min = seconds / 60
        let sec = seconds % 60
        return min > 0 ? String(format: "%d:%02d", min, sec) : "\(sec)"
    }
}

// MARK: - Dashboard Widget

struct RecoveryDayDashboardWidget: View {
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var showingRecoveryDay = false
    
    private let engine = RecoveryDayEngine.shared
    
    var body: some View {
        let topMuscles = engine.topRecoveringMuscles.prefix(3)
        
        Button(action: {
            HapticManager.impact(.light)
            showingRecoveryDay = true
        }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "leaf.fill")
                        .font(.ds_bodyRegular)
                        .foregroundColor(.teal)
                    Text("Recovery Day")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.ds_labelMedium)
                        .foregroundColor(.secondary)
                }
                
                if !topMuscles.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(Array(topMuscles), id: \.muscle) { item in
                            HStack(spacing: 8) {
                                Text(item.muscle)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 70, alignment: .leading)
                                
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .fill(Color.gray.opacity(0.2))
                                            .frame(height: 6)
                                        Capsule()
                                            .fill(recoveryColor(item.recovery))
                                            .frame(width: max(0, geo.size.width * item.recovery / 100), height: 6)
                                    }
                                }
                                .frame(height: 6)
                                
                                Text("\(Int(item.recovery))%")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .frame(width: 32, alignment: .trailing)
                            }
                        }
                    }
                }
                
                HStack(spacing: 4) {
                    let routine = engine.generateRoutine()
                    Image(systemName: "clock")
                        .font(.ds_caption)
                    Text("~\(routine.totalDurationMinutes) min routine")
                        .font(.caption)
                }
                .foregroundColor(.teal)
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(colorScheme == .dark ? Color(white: 0.14) : Color.white)
            )
            .shadow(color: colorScheme == .dark ? .clear : .black.opacity(0.06), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $showingRecoveryDay) {
            RecoveryDayView(routine: engine.generateRoutine())
        }
    }
    
    private func recoveryColor(_ pct: Double) -> Color {
        if pct < 40 { return .red }
        if pct < 70 { return .orange }
        return .green
    }
}
